import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { ChatView() }
                .tabItem { Label("Ask", systemImage: "message.fill") }

            NavigationStack { GuideLibraryView() }
                .tabItem { Label("Guide", systemImage: "books.vertical.fill") }

            NavigationStack { ReadinessView() }
                .tabItem { Label("Ready", systemImage: "checklist") }

            NavigationStack { ModelSettingsView() }
                .tabItem { Label("Models", systemImage: "cpu.fill") }

            NavigationStack { SystemStatusView() }
                .tabItem { Label("Status", systemImage: "shield.lefthalf.filled") }
        }
    }
}
