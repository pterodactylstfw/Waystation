import SwiftUI

/// Main container view coordinating the 3-tab layout, Doctor environment banner, and live log drawer.
public struct MainView: View {
    @State private var appState = AppState()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            DoctorBannerView(appState: appState)

            TabView(selection: $appState.selectedTab) {
                VStack {
                    Spacer()
                    Image(systemName: AppTab.store.iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Chrome Web Store")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 8)
                    Text("Coming in Epic 2: In-app browsing with 'Add to Safari' injection")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .tabItem {
                    Label(AppTab.store.rawValue, systemImage: AppTab.store.iconName)
                }
                .tag(AppTab.store)

                DropZoneView()
                    .tabItem {
                        Label(AppTab.dropZone.rawValue, systemImage: AppTab.dropZone.iconName)
                    }
                    .tag(AppTab.dropZone)

                VStack {
                    Spacer()
                    Image(systemName: AppTab.library.iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Installed Extensions Library")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top, 8)
                    Text("Coming in Epic 3: 7-day certificate countdown & batch re-signing")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .tabItem {
                    Label(AppTab.library.rawValue, systemImage: AppTab.library.iconName)
                }
                .tag(AppTab.library)
            }

            LogDrawerView(viewModel: appState.logDrawerViewModel)
        }
        .frame(minWidth: 900, minHeight: 620)
        .task {
            await appState.checkEnvironment()
        }
    }
}
