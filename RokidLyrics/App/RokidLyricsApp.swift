import SwiftUI

@main
struct RokidLyricsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView(model: model)
                .task { await model.bootstrap() }
                .onOpenURL { url in model.handleRokidOpenURL(url) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.consumeSharedDraft() }
                }
        }
    }
}
