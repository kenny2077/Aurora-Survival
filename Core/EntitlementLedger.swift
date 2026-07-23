import Foundation

public enum EntitlementEventKind: String, Codable, Sendable {
    case purchased
    case renewed
    case restored
    case familyShared = "family_shared"
    case refunded
    case revoked
}

public struct VerifiedEntitlementEvent: Codable, Equatable, Sendable {
    public let eventID: String
    public let productID: String
    public let kind: EntitlementEventKind
    public let verifiedAt: String
    public let verificationSucceeded: Bool

    public init(
        eventID: String,
        productID: String,
        kind: EntitlementEventKind,
        verifiedAt: String,
        verificationSucceeded: Bool
    ) {
        self.eventID = eventID
        self.productID = productID
        self.kind = kind
        self.verifiedAt = verifiedAt
        self.verificationSucceeded = verificationSucceeded
    }
}

public struct EntitlementRecord: Codable, Equatable, Sendable {
    public let productID: String
    public let isActive: Bool
    public let lastVerifiedAt: String
    public let lastEventID: String
    public let source: EntitlementEventKind

    public init(
        productID: String,
        isActive: Bool,
        lastVerifiedAt: String,
        lastEventID: String,
        source: EntitlementEventKind
    ) {
        self.productID = productID
        self.isActive = isActive
        self.lastVerifiedAt = lastVerifiedAt
        self.lastEventID = lastEventID
        self.source = source
    }
}

public struct EntitlementLedgerState: Codable, Equatable, Sendable {
    public var records: [String: EntitlementRecord]
    public var processedEventIDs: Set<String>

    public init(
        records: [String: EntitlementRecord] = [:],
        processedEventIDs: Set<String> = []
    ) {
        self.records = records
        self.processedEventIDs = processedEventIDs
    }
}

public enum EntitlementLedgerError: Error, Equatable {
    case unverifiedEvent
    case invalidEvent
    case persistenceFailed
}

public actor EntitlementLedger {
    private let fileURL: URL
    private let fileManager: FileManager
    private var state: EntitlementLedgerState

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(
               EntitlementLedgerState.self,
               from: data
           ) {
            state = decoded
        } else {
            state = EntitlementLedgerState()
        }
    }

    public func apply(_ event: VerifiedEntitlementEvent) throws {
        guard event.verificationSucceeded else {
            throw EntitlementLedgerError.unverifiedEvent
        }
        guard !event.eventID.isEmpty,
              !event.productID.isEmpty,
              ISO8601DateFormatter().date(from: event.verifiedAt) != nil
        else {
            throw EntitlementLedgerError.invalidEvent
        }
        guard !state.processedEventIDs.contains(event.eventID) else {
            return
        }

        let isActive: Bool
        switch event.kind {
        case .purchased, .renewed, .restored, .familyShared:
            isActive = true
        case .refunded, .revoked:
            isActive = false
        }
        state.records[event.productID] = EntitlementRecord(
            productID: event.productID,
            isActive: isActive,
            lastVerifiedAt: event.verifiedAt,
            lastEventID: event.eventID,
            source: event.kind
        )
        state.processedEventIDs.insert(event.eventID)
        try persist()
    }

    public func snapshots() -> [EntitlementSnapshot] {
        state.records.values
            .filter(\.isActive)
            .map {
                EntitlementSnapshot(
                    productID: $0.productID,
                    verified: true,
                    verifiedAt: $0.lastVerifiedAt
                )
            }
            .sorted { $0.productID < $1.productID }
    }

    public func record(for productID: String) -> EntitlementRecord? {
        state.records[productID]
    }

    private func persist() throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder.trailGuard.encode(state).write(
                to: fileURL,
                options: [.atomic]
            )
        } catch {
            throw EntitlementLedgerError.persistenceFailed
        }
    }
}
