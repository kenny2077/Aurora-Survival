import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class SurvivalMapCoreTests: XCTestCase {
    func testSamplingRejectsPoorAccuracyAndAcceptsDistanceOrTime() {
        let policy = TrackSamplingPolicy()
        let start = fix(latitude: 44, longitude: -93, time: 0)
        XCTAssertTrue(policy.accepts(start, after: nil))
        XCTAssertFalse(policy.accepts(
            fix(latitude: 44.001, longitude: -93, accuracy: 100, time: 20),
            after: start
        ))
        XCTAssertTrue(policy.accepts(
            fix(latitude: 44.0002, longitude: -93, time: 2),
            after: start
        ))
        XCTAssertTrue(policy.accepts(
            fix(latitude: 44, longitude: -93, time: 10),
            after: start
        ))
    }

    func testRecordingPauseExcludesPausedTimeAndPersistsPoints() async throws {
        let repository = MemorySurvivalMapRepository()
        let engine = TrailRecordingEngine(repository: repository, batchSize: 1)
        let base = Date(timeIntervalSince1970: 1_000)
        try await engine.start(name: "Test", at: base)
        _ = try await engine.ingest(fix(latitude: 44, longitude: -93, date: base))
        try await engine.pause(at: base.addingTimeInterval(60))
        try await engine.resume(at: base.addingTimeInterval(660))
        let snapshot = try await engine.ingest(
            fix(latitude: 44.001, longitude: -93, date: base.addingTimeInterval(720))
        )
        XCTAssertEqual(snapshot.summary.elapsedSeconds, 120, accuracy: 0.01)
        XCTAssertEqual(snapshot.points.count, 2)
        XCTAssertGreaterThan(snapshot.summary.distanceMeters, 100)
    }

    func testCheckpointAndLoopAdvisoryUsesCooldownSafeHeuristic() async throws {
        let repository = MemorySurvivalMapRepository()
        let engine = TrailRecordingEngine(repository: repository, batchSize: 1)
        let base = Date(timeIntervalSince1970: 10_000)
        try await engine.start(name: "Loop", at: base)
        _ = try await engine.ingest(fix(latitude: 44, longitude: -93, date: base))
        _ = try await engine.ingest(fix(latitude: 44.0091, longitude: -93, date: base.addingTimeInterval(60)))
        _ = try await engine.ingest(fix(latitude: 44.0182, longitude: -93, date: base.addingTimeInterval(120)))
        let loop = try await engine.ingest(
            fix(latitude: 44.00915, longitude: -93, date: base.addingTimeInterval(1_200))
        )
        XCTAssertGreaterThanOrEqual(loop.checkpoints.count, 2)
        XCTAssertTrue(loop.possibleLoop)
    }

    func testSQLiteStoreRoundTripsAndDeletesOwnedAttachmentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SurvivalMapStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SQLiteSurvivalMapStore(
            databaseURL: root.appendingPathComponent("maps.sqlite"),
            attachmentsDirectory: root.appendingPathComponent("attachments", isDirectory: true)
        )
        let waypoint = Waypoint(
            kind: .water,
            coordinate: GeoCoordinate(latitude: 44.9, longitude: -93.2),
            note: "Filtered creek"
        )
        try await store.save(waypoint: waypoint)
        let directory = try await store.attachmentDirectory(for: waypoint.id)
        try Data("photo".utf8).write(to: directory.appendingPathComponent("photo.jpg"))
        let stored = try await store.waypoints()
        XCTAssertEqual(stored.map(\.id), [waypoint.id])
        XCTAssertEqual(stored.first?.note, waypoint.note)
        XCTAssertEqual(stored.first?.coordinate, waypoint.coordinate)
        try await store.deleteWaypoint(id: waypoint.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testOfflineMapPackV1DefaultsToLegacyLayer() throws {
        let data = Data(
            """
            {
              "id":"map.mn","name":"Minnesota","regionCode":"Minnesota","tier":"scout",
              "version":"1.0.0","generatedAt":"2026-01-01T00:00:00Z",
              "recommendedRefreshAfter":"2027-01-01T00:00:00Z",
              "bounds":{"southWest":{"latitude":43.4,"longitude":-97.5},"northEast":{"latitude":49.4,"longitude":-89.4}},
              "pmtilesPath":"maps/mn.pmtiles","stylePath":"style/style.json","byteCount":123
            }
            """.utf8
        )
        let pack = try JSONDecoder().decode(OfflineMapPack.self, from: data)
        XCTAssertEqual(pack.schemaVersion, 1)
        XCTAssertEqual(pack.availableLayers, [.legacy])
        XCTAssertEqual(pack.unpackedByteCount, 123)

        let encodedV2 = try JSONEncoder().encode(
            OfflineMapPack(
                schemaVersion: 2,
                id: "map.mn.v2",
                name: "Minnesota",
                regionCode: "Minnesota",
                tier: .field,
                version: "2.0.0",
                generatedAt: "2026-08-22T00:00:00Z",
                recommendedRefreshAfter: "2027-08-22T00:00:00Z",
                bounds: pack.bounds,
                pmtilesPath: "maps/mn.pmtiles",
                stylePath: "style/terrain.json",
                stylePaths: [.terrain: "style/terrain.json", .trail: "style/trail.json"],
                availableLayers: [.terrain, .trail],
                byteCount: 456
            )
        )
        let v2 = try JSONDecoder().decode(OfflineMapPack.self, from: encodedV2)
        XCTAssertEqual(v2.stylePaths[.trail], "style/trail.json")
    }

    private func fix(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 5,
        time: TimeInterval
    ) -> LocationFix {
        fix(
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            date: Date(timeIntervalSince1970: time)
        )
    }

    private func fix(
        latitude: Double,
        longitude: Double,
        accuracy: Double = 5,
        date: Date
    ) -> LocationFix {
        LocationFix(
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
            altitude: 250,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 8,
            speed: 1.4,
            course: 0,
            heading: 0,
            timestamp: date
        )
    }
}

private actor MemorySurvivalMapRepository: TrailRepository {
    private var storedTrails: [Trail] = []
    private var storedPoints: [UUID: [TrackPoint]] = [:]
    private var storedCheckpoints: [UUID: [TrailCheckpoint]] = [:]

    func activeTrail() -> Trail? {
        storedTrails.last { $0.state == .recording || $0.state == .paused }
    }

    func trails() -> [Trail] { storedTrails }

    func save(trail: Trail) {
        storedTrails.removeAll { $0.id == trail.id }
        storedTrails.append(trail)
    }

    func append(points: [TrackPoint]) {
        for point in points { storedPoints[point.trailID, default: []].append(point) }
    }

    func points(trailID: UUID) -> [TrackPoint] { storedPoints[trailID] ?? [] }

    func save(checkpoint: TrailCheckpoint) {
        storedCheckpoints[checkpoint.trailID, default: []].append(checkpoint)
    }

    func checkpoints(trailID: UUID) -> [TrailCheckpoint] {
        storedCheckpoints[trailID] ?? []
    }

    func deleteTrail(id: UUID) {
        storedTrails.removeAll { $0.id == id }
        storedPoints[id] = nil
        storedCheckpoints[id] = nil
    }
}
