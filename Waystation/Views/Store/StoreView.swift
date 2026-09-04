import SwiftUI

struct StoreView: View {
    @State private var viewModel = StoreViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack(spacing: 8) {
                // Navigation buttons
                HStack(spacing: 2) {
                    Button {
                        viewModel.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canGoBack)
                    .opacity(viewModel.canGoBack ? 1.0 : 0.35)
                    .frame(width: 28, height: 28)
                    .help("Back")

                    Button {
                        viewModel.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canGoForward)
                    .opacity(viewModel.canGoForward ? 1.0 : 0.35)
                    .frame(width: 28, height: 28)
                    .help("Forward")

                    Button {
                        if viewModel.isLoading {
                            viewModel.stopLoading()
                        } else {
                            viewModel.reload()
                        }
                    } label: {
                        Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .help(viewModel.isLoading ? "Stop Loading" : "Reload Page")

                    Button {
                        viewModel.goHome()
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .help("Chrome Web Store Home")
                }

                // Address & Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Search extensions or enter web address...", text: $viewModel.inputURLString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            viewModel.handleSubmit()
                        }

                    if !viewModel.inputURLString.isEmpty {
                        Button {
                            viewModel.inputURLString = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            // Loading Progress Bar
            if viewModel.isLoading {
                ProgressView(value: viewModel.estimatedProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
            } else {
                Divider()
            }

            // Embedded Web View
            StoreWebView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
