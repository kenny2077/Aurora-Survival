import AVFoundation
import PhotosUI
import SwiftUI

struct MapPackView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var coordinator = MapsFeatureCoordinator()
    @State private var showsDownloadCenter = false
    @State private var showsWaypointEditor = false
    @State private var bottomChromeHeight: CGFloat = 0
    @State private var mapChromeVisible = true
    @State private var mapFocus: MapCameraFocus?

    var body: some View {
        ZStack {
            mapSurface
                .ignoresSafeArea(edges: .top)
                .accessibilityIdentifier("maps.canvas")
            VStack(spacing: AuroraDesign.Space.sm) {
                if mapChromeVisible {
                    HStack {
                        Spacer()
                        mapStyleButton
                    }
                    .transition(.opacity)
                }
                if mapChromeVisible,
                   let message = coordinator.statusMessage {
                    statusBanner(message)
                        .transition(.opacity)
                }
                Spacer()
                if mapChromeVisible {
                    bottomChrome
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, AuroraDesign.Space.sm)
            .padding(.vertical, AuroraDesign.Space.xs)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsDownloadCenter) {
            NavigationStack {
                DownloadCenterView(
                    kindFilter: .map,
                    showsCatalogConnection: false,
                    onOpenMap: { packID, layer in
                        coordinator.selectSource(
                            .offline(packID: packID, layer: layer)
                        )
                        showsDownloadCenter = false
                    }
                )
                    .task { await model.ensureCatalogLoaded() }
            }
        }
        .sheet(isPresented: $showsWaypointEditor) {
            WaypointEditorSheet(coordinator: coordinator)
        }
        .onAppear {
            mapChromeVisible = true
            configure()
            coordinator.requestLocation()
        }
        .onDisappear { coordinator.stopDisplayLocation() }
        .onChange(of: model.offlineMaps.map(\.id)) { _, _ in configure() }
        .onChange(of: coordinator.pendingWaypointCoordinate) { _, coordinate in
            showsWaypointEditor = coordinate != nil
        }
        .onPreferenceChange(MapBottomChromeHeightKey.self) { height in
            if abs(bottomChromeHeight - height) > 1 {
                bottomChromeHeight = height
            }
        }
    }

    @ViewBuilder private var mapSurface: some View {
        switch coordinator.source {
        case .appleStandard, .appleSatellite:
            AppleMapCanvas(
                source: coordinator.source,
                scene: coordinator.scene,
                bottomChromeInset: mapChromeVisible ? bottomChromeHeight : 0,
                showsChrome: mapChromeVisible,
                focus: mapFocus,
                onLongPress: { coordinator.prepareWaypoint(at: $0) },
                onSingleTap: toggleMapChrome
            )
        case let .offline(packID, layer):
            if let map = model.offlineMaps.first(where: { $0.id == packID }) {
                PreparedOfflineMapSurface(
                    map: map,
                    layer: layer,
                    scene: coordinator.scene,
                    showsChrome: mapChromeVisible,
                    focus: mapFocus,
                    onLongPress: { coordinator.prepareWaypoint(at: $0) },
                    onSingleTap: toggleMapChrome
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
            Label("Survival Waypoints", systemImage: "mappin.and.ellipse")
                .font(.headline)
            if coordinator.scene.waypoints.isEmpty {
                Text("Long-press the map to add.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(coordinator.scene.waypoints) { waypoint in
                            Button {
                                mapFocus = MapCameraFocus(
                                    coordinate: waypoint.coordinate
                                )
                            } label: {
                                Label(
                                    waypoint.kind.displayName,
                                    systemImage: waypoint.kind.systemImage
                                )
                                .font(.caption.bold())
                                .padding(8)
                                .glassEffect(
                                    .regular.interactive(),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "maps.waypoint.saved.\(waypoint.id.uuidString)"
                            )
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    coordinator.deleteWaypoint(waypoint)
                                }
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
        HStack(spacing: AuroraDesign.Space.md) {
            Label("Offline Maps", systemImage: "map.fill")
                .font(.headline)
            Spacer(minLength: AuroraDesign.Space.sm)
            Button("Downloads") {
                showsDownloadCenter = true
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityIdentifier("maps.download.manage")
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(Array(MapsMode.allCases.enumerated()), id: \.element) {
                index,
                mode in
                if index > 0 {
                    Divider()
                        .frame(height: 28)
                        .opacity(0.38)
                        .accessibilityHidden(true)
                        .accessibilityIdentifier("maps.mode.divider.\(index)")
                }
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
                        ? Color.accentColor.opacity(0.22)
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
        .sensoryFeedback(.selection, trigger: coordinator.mode)
    }

    private var bottomChrome: some View {
        VStack(spacing: AuroraDesign.Space.sm) {
            modePanel
            modeSwitcher
        }
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Map controls")
                .accessibilityIdentifier("maps.chrome")
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MapBottomChromeHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private func configure() {
        coordinator.configure(maps: model.offlineMaps)
    }

    private func toggleMapChrome() {
        withAnimation(
            reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.24)
        ) {
            mapChromeVisible.toggle()
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
    let showsChrome: Bool
    let focus: MapCameraFocus?
    let onLongPress: (GeoCoordinate) -> Void
    let onSingleTap: () -> Void
    @State private var preparedStyleURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let preparedStyleURL {
                SurvivalOfflineMapCanvas(
                    map: map,
                    layer: layer,
                    styleURL: preparedStyleURL,
                    scene: scene,
                    showsChrome: showsChrome,
                    focus: focus,
                    onLongPress: onLongPress,
                    onSingleTap: onSingleTap
                )
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

private struct MapBottomChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
            .accessibilityIdentifier("maps.waypoint.editor")
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
