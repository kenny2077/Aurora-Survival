import SwiftUI
import UIKit

enum AppTab: String, Hashable {
    case ask
    case manual
    case maps
    case tools
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                ZStack {
                    if horizontalSizeClass == .regular {
                        tabs
                            .tabViewStyle(.tabBarOnly)
                    } else {
                        tabs
                    }
#if DEBUG
                    if let status = model.debugPhysicalStatus {
                        PhysicalBenchmarkOverlay(status: status) {
                            model.stopDebugPhysicalBenchmark()
                        }
                    }
#endif
                }
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshPhotoAuthorizationStatus()
            } else {
                model.unloadSpeciesClassifier()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )) { _ in
            Task { await model.handleRuntimePressure() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification
        )) { _ in
            let state = ProcessInfo.processInfo.thermalState
            guard state == .serious || state == .critical else { return }
            Task { await model.handleRuntimePressure() }
        }
    }

    private var tabs: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { ChatView() }
                .tabItem { Label("Ask", systemImage: "message.fill") }
                .tag(AppTab.ask)

            NavigationStack(path: $model.manualPath) { GuideLibraryView() }
                .tabItem { Label("Manual", systemImage: "books.vertical.fill") }
                .tag(AppTab.manual)

            NavigationStack { MapPackView() }
                .tabItem { Label("Maps", systemImage: "map.fill") }
                .tag(AppTab.maps)

            NavigationStack { ToolsView() }
                .tabItem { Label("Tools", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.tools)
        }
    }
}

#if DEBUG
private struct PhysicalBenchmarkOverlay: View {
    let status: PhysicalBenchmarkStatus
    let stop: () -> Void

    var body: some View {
        VStack(spacing: AuroraDesign.Space.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Aurora Expert validation")
                .font(.title2.weight(.semibold))
            Text(status.phase.capitalized)
                .foregroundStyle(.secondary)
            if status.totalCases > 0 {
                ProgressView(
                    value: Double(status.completedCases),
                    total: Double(status.totalCases)
                )
                Text("Case \(min(status.completedCases + 1, status.totalCases)) of \(status.totalCases)")
                    .font(.subheadline.monospacedDigit())
            }
            Grid(horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow { Text("Thermal"); Text(status.thermal.rawValue.capitalized) }
                GridRow { Text("Battery"); Text(status.batteryLevel.formatted(.percent)) }
                if let memory = status.availableMemoryBytes {
                    GridRow { Text("Memory free"); Text(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory)) }
                }
                if let seconds = status.cooldownSecondsRemaining {
                    GridRow { Text("Cooldown"); Text("\(seconds)s") }
                }
            }
            .font(.subheadline)
            Button("Stop validation", role: .destructive, action: stop)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
        }
        .padding(AuroraDesign.Space.xl)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AuroraDesign.Radius.prominent))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).opacity(0.96))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("expert.physical.status")
    }
}
#endif
