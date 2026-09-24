import SwiftUI

/// ViewModel driving Tab 3 (Library): extension list, search filter, expiration warnings, and batch re-signing.
/// Conforms to Story 3.1, Story 3.2, Story 3.3, and Swift 6 concurrency specifications.
@Observable
@MainActor
public final class LibraryViewModel {
    public var extensions: [InstalledExtension] = []
    public var searchText: String = ""
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var extensionToUninstall: InstalledExtension?
    public var showUninstallConfirmation: Bool = false

    // Story 3.2: Re-signing state
    public var isResigningAll: Bool = false
    public var resigningExtensionName: String?

    // Signature Verification & Real-time Safari Health State
    public var signatureStatuses: [String: SignatureVerificationResult] = [:]
    public var isVerifyingSignatures: Bool = false
    public var safariStatus: SafariHealthStatus?
    public var isCheckingSafari: Bool = false

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
        self.logDrawerViewModel = logDrawerViewModel ?? .shared
    }

    /// Filtered extensions matching the user's search query (Story 3.1).
    public var filteredExtensions: [InstalledExtension] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return extensions
        }
        let query = searchText.lowercased()
        return extensions.filter { ext in
            ext.name.lowercased().contains(query) ||
            ext.bundleIdentifier.lowercased().contains(query) ||
            ext.version.lowercased().contains(query)
        }
    }

    /// Loads all installed extensions from the registry and checks their real-time status.
    public func loadExtensions() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await registry.loadAll()
            self.extensions = loaded.sorted { $0.installedDate > $1.installedDate }
            isLoading = false
            await verifyAllSignatures()
            await checkSafariHealth()
        } catch {
            self.errorMessage = "Failed to load installed extensions: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Verifies on-disk code signatures for all installed extensions in parallel.
    public func verifyAllSignatures() async {
        isVerifyingSignatures = true
        var results: [String: SignatureVerificationResult] = [:]

        for ext in extensions {
            let appURL = ext.containerAppURL
            if FileManager.default.fileExists(atPath: appURL.path) {
                let verification = await signingManager.verifySignature(for: appURL)
                results[ext.id] = verification
            } else {
                results[ext.id] = SignatureVerificationResult(
                    isValidOnDisk: false,
                    isAdHoc: false,
                    authority: nil,
                    statusMessage: "Bundle missing on disk"
                )
            }
        }

        self.signatureStatuses = results
        self.isVerifyingSignatures = false
    }

    /// Checks Safari's running state, Develop menu, and "Allow Unsigned Extensions" toggle.
    public func checkSafariHealth() async {
        isCheckingSafari = true
        let status = await SafariAutomationService.shared.checkSafariHealth()
        self.safariStatus = status
        self.isCheckingSafari = false
    }

    /// Requests automated toggle of "Allow Unsigned Extensions" in Safari.
    public func toggleSafariUnsignedExtensions() async {
        let drawer = self.logDrawerViewModel
        _ = await SafariAutomationService.shared.toggleAllowUnsignedExtensions { line in
            Task { @MainActor in
                drawer?.append(line: line)
            }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        await checkSafariHealth()
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
                    Task { @MainActor [weak self] in
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
            await verifyAllSignatures()
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

    /// Confirms and performs uninstallation of the active extension (Story 3.3).
    public func confirmUninstall() async {
        guard let ext = extensionToUninstall else { return }
        errorMessage = nil

        do {
            try await registry.remove(id: ext.id)

            // Remove container .app from disk if present
            let appURL = ext.containerAppURL
            if FileManager.default.fileExists(atPath: appURL.path) {
                try? FileManager.default.removeItem(at: appURL)
            }

            self.extensions.removeAll { $0.id == ext.id }
            self.extensionToUninstall = nil
            self.showUninstallConfirmation = false
            logDrawerViewModel?.append(line: "[Library] Uninstalled extension '\(ext.name)'.")
        } catch {
            self.errorMessage = "Failed to uninstall extension: \(error.localizedDescription)"
            self.extensionToUninstall = nil
            self.showUninstallConfirmation = false
        }
    }
}
