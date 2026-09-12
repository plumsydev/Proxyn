import SwiftUI

@main
struct ProxynApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
                .preferredColorScheme(model.preferredColorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.resume() }
            case .background:
                model.suspend()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
