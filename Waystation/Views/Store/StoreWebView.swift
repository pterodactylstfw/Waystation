import SwiftUI
import WebKit

struct StoreWebView: NSViewRepresentable {
    @Bindable var viewModel: StoreViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let userContentController = WKUserContentController()

        // Inject initial installed extensions state if available on disk
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let registryURL = appSupport.appendingPathComponent("Waystation/registry.json")
            if let data = try? Data(contentsOf: registryURL),
               let exts = try? JSONDecoder().decode([InstalledExtension].self, from: data) {
                let names = exts.map { $0.name }
                let ids = exts.map { $0.id }
                if let jsonData = try? JSONSerialization.data(withJSONObject: ["names": names, "ids": ids]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let preload = WKUserScript(
                        source: "window.__waystationInstalled = \(jsonString);",
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                    userContentController.addUserScript(preload)
                }
            }
        }

        // Injected WebStoreScript (main frame only)
        let userScript = WKUserScript(
            source: WebStoreScript.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(userScript)
        userContentController.add(context.coordinator, name: "waystationHandler")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Use modern desktop Chrome User-Agent so Chrome Web Store renders native desktop extension detail pages
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        context.coordinator.setupObservers(for: webView)

        // Initial load
        let initialURL = URL(string: viewModel.currentURLString) ?? StoreViewModel.homeURL
        context.coordinator.lastLoadedURL = initialURL
        let request = URLRequest(url: initialURL)
        webView.load(request)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let action = viewModel.navigationAction,
              context.coordinator.lastHandledActionId != action.id else {
            return
        }

        // Mark this action as handled to prevent secondary render loops
        context.coordinator.lastHandledActionId = action.id

        switch action.kind {
        case .load(let url):
            if context.coordinator.lastLoadedURL != url {
                context.coordinator.lastLoadedURL = url
                webView.load(URLRequest(url: url))
            }
        case .goBack:
            if webView.canGoBack {
                webView.goBack()
            }
        case .goForward:
            if webView.canGoForward {
                webView.goForward()
            }
        case .reload:
            webView.reload()
        case .stopLoading:
            webView.stopLoading()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var viewModel: StoreViewModel
        var lastLoadedURL: URL?
        var lastHandledActionId: UUID?
        private var observations: [NSKeyValueObservation] = []

        init(viewModel: StoreViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "waystationHandler",
                  let body = message.body as? [String: Any],
                  let extensionId = body["extensionId"] as? String,
                  let title = body["title"] as? String,
                  let urlString = body["url"] as? String,
                  let storeURL = URL(string: urlString) else {
                return
            }

            do {
                let payload = try StoreExtensionPayload(extensionId: extensionId, title: title, storeURL: storeURL)
                Task { @MainActor in
                    self.viewModel.handleAddToSafari(payload: payload)
                }
            } catch {
                Task { @MainActor in
                    self.viewModel.downloadErrorMessage = error.localizedDescription
                }
            }
        }

        func injectInstalledExtensions(into webView: WKWebView) async {
            guard let installed = try? await ExtensionRegistry.shared.loadAll() else { return }
            let names = installed.map { $0.name }
            let ids = installed.map { $0.id }
            if let jsonData = try? JSONSerialization.data(withJSONObject: ["names": names, "ids": ids]),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let injection = "window.__waystationInstalled = \(jsonString); if (typeof window.__waystationUpdateButtons === 'function') { window.__waystationUpdateButtons(); }"
                webView.evaluateJavaScript(injection, completionHandler: nil)
            }
        }

        func setupObservers(for webView: WKWebView) {
            observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.viewModel.updateState(
                        url: view.url,
                        title: view.title,
                        canGoBack: view.canGoBack,
                        canGoForward: view.canGoForward,
                        isLoading: view.isLoading,
                        progress: view.estimatedProgress
                    )
                }
            })

            observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.viewModel.updateState(
                        url: view.url,
                        title: view.title,
                        canGoBack: view.canGoBack,
                        canGoForward: view.canGoForward,
                        isLoading: view.isLoading,
                        progress: view.estimatedProgress
                    )
                }
            })

            observations.append(webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.viewModel.updateState(
                        url: view.url,
                        title: view.title,
                        canGoBack: view.canGoBack,
                        canGoForward: view.canGoForward,
                        isLoading: view.isLoading,
                        progress: view.estimatedProgress
                    )
                }
            })

            observations.append(webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.viewModel.updateState(
                        url: view.url,
                        title: view.title,
                        canGoBack: view.canGoBack,
                        canGoForward: view.canGoForward,
                        isLoading: view.isLoading,
                        progress: view.estimatedProgress
                    )
                    await self.injectInstalledExtensions(into: view)
                }
            })

            observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.estimatedProgress = view.estimatedProgress
                }
            })

            observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.isLoading = view.isLoading
                }
            })
        }

        private func isInternalStoreOrGoogleHost(_ host: String) -> Bool {
            let lower = host.lowercased()
            return lower == "chromewebstore.google.com" ||
                   lower == "chrome.google.com" ||
                   lower.hasSuffix(".google.com") ||
                   lower.hasSuffix(".googleapis.com") ||
                   lower.hasSuffix(".gstatic.com") ||
                   lower.hasSuffix(".googleusercontent.com")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Always allow about:blank or internal custom schemes
            if url.scheme == "about" || url.scheme == "data" {
                decisionHandler(.allow)
                return
            }

            // If it's a Chrome Web Store internal or Google auth URL, load inside WKWebView
            if let host = url.host, isInternalStoreOrGoogleHost(host) {
                decisionHandler(.allow)
                return
            }

            // Otherwise, open external links (developer websites, privacy policies, etc.) in the user's default browser
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
