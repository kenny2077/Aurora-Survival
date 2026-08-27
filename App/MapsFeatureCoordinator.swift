import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class MapsFeatureCoordinator: ObservableObject {
    @Published var mode: MapsMode = .waypoints
    @Published var source: MapSource = .appleStandard
    @Published private(set) var scene = MapSceneSnapshot()
    @Published private(set) var recording = TrailRecordingSnapshot(
        trail: nil,
        points: [],
        checkpoints: [],
        summary: .empty
    )
    @Published private(set) var savedTrails: [Trail] = []
    @Published private(set) var isConnected = true
    @Published var statusMessage: String?
    @Published var pendingWaypointCoordinate: GeoCoordinate?
    @Published var breadcrumbReturnEnabled = false

    private let locationService: any LocationProviding
    private let connectivity: any ConnectivityProviding
    private let store: SQLiteSurvivalMapStore
    private let recorder: TrailRecordingEngine
    private var maps: [ResolvedOfflineMap] = []
    private var locationTask: Task<Void, Never>?
    private var connectivityTask: Task<Void, Never>?

    init(
        locationService: (any LocationProviding)? = nil,
        connectivity: any ConnectivityProviding = NetworkConnectivityService()
    ) {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Aurora", isDirectory: true)
            .appendingPathComponent("SurvivalMaps", isDirectory: true)
        let store = SQLiteSurvivalMapStore(
            databaseURL: root.appendingPathComponent("survival-maps.sqlite"),
            attachmentsDirectory: root.appendingPathComponent(
                "WaypointAttachments",
                isDirectory: true
            )
        )
        self.locationService = locationService ?? SurvivalLocationService()
        self.connectivity = connectivity
        self.store = store
        recorder = TrailRecordingEngine(repository: store)
        beginStreams()
        Task { await restore() }
    }

    deinit {
        locationTask?.cancel()
        connectivityTask?.cancel()
    }

    var currentOfflineMap: ResolvedOfflineMap? {
        guard case let .offline(packID, _) = source else { return nil }
        return maps.first { $0.id == packID }
    }

    func configure(maps: [ResolvedOfflineMap]) {
        self.maps = maps
    }

    func requestLocation() {
        locationService.requestWhenInUseAuthorization()
        locationService.startDisplayUpdates()
    }

    func stopDisplayLocation() {
        guard recording.trail?.state != .recording else { return }
        locationService.stopDisplayUpdates()
    }

    func selectSource(_ newSource: MapSource) {
        guard !newSource.requiresNetwork || isConnected else {
            statusMessage = "Online maps need a network connection."
            return
        }
        source = newSource
    }

    func startRecording() {
        requestLocation()
        Task {
            do {
                try await recorder.start(
                    name: "Trail \(Date().formatted(date: .abbreviated, time: .shortened))",
                    at: Date()
                )
                locationService.startRecordingUpdates()
                await refreshRecording()
            } catch {
                statusMessage = "A trail is already active."
            }
        }
    }

    func pauseRecording() {
        Task {
            do {
                try await recorder.pause(at: Date())
                locationService.stopRecordingUpdates()
                await refreshRecording()
            } catch { statusMessage = "The trail could not be paused." }
        }
    }

    func resumeRecording() {
        Task {
            do {
                try await recorder.resume(at: Date())
                locationService.startRecordingUpdates()
                await refreshRecording()
            } catch { statusMessage = "The trail could not resume." }
        }
    }

    func finishRecording() {
        Task {
            do {
                try await recorder.finish(at: Date())
                locationService.stopRecordingUpdates()
                breadcrumbReturnEnabled = false
                await refreshRecording()
                savedTrails = (try? await store.trails()) ?? []
            } catch { statusMessage = "The trail could not be finished." }
        }
    }

    func prepareWaypoint(at coordinate: GeoCoordinate? = nil) {
        pendingWaypointCoordinate = coordinate ?? scene.location?.coordinate
        if pendingWaypointCoordinate == nil {
            statusMessage = "Wait for a GPS fix before adding a waypoint."
        }
    }

    func saveWaypoint(kind: WaypointKind, note: String) async -> Waypoint? {
        guard let coordinate = pendingWaypointCoordinate else { return nil }
        let waypoint = Waypoint(kind: kind, coordinate: coordinate, note: note)
        do {
            try await store.save(waypoint: waypoint)
            pendingWaypointCoordinate = nil
            await reloadWaypoints()
            return waypoint
        } catch {
            statusMessage = "The waypoint could not be saved."
            return nil
        }
    }

    func savePhoto(_ data: Data, for waypoint: Waypoint) async {
        await saveAttachment(data, filename: "photo.jpg", waypoint: waypoint, isPhoto: true)
    }

    func saveAudio(at sourceURL: URL, for waypoint: Waypoint) async {
        guard let data = try? Data(contentsOf: sourceURL) else {
            statusMessage = "The voice note could not be read."
            return
        }
        await saveAttachment(data, filename: "voice.m4a", waypoint: waypoint, isPhoto: false)
    }

    func deleteWaypoint(_ waypoint: Waypoint) {
        Task {
            try? await store.deleteWaypoint(id: waypoint.id)
            await reloadWaypoints()
        }
    }

    private func beginStreams() {
        locationTask = Task { [weak self] in
            guard let self else { return }
            for await fix in locationService.updates() {
                if Task.isCancelled { return }
                await receive(fix)
            }
        }
        connectivityTask = Task { [weak self] in
            guard let self else { return }
            for await connected in connectivity.connectivityUpdates() {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.isConnected = connected
                    if !connected && self.source.requiresNetwork {
                        self.selectOfflineFallback()
                    }
                }
            }
        }
    }

    private func receive(_ fix: LocationFix) async {
        scene.location = fix
        if recording.trail?.state == .recording {
            do {
                recording = try await recorder.ingest(fix)
                updateSceneFromRecording()
                if recording.possibleLoop {
                    statusMessage = "Possible loop: you are near an older checkpoint."
                }
            } catch { statusMessage = "This GPS point could not be recorded." }
        }
    }

    private func restore() async {
        try? await store.prepare()
        await reloadWaypoints()
        savedTrails = (try? await store.trails()) ?? []
        if let snapshot = try? await recorder.snapshot(at: Date()),
           snapshot.trail != nil {
            recording = snapshot
            if snapshot.trail?.state == .recording {
                try? await recorder.pause(at: Date())
                recording = (try? await recorder.snapshot(at: Date())) ?? snapshot
                statusMessage = "An unfinished trail was recovered. Resume or finish it."
            }
            updateSceneFromRecording()
        }
        requestLocation()
    }

    private func refreshRecording() async {
        if let snapshot = try? await recorder.snapshot(at: Date()) {
            recording = snapshot
            updateSceneFromRecording()
        }
    }

    private func updateSceneFromRecording() {
        scene.activeTrack = recording.points.map(\.fix.coordinate)
        scene.checkpoints = recording.checkpoints
    }

    private func reloadWaypoints() async {
        scene.waypoints = (try? await store.waypoints()) ?? []
    }

    private func selectOfflineFallback() {
        let coordinate = scene.location?.coordinate
        let candidate = maps.first { map in
            coordinate.map(map.pack.bounds.contains) ?? false
        } ?? maps.first
        guard let candidate, let layer = candidate.pack.availableLayers.first else {
            statusMessage = "No downloaded map covers this location."
            mode = .offlineMaps
            return
        }
        source = .offline(packID: candidate.id, layer: layer)
        statusMessage = "Switched to \(layer.displayName) offline map."
    }

    private func saveAttachment(
        _ data: Data,
        filename: String,
        waypoint: Waypoint,
        isPhoto: Bool
    ) async {
        do {
            let directory = try await store.attachmentDirectory(for: waypoint.id)
            let destination = directory.appendingPathComponent(filename)
            try data.write(to: destination, options: .atomic)
            var updated = waypoint
            let relative = "\(waypoint.id.uuidString)/\(filename)"
            if isPhoto { updated.photoRelativePath = relative }
            else { updated.audioRelativePath = relative }
            try await store.save(waypoint: updated)
            await reloadWaypoints()
        } catch { statusMessage = "The waypoint attachment could not be saved." }
    }
}
