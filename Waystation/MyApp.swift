import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupIcons()

        // Handle background launchd invocation for silent auto-re-signing
        if CommandLine.arguments.contains("--headless-resign") {
            Task {
                print("[Waystation Daemon] Initiating background auto-resign...")
                do {
                    let updated = try await SigningManager.shared.reSignAll { current, total, name in
                        print("[Waystation Daemon] [\(current)/\(total)] Re-signed \(name)")
                    }
                    print("[Waystation Daemon] Successfully refreshed \(updated.count) extension certificates.")
                } catch {
                    print("[Waystation Daemon] Auto-resign failed: \(error.localizedDescription)")
                }
                exit(0)
            }
        }
    }

    func setupIcons() {
        let icon = NSImage(named: "AppIcon")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }

        if let icon = icon {
            NSApplication.shared.applicationIconImage = icon
            for window in NSApplication.shared.windows {
                window.miniwindowImage = icon
            }
        }
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var settings = AppSettings.shared

    init() {
        if let icon = NSImage(named: "AppIcon")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap({ NSImage(contentsOf: $0) }) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(settings.theme.colorScheme)
                .task {
                    // Keep background launch agent path synced if app was moved or settings enabled
                    await LaunchdManager.shared.syncWithSettings(
                        enabled: AppSettings.shared.autoResignEnabled,
                        intervalDays: AppSettings.shared.autoResignIntervalDays
                    )
                }
                .task {
                    // Ensure window miniwindow icons match AppIcon smoothly without blocking main thread
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if let icon = NSApplication.shared.applicationIconImage {
                        for window in NSApplication.shared.windows {
                            window.miniwindowImage = icon
                        }
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1050, height: 720)
        .commands {
            CommandMenu("Extensions") {
                Button("Re-sign All Extensions") {
                    Task {
                        _ = try? await SigningManager.shared.reSignAll()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button("Waystation Guide & Setup") {
                    NotificationCenter.default.post(name: .showHelpGuide, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
