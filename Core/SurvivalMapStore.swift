import Foundation
import SQLite3

public enum SurvivalMapStoreError: Error {
    case openFailed
    case migrationFailed
    case statementFailed
}

public actor SQLiteSurvivalMapStore: TrailRepository, WaypointRepository {
    private let databaseURL: URL
    private let attachmentsDirectory: URL
    private var database: OpaquePointer?

    public init(databaseURL: URL, attachmentsDirectory: URL) {
        self.databaseURL = databaseURL
        self.attachmentsDirectory = attachmentsDirectory
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func prepare() throws {
        if database != nil { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )
        try? (databaseURL.deletingLastPathComponent() as NSURL).setResourceValue(
            true,
            forKey: .isExcludedFromBackupKey
        )
#if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
#endif
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            throw SurvivalMapStoreError.openFailed
        }
        guard execute("PRAGMA journal_mode=WAL;"),
              execute("PRAGMA foreign_keys=ON;"),
              execute("PRAGMA user_version=1;"),
              execute(Self.schema)
        else { throw SurvivalMapStoreError.migrationFailed }
    }

    public func activeTrail() throws -> Trail? {
        try prepare()
        let sql = "SELECT id,name,started_at,ended_at,state,active_seconds,last_resumed_at FROM trails WHERE state IN ('recording','paused') ORDER BY started_at DESC LIMIT 1"
        return try queryTrails(sql).first
    }

    public func trails() throws -> [Trail] {
        try prepare()
        return try queryTrails(
            "SELECT id,name,started_at,ended_at,state,active_seconds,last_resumed_at FROM trails ORDER BY started_at DESC"
        )
    }

    public func save(trail: Trail) throws {
        try prepare()
        let sql = "INSERT INTO trails(id,name,started_at,ended_at,state,active_seconds,last_resumed_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,ended_at=excluded.ended_at,state=excluded.state,active_seconds=excluded.active_seconds,last_resumed_at=excluded.last_resumed_at"
        let statement = try prepared(sql)
        defer { sqlite3_finalize(statement) }
        bind(trail.id.uuidString, at: 1, to: statement)
        bind(trail.name, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, trail.startedAt.timeIntervalSince1970)
        if let endedAt = trail.endedAt {
            sqlite3_bind_double(statement, 4, endedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        bind(trail.state.rawValue, at: 5, to: statement)
        sqlite3_bind_double(statement, 6, trail.accumulatedActiveSeconds)
        if let lastResumedAt = trail.lastResumedAt {
            sqlite3_bind_double(statement, 7, lastResumedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        try stepDone(statement)
    }

    public func append(points: [TrackPoint]) throws {
        guard !points.isEmpty else { return }
        try prepare()
        guard execute("BEGIN IMMEDIATE TRANSACTION;") else {
            throw SurvivalMapStoreError.statementFailed
        }
        do {
            let sql = "INSERT OR REPLACE INTO track_points(id,trail_id,sequence,latitude,longitude,altitude,h_accuracy,v_accuracy,speed,course,heading,timestamp) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)"
            let statement = try prepared(sql)
            defer { sqlite3_finalize(statement) }
            for point in points {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bind(point.id.uuidString, at: 1, to: statement)
                bind(point.trailID.uuidString, at: 2, to: statement)
                sqlite3_bind_int64(statement, 3, Int64(point.sequence))
                sqlite3_bind_double(statement, 4, point.fix.coordinate.latitude)
                sqlite3_bind_double(statement, 5, point.fix.coordinate.longitude)
                sqlite3_bind_double(statement, 6, point.fix.altitude)
                sqlite3_bind_double(statement, 7, point.fix.horizontalAccuracy)
                sqlite3_bind_double(statement, 8, point.fix.verticalAccuracy)
                sqlite3_bind_double(statement, 9, point.fix.speed)
                sqlite3_bind_double(statement, 10, point.fix.course)
                if let heading = point.fix.heading {
                    sqlite3_bind_double(statement, 11, heading)
                } else {
                    sqlite3_bind_null(statement, 11)
                }
                sqlite3_bind_double(statement, 12, point.fix.timestamp.timeIntervalSince1970)
                try stepDone(statement)
            }
            guard execute("COMMIT;") else { throw SurvivalMapStoreError.statementFailed }
        } catch {
            _ = execute("ROLLBACK;")
            throw error
        }
    }

    public func points(trailID: UUID) throws -> [TrackPoint] {
        try prepare()
        let statement = try prepared(
            "SELECT id,sequence,latitude,longitude,altitude,h_accuracy,v_accuracy,speed,course,heading,timestamp FROM track_points WHERE trail_id=? ORDER BY sequence"
        )
        defer { sqlite3_finalize(statement) }
        bind(trailID.uuidString, at: 1, to: statement)
        var output: [TrackPoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else { continue }
            let heading = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 9)
            output.append(
                TrackPoint(
                    id: id,
                    trailID: trailID,
                    sequence: Int(sqlite3_column_int64(statement, 1)),
                    fix: LocationFix(
                        coordinate: GeoCoordinate(
                            latitude: sqlite3_column_double(statement, 2),
                            longitude: sqlite3_column_double(statement, 3)
                        ),
                        altitude: sqlite3_column_double(statement, 4),
                        horizontalAccuracy: sqlite3_column_double(statement, 5),
                        verticalAccuracy: sqlite3_column_double(statement, 6),
                        speed: sqlite3_column_double(statement, 7),
                        course: sqlite3_column_double(statement, 8),
                        heading: heading,
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
                    )
                )
            )
        }
        return output
    }

    public func save(checkpoint: TrailCheckpoint) throws {
        try prepare()
        let statement = try prepared(
            "INSERT OR REPLACE INTO checkpoints(id,trail_id,latitude,longitude,created_at,distance_meters) VALUES(?,?,?,?,?,?)"
        )
        defer { sqlite3_finalize(statement) }
        bind(checkpoint.id.uuidString, at: 1, to: statement)
        bind(checkpoint.trailID.uuidString, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, checkpoint.coordinate.latitude)
        sqlite3_bind_double(statement, 4, checkpoint.coordinate.longitude)
        sqlite3_bind_double(statement, 5, checkpoint.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, checkpoint.distanceMeters)
        try stepDone(statement)
    }

    public func checkpoints(trailID: UUID) throws -> [TrailCheckpoint] {
        try prepare()
        let statement = try prepared(
            "SELECT id,latitude,longitude,created_at,distance_meters FROM checkpoints WHERE trail_id=? ORDER BY created_at"
        )
        defer { sqlite3_finalize(statement) }
        bind(trailID.uuidString, at: 1, to: statement)
        var output: [TrailCheckpoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else { continue }
            output.append(
                TrailCheckpoint(
                    id: id,
                    trailID: trailID,
                    coordinate: GeoCoordinate(
                        latitude: sqlite3_column_double(statement, 1),
                        longitude: sqlite3_column_double(statement, 2)
                    ),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    distanceMeters: sqlite3_column_double(statement, 4)
                )
            )
        }
        return output
    }

    public func deleteTrail(id: UUID) throws {
        try prepare()
        try executeBound("DELETE FROM trails WHERE id=?", value: id.uuidString)
    }

    public func waypoints() throws -> [Waypoint] {
        try prepare()
        let statement = try prepared(
            "SELECT id,kind,latitude,longitude,created_at,note,photo_path,audio_path FROM waypoints ORDER BY created_at DESC"
        )
        defer { sqlite3_finalize(statement) }
        var output: [Waypoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)),
                  let kind = WaypointKind(rawValue: text(statement, 1))
            else { continue }
            output.append(
                Waypoint(
                    id: id,
                    kind: kind,
                    coordinate: GeoCoordinate(
                        latitude: sqlite3_column_double(statement, 2),
                        longitude: sqlite3_column_double(statement, 3)
                    ),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    note: text(statement, 5),
                    photoRelativePath: nullableText(statement, 6),
                    audioRelativePath: nullableText(statement, 7)
                )
            )
        }
        return output
    }

    public func save(waypoint: Waypoint) throws {
        try prepare()
        let statement = try prepared(
            "INSERT INTO waypoints(id,kind,latitude,longitude,created_at,note,photo_path,audio_path) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,latitude=excluded.latitude,longitude=excluded.longitude,note=excluded.note,photo_path=excluded.photo_path,audio_path=excluded.audio_path"
        )
        defer { sqlite3_finalize(statement) }
        bind(waypoint.id.uuidString, at: 1, to: statement)
        bind(waypoint.kind.rawValue, at: 2, to: statement)
        sqlite3_bind_double(statement, 3, waypoint.coordinate.latitude)
        sqlite3_bind_double(statement, 4, waypoint.coordinate.longitude)
        sqlite3_bind_double(statement, 5, waypoint.createdAt.timeIntervalSince1970)
        bind(waypoint.note, at: 6, to: statement)
        bindNullable(waypoint.photoRelativePath, at: 7, to: statement)
        bindNullable(waypoint.audioRelativePath, at: 8, to: statement)
        try stepDone(statement)
    }

    public func deleteWaypoint(id: UUID) throws {
        try prepare()
        let ownedDirectory = attachmentsDirectory.appendingPathComponent(
            id.uuidString,
            isDirectory: true
        )
        try executeBound("DELETE FROM waypoints WHERE id=?", value: id.uuidString)
        try? FileManager.default.removeItem(at: ownedDirectory)
    }

    public func attachmentDirectory(for waypointID: UUID) throws -> URL {
        try prepare()
        let directory = attachmentsDirectory.appendingPathComponent(
            waypointID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func queryTrails(_ sql: String) throws -> [Trail] {
        let statement = try prepared(sql)
        defer { sqlite3_finalize(statement) }
        var output: [Trail] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)),
                  let state = TrailRecordingState(rawValue: text(statement, 4))
            else { continue }
            let endedAt = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let lastResumedAt = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
            output.append(
                Trail(
                    id: id,
                    name: text(statement, 1),
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    endedAt: endedAt,
                    state: state,
                    accumulatedActiveSeconds: sqlite3_column_double(statement, 5),
                    lastResumedAt: lastResumedAt
                )
            )
        }
        return output
    }

    private func executeBound(_ sql: String, value: String) throws {
        let statement = try prepared(sql)
        defer { sqlite3_finalize(statement) }
        bind(value, at: 1, to: statement)
        try stepDone(statement)
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw SurvivalMapStoreError.statementFailed }
        return statement
    }

    private func execute(_ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SurvivalMapStoreError.statementFailed
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func bindNullable(_ value: String?, at index: Int32, to statement: OpaquePointer) {
        if let value { bind(value, at: index, to: statement) }
        else { sqlite3_bind_null(statement, index) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func nullableText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static let schema = """
    CREATE TABLE IF NOT EXISTS trails(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        started_at REAL NOT NULL,
        ended_at REAL,
        state TEXT NOT NULL
        ,active_seconds REAL NOT NULL DEFAULT 0
        ,last_resumed_at REAL
    );
    CREATE TABLE IF NOT EXISTS track_points(
        id TEXT PRIMARY KEY,
        trail_id TEXT NOT NULL REFERENCES trails(id) ON DELETE CASCADE,
        sequence INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL NOT NULL,
        h_accuracy REAL NOT NULL,
        v_accuracy REAL NOT NULL,
        speed REAL NOT NULL,
        course REAL NOT NULL,
        heading REAL,
        timestamp REAL NOT NULL,
        UNIQUE(trail_id, sequence)
    );
    CREATE INDEX IF NOT EXISTS track_points_trail_sequence
        ON track_points(trail_id, sequence);
    CREATE TABLE IF NOT EXISTS checkpoints(
        id TEXT PRIMARY KEY,
        trail_id TEXT NOT NULL REFERENCES trails(id) ON DELETE CASCADE,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at REAL NOT NULL,
        distance_meters REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS waypoints(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        created_at REAL NOT NULL,
        note TEXT NOT NULL,
        photo_path TEXT,
        audio_path TEXT
    );
    """
}
