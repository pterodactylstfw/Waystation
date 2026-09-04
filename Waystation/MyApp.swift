import SwiftUI
import AppKit

@main
struct MyApp: App {
    init() {
        // Guarantee the custom Dock icon displays with transparent squircle background
        if let transparentIcon = NSImage(contentsOfFile: "/Users/raulconstantin/Projects/Waystation/AppIcon_transparent.png") {
            NSApplication.shared.applicationIconImage = transparentIcon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1050, height: 720)
    }
}
