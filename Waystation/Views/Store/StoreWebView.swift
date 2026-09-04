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

        // Content controller with injected WebStoreScript
        let userContentController = WKUserContentController()
        let userScript = WKUserScript(
            source: WebStoreScript.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(userScript)
        userContentController.add(context.coordinator, name: "waystationHandler")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Use desktop Chrome User-Agent so Chrome Web Store renders native desktop extension detail pages
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

        context.coordinator.setupObservers(for: webView)

        // Initial load
        let initialURL = URL(string: viewModel.currentURLString) ?? StoreViewModel.homeURL
        let request = URLRequest(url: initialURL)
        webView.load(request)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let action = viewModel.navigationAction else { return }

        switch action {
        case .load(let url):
            if webView.url != url {
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

        DispatchQueue.main.async {
            self.viewModel.navigationAction = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var viewModel: StoreViewModel
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

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            Task { @MainActor in
                viewModel.isLoading = false
            }
        }

        // Handle target="_blank" links within the same webview
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
