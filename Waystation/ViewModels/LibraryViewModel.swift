import SwiftUI
import AppKit

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

    // Lifecycle observers for real-time Safari process detection
    private var workspaceObservers: [NSObjectProtocol] = []
    private var defaultNotificationObservers: [NSObjectProtocol] = []

    public init(
        registry: ExtensionRegistry = .shared,
        signingManager: SigningManager = .shared,
        logDrawerViewModel: LogDrawerViewModel? = nil
    ) {
        self.registry = registry
        self.signingManager = signingManager
        self.logDrawerViewModel = logDrawerViewModel ?? .shared
    }

    /// Automatically observes Safari launches, quits (⌘Q), and window activations in real time.
    public func startObservingSafariLifecycle() {
        guard workspaceObservers.isEmpty && defaultNotificationObservers.isEmpty else { return }

        let wsCenter = NSWorkspace.shared.notificationCenter

        let termObs = wsCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Safari" else { return }
            Task { @MainActor [weak self] in
                await self?.checkSafariHealth()
            }
        }

        let launchObs = wsCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Safari" else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                await self?.checkSafariHealth()
            }
        }

        let activateObs = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Safari" else { return }
            Task { @MainActor [weak self] in
                await self?.checkSafariHealth()
            }
        }

        workspaceObservers = [termObs, launchObs, activateObs]

        let appFocusObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkSafariHealth()
            }
        }

        defaultNotificationObservers = [appFocusObs]
    }

    /// Cleans up observers when the view disappears.
    public func stopObservingSafariLifecycle() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers {
            wsCenter.removeObserver(obs)
        }
        workspaceObservers.removeAll()

        for obs in defaultNotificationObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        defaultNotificationObservers.removeAll()
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
        } catch {
            self.errorMessage = "Failed to load extensions: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    /// Verifies the codesign and gatekeeper validity of each installed extension in parallel.
    public func verifyAllSignatures() async {
        isVerifyingSignatures = true
        var results: [String: SignatureVerificationResult] = [:]

        for ext in extensions {
            let status = await signingManager.verifySignature(for: ext.containerAppURL)
            results[ext.id] = status
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
        _ = await SafariAutomationService.shared.toggleAllowUnsignedExtensions { [weak self] line in
            Task { @MainActor [weak self] in
                self?.logDrawerViewModel?.append(line: line)
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

        var updatedList = extensions
        var successCount = 0

        for idx in updatedList.indices {
            let ext = updatedList[idx]
            resigningExtensionName = ext.name
            logDrawerViewModel?.append(line: "[Re-sign] Processing '\(ext.name)' (v\(ext.version))...")

            let appURL = ext.containerAppURL
            guard FileManager.default.fileExists(atPath: appURL.path) else {
                logDrawerViewModel?.append(line: "[Re-sign] Warning: Container app missing at \(appURL.path)")
                continue
            }

            do {
                try await signingManager.sign(targetURL: appURL) { [weak self] line in
                    Task { @MainActor [weak self] in
                        self?.logDrawerViewModel?.append(line: line)
                    }
                }

                // Update lastSignedDate to now
                updatedList[idx].lastSignedDate = Date()
                try await registry.update(updatedList[idx])
                successCount += 1
                logDrawerViewModel?.append(line: "[Re-sign] Successfully re-signed '\(ext.name)'. Expiration reset to 7 days.")
            } catch {
                logDrawerViewModel?.append(line: "[Re-sign] Error re-signing '\(ext.name)': \(error.localizedDescription)")
            }
        }

        self.extensions = updatedList
        self.isResigningAll = false
        self.resigningExtensionName = nil
        logDrawerViewModel?.isStreaming = false
        logDrawerViewModel?.append(line: "--- Batch Re-signing Finished (\(successCount)/\(extensions.count) succeeded) ---")

        await verifyAllSignatures()
    }

    /// Prompts user confirmation before uninstalling an extension (Story 3.3).
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

    /// Reveals the extension container app in Finder.
    public func revealInFinder(_ ext: InstalledExtension) {
        let url = ext.containerAppURL
        let dirPath = url.deletingLastPathComponent().path
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: dirPath)
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dirPath)
        }
    }
}
