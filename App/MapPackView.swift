import SwiftUI

struct MapPackView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedMapID = ""

    private var selectedMap: ResolvedOfflineMap? {
        model.offlineMaps.first { $0.id == selectedMapID }
            ?? model.offlineMaps.first { $0.id.contains("twin-cities") }
            ?? model.offlineMaps.first
    }

    var body: some View {
        Group {
            if let selectedMap {
                OfflineMapDetailView(
                    map: selectedMap,
                    availableMaps: model.offlineMaps,
                    selectedMapID: $selectedMapID
                )
            } else {
                DownloadCenterView(
                    kindFilter: .map,
                    showsCatalogConnection: false
                )
            }
        }
        .navigationTitle("Offline Maps")
        .toolbar {
            if !model.offlineMaps.isEmpty {
                NavigationLink {
                    DownloadCenterView(
                        kindFilter: .map,
                        showsCatalogConnection: false
                    )
                } label: {
                    Label("Manage map downloads", systemImage: "arrow.down.circle")
                }
            }
        }
        .onAppear {
            if selectedMapID.isEmpty {
                selectedMapID = selectedMap?.id ?? ""
            }
        }
        .onChange(of: model.offlineMaps.map(\.id)) { _, identifiers in
            if !identifiers.contains(selectedMapID) {
                selectedMapID = selectedMap?.id ?? ""
            }
        }
    }
}
