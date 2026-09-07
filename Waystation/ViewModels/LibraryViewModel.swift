import SwiftUI
import Observation

/// ViewModel managing state and actions for the Installed Extensions Library.
/// Conforms to AD-1, Story 3.1, Story 3.2, and Story 3.3 acceptance criteria.
@Observable
@MainActor
public final class LibraryViewModel {
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

    /// Filtered list based on search text.
    public var filteredExtensions: [InstalledExtension] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return extensions }
        return extensions.filter {
            $0.name.lowercased().contains(trimmed) ||
            $0.bundleIdentifier.lowercased().contains(trimmed) ||
            $0.id.lowercased().contains(trimmed)
        }
    }

    /// Count of extensions requiring re-signing soon (<= 2 days).
    public var expiringSoonCount: Int {
        extensions.filter { $0.expirationStatus != .valid }.count
    }

    /// Loads all installed extensions from disk (`registry.json`).
    public func loadExtensions() async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await registry.loadAll()
            self.extensions = loaded.sorted { $0.installedDate > $1.installedDate }
            self.isLoading = false
        } catch {
            self.errorMessage = "Eșec la încărcarea extensiilor: \(error.localizedDescription)"
            self.isLoading = false
        }
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
                onProgress: { [weak self] current, total, name in
                    Task { @MainActor in
                        self?.resigningExtensionName = "\(name) (\(current)/\(total))"
                    }
                },
                onOutputLine: { line in
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

    /// Confirms and executes uninstallation (Story 3.3).
    public func confirmUninstall() async {
        guard let ext = extensionToUninstall else { return }
        showUninstallConfirmation = false
        logDrawerViewModel?.append(line: "[Library] Uninstalling extension '\(ext.name)'...")

        do {
            // 1. Remove .app from disk if exists
            if FileManager.default.fileExists(atPath: ext.containerAppPath) {
                try FileManager.default.removeItem(atPath: ext.containerAppPath)
            }

            // 2. Remove from registry.json
            try await registry.remove(id: ext.id)
            logDrawerViewModel?.append(line: "[Library] Successfully removed '\(ext.name)' from registry.")

            // 3. Refresh list
            await loadExtensions()
            self.extensionToUninstall = nil
        } catch {
            logDrawerViewModel?.append(line: "[Library] Error uninstalling '\(ext.name)': \(error.localizedDescription)")
            self.errorMessage = "Eșec la dezinstalare: \(error.localizedDescription)"
        }
    }
}
