import AVFoundation
import PhotosUI
import SwiftUI

struct MapPackView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var coordinator = MapsFeatureCoordinator()
    @State private var showsDownloadCenter = false
    @State private var showsWaypointEditor = false

    var body: some View {
        ZStack {
            mapSurface.ignoresSafeArea(edges: .top)
            VStack(spacing: AuroraDesign.Space.sm) {
                HStack {
                    Spacer()
                    mapStyleButton
                }
                if let message = coordinator.statusMessage { statusBanner(message) }
                Spacer()
                modePanel
                modeSwitcher
            }
            .padding(.horizontal, AuroraDesign.Space.sm)
            .padding(.vertical, AuroraDesign.Space.xs)
        }
        .navigationTitle("Maps")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("maps.home")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsDownloadCenter) {
            NavigationStack {
                DownloadCenterView(kindFilter: .map, showsCatalogConnection: true)
            }
        }
        .sheet(isPresented: $showsWaypointEditor) {
            WaypointEditorSheet(coordinator: coordinator)
        }
        .onAppear { configure() }
        .onChange(of: model.offlineMaps.map(\.id)) { _, _ in configure() }
        .onChange(of: coordinator.pendingWaypointCoordinate) { _, coordinate in
            showsWaypointEditor = coordinate != nil
        }
    }

    @ViewBuilder private var mapSurface: some View {
        switch coordinator.source {
        case .appleStandard, .appleSatellite:
            AppleMapCanvas(
                source: coordinator.source,
                scene: coordinator.scene,
                onLongPress: { coordinator.prepareWaypoint(at: $0) }
            )
        case let .offline(packID, layer):
            if let map = model.offlineMaps.first(where: { $0.id == packID }) {
                PreparedOfflineMapSurface(
                    map: map,
                    layer: layer,
                    scene: coordinator.scene,
                    onLongPress: { coordinator.prepareWaypoint(at: $0) }
                )
            } else {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    ContentUnavailableView(
                        "No Offline Coverage",
                        systemImage: "map",
                        description: Text("GPS still works. Download a signed region for terrain context.")
                    )
                }
            }
        }
    }

    private var mapStyleButton: some View {
        Menu {
            Button {
                coordinator.selectSource(.appleStandard)
            } label: {
                Label(
                    "Standard",
                    systemImage: coordinator.source == .appleStandard
                        ? "checkmark"
                        : "map"
                )
            }
            Button {
                coordinator.selectSource(.appleSatellite)
            } label: {
                Label(
                    "Satellite",
                    systemImage: coordinator.source == .appleSatellite
                        ? "checkmark"
                        : "globe.americas.fill"
                )
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .offset(y: -8)
        .accessibilityLabel("Map type")
        .accessibilityIdentifier("maps.source")
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: AuroraDesign.Space.sm) {
            Image(systemName: "info.circle.fill")
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { coordinator.statusMessage = nil } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .padding(AuroraDesign.Space.sm)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var modePanel: some View {
        Group {
            switch coordinator.mode {
            case .waypoints: waypointPanel
            case .record: recordPanel
            case .offlineMaps: offlinePanel
            }
        }
        .padding(AuroraDesign.Space.md)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    private var waypointPanel: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            HStack {
                Label("Survival Waypoints", systemImage: "mappin.and.ellipse").font(.headline)
                Spacer()
                Button { coordinator.prepareWaypoint() } label: {
                    Label("Mark Here", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("maps.waypoint.add")
            }
            if coordinator.scene.waypoints.isEmpty {
                Text("Mark your location or long-press the map. Notes and attachments remain offline.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(coordinator.scene.waypoints) { waypoint in
                            Label(waypoint.kind.displayName, systemImage: waypoint.kind.systemImage)
                                .font(.caption.bold()).padding(8)
                                .glassEffect(.regular.interactive(), in: Capsule())
                                .contextMenu {
                                    Button("Delete", role: .destructive) { coordinator.deleteWaypoint(waypoint) }
                                }
                        }
                    }
                }
            }
        }
    }

    private var recordPanel: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            HStack {
                Label("Trail Recording", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                Spacer()
                recordingAction
            }
            if let trail = coordinator.recording.trail {
                HStack(spacing: AuroraDesign.Space.lg) {
                    stat("Distance", distance(coordinator.recording.summary.distanceMeters))
                    stat("Time", duration(coordinator.recording.summary.elapsedSeconds))
                    stat("Speed", "\((coordinator.recording.summary.currentSpeedMetersPerSecond * 3.6).formatted(.number.precision(.fractionLength(1)))) km/h")
                    stat("Gain", "\(coordinator.recording.summary.elevationGainMeters.formatted(.number.precision(.fractionLength(0)))) m")
                }
                .accessibilityIdentifier("maps.record.stats")
                HStack {
                    Button { coordinator.breadcrumbReturnEnabled.toggle() } label: {
                        Label(coordinator.breadcrumbReturnEnabled ? "Return Active" : "Return by Breadcrumb", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.glass)
                    Text(trail.state.rawValue.capitalized).font(.caption.bold()).foregroundStyle(.secondary)
                }
            } else {
                Text("Record a durable breadcrumb trail while the screen is locked or the app is backgrounded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !coordinator.savedTrails.filter({ $0.state == .idle }).isEmpty {
                DisclosureGroup("Route history") {
                    ForEach(coordinator.savedTrails.filter { $0.state == .idle }.prefix(5)) { trail in
                        Text(trail.name).font(.caption)
                    }
                }
                .font(.caption.bold())
            }
        }
    }

    @ViewBuilder private var recordingAction: some View {
        switch coordinator.recording.trail?.state {
        case .recording:
            HStack {
                Button("Pause") { coordinator.pauseRecording() }.buttonStyle(.glass)
                Button("Finish") { coordinator.finishRecording() }.buttonStyle(.glass)
            }
        case .paused:
            HStack {
                Button("Resume") { coordinator.resumeRecording() }.buttonStyle(.glass)
                Button("Finish") { coordinator.finishRecording() }.buttonStyle(.glass)
            }
        case .idle, nil:
            Button("Start") { coordinator.startRecording() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("maps.record.start")
        }
    }

    private var offlinePanel: some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            HStack {
                Label("Offline Maps", systemImage: "internaldrive").font(.headline)
                Spacer()
                Button("Manage Downloads") { showsDownloadCenter = true }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("maps.download.manage")
            }
            if model.offlineMaps.isEmpty {
                Text("No signed region is installed. Minnesota is the test region for this release.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.offlineMaps) { map in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(map.pack.regionCode).font(.subheadline.bold())
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: map.pack.unpackedByteCount, countStyle: .file))
                                .font(.caption.monospacedDigit())
                        }
                        HStack(spacing: 8) {
                            ForEach(map.pack.availableLayers, id: \.self) { layer in
                                Button {
                                    coordinator.selectSource(.offline(packID: map.id, layer: layer))
                                } label: {
                                    Label(
                                        layer == .legacy ? "Open Offline" : layer.displayName,
                                        systemImage: layerIcon(layer)
                                    )
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(MapsMode.allCases, id: \.self) { mode in
                Button {
                    coordinator.mode = mode
                } label: {
                    Label(mode.displayName, systemImage: icon(for: mode))
                        .font(.caption.bold()).frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(
                    coordinator.mode == mode
                        ? AuroraDesign.spruce.opacity(0.22)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .accessibilityIdentifier("maps.mode.\(mode.rawValue)")
                .accessibilityAddTraits(
                    coordinator.mode == mode ? .isSelected : []
                )
            }
        }
        .padding(5).frame(maxWidth: 520)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18))
    }

    private func configure() {
        coordinator.configure(maps: model.offlineMaps)
    }

    private func layerIcon(_ layer: OfflineMapLayer) -> String {
        switch layer {
        case .legacy: "map"
        case .terrain: "mountain.2"
        case .topographic: "lines.measurement.horizontal"
        case .trail: "figure.hiking"
        }
    }

    private func icon(for mode: MapsMode) -> String {
        switch mode {
        case .waypoints: "mappin"
        case .record: "record.circle"
        case .offlineMaps: "map.fill"
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func distance(_ meters: Double) -> String {
        meters >= 1_000
            ? "\((meters / 1_000).formatted(.number.precision(.fractionLength(2)))) km"
            : "\(meters.formatted(.number.precision(.fractionLength(0)))) m"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }
}

private struct PreparedOfflineMapSurface: View {
    let map: ResolvedOfflineMap
    let layer: OfflineMapLayer
    let scene: MapSceneSnapshot
    let onLongPress: (GeoCoordinate) -> Void
    @State private var preparedStyleURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let preparedStyleURL {
                SurvivalOfflineMapCanvas(map: map, layer: layer, styleURL: preparedStyleURL, scene: scene, onLongPress: onLongPress)
            } else if let errorMessage {
                ContentUnavailableView("Offline Map Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView("Opening verified offline map…")
            }
        }
        .task(id: "\(map.id)-\(layer.rawValue)") { prepare() }
    }

    private func prepare() {
        do {
            let templateURL = map.styleURL(for: layer) ?? map.styleURL
            let data = try OfflineMapStyleAssembler().assemble(
                templateData: Data(contentsOf: templateURL),
                sourceURLs: map.sourceURLs,
                glyphsDirectoryURL: map.glyphsDirectoryURL
            )
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AuroraMapStyles", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appendingPathComponent("\(map.id)-\(layer.rawValue)-\(map.pack.version).json")
            try data.write(to: output, options: .atomic)
            preparedStyleURL = output
        } catch {
            errorMessage = "The signed local map style failed validation."
        }
    }
}

private struct WaypointEditorSheet: View {
    @ObservedObject var coordinator: MapsFeatureCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var kind: WaypointKind = .water
    @State private var note = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var showsCamera = false
    @StateObject private var audioRecorder = WaypointAudioRecorder()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Marker", selection: $kind) {
                    ForEach(WaypointKind.allCases, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
                TextField("Offline note", text: $note, axis: .vertical).lineLimit(3...6)
                Section("Attachments") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Choose Photo" : "Photo Selected", systemImage: "photo")
                    }
                    Button { showsCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    Button { Task { await audioRecorder.toggle() } } label: {
                        Label(audioRecorder.isRecording ? "Stop Voice Note" : "Record Voice Note", systemImage: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle")
                    }
                }
            }
            .navigationTitle("New Waypoint")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.pendingWaypointCoordinate = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onChange(of: photoItem) { _, item in
                Task { photoData = try? await item?.loadTransferable(type: Data.self) }
            }
            .sheet(isPresented: $showsCamera) {
                CameraCaptureView(
                    onCapture: { photoData = $0; showsCamera = false },
                    onCancel: { showsCamera = false },
                    onFailure: { _ in showsCamera = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func save() {
        Task {
            if audioRecorder.isRecording { await audioRecorder.toggle() }
            guard let waypoint = await coordinator.saveWaypoint(kind: kind, note: note) else { return }
            if let photoData { await coordinator.savePhoto(photoData, for: waypoint) }
            if let audioURL = audioRecorder.outputURL { await coordinator.saveAudio(at: audioURL, for: waypoint) }
            dismiss()
        }
    }
}

@MainActor private final class WaypointAudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private(set) var outputURL: URL?

    func toggle() async {
        if isRecording {
            recorder?.stop()
            isRecording = false
            return
        }
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .spokenAudio)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("waypoint-\(UUID().uuidString).m4a")
            recorder = try AVAudioRecorder(
                url: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 22_050,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                ]
            )
            recorder?.record()
            outputURL = url
            isRecording = true
        } catch {
            recorder = nil
            isRecording = false
        }
    }
}
