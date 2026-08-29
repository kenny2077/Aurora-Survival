import SwiftUI
import UIKit

final class AuroraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundURLSessionPackageTransport.handleEvents(
            for: identifier,
            completionHandler: completionHandler
        )
    }
}

@main
struct AuroraApp: App {
    @UIApplicationDelegateAdaptor(AuroraAppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .tint(Color.accentColor)
                .task {
                    await appModel.restoreBackgroundDownloads()
                    await appModel.refreshActivePacks()
                    await appModel.loadDebugOCRFixtureIfPresent()
                    appModel.resetDebugOnboardingIfRequested()
                    await appModel.installDebugPackagesOnlyIfRequested()
                    await appModel.runDebugPhysicalInferenceIfRequested()
                }
        }
    }
}
