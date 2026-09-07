import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupIcons()
    }

    func setupIcons() {
        let icon = NSImage(named: "AppIcon")
            ?? NSImage(contentsOfFile: "/Users/raulconstantin/Projects/Waystation/AppIcon_transparent.png")
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
        // Guarantee the custom Dock icon displays with transparent squircle background
        if let transparentIcon = NSImage(contentsOfFile: "/Users/raulconstantin/Projects/Waystation/AppIcon_transparent.png") {
            NSApplication.shared.applicationIconImage = transparentIcon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        }

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

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(settings.theme.colorScheme)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let icon = NSApplication.shared.applicationIconImage {
                            for window in NSApplication.shared.windows {
                                window.miniwindowImage = icon
                            }
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
        }

        Settings {
            SettingsView()
                .preferredColorScheme(settings.theme.colorScheme)
        }
    }
}
