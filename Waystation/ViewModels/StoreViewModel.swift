import Foundation
import SwiftUI
import Observation
import WebKit

@Observable
@MainActor
final class StoreViewModel {
    static let homeURL = URL(string: "https://chromewebstore.google.com")!

    var currentURLString: String = "https://chromewebstore.google.com"
    var inputURLString: String = ""
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var estimatedProgress: Double = 0.0

    // Navigation triggers observed by StoreWebView
    var navigationAction: NavigationAction?

    enum NavigationAction: Equatable {
        case load(URL)
        case goBack
        case goForward
        case reload
        case stopLoading
    }

    init() {
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
        }
        if let title = title, !title.isEmpty {
            self.pageTitle = title
        }
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.estimatedProgress = progress
    }
}
