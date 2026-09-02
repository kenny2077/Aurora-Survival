#if AURORA_MESH_BETA
import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct AuroraStoredMeshEnvelope: Sendable {
    public let packet: AuroraMeshWirePacket
    public let groupID: UUID
    public let firstSeenAt: Date
}

public struct AuroraStoredMeshDisplayName: Sendable {
    public let groupID: UUID
    public let memberID: String
    public let displayName: String
    public let sequence: UInt64
}

public final class AuroraMeshStore: @unchecked Sendable {
    private let databaseURL: URL
    private let lock = NSLock()
    #if canImport(SQLite3)
    private var database: OpaquePointer?
    #endif

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if canImport(SQLite3)
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else { throw AuroraMeshError.persistenceFailed }
        guard execute("PRAGMA journal_mode=WAL;"),
              execute("PRAGMA foreign_keys=ON;"),
              execute(Self.schema)
        else { throw AuroraMeshError.persistenceFailed }
        #else
        throw AuroraMeshError.persistenceFailed
        #endif
    }

    deinit {
        #if canImport(SQLite3)
        sqlite3_close(database)
        #endif
    }

    public func save(group: AuroraMeshGroup) throws {
        let data = try Self.encoder.encode(group)
        try locked {
            try run(
                "INSERT OR REPLACE INTO mesh_groups(id, document) VALUES(?, ?);",
                bindings: [.text(group.id.uuidString), .blob(data)]
            )
        }
    }

    public func groups() throws -> [AuroraMeshGroup] {
        try locked {
            let rows = try query("SELECT document FROM mesh_groups ORDER BY id;", bindings: [])
            return try rows.compactMap { row in
                guard case let .blob(data) = row[0] else { return nil }
                return try Self.decoder.decode(AuroraMeshGroup.self, from: data)
            }
        }
    }

    public func markGroupEnded(
        _ group: AuroraMeshGroup,
        terminationPacket: AuroraMeshWirePacket,
        firstSeenAt: Date
    ) throws {
        let document = try Self.encoder.encode(group)
        let wire = try AuroraMeshWireCodec.encode(terminationPacket)
        try locked {
            try run("BEGIN IMMEDIATE;", bindings: [])
            do {
                try run(
                    "INSERT OR REPLACE INTO mesh_groups(id, document) VALUES(?, ?);",
                    bindings: [.text(group.id.uuidString), .blob(document)]
                )
                try run(
                    """
                    INSERT OR REPLACE INTO mesh_envelopes
                        (message_id, group_id, first_seen, wire)
                    VALUES(?, ?, ?, ?);
                    """,
                    bindings: [
                        .text(terminationPacket.messageID.uuidString),
                        .text(group.id.uuidString),
                        .double(firstSeenAt.timeIntervalSince1970),
                        .blob(wire),
                    ]
                )
                try run(
                    """
                    DELETE FROM mesh_acknowledgements
                    WHERE message_id IN (
                      SELECT message_id FROM mesh_envelopes WHERE group_id = ?
                    );
                    """,
                    bindings: [.text(group.id.uuidString)]
                )
                try run(
                    "DELETE FROM mesh_envelopes WHERE group_id = ? AND message_id != ?;",
                    bindings: [.text(group.id.uuidString), .text(terminationPacket.messageID.uuidString)]
                )
                for table in [
                    "mesh_sender_sequences",
                    "mesh_sync_indexes",
                    "mesh_seen_sequences",
                    "mesh_display_names",
                ] {
                    try run("DELETE FROM \(table) WHERE group_id = ?;", bindings: [.text(group.id.uuidString)])
                }
                try run("COMMIT;", bindings: [])
            } catch {
                try? run("ROLLBACK;", bindings: [])
                throw error
            }
        }
    }

    public func terminationPacket(groupID: UUID) throws -> AuroraMeshWirePacket? {
        try locked {
            let rows = try query(
                "SELECT wire FROM mesh_envelopes WHERE group_id = ? ORDER BY first_seen DESC LIMIT 1;",
                bindings: [.text(groupID.uuidString)]
            )
            guard let row = rows.first, case let .blob(wire) = row[0] else { return nil }
            return try AuroraMeshWireCodec.decode(wire)
        }
    }

    public func purgeGroup(groupID: UUID) throws {
        try locked {
            try run("BEGIN IMMEDIATE;", bindings: [])
            do {
                try run(
                    """
                    DELETE FROM mesh_acknowledgements
                    WHERE message_id IN (
                      SELECT message_id FROM mesh_envelopes WHERE group_id = ?
                    );
                    """,
                    bindings: [.text(groupID.uuidString)]
                )
                for table in [
                    "mesh_envelopes",
                    "mesh_sender_sequences",
                    "mesh_sync_indexes",
                    "mesh_key_epochs",
                    "mesh_seen_sequences",
                    "mesh_display_names",
                    "mesh_groups",
                ] {
                    try run("DELETE FROM \(table) WHERE \(table == "mesh_groups" ? "id" : "group_id") = ?;", bindings: [.text(groupID.uuidString)])
                }
                try run("COMMIT;", bindings: [])
            } catch {
                try? run("ROLLBACK;", bindings: [])
                throw error
            }
        }
    }

    public func recordDisplayName(
        _ displayName: String,
        groupID: UUID,
        memberID: String,
        sequence: UInt64
    ) throws {
        try locked {
            try run(
                """
                INSERT INTO mesh_display_names(group_id, member_id, display_name, sequence)
                VALUES(?, ?, ?, ?)
                ON CONFLICT(group_id, member_id) DO UPDATE SET
                  display_name = excluded.display_name,
                  sequence = excluded.sequence
                WHERE excluded.sequence > mesh_display_names.sequence;
                """,
                bindings: [
                    .text(groupID.uuidString),
                    .text(memberID),
                    .text(displayName),
                    .integer(Int64(clamping: sequence)),
                ]
            )
        }
    }

    public func displayNameRecords() throws -> [AuroraStoredMeshDisplayName] {
        try locked {
            let rows = try query(
                "SELECT group_id, member_id, display_name, sequence FROM mesh_display_names;",
                bindings: []
            )
            return rows.compactMap { row in
                guard case let .text(groupText) = row[0],
                      let groupID = UUID(uuidString: groupText),
                      case let .text(memberID) = row[1],
                      case let .text(displayName) = row[2],
                      case let .integer(sequence) = row[3], sequence >= 0
                else { return nil }
                return AuroraStoredMeshDisplayName(
                    groupID: groupID,
                    memberID: memberID,
                    displayName: displayName,
                    sequence: UInt64(sequence)
                )
            }
        }
    }

    public func displayNamesByGroup() throws -> [UUID: [String: String]] {
        var names: [UUID: [String: String]] = [:]
        for record in try displayNameRecords() {
            names[record.groupID, default: [:]][record.memberID] = record.displayName
        }
        return names
    }

    public func save(
        packet: AuroraMeshWirePacket,
        groupID: UUID,
        firstSeenAt: Date
    ) throws {
        let wire = try AuroraMeshWireCodec.encode(packet)
        try locked {
            try run(
                """
                INSERT OR IGNORE INTO mesh_envelopes
                    (message_id, group_id, first_seen, wire)
                VALUES(?, ?, ?, ?);
                """,
                bindings: [
                    .text(packet.messageID.uuidString),
                    .text(groupID.uuidString),
                    .double(firstSeenAt.timeIntervalSince1970),
                    .blob(wire),
                ]
            )
        }
    }

    public func envelopes(
        groupID: UUID,
        since: Date,
        limit: Int = AuroraMeshLimits.maximumCatchUpMessages
    ) throws -> [AuroraStoredMeshEnvelope] {
        try locked {
            let rows = try query(
                """
                SELECT first_seen, wire FROM mesh_envelopes
                WHERE group_id = ? AND first_seen >= ?
                  AND message_id NOT IN (SELECT message_id FROM mesh_tombstones)
                ORDER BY first_seen ASC LIMIT ?;
                """,
                bindings: [
                    .text(groupID.uuidString),
                    .double(since.timeIntervalSince1970),
                    .integer(Int64(max(1, min(limit, AuroraMeshLimits.maximumCatchUpMessages)))),
                ]
            )
            return try rows.compactMap { row in
                guard case let .double(timestamp) = row[0],
                      case let .blob(wire) = row[1]
                else { return nil }
                return AuroraStoredMeshEnvelope(
                    packet: try AuroraMeshWireCodec.decode(wire),
                    groupID: groupID,
                    firstSeenAt: Date(timeIntervalSince1970: timestamp)
                )
            }
        }
    }

    public func recordAcknowledgement(messageID: UUID, memberID: String) throws {
        try locked {
            try run(
                "INSERT OR IGNORE INTO mesh_acknowledgements(message_id, member_id) VALUES(?, ?);",
                bindings: [.text(messageID.uuidString), .text(memberID)]
            )
        }
    }

    public func acknowledgementMemberIDs(messageID: UUID) throws -> Set<String> {
        try locked {
            let rows = try query(
                "SELECT member_id FROM mesh_acknowledgements WHERE message_id = ?;",
                bindings: [.text(messageID.uuidString)]
            )
            return Set(rows.compactMap { row in
                guard case let .text(value) = row[0] else { return nil }
                return value
            })
        }
    }

    public func saveSenderSequence(_ sequence: UInt64, groupID: UUID, senderID: String) throws {
        try locked {
            try run(
                "INSERT OR REPLACE INTO mesh_sender_sequences(group_id, sender_id, sequence) VALUES(?, ?, ?);",
                bindings: [.text(groupID.uuidString), .text(senderID), .integer(Int64(clamping: sequence))]
            )
        }
    }

    public func recordKeyEpoch(groupID: UUID, epoch: Int) throws {
        try locked {
            try run(
                "INSERT OR IGNORE INTO mesh_key_epochs(group_id, epoch) VALUES(?, ?);",
                bindings: [.text(groupID.uuidString), .integer(Int64(epoch))]
            )
        }
    }

    public func keyEpochs(groupID: UUID) throws -> [Int] {
        try locked {
            try query(
                "SELECT epoch FROM mesh_key_epochs WHERE group_id = ? ORDER BY epoch;",
                bindings: [.text(groupID.uuidString)]
            ).compactMap { row in
                guard case let .integer(value) = row[0] else { return nil }
                return Int(value)
            }
        }
    }

    public func deleteKeyEpoch(groupID: UUID, epoch: Int) throws {
        try locked {
            try run(
                "DELETE FROM mesh_key_epochs WHERE group_id = ? AND epoch = ?;",
                bindings: [.text(groupID.uuidString), .integer(Int64(epoch))]
            )
        }
    }

    public func senderSequence(groupID: UUID, senderID: String) throws -> UInt64 {
        try locked {
            let rows = try query(
                "SELECT sequence FROM mesh_sender_sequences WHERE group_id = ? AND sender_id = ? LIMIT 1;",
                bindings: [.text(groupID.uuidString), .text(senderID)]
            )
            guard let row = rows.first, case let .integer(value) = row[0], value >= 0 else { return 0 }
            return UInt64(value)
        }
    }

    public func recordSyncIndex(groupID: UUID, senderID: String, sequence: UInt64) throws {
        try locked {
            try run(
                """
                INSERT INTO mesh_sync_indexes(group_id, sender_id, sequence) VALUES(?, ?, ?)
                ON CONFLICT(group_id, sender_id) DO UPDATE SET sequence = MAX(sequence, excluded.sequence);
                """,
                bindings: [.text(groupID.uuidString), .text(senderID), .integer(Int64(clamping: sequence))]
            )
        }
    }

    public func syncIndex(groupID: UUID, senderID: String) throws -> UInt64 {
        try locked {
            let rows = try query(
                "SELECT sequence FROM mesh_sync_indexes WHERE group_id = ? AND sender_id = ? LIMIT 1;",
                bindings: [.text(groupID.uuidString), .text(senderID)]
            )
            guard let row = rows.first, case let .integer(value) = row[0], value >= 0 else { return 0 }
            return UInt64(value)
        }
    }

    public func syncIndexes(groupID: UUID) throws -> [String: UInt64] {
        try locked {
            let rows = try query(
                "SELECT sender_id, sequence FROM mesh_sync_indexes WHERE group_id = ?;",
                bindings: [.text(groupID.uuidString)]
            )
            return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard case let .text(senderID) = row[0],
                      case let .integer(value) = row[1], value >= 0
                else { return nil }
                return (senderID, UInt64(value))
            })
        }
    }

    public func hasSeenSequence(groupID: UUID, senderID: String, sequence: UInt64) throws -> Bool {
        try locked {
            try !query(
                "SELECT 1 FROM mesh_seen_sequences WHERE group_id = ? AND sender_id = ? AND sequence = ? LIMIT 1;",
                bindings: [
                    .text(groupID.uuidString),
                    .text(senderID),
                    .integer(Int64(clamping: sequence)),
                ]
            ).isEmpty
        }
    }

    public func recordSeenSequence(groupID: UUID, senderID: String, sequence: UInt64) throws {
        try locked {
            try run(
                "INSERT OR IGNORE INTO mesh_seen_sequences(group_id, sender_id, sequence) VALUES(?, ?, ?);",
                bindings: [
                    .text(groupID.uuidString),
                    .text(senderID),
                    .integer(Int64(clamping: sequence)),
                ]
            )
            let floor = sequence > AuroraMeshLimits.maximumSequenceReorderWindow
                ? sequence - AuroraMeshLimits.maximumSequenceReorderWindow
                : 0
            try run(
                "DELETE FROM mesh_seen_sequences WHERE group_id = ? AND sender_id = ? AND sequence < ?;",
                bindings: [
                    .text(groupID.uuidString),
                    .text(senderID),
                    .integer(Int64(clamping: floor)),
                ]
            )
        }
    }

    public func historyPage(groupID: UUID, before: Date? = nil, limit: Int = 100) throws -> [AuroraStoredMeshEnvelope] {
        try locked {
            let boundedLimit = max(1, min(100, limit))
            let sql: String
            let bindings: [Value]
            if let before {
                sql = """
                SELECT first_seen, wire FROM mesh_envelopes
                WHERE group_id = ? AND first_seen < ?
                  AND message_id NOT IN (SELECT message_id FROM mesh_tombstones)
                ORDER BY first_seen DESC LIMIT ?;
                """
                bindings = [.text(groupID.uuidString), .double(before.timeIntervalSince1970), .integer(Int64(boundedLimit))]
            } else {
                sql = """
                SELECT first_seen, wire FROM mesh_envelopes
                WHERE group_id = ? AND message_id NOT IN (SELECT message_id FROM mesh_tombstones)
                ORDER BY first_seen DESC LIMIT ?;
                """
                bindings = [.text(groupID.uuidString), .integer(Int64(boundedLimit))]
            }
            let rows = try query(sql, bindings: bindings)
            return try rows.reversed().compactMap { row in
                guard case let .double(timestamp) = row[0], case let .blob(wire) = row[1] else { return nil }
                return AuroraStoredMeshEnvelope(
                    packet: try AuroraMeshWireCodec.decode(wire),
                    groupID: groupID,
                    firstSeenAt: Date(timeIntervalSince1970: timestamp)
                )
            }
        }
    }

    public func tombstone(messageID: UUID, at date: Date = Date()) throws {
        try locked {
            try run(
                "INSERT OR REPLACE INTO mesh_tombstones(message_id, deleted_at) VALUES(?, ?);",
                bindings: [.text(messageID.uuidString), .double(date.timeIntervalSince1970)]
            )
            try run(
                "DELETE FROM mesh_envelopes WHERE message_id = ?;",
                bindings: [.text(messageID.uuidString)]
            )
        }
    }

    public func isTombstoned(messageID: UUID) -> Bool {
        (try? locked {
            try !query(
                "SELECT 1 FROM mesh_tombstones WHERE message_id = ? LIMIT 1;",
                bindings: [.text(messageID.uuidString)]
            ).isEmpty
        }) ?? false
    }

    public func deleteHistory(groupID: UUID, at date: Date = Date()) throws {
        try locked {
            try run("BEGIN IMMEDIATE;", bindings: [])
            do {
                try run(
                    """
                    INSERT OR REPLACE INTO mesh_tombstones(message_id, deleted_at)
                    SELECT message_id, ? FROM mesh_envelopes WHERE group_id = ?;
                    """,
                    bindings: [.double(date.timeIntervalSince1970), .text(groupID.uuidString)]
                )
                try run(
                    """
                    DELETE FROM mesh_acknowledgements
                    WHERE message_id IN (
                      SELECT message_id FROM mesh_envelopes WHERE group_id = ?
                    );
                    """,
                    bindings: [.text(groupID.uuidString)]
                )
                try run(
                    "DELETE FROM mesh_envelopes WHERE group_id = ?;",
                    bindings: [.text(groupID.uuidString)]
                )
                try run("COMMIT;", bindings: [])
            } catch {
                try? run("ROLLBACK;", bindings: [])
                throw error
            }
        }
    }

    public func pruneTombstones(olderThan date: Date) throws {
        try locked {
            try run(
                "DELETE FROM mesh_tombstones WHERE deleted_at < ?;",
                bindings: [.double(date.timeIntervalSince1970)]
            )
        }
    }

    public func isInvitationConsumed(_ invitationID: UUID) -> Bool {
        (try? locked {
            try !query(
                "SELECT 1 FROM mesh_consumed_invitations WHERE invitation_id = ? LIMIT 1;",
                bindings: [.text(invitationID.uuidString)]
            ).isEmpty
        }) ?? false
    }

    public func markInvitationConsumed(_ invitationID: UUID, at date: Date) throws {
        try locked {
            try run(
                "INSERT OR IGNORE INTO mesh_consumed_invitations(invitation_id, consumed_at) VALUES(?, ?);",
                bindings: [.text(invitationID.uuidString), .double(date.timeIntervalSince1970)]
            )
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    #if canImport(SQLite3)
    private enum Value {
        case text(String)
        case blob(Data)
        case integer(Int64)
        case double(Double)
        case null
    }

    private func execute(_ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func run(_ sql: String, bindings: [Value]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AuroraMeshError.persistenceFailed
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AuroraMeshError.persistenceFailed
        }
    }

    private func query(_ sql: String, bindings: [Value]) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AuroraMeshError.persistenceFailed
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [[Value]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { index in
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: return .double(sqlite3_column_double(statement, index))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    guard let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
                    return .blob(Data(bytes: bytes, count: count))
                case SQLITE_TEXT:
                    guard let text = sqlite3_column_text(statement, index) else { return .text("") }
                    return .text(String(cString: text))
                default: return .null
                }
            })
        }
        return rows
    }

    private func bind(_ values: [Value], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case let .text(text):
                result = sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case let .blob(data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), Self.transient)
                }
            case let .integer(integer): result = sqlite3_bind_int64(statement, index, integer)
            case let .double(double): result = sqlite3_bind_double(statement, index, double)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw AuroraMeshError.persistenceFailed }
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let schema = """
    CREATE TABLE IF NOT EXISTS mesh_schema(version INTEGER NOT NULL);
    INSERT INTO mesh_schema(version)
      SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM mesh_schema);
    CREATE TABLE IF NOT EXISTS mesh_groups(
      id TEXT PRIMARY KEY NOT NULL,
      document BLOB NOT NULL
    );
    CREATE TABLE IF NOT EXISTS mesh_envelopes(
      message_id TEXT PRIMARY KEY NOT NULL,
      group_id TEXT NOT NULL,
      first_seen REAL NOT NULL,
      wire BLOB NOT NULL
    );
    CREATE INDEX IF NOT EXISTS mesh_envelopes_group_seen
      ON mesh_envelopes(group_id, first_seen);
    CREATE TABLE IF NOT EXISTS mesh_acknowledgements(
      message_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      PRIMARY KEY(message_id, member_id)
    );
    CREATE TABLE IF NOT EXISTS mesh_tombstones(
      message_id TEXT PRIMARY KEY NOT NULL,
      deleted_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS mesh_sender_sequences(
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      PRIMARY KEY(group_id, sender_id)
    );
    CREATE TABLE IF NOT EXISTS mesh_sync_indexes(
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      PRIMARY KEY(group_id, sender_id)
    );
    CREATE TABLE IF NOT EXISTS mesh_key_epochs(
      group_id TEXT NOT NULL,
      epoch INTEGER NOT NULL,
      PRIMARY KEY(group_id, epoch)
    );
    CREATE TABLE IF NOT EXISTS mesh_seen_sequences(
      group_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      PRIMARY KEY(group_id, sender_id, sequence)
    );
    CREATE TABLE IF NOT EXISTS mesh_consumed_invitations(
      invitation_id TEXT PRIMARY KEY NOT NULL,
      consumed_at REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS mesh_display_names(
      group_id TEXT NOT NULL,
      member_id TEXT NOT NULL,
      display_name TEXT NOT NULL,
      sequence INTEGER NOT NULL,
      PRIMARY KEY(group_id, member_id)
    );
    UPDATE mesh_schema SET version = 2 WHERE version < 2;
    """
    #endif

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
#endif
