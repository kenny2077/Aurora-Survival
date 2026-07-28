import SwiftUI

@main
struct AuroraApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .tint(Color("SignalOrange"))
                .task {
                    await appModel.refreshActivePacks()
                }
        }
    }
}
