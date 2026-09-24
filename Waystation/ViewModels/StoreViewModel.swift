import Foundation
import SwiftUI
import Observation
import WebKit

@Observable
@MainActor
final class StoreViewModel: Sendable {
    static let homeURL = URL(string: "https://chromewebstore.google.com/category/extensions")!
    private static let detailRegex = try? NSRegularExpression(pattern: "/detail/(?:([^/]+)/)?([a-z]{32})")

    var currentURLString: String = "https://chromewebstore.google.com/category/extensions"
    var inputURLString: String = ""
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var estimatedProgress: Double = 0.0

    // Extension detail detected from current page
    var activeExtensionDetail: StoreExtensionPayload?

    // Extension installation payload captured from "Add to Safari" button
    var selectedExtension: StoreExtensionPayload?
    var showInstallConfirmation: Bool = false

    // Matches installed extension in Library (if already present)
    var installedMatch: InstalledExtension?

    // Download & pipeline state for Story 2.3
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
    var downloadErrorMessage: String?
    var onTriggerPipeline: ((URL) async -> Void)?

    var logDrawerViewModel: LogDrawerViewModel?

    // Navigation triggers observed by StoreWebView
    var navigationAction: NavigationAction?

    enum NavigationAction: Equatable {
        case load(URL)
        case goBack
        case goForward
        case reload
        case stopLoading
    }

    init(logDrawerViewModel: LogDrawerViewModel? = nil, onTriggerPipeline: ((URL) async -> Void)? = nil) {
        self.logDrawerViewModel = logDrawerViewModel
        self.onTriggerPipeline = onTriggerPipeline
        self.inputURLString = Self.homeURL.absoluteString
    }

    func goBack() {
        navigationAction = .goBack
    }

    func goForward() {
        navigationAction = .goForward
    }

    func reload() {
        navigationAction = .reload
    }

    func stopLoading() {
        navigationAction = .stopLoading
    }

    func goHome() {
        navigateTo(url: Self.homeURL)
    }

    func navigateTo(url: URL) {
        navigationAction = .load(url)
        inputURLString = url.absoluteString
    }

    func handleSubmit() {
        let trimmed = inputURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            navigateTo(url: url)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            if let url = URL(string: "https://\(trimmed)") {
                navigateTo(url: url)
            }
        } else {
            // Treat as Chrome Web Store search query
            if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let searchURL = URL(string: "https://chromewebstore.google.com/search/\(encoded)") {
                navigateTo(url: searchURL)
            }
        }
    }

    func updateState(url: URL?, title: String?, canGoBack: Bool, canGoForward: Bool, isLoading: Bool, progress: Double) {
        if let url = url {
            // Guard against Themes category: auto-redirect back to Extensions
            if url.path.contains("/category/themes") {
                navigateTo(url: Self.homeURL)
                return
            }
            self.currentURLString = url.absoluteString
            if !isLoading {
                self.inputURLString = url.absoluteString
            }
            checkForExtensionDetailPage(url: url)
        }
        if let title = title, !title.isEmpty {
            self.pageTitle = title
        }
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.estimatedProgress = progress
    }

    private func checkForExtensionDetailPage(url: URL) {
        let path = url.path
        guard path.contains("/detail/") else {
            self.activeExtensionDetail = nil
            self.installedMatch = nil
            return
        }

        guard let regex = Self.detailRegex,
              let match = regex.firstMatch(in: path, range: NSRange(location: 0, length: path.utf16.count)),
              match.numberOfRanges >= 3,
              let idRange = Range(match.range(at: 2), in: path) else {
            self.activeExtensionDetail = nil
            self.installedMatch = nil
            return
        }

        let extId = String(path[idRange])

        // Prioritize the URL slug so SPA transitions never inherit the previous extension's title
        var title = "Chrome Extension"
        if let slugRange = Range(match.range(at: 1), in: path) {
            let slug = String(path[slugRange])
            title = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        } else if !pageTitle.isEmpty && pageTitle != "Chrome Web Store" {
            title = pageTitle.replacingOccurrences(of: " - Chrome Web Store", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.activeExtensionDetail = StoreExtensionPayload(extensionId: extId, title: title, storeURL: url)
        Task {
            self.installedMatch = await findInstalledExtension(title: title, extId: extId)
        }
    }

    /// Checks if the extension is already present in the local Library registry
    func findInstalledExtension(title: String, extId: String) async -> InstalledExtension? {
        guard let installed = try? await ExtensionRegistry.shared.loadAll() else { return nil }

        let normalize: (String) -> String = { text in
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        let cleanTitle = normalize(title)
        let cleanExtId = normalize(extId)

        return installed.first { ext in
            let cleanName = normalize(ext.name)
            let cleanId = normalize(ext.id)

            // Direct ID match
            if !cleanExtId.isEmpty && cleanId == cleanExtId {
                return true
            }

            // Exact or clean title/name match
            if !cleanTitle.isEmpty {
                if cleanName == cleanTitle || cleanId == cleanTitle {
                    return true
                }
                // Only allow mutual containment if both strings are substantial (>= 6 chars) to avoid false positives
                if cleanTitle.count >= 6 && cleanName.count >= 6 {
                    if cleanName.contains(cleanTitle) || cleanTitle.contains(cleanName) {
                        return true
                    }
                }
            }
            return false
        }
    }

    func handleAddToSafari(payload: StoreExtensionPayload) {
        self.selectedExtension = payload
        Task {
            let match = await findInstalledExtension(title: payload.title, extId: payload.extensionId)
            self.installedMatch = match
            self.showInstallConfirmation = true
            if let match = match {
                logDrawerViewModel?.append(line: "[Store] '\(payload.title)' is already installed in Library (v\(match.version)). Prompting user to reinstall/update.")
            } else {
                logDrawerViewModel?.append(line: "[Store] 'Add to Safari' clicked for '\(payload.title)' (ID: \(payload.extensionId))")
            }
        }
    }

    /// Downloads the CRX binary and triggers the automated Safari conversion pipeline.
    func startDownloadAndPipeline(payload: StoreExtensionPayload) async {
        isDownloading = true
        downloadProgress = 0.0
        downloadErrorMessage = nil
        logDrawerViewModel?.isStreaming = true
        logDrawerViewModel?.append(line: "[Store] Starting automated CRX download for '\(payload.title)' (ID: \(payload.extensionId))...")

        do {
            let crxURL = try await CRXDownloader.shared.downloadCRX(
                extensionId: payload.extensionId
            ) { [self] progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            }
            logDrawerViewModel?.append(line: "[Store] CRX download completed: \(crxURL.path)")
            isDownloading = false
            showInstallConfirmation = false
            let destinationURL = crxURL
            selectedExtension = nil
            installedMatch = nil

            // Hand off to the conversion pipeline
            if let onTriggerPipeline = onTriggerPipeline {
                await onTriggerPipeline(destinationURL)
            }
        } catch let error as WaystationError {
            logDrawerViewModel?.append(line: "[Store] Error downloading CRX: \(error.localizedDescription)")
            downloadErrorMessage = error.errorDescription
            isDownloading = false
        } catch {
            logDrawerViewModel?.append(line: "[Store] Error: \(error.localizedDescription)")
            downloadErrorMessage = error.localizedDescription
            isDownloading = false
        }
    }
}
