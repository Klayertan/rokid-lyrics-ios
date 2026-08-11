import SwiftUI

struct RootTabView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                HomeView(model: model)
            }
            .tabItem { Label("Home", systemImage: "waveform") }
            .tag(AppTab.home)

            NavigationStack {
                NowPlayingView(model: model)
            }
            .tabItem { Label("Lyrics", systemImage: "quote.bubble") }
            .tag(AppTab.nowPlaying)

            NavigationStack {
                ConnectionView(model: model)
            }
            .tabItem { Label("Rokid", systemImage: "eyeglasses") }
            .tag(AppTab.connection)

            NavigationStack {
                SearchView(model: model)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(AppTab.search)

            NavigationStack {
                SettingsView(model: model)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .tint(.mint)
    }
}
