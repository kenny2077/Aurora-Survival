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

            NavigationStack { DownloadCenterView() }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }

            NavigationStack { SystemStatusView() }
                .tabItem { Label("Status", systemImage: "shield.lefthalf.filled") }
        }
    }
}
