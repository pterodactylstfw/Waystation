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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var viewModel: StoreViewModel
        private var observations: [NSKeyValueObservation] = []

        init(viewModel: StoreViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        func setupObservers(for webView: WKWebView) {
            observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.canGoBack = view.canGoBack
                }
            })

            observations.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    self?.viewModel.canGoForward = view.canGoForward
                }
            })

            observations.append(webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    if let title = view.title {
                        self?.viewModel.pageTitle = title
                    }
                }
            })

            observations.append(webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in
                    if let url = view.url {
                        self?.viewModel.currentURLString = url.absoluteString
                        self?.viewModel.inputURLString = url.absoluteString
                    }
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
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
                if let url = webView.url {
                    viewModel.currentURLString = url.absoluteString
                }
            }
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
