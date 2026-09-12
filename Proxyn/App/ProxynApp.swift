import SwiftUI

@main
struct ProxynApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Palette.ember)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.resumeLive() }
            case .background, .inactive:
                model.stopPolling()
            @unknown default:
                break
            }
        }
    }
}
