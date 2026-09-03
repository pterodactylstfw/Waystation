import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1050, height: 720)
    }
}
