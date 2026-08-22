import Foundation

public enum MapsMode: String, CaseIterable, Codable, Sendable {
    case waypoints
    case record
    case offlineMaps

    public var displayName: String {
        switch self {
        case .waypoints: "Waypoints"
        case .record: "Record"
        case .offlineMaps: "Offline Maps"
        }
    }
}

public enum OfflineMapLayer: String, CaseIterable, Codable, Sendable {
    case legacy
    case terrain
    case topographic
    case trail

    public var displayName: String {
        switch self {
        case .legacy: "Legacy Offline"
        case .terrain: "Terrain"
        case .topographic: "Topographic"
        case .trail: "Trail"
        }
    }
}

public enum MapSource: Hashable, Codable, Sendable {
    case appleStandard
    case appleSatellite
    case offline(packID: String, layer: OfflineMapLayer)

    public var displayName: String {
        switch self {
        case .appleStandard: "Standard"
        case .appleSatellite: "Satellite"
        case let .offline(_, layer): layer.displayName
        }
    }

    public var requiresNetwork: Bool {
        switch self {
        case .appleStandard, .appleSatellite: true
        case .offline: false
        }
    }
}

public enum TrailRecordingState: String, Codable, Sendable {
    case idle
    case recording
    case paused
}

public enum WaypointKind: String, CaseIterable, Codable, Sendable {
    case water
    case shelter
    case danger
    case junction
    case vehicle
    case resource

    public var displayName: String { rawValue.capitalized }

    public var systemImage: String {
        switch self {
        case .water: "drop.fill"
        case .shelter: "tent.fill"
        case .danger: "exclamationmark.triangle.fill"
        case .junction: "arrow.triangle.branch"
        case .vehicle: "car.fill"
        case .resource: "leaf.fill"
        }
    }
}

public struct LocationFix: Equatable, Codable, Sendable {
    public let coordinate: GeoCoordinate
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let verticalAccuracy: Double
    public let speed: Double
    public let course: Double
    public let heading: Double?
    public let timestamp: Date

    public init(
        coordinate: GeoCoordinate,
        altitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        speed: Double,
        course: Double,
        heading: Double?,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.heading = heading
        self.timestamp = timestamp
    }
}

public struct TrackPoint: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let trailID: UUID
    public let sequence: Int
    public let fix: LocationFix

    public init(id: UUID = UUID(), trailID: UUID, sequence: Int, fix: LocationFix) {
        self.id = id
        self.trailID = trailID
        self.sequence = sequence
        self.fix = fix
    }
}

public struct TrailCheckpoint: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let trailID: UUID
    public let coordinate: GeoCoordinate
    public let createdAt: Date
    public let distanceMeters: Double

    public init(
        id: UUID = UUID(),
        trailID: UUID,
        coordinate: GeoCoordinate,
        createdAt: Date,
        distanceMeters: Double
    ) {
        self.id = id
        self.trailID = trailID
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.distanceMeters = distanceMeters
    }
}

public struct Trail: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public let startedAt: Date
    public var endedAt: Date?
    public var state: TrailRecordingState
    public var accumulatedActiveSeconds: TimeInterval
    public var lastResumedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        state: TrailRecordingState,
        accumulatedActiveSeconds: TimeInterval = 0,
        lastResumedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.accumulatedActiveSeconds = accumulatedActiveSeconds
        self.lastResumedAt = lastResumedAt
    }
}

public struct TrailSummary: Equatable, Codable, Sendable {
    public var elapsedSeconds: TimeInterval
    public var distanceMeters: Double
    public var currentSpeedMetersPerSecond: Double
    public var averageSpeedMetersPerSecond: Double
    public var elevationGainMeters: Double
    public var latestAccuracyMeters: Double?

    public static let empty = TrailSummary(
        elapsedSeconds: 0,
        distanceMeters: 0,
        currentSpeedMetersPerSecond: 0,
        averageSpeedMetersPerSecond: 0,
        elevationGainMeters: 0,
        latestAccuracyMeters: nil
    )
}

