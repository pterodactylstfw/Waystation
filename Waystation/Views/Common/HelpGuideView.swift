import SwiftUI

/// Interactive Help & Safari Setup Guide sheet.
/// Explains Safari developer settings, the ⌘W persistence rule, and automated 7-day certificate renewals.
/// Conforms to modern 2026 macOS Human Interface Guidelines.
public struct HelpGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: GuideSection = .setup

    public init() {}

    public enum GuideSection: String, CaseIterable, Identifiable {
        case setup = "Safari Setup"
        case persistence = "Staying Active (⌘W)"
        case signing = "7-Day Auto-Renewal"
        case tips = "FAQ & Tips"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .setup: return "safari.fill"
            case .persistence: return "clock.arrow.2.circlepath"
            case .signing: return "checkmark.seal.fill"
            case .tips: return "sparkles"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Hero Header Bar
            headerBar

            Divider()

            // Modern Pill Navigation Bar
            navigationBar

            Divider()

            // Content Body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedSection {
                    case .setup:
                        setupSection
                    case .persistence:
                        persistenceSection
                    case .signing:
                        signingSection
                    case .tips:
                        tipsSection
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer Actions
            footerBar
        }
        .frame(width: 720, height: 560)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 2)

                Image(systemName: "safari")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Waystation Guide & Workflow")
                    .font(.headline)
                    .fontWeight(.bold)

                Text("Everything you need to run Chrome extensions seamlessly on macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(spacing: 8) {
            ForEach(GuideSection.allCases) { section in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 12))
                        Text(section.rawValue)
                            .font(.system(size: 12, weight: selectedSection == section ? .semibold : .regular))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        selectedSection == section ?
                            Color.accentColor.opacity(0.15) :
                            Color.secondary.opacity(0.06)
                    )
                    .foregroundStyle(selectedSection == section ? Color.accentColor : Color.secondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                selectedSection == section ?
                                    Color.accentColor.opacity(0.3) :
                                    Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    // MARK: - Section 1: Safari Setup
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            guideCard(
                step: "1",
                badgeColor: .blue,
                title: "Enable Developer Features in Safari",
                description: "Open Safari, press ⌘, to open Settings, switch to the 'Advanced' tab, and check 'Show features for web developers'.",
                keycapShortcut: "⌘ ,",
                symbol: "gearshape.2.fill"
            )

            guideCard(
                step: "2",
                badgeColor: .orange,
                title: "Allow Unsigned Extensions (Safari 17+ / Sequoia)",
                description: "In Safari Settings → Developer tab, check 'Allow unsigned extensions' and authenticate with Touch ID or your Mac password.",
                symbol: "lock.open.fill",
                actionLabel: "Open Safari Settings",
                action: {
                    Task {
                        await SafariAutomationService.shared.openDeveloperSettings()
                    }
                }
            )

            guideCard(
                step: "3",
                badgeColor: .green,
                title: "Enable Your Extensions",
                description: "In Safari Settings → Extensions tab, enable each converted extension. You can also configure website permissions there.",
                symbol: "puzzlepiece.extension.fill"
            )
        }
    }

    // MARK: - Section 2: Persistence (⌘W vs ⌘Q)
    private var persistenceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Modern Alert Box
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 5) {
                    Text("The Apple Safari Security Rule")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("For security, Apple resets the 'Allow Unsigned Extensions' authorization whenever Safari is fully terminated with ⌘Q. It remains active as long as Safari stays running in memory.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )

            Text("Best practice for daily usage:")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                // Do Not Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Quit with")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        KeyCapView("⌘ Q")
                    }

                    Text("Terminates Safari completely. The next time you open Safari, macOS will require you to re-enable unsigned extensions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )

                // Recommended Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Close with")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        KeyCapView("⌘ W")
                    }

                    Text("Closes windows while Safari stays active in the background. Your extensions remain enabled indefinitely with 0% CPU overhead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.green.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Section 3: 7-Day Auto-Renewal
    private var signingSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Automated 7-Day Renewal Engine")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Free Apple Developer certificates expire after 7 days. Waystation automates renewals so you never have to think about expiration dates.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )

            VStack(spacing: 12) {
                featureRow(
                    icon: "gearshape.arrow.triangle.2.circlepath",
                    color: .purple,
                    title: "Silent Background launchd Agent",
                    description: "Waystation installs a lightweight native macOS launchd daemon (~/Library/LaunchAgents) that checks certificate health daily."
                )

                featureRow(
                    icon: "arrow.clockwise.circle.fill",
                    color: .blue,
                    title: "Proactive 6-Day Auto Re-sign",
                    description: "When an extension reaches 6 days of age, the daemon automatically re-signs the bundle with your local identity."
                )

                featureRow(
                    icon: "signature",
                    color: .teal,
                    title: "Instant Manual Batch Re-sign",
                    description: "Click 'Re-sign All' in the Library tab anytime to renew all installed extensions at once."
                )
            }
        }
    }

    // MARK: - Section 4: Tips & Troubleshooting
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            faqCard(
                question: "Which extensions work best?",
                answer: "Extensions like SponsorBlock, Return YouTube Dislike, Notion Web Clipper, Dark Reader, JSON viewers, and user script runners work wonderfully. Extensions requiring Chrome-exclusive APIs (like side panels or debugging) will trigger a compatibility advisory."
            )

            faqCard(
                question: "Where are converted extensions stored?",
                answer: "Inside '~/Library/Application Support/Waystation/Extensions/'. They run as native macOS container apps signed with your Mac's development identity."
            )

            faqCard(
                question: "How do I cleanly uninstall an extension?",
                answer: "Click the trash icon in Waystation's Library. Waystation cleanly unregisters the extension bundle from macOS LaunchServices and removes it from disk."
            )
        }
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            Button {
                Task {
                    await SafariAutomationService.shared.launchSafariAndPrepare()
                }
            } label: {
                Label("Launch Safari", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()

            Button("Got it, Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    // MARK: - UI Helpers
    private func guideCard(
        step: String,
        badgeColor: Color,
        title: String,
        description: String,
        keycapShortcut: String? = nil,
        symbol: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(badgeColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                Text(step)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(badgeColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(badgeColor)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let shortcut = keycapShortcut {
                        KeyCapView(shortcut)
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let label = actionLabel, let action = action {
                    Button(action: action) {
                        Text(label)
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    private func faqCard(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}
