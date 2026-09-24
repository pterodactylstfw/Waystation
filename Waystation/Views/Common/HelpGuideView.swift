import SwiftUI

/// Interactive Help & Safari Setup Guide sheet.
/// Explains Safari developer settings, the ⌘W persistence rule, and automated 7-day certificate renewals.
public struct HelpGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: GuideSection = .setup

    public init() {}

    public enum GuideSection: String, CaseIterable, Identifiable {
        case setup = "Safari Setup"
        case persistence = "Staying Active (⌘W)"
        case signing = "7-Day Auto-Renewal"
        case tips = "Tips & Troubleshooting"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .setup: return "safari"
            case .persistence: return "clock.arrow.2.circlepath"
            case .signing: return "checkmark.seal.fill"
            case .tips: return "lightbulb.fill"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Waystation Guide & Setup")
                        .font(.headline)
                    Text("Everything you need to know about running Chrome extensions in Safari")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Segmented Picker
            Picker("", selection: $selectedSection) {
                ForEach(GuideSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.iconName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

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
            HStack {
                Button {
                    Task {
                        await SafariAutomationService.shared.launchSafariAndPrepare()
                    }
                } label: {
                    Label("Launch Safari Now", systemImage: "safari")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Got it, Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 680, height: 540)
    }

    // MARK: - Section 1: Safari Setup
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            guideCard(
                step: "1",
                title: "Enable the Develop Menu in Safari",
                description: "Safari hides developer features by default. Open Safari, press ⌘, to open Settings, switch to the 'Advanced' tab, and check 'Show features for web developers' (or 'Show Develop menu in menu bar').",
                symbol: "gearshape.2.fill"
            )

            guideCard(
                step: "2",
                title: "Allow Unsigned Extensions",
                description: "In Safari's top menu bar, click Develop → Allow Unsigned Extensions. When prompted by macOS, enter your Mac's administrator password.",
                symbol: "lock.open.fill"
            )

            guideCard(
                step: "3",
                title: "Enable Extensions in Safari Settings",
                description: "Open Safari Settings (⌘,) → Extensions. Check the box next to your newly converted extension. You can also grant permissions per website here.",
                symbol: "puzzlepiece.extension.fill"
            )
        }
    }

    // MARK: - Section 2: Persistence (⌘W vs ⌘Q)
    private var persistenceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("The Apple Safari Security Quirk")
                        .font(.headline)
                    Text("For security reasons, Apple automatically resets the 'Allow Unsigned Extensions' setting when Safari is fully terminated with ⌘Q.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                Text("How to keep extensions running permanently:")
                    .font(.headline)

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("❌ Quit with ⌘Q")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                        }
                        Text("Terminates the Safari process and resets the developer toggle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("✅ Close with ⌘W / Red dot")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                        }
                        Text("Closes windows while keeping Safari active in the background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text("Because modern macOS suspends background apps efficiently, leaving Safari running in your Dock uses practically zero CPU or battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Section 3: 7-Day Auto-Renewal
    private var signingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Automatic 7-Day Certificate Management")
                        .font(.headline)
                    Text("Free Apple Developer certificates expire after 7 days. Waystation automates this so you never have to think about it.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background launchd Daemon")
                            .font(.subheadline.bold())
                        Text("Waystation installs a silent user daemon that runs in the background and checks your certificates daily.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Silent Re-signing")
                            .font(.subheadline.bold())
                        Text("When an extension reaches 6 days of age, the daemon automatically re-signs it with your Apple ID before expiration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual Re-sign Shortcut (⌘R)")
                            .font(.subheadline.bold())
                        Text("You can also press ⌘R anytime in Waystation to batch re-sign all installed extensions instantly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Section 4: Tips & Troubleshooting
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            faqItem(
                question: "Which extensions work best?",
                answer: "Most popular WebExtensions (like Dark Reader, SponsorBlock, YouTube Dislike, userscript runners) work flawlessly. Extensions requiring Chrome-exclusive APIs (like chrome.debugger or side panels) will display a compatibility notice before conversion."
            )

            faqItem(
                question: "Where are converted extensions stored?",
                answer: "In '~/Library/Application Support/Waystation/Extensions/'. They run as standalone native container apps signed with your personal identity."
            )

            faqItem(
                question: "How do I completely remove an extension?",
                answer: "Go to the Library tab in Waystation and click the red trash icon. Waystation cleanly unregisters the extension from macOS LaunchServices and deletes the app bundle."
            )
        }
    }

    // MARK: - Helper Views
    private func guideCard(step: String, title: String, description: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(step)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.subheadline.bold())
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
