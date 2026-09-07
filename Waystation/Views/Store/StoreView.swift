import SwiftUI

struct StoreView: View {
    @State private var viewModel: StoreViewModel

    init(
        logDrawerViewModel: LogDrawerViewModel? = nil,
        onTriggerPipeline: ((URL) async -> Void)? = nil
    ) {
        _viewModel = State(initialValue: StoreViewModel(
            logDrawerViewModel: logDrawerViewModel,
            onTriggerPipeline: onTriggerPipeline
        ))
    }

    var body: some View {
        ZStack {
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

                // Embedded Web View with injected native "Add to Safari" button
                StoreWebView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Live Download Progress HUD overlay during CRX download
            if viewModel.isDownloading {
                VStack {
                    Spacer()
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Downloading \(viewModel.selectedExtension?.title ?? "Extension")...")
                                .font(.system(size: 13, weight: .semibold))

                            HStack(spacing: 8) {
                                ProgressView(value: viewModel.downloadProgress, total: 1.0)
                                    .progressViewStyle(.linear)
                                    .frame(width: 180)

                                Text("\(Int(viewModel.downloadProgress * 100))%")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isDownloading)
            }
        }
        .alert(
            "Add to Safari: \(viewModel.selectedExtension?.title ?? "Extension")",
            isPresented: $viewModel.showInstallConfirmation
        ) {
            Button("Convert & Install", role: .none) {
                if let ext = viewModel.selectedExtension {
                    Task {
                        await viewModel.startDownloadAndPipeline(payload: ext)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.selectedExtension = nil
            }
        } message: {
            if let ext = viewModel.selectedExtension {
                Text("Extension ID: \(ext.extensionId)\nWaystation will download the CRX package and automatically launch the Safari conversion pipeline.")
            }
        }
        .alert(
            "Download Failed",
            isPresented: Binding(
                get: { viewModel.downloadErrorMessage != nil },
                set: { if !$0 { viewModel.downloadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.downloadErrorMessage = nil
            }
        } message: {
            if let msg = viewModel.downloadErrorMessage {
                Text(msg)
            }
        }
    }
}
