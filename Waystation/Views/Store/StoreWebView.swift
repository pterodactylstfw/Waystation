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
        guard let action = viewModel.navigationAction else { return }

        // Clear action on next tick so state isn't mutated synchronously during render
        DispatchQueue.main.async {
            self.viewModel.navigationAction = nil
        }

        switch action {
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
                  let storeURL = URL(string: urlString),
                  let payload = StoreExtensionPayload(extensionId: extensionId, title: title, storeURL: storeURL) else {
                return
            }

            Task { @MainActor in
                self.viewModel.handleAddToSafari(payload: payload)
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Handle target="_blank" links within the same webview
            if navigationAction.targetFrame == nil {
                if let url = navigationAction.request.url {
                    lastLoadedURL = url
                    webView.load(URLRequest(url: url))
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastLoadedURL = webView.url
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.updateState(
                    url: webView.url,
                    title: webView.title,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward,
                    isLoading: false,
                    progress: 1.0
                )

                await self.injectInstalledExtensions(into: webView)
            }
            // Re-evaluate script to ensure dynamic injection kicks in
            webView.evaluateJavaScript(WebStoreScript.scriptSource, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // Ignore NSURLErrorCancelled (-999) when user navigates or redirects
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            Task { @MainActor in
                viewModel.isLoading = false
            }
        }

        // Handle target="_blank" links / window.open within the same webview
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, url.absoluteString != "about:blank" {
                lastLoadedURL = url
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
