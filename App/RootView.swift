import SwiftUI

enum AppTab: String, Hashable {
    case ask
    case manual
    case maps
    case tools
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    var body: some View {
        if #available(iOS 18.0, *), horizontalSizeClass == .regular {
            tabs
                .tabViewStyle(.tabBarOnly)
        } else {
            tabs
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
