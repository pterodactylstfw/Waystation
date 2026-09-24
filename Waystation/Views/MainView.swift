import SwiftUI

/// Main container view coordinating the 3-tab layout, Doctor environment banner, and live log drawer.
/// Styled with macOS 26/27 Liquid Glass translucent ambient materials.
public struct MainView: View {
    @State private var appState = AppState()

    public init() {}

    public var body: some View {
        ZStack {
            LiquidAmbientBackground()

            VStack(spacing: 0) {
                DoctorBannerView(appState: appState)

                TabView(selection: $appState.selectedTab) {
                    StoreView(
                        logDrawerViewModel: appState.logDrawerViewModel,
                        onTriggerPipeline: { crxURL in
                            await appState.triggerConversionPipeline(for: crxURL)
                        }
                    )
                    .tabItem {
                        Label(AppTab.store.rawValue, systemImage: AppTab.store.iconName)
                    }
                    .tag(AppTab.store)

                    DropZoneView(viewModel: appState.dropZoneViewModel)
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
            await appState.checkEnvironment()
        }
    }
}
