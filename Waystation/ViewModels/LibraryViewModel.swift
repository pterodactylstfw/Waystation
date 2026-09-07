import SwiftUI
import Observation

/// ViewModel managing state and actions for the Installed Extensions Library.
/// Conforms to AD-1, Story 3.1, Story 3.2, and Story 3.3 acceptance criteria.
@Observable
@MainActor
public final class LibraryViewModel: Sendable {
    public var extensions: [InstalledExtension] = []
    public var searchText: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String?

    // Story 3.2: Re-signing state
    public var isResigningAll: Bool = false
    public var resigningExtensionName: String?

    // Story 3.3: Uninstallation confirmation state
    public var extensionToUninstall: InstalledExtension?
    public var showUninstallConfirmation: Bool = false

    public let logDrawerViewModel: LogDrawerViewModel?
    private let registry: ExtensionRegistry
    private let signingManager: SigningManager

    public init(
        registry: ExtensionRegistry = .shared,
        signingManager: SigningManager = .shared,
        logDrawerViewModel: LogDrawerViewModel? = nil
    ) {
        self.registry = registry
        self.signingManager = signingManager
        self.logDrawerViewModel = logDrawerViewModel
    }

    /// Filtered list of extensions based on search query.
    public var filteredExtensions: [InstalledExtension] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return extensions
        }
        return extensions.filter { ext in
            ext.name.localizedCaseInsensitiveContains(searchText) ||
            ext.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Loads all installed extensions from the registry and checks their physical presence on disk.
    public func loadExtensions() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await registry.loadAll()
            self.extensions = loaded.sorted { $0.installedDate > $1.installedDate }
        } catch {
            self.errorMessage = "Nu s-au putut încărca extensiile: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Re-signs all installed extensions in batch and resets their expiration countdowns to 7 days (Story 3.2).
    public func reSignAll() async {
        isResigningAll = true
        errorMessage = nil
        logDrawerViewModel?.isStreaming = true
        logDrawerViewModel?.append(line: "--- Initiating Batch Re-signing (Story 3.2) ---")

        let drawer = self.logDrawerViewModel

        do {
            let updated = try await signingManager.reSignAll(
                onProgress: { [self] current, total, name in
                    Task { @MainActor in
                        self.resigningExtensionName = "\(name) (\(current)/\(total))"
                    }
                },
                onOutputLine: { [drawer] line in
                    Task { @MainActor in
                        drawer?.append(line: line)
                    }
                }
            )
            self.extensions = updated.sorted { $0.installedDate > $1.installedDate }
            self.isResigningAll = false
            self.resigningExtensionName = nil
            self.logDrawerViewModel?.isStreaming = false
        } catch {
            logDrawerViewModel?.append(line: "[Signing] Batch re-signing error: \(error.localizedDescription)")
            self.errorMessage = "Eșec la re-semnare: \(error.localizedDescription)"
            self.isResigningAll = false
            self.resigningExtensionName = nil
            self.logDrawerViewModel?.isStreaming = false
        }
    }

    /// Reveals the container `.app` bundle in macOS Finder.
    public func revealInFinder(_ ext: InstalledExtension) {
        let url = ext.containerAppURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
        } else {
            // If .app does not exist yet at target location, reveal parent folder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ext.containerAppURL.deletingLastPathComponent().path)
        }
    }

    /// Prompts uninstallation confirmation for the specified extension.
    public func requestUninstall(_ ext: InstalledExtension) {
        self.extensionToUninstall = ext
        self.showUninstallConfirmation = true
    }

    /// Executes permanent uninstallation of the selected extension (Story 3.3).
    public func confirmUninstall() async {
        guard let ext = extensionToUninstall else { return }
        showUninstallConfirmation = false
        extensionToUninstall = nil

        logDrawerViewModel?.append(line: "[Uninstall] Removing '\(ext.name)'...")

        // 1. Delete .app bundle from disk
        let appURL = ext.containerAppURL
        if FileManager.default.fileExists(atPath: appURL.path) {
            do {
                try FileManager.default.removeItem(at: appURL)
                logDrawerViewModel?.append(line: "[Uninstall] Deleted container bundle at '\(appURL.path)'.")
            } catch {
                logDrawerViewModel?.append(line: "[Uninstall] Warning: Could not delete bundle: \(error.localizedDescription)")
            }
        }

        // 2. Remove entry from registry.json
        do {
            try await registry.remove(id: ext.id)
            logDrawerViewModel?.append(line: "[Uninstall] Removed '\(ext.name)' from registry.")
            await loadExtensions()
        } catch {
            errorMessage = "Nu s-a putut șterge extensia din registru: \(error.localizedDescription)"
            logDrawerViewModel?.append(line: "[Uninstall] Error: \(error.localizedDescription)")
        }
    }
}
