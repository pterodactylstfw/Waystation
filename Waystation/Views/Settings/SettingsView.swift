import SwiftUI

/// Settings and preferences window for Waystation.
/// Conforms to macOS Human Interface Guidelines and AD-1.
public struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var detectedIdentity: String = "Detecting..."
    @State private var isAgentActive: Bool = false
    @State private var isAccessibilityGranted: Bool = false

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            signingTab
                .tabItem {
                    Label("Code Signing", systemImage: "signature")
                }

            safariTab
                .tabItem {
                    Label("Safari Setup & Persistence", systemImage: "safari")
                }
        }
        .frame(width: 560, height: 440)
        .padding(20)
        .task {
            let identity = await SigningManager.shared.detectSigningIdentity()
            self.detectedIdentity = identity == "-" ? "Ad-hoc (No developer certificate)" : identity
            if settings.autoResignEnabled {
                _ = await LaunchdManager.shared.installAgent(intervalDays: settings.autoResignIntervalDays)
            }
            self.isAgentActive = await LaunchdManager.shared.isAgentInstalled()
            self.isAccessibilityGranted = SafariAutomationService.shared.isAccessibilityGranted()
        }
        .onChange(of: settings.autoResignEnabled) { _, isEnabled in
            Task {
                if isEnabled {
                    _ = await LaunchdManager.shared.installAgent(intervalDays: settings.autoResignIntervalDays)
                } else {
                    await LaunchdManager.shared.uninstallAgent()
                }
                self.isAgentActive = await LaunchdManager.shared.isAgentInstalled()
            }
        }
        .onChange(of: settings.autoResignIntervalDays) { _, newInterval in
            Task {
                if settings.autoResignEnabled {
                    _ = await LaunchdManager.shared.installAgent(intervalDays: newInterval)
                    self.isAgentActive = await LaunchdManager.shared.isAgentInstalled()
                }
            }
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                Picker("Appearance:", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)

                Toggle("Open container app automatically after conversion", isOn: $settings.autoOpenSafariOnInstall)
                    .help("Launches the generated container app once so Safari registers the extension.")
            } header: {
                Text("Appearance & Behavior")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Code Signing Tab
    private var signingTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detected Developer Identity:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.green)
                        Text(detectedIdentity)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Toggle("Enable Background Auto-Resigning (launchd)", isOn: $settings.autoResignEnabled)

                if settings.autoResignEnabled {
                    Picker("Re-sign every:", selection: $settings.autoResignIntervalDays) {
                        Text("3 days").tag(3)
                        Text("5 days (Recommended)").tag(5)
                        Text("6 days").tag(6)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(isAgentActive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isAgentActive ? "macOS LaunchAgent active in background" : "LaunchAgent initializing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            } header: {
                Text("Automatic 7-Day Certificate Renewal")
                    .font(.headline)
            } footer: {
                Text("Free Apple IDs sign binaries with a 7-day expiration. When enabled, Waystation automatically refreshes certificates in the background so your extensions never stop working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Safari Setup Tab
    private var safariTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Why does Safari reset 'Allow Unsigned Extensions'?")
                    .font(.headline)

                Text("Apple's security policy requires free Apple ID certificates to be confirmed each session. When Safari quits completely (⌘Q), macOS turns off this toggle to protect against untrusted sideloaded software.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Best Practice Card
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best Practice: Keep Safari Running in Background")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Close Safari windows with ⌘W instead of quitting with ⌘Q. As long as Safari remains in memory (even through Mac Sleep), your extensions stay enabled indefinitely!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                Text("Experimental: Auto-Click 'Allow Unsigned Extensions'")
                    .font(.headline)

                Toggle("Attempt automatic menu click via Accessibility API on Safari launch", isOn: $settings.autoToggleSafariDevelopOption)
                    .font(.callout)

                HStack {
                    Circle()
                        .fill(isAccessibilityGranted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(isAccessibilityGranted ? "Accessibility Permission: Granted" : "Accessibility Permission: Needed for auto-click")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !isAccessibilityGranted {
                        Button("Grant Permission") {
                            SafariAutomationService.shared.requestAccessibilityPermission()
                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                self.isAccessibilityGranted = SafariAutomationService.shared.isAccessibilityGranted()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Divider()

                HStack {
                    Button(action: {
                        Task {
                            await SafariAutomationService.shared.launchSafariAndPrepare(
                                autoToggleDevelopOption: settings.autoToggleSafariDevelopOption
                            )
                        }
                    }) {
                        Label("Launch Safari & Prepare Extensions", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("Open Safari Settings") {
                        if let url = URL(string: "x-apple.systempreferences:") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
    }
}