public struct Waypoint: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var kind: WaypointKind
    public var coordinate: GeoCoordinate
    public let createdAt: Date
    public var note: String
    public var photoRelativePath: String?
    public var audioRelativePath: String?

    public init(
        id: UUID = UUID(),
        kind: WaypointKind,
        coordinate: GeoCoordinate,
        createdAt: Date = Date(),
        note: String = "",
        photoRelativePath: String? = nil,
        audioRelativePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.note = note
        self.photoRelativePath = photoRelativePath
        self.audioRelativePath = audioRelativePath
    }
}

public struct MapSceneSnapshot: Equatable, Sendable {
    public var location: LocationFix?
    public var activeTrack: [GeoCoordinate]
    public var checkpoints: [TrailCheckpoint]
    public var waypoints: [Waypoint]

    public init(
        location: LocationFix? = nil,
        activeTrack: [GeoCoordinate] = [],
        checkpoints: [TrailCheckpoint] = [],
        waypoints: [Waypoint] = []
    ) {
        self.location = location
        self.activeTrack = activeTrack
        self.checkpoints = checkpoints
        self.waypoints = waypoints
    }
}

public protocol TrailRepository: Sendable {
    func activeTrail() async throws -> Trail?
    func trails() async throws -> [Trail]
    func save(trail: Trail) async throws
    func append(points: [TrackPoint]) async throws
    func points(trailID: UUID) async throws -> [TrackPoint]
    func save(checkpoint: TrailCheckpoint) async throws
    func checkpoints(trailID: UUID) async throws -> [TrailCheckpoint]
    func deleteTrail(id: UUID) async throws
}

public protocol WaypointRepository: Sendable {
    func waypoints() async throws -> [Waypoint]
    func save(waypoint: Waypoint) async throws
    func deleteWaypoint(id: UUID) async throws
}

public protocol TrailRecording: Sendable {
    func start(name: String, at date: Date) async throws
    func pause(at date: Date) async throws
    func resume(at date: Date) async throws
    func finish(at date: Date) async throws
    func ingest(_ fix: LocationFix) async throws -> TrailRecordingSnapshot
    func snapshot(at date: Date) async throws -> TrailRecordingSnapshot
}

public struct TrailRecordingSnapshot: Equatable, Sendable {
    public let trail: Trail?
    public let points: [TrackPoint]
    public let checkpoints: [TrailCheckpoint]
    public let summary: TrailSummary
    public let possibleLoop: Bool

    public init(
        trail: Trail?,
        points: [TrackPoint],
        checkpoints: [TrailCheckpoint],
        summary: TrailSummary,
        possibleLoop: Bool = false
    ) {
        self.trail = trail
        self.points = points
        self.checkpoints = checkpoints
        self.summary = summary
        self.possibleLoop = possibleLoop
    }
}

public struct TrackSamplingPolicy: Sendable {
    public let maximumHorizontalAccuracy: Double
    public let minimumDistanceMeters: Double
    public let maximumInterval: TimeInterval
    public let maximumDerivedSpeed: Double

    public init(
        maximumHorizontalAccuracy: Double = 65,
        minimumDistanceMeters: Double = 10,
        maximumInterval: TimeInterval = 10,
        maximumDerivedSpeed: Double = 60
    ) {
        self.maximumHorizontalAccuracy = maximumHorizontalAccuracy
        self.minimumDistanceMeters = minimumDistanceMeters
        self.maximumInterval = maximumInterval
        self.maximumDerivedSpeed = maximumDerivedSpeed
    }

    public func accepts(_ fix: LocationFix, after previous: LocationFix?) -> Bool {
        guard fix.coordinate.isValid,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumHorizontalAccuracy
        else { return false }
        guard let previous else { return true }
        let interval = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return false }
        let distance = Self.distance(from: previous.coordinate, to: fix.coordinate)
        guard distance / interval <= maximumDerivedSpeed else { return false }
        return distance >= minimumDistanceMeters || interval >= maximumInterval
    }

    public static func distance(from lhs: GeoCoordinate, to rhs: GeoCoordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
