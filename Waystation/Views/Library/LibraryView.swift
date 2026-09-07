import SwiftUI

/// Tab 3 View: Displays the persistent library of installed Safari Web Extensions.
/// Conforms strictly to Story 3.1, Story 3.2, Story 3.3, and AD-1/HIG standards.
public struct LibraryView: View {
    @Bindable var viewModel: LibraryViewModel
    var onExploreStore: (() -> Void)?
    @State private var showPersistenceTip: Bool = true

    public init(
        viewModel: LibraryViewModel,
        onExploreStore: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onExploreStore = onExploreStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar with Search and Re-sign action
            headerBar

            Divider()

            if !viewModel.extensions.isEmpty && showPersistenceTip {
                persistenceTipBanner
                Divider()
            }

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

    private var persistenceTipBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)

            Text("Tip: Safari keeps unsigned extensions active until you quit with ⌘Q. Close tabs with ⌘W to keep extensions running continuously.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                showPersistenceTip = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.06))
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

            // Open Safari Action
            Button {
                Task {
                    await SafariAutomationService.shared.launchSafariAndPrepare(
                        autoToggleDevelopOption: AppSettings.shared.autoToggleSafariDevelopOption
                    )
                }
            } label: {
                Label("Open Safari", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Launches Safari and registers installed extension containers")

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

                Text("Convert extensions via the Drop Zone or install directly from the Chrome Web Store.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if let onExploreStore = onExploreStore {
                Button(action: onExploreStore) {
                    Label("Explore Web Store", systemImage: "bag")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 4)
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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }
}
