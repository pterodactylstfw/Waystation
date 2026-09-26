import SwiftUI

/// Main container view coordinating the 3-tab layout, Doctor environment banner, and live log drawer.
/// Conforms to AD-1 and integrates Story 1.1, Story 1.4, Story 2.1, and Story 3.1.
public struct MainView: View {
    @State private var appState = AppState()

    public init() {}

    public var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(spacing: 0) {
                DoctorBannerView(appState: appState)

                TabView(selection: $appState.selectedTab) {
                    StoreView(viewModel: appState.storeViewModel)
                        .tabItem {
                            Label(AppTab.store.rawValue, systemImage: AppTab.store.iconName)
                        }
                        .tag(AppTab.store)

                    DropZoneView(
                        viewModel: appState.dropZoneViewModel,
                        onGoToLibrary: {
                            appState.selectedTab = .library
                        }
                    )
                        .tabItem {
                            Label(AppTab.dropZone.rawValue, systemImage: AppTab.dropZone.iconName)
                        }
                        .tag(AppTab.dropZone)

                    LibraryView(
                        viewModel: appState.libraryViewModel,
                        onExploreStore: {
                            appState.selectedTab = .store
                        }
                    )
                    .tabItem {
                        Label(AppTab.library.rawValue, systemImage: AppTab.library.iconName)
                    }
                    .tag(AppTab.library)
                }

                // Live Log Drawer pinned to bottom (Story 1.4 / AD-1)
                LogDrawerView(viewModel: appState.logDrawerViewModel)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.showHelpGuide = true
                } label: {
                    Label("Help & Guide", systemImage: "questionmark.circle")
                }
                .help("Open Safari Setup & Persistence Guide (⌘/)")
            }
        }
        .sheet(isPresented: $appState.showHelpGuide) {
            HelpGuideView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelpGuide)) { _ in
            appState.showHelpGuide = true
        }
        .task {
            // Verify developer environment when launching the app
            await appState.checkEnvironment()
        }
    }
}
