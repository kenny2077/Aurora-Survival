import CoreLocation
import MapLibre
import SwiftUI

struct OfflineMapDetailView: View {
    let map: ResolvedOfflineMap
    let availableMaps: [ResolvedOfflineMap]
    @Binding var selectedMapID: String
    @State private var resetToken = UUID()
    @State private var preparedStyleURL: URL?
    @State private var preparationError: String?

    var body: some View {
        List {
            if availableMaps.count > 1 {
                Section("Downloaded region") {
                    Picker("Map", selection: $selectedMapID) {
                        ForEach(availableMaps) { candidate in
                            Text(candidate.pack.regionCode).tag(candidate.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Group {
                    if let preparedStyleURL {
                        OfflineMapCanvas(
                            map: map,
                            styleURL: preparedStyleURL,
                            resetToken: resetToken
                        )
                        .frame(maxWidth: .infinity, minHeight: 420)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(map.pack.regionCode) offline map")
                        .accessibilityValue(
                            "Interactive map rendered from the verified local package"
                        )
                        .accessibilityIdentifier("offline.map.canvas")
                    } else if let preparationError {
                        ContentUnavailableView(
                            "Map could not open",
                            systemImage: "map.fill",
                            description: Text(preparationError)
                        )
                    } else {
                        ProgressView("Opening verified offline map…")
                            .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .listRowInsets(EdgeInsets())

                Button {
                    resetToken = UUID()
                } label: {
                    Label("Show downloaded region", systemImage: "viewfinder")
                }
                .disabled(preparedStyleURL == nil)
            }

            Section("Offline coverage") {
                LabeledContent("Region", value: map.pack.regionCode)
                    .accessibilityIdentifier("offline.map.region")
                LabeledContent("Detail", value: map.pack.tier.displayName)
                LabeledContent(
                    "Map data",
                    value: ByteCountFormatter.string(
                        fromByteCount: map.pack.byteCount,
                        countStyle: .file
                    )
                )
                Label(
                    "Tiles, labels, and style are loaded from this signed package. No map server is required.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(.callout)
                Text(map.attribution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: map.id) {
            prepareStyle()
        }
    }

    private func prepareStyle() {
        preparedStyleURL = nil
        preparationError = nil
        do {
            let templateData = try Data(contentsOf: map.styleURL)
            let styleData = try OfflineMapStyleAssembler().assemble(
                templateData: templateData,
                pmtilesURL: map.pmtilesURL,
                glyphsDirectoryURL: map.glyphsDirectoryURL
            )
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TrailGuardMapStyles", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let output = directory.appendingPathComponent(
                "\(map.id)-\(map.pack.version).json"
            )
            try styleData.write(to: output, options: .atomic)
            preparedStyleURL = output
        } catch {
            preparationError = "The signed local style or label assets failed validation."
        }
    }
}

private struct OfflineMapCanvas: UIViewRepresentable {
    let map: ResolvedOfflineMap
    let styleURL: URL
    let resetToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.minimumZoomLevel = 3
        mapView.maximumZoomLevel = 16
        mapView.preferredFramesPerSecond = .lowPower
        mapView.showsScale = true
        mapView.compassViewPosition = .topRight
        context.coordinator.lastMapID = map.id
        context.coordinator.lastResetToken = resetToken
        DispatchQueue.main.async {
            mapView.setNeedsLayout()
            mapView.layoutIfNeeded()
            fit(mapView, animated: false)
            context.coordinator.lastViewportSize = mapView.bounds.size
        }
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
        let viewportSize = mapView.bounds.size
        let viewportChanged = viewportSize.width > 0
            && viewportSize.height > 0
            && context.coordinator.lastViewportSize != viewportSize
        guard viewportChanged
                || context.coordinator.lastMapID != map.id
                || context.coordinator.lastResetToken != resetToken
        else { return }
        fit(mapView, animated: !viewportChanged)
        context.coordinator.lastMapID = map.id
        context.coordinator.lastResetToken = resetToken
        context.coordinator.lastViewportSize = viewportSize
    }

    private func fit(_ mapView: MLNMapView, animated: Bool) {
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(
                latitude: map.pack.bounds.southWest.latitude,
                longitude: map.pack.bounds.southWest.longitude
            ),
            ne: CLLocationCoordinate2D(
                latitude: map.pack.bounds.northEast.latitude,
                longitude: map.pack.bounds.northEast.longitude
            )
        )
        mapView.setVisibleCoordinateBounds(
            bounds,
            edgePadding: UIEdgeInsets(top: 28, left: 20, bottom: 28, right: 20),
            animated: animated,
            completionHandler: nil
        )
    }

    final class Coordinator {
        var lastMapID = ""
        var lastResetToken = UUID()
        var lastViewportSize = CGSize.zero
    }
}
