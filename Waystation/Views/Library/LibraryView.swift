import SwiftUI

/// Tab 3 View: Displays the persistent library of installed Safari Web Extensions.
/// Conforms to macOS 26/27 Liquid Glass design principles.
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
            // Header Bar with Search, Status Chip, and Actions
            headerBar

            Divider()

            // Floating Attention Alert (only shown when Safari is closed or action is needed)
            safariAttentionCard

            // Modern Tactile Persistence Tip Card
            if !viewModel.extensions.isEmpty && showPersistenceTip {
                persistenceTipCard
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

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Search Field with Translucent Glass Fill
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .frame(maxWidth: 300)

            Spacer()

            // Safari Active Status Pill (when completely healthy and operational)
            if let safari = viewModel.safariStatus, safari.unsignedStatus == .enabled {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.green.opacity(0.8), radius: 4)

                    Text("Safari Active")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    Button {
                        Task {
                            await viewModel.checkSafariHealth()
                            await viewModel.verifyAllSignatures()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Safari status")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }

            // Open Safari Action
            Button {
                Task {
                    await SafariAutomationService.shared.launchSafariAndPrepare(
                        autoToggleDevelopOption: true
                    )
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await viewModel.checkSafariHealth()
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
        .background(.ultraThinMaterial)
    }

    // MARK: - Floating Attention Card (Only when Safari needs attention)
    @ViewBuilder
    private var safariAttentionCard: some View {
        if let safari = viewModel.safariStatus, safari.unsignedStatus != .enabled {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(statusColor(safari.unsignedStatus).opacity(0.2))
                        .frame(width: 34, height: 34)

                    Image(systemName: statusIcon(safari.unsignedStatus))
                        .font(.system(size: 16))
                        .foregroundStyle(statusColor(safari.unsignedStatus))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(safari.unsignedStatus))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(statusSubtitle(safari.unsignedStatus))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let buttonInfo = statusAction(safari.unsignedStatus) {
                    Button(buttonInfo.title) {
                        buttonInfo.action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    Task {
                        await viewModel.checkSafariHealth()
                        await viewModel.verifyAllSignatures()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 14, intensity: .prominent, tintColor: statusColor(safari.unsignedStatus))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: - Persistence Tip Card
    private var persistenceTipCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 6) {
                Text("Tip: Keep extensions active permanently by closing tabs with")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                KeyCapView("⌘ W")

                Text("instead of quitting with")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                KeyCapView("⌘ Q")
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showPersistenceTip = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss tip")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 12, intensity: .subtle, tintColor: Color.accentColor)
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
                        signatureStatus: viewModel.signatureStatuses[ext.id],
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
        .background(Color.clear)
    }

    // MARK: - Attention Helpers
    private func statusColor(_ status: SafariUnsignedStatus) -> Color {
        switch status {
        case .enabled: return .green
        case .disabled: return .orange
        case .safariNotRunning: return .secondary
        case .developMenuMissing, .accessibilityRequired: return .orange
        case .unknown: return .secondary
        }
    }

    private func statusIcon(_ status: SafariUnsignedStatus) -> String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        case .disabled: return "exclamationmark.triangle.fill"
        case .safariNotRunning: return "safari"
        case .developMenuMissing: return "wrench.and.screwdriver"
        case .accessibilityRequired: return "hand.raised.fill"
        case .unknown: return "info.circle"
        }
    }

    private func statusTitle(_ status: SafariUnsignedStatus) -> String {
        switch status {
        case .enabled: return "Safari is Active"
        case .disabled: return "Allow Unsigned Extensions is OFF"
        case .safariNotRunning: return "Safari is Closed (Setting Reset)"
        case .developMenuMissing: return "Develop Menu Not Enabled"
        case .accessibilityRequired: return "Accessibility Permission Needed"
        case .unknown(let msg): return msg
        }
    }

    private func statusSubtitle(_ status: SafariUnsignedStatus) -> String {
        switch status {
        case .enabled: return "Extensions are registered and running."
        case .disabled: return "Apple turns off unsigned extensions on every Safari restart. Click 'Enable in Safari' to turn it on."
        case .safariNotRunning: return "Quitting Safari (⌘Q) unchecks 'Allow Unsigned Extensions'. Launch Safari and re-enable it to run extensions."
        case .developMenuMissing: return "Check 'Show features for web developers' in Safari Settings > Advanced."
        case .accessibilityRequired: return "Waystation requires accessibility permission to detect developer menu status."
        case .unknown: return "Unable to verify current Safari extension configuration."
        }
    }

    private struct StatusAction {
        let title: String
        let action: () -> Void
    }

    private func statusAction(_ status: SafariUnsignedStatus) -> StatusAction? {
        switch status {
        case .disabled:
            return StatusAction(title: "Enable in Safari") {
                Task {
                    await viewModel.toggleSafariUnsignedExtensions()
                }
            }
        case .safariNotRunning:
            return StatusAction(title: "Launch & Enable") {
                Task {
                    await SafariAutomationService.shared.launchSafariAndPrepare(
                        autoToggleDevelopOption: true
                    )
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await viewModel.checkSafariHealth()
                }
            }
        case .accessibilityRequired:
            return StatusAction(title: "Grant Permission") {
                SafariAutomationService.shared.requestAccessibilityPermission()
            }
        default:
            return nil
        }
    }
}
