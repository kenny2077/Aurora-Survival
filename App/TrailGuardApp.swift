import SwiftUI

@main
struct TrailGuardApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .tint(Color("SignalOrange"))
                .task {
                    await appModel.refreshActivePacks()
                    await appModel.loadDebugOCRFixtureIfPresent()
                    await appModel.runDebugPhysicalInferenceIfRequested()
                }
        }
    }
}
