import SwiftUI

/// Main view for Tab 3: Installed Extensions Library.
/// Conforms to Story 3.1, Story 3.2, and Story 3.3 acceptance criteria.
@MainActor
public struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    public var onExploreStore: (() -> Void)?

    public init(
        viewModel: LibraryViewModel,
        onExploreStore: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onExploreStore = onExploreStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar with Search and Re-sign action
            headerBar

            Divider()

            // Main Content Area
            if viewModel.isLoading && viewModel.extensions.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading installed extensions...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.extensions.isEmpty {
                emptyStateView
            } else {
                extensionListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.loadExtensions()
        }
        .confirmationDialog(
            "Uninstall \(viewModel.extensionToUninstall?.name ?? "Extension")?",
            isPresented: $viewModel.showUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                Task {
                    await viewModel.confirmUninstall()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.extensionToUninstall = nil
            }
        } message: {
            if let ext = viewModel.extensionToUninstall {
                Text("This will delete the container app '\(ext.name).app' from disk and remove it from your installed extensions.")
            }
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            if let err = viewModel.errorMessage {
                Text(err)
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search installed extensions...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
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
            .frame(maxWidth: 320)

            Spacer()

            // Extension count badge
            Text("\(viewModel.extensions.count) extension\(viewModel.extensions.count == 1 ? "" : "s") installed")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Re-sign All button (Story 3.2)
            Button {
                Task {
                    await viewModel.reSignAll()
                }
            } label: {
                if viewModel.isResigningAll {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.resigningExtensionName ?? "Re-signing...")
                    }
                } else {
                    Label("Re-sign All", systemImage: "signature")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(viewModel.extensions.isEmpty || viewModel.isResigningAll)
            .help("Re-sign all installed extensions to reset the 7-day personal certificate")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary.opacity(0.6))

            VStack(spacing: 6) {
                Text("No Extensions Installed Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Browse the Chrome Web Store or drop an extension file to install it into Safari.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if let onExploreStore = onExploreStore {
                Button {
                    onExploreStore()
                } label: {
                    Label("Explore Web Store", systemImage: "globe")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var extensionListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredExtensions) { ext in
                    ExtensionRowView(
                        ext: ext,
                        onReveal: {
                            viewModel.revealInFinder(ext)
                        },
                        onUninstall: {
                            viewModel.requestUninstall(ext)
                        }
                    )
                }
            }
            .padding(16)
        }
    }
}
