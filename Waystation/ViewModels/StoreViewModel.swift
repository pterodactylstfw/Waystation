import Foundation
import SwiftUI
import Observation
import WebKit

@Observable
@MainActor
final class StoreViewModel {
    static let homeURL = URL(string: "https://chromewebstore.google.com")!
    private static let detailRegex = try? NSRegularExpression(pattern: "/detail/(?:([^/]+)/)?([a-z]{32})")

    var currentURLString: String = "https://chromewebstore.google.com"
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

    init(logDrawerViewModel: LogDrawerViewModel? = nil) {
        self.logDrawerViewModel = logDrawerViewModel
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
            self.currentURLString = url.absoluteString
            if !self.isLoading || self.inputURLString.isEmpty {
                self.inputURLString = url.absoluteString
            }
            checkForExtensionDetailPage(url: url)
        }
        if let title = title, !title.isEmpty {
            self.pageTitle = title
            // Refresh title if active detail was already detected
            if let active = self.activeExtensionDetail, let url = url {
                checkForExtensionDetailPage(url: url)
            }
        }
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.estimatedProgress = progress
    }

    func checkForExtensionDetailPage(url: URL) {
        let path = url.path
        guard let regex = Self.detailRegex,
              let match = regex.firstMatch(in: path, range: NSRange(location: 0, length: path.utf16.count)),
              match.numberOfRanges >= 3,
              let idRange = Range(match.range(at: 2), in: path) else {
            self.activeExtensionDetail = nil
            return
        }

        let extId = String(path[idRange])
        var title = pageTitle.replacingOccurrences(of: " - Chrome Web Store", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == "Chrome Web Store" {
            if let slugRange = Range(match.range(at: 1), in: path) {
                title = String(path[slugRange]).replacingOccurrences(of: "-", with: " ").capitalized
            } else {
                title = "Chrome Extension"
            }
        }

        self.activeExtensionDetail = StoreExtensionPayload(extensionId: extId, title: title, storeURL: url)
    }

    func handleAddToSafari(payload: StoreExtensionPayload) {
        self.selectedExtension = payload
        self.showInstallConfirmation = true
        logDrawerViewModel?.append(line: "[Store] 'Add to Safari' clicked for '\(payload.title)' (ID: \(payload.extensionId))")
    }
}
