import Foundation

public struct OBDObservationRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let capturedAt: String
    public let adapterID: String
    public let vehicle: VehicleProfile
    public let rawResponse: String
    public let troubleCodes: [DiagnosticTroubleCode]
    public let sourceIDs: [String]

    public init(
        id: String,
        capturedAt: String,
        adapterID: String,
        vehicle: VehicleProfile,
        rawResponse: String,
        troubleCodes: [DiagnosticTroubleCode],
        sourceIDs: [String]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.adapterID = adapterID
        self.vehicle = vehicle
        self.rawResponse = rawResponse
        self.troubleCodes = troubleCodes
        self.sourceIDs = sourceIDs
    }
}

public enum OBDObservationStoreError: Error, Equatable {
    case invalidRecord
    case persistenceFailed
}

public actor OBDObservationStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private var records: [OBDObservationRecord]

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(
               [OBDObservationRecord].self,
               from: data
           ) {
            records = decoded
        } else {
            records = []
        }
    }

    public func append(_ record: OBDObservationRecord) throws {
        guard !record.id.isEmpty,
              !record.adapterID.isEmpty,
              record.vehicle.isPlausible,
              ISO8601DateFormatter().date(from: record.capturedAt) != nil,
              !record.rawResponse.isEmpty
        else {
            throw OBDObservationStoreError.invalidRecord
        }
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.capturedAt < $1.capturedAt }
        try persist()
    }

    public func all(for vehicle: VehicleProfile) -> [OBDObservationRecord] {
        records.filter { $0.vehicle == vehicle }
    }

    private func persist() throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder.trailGuard.encode(records).write(
                to: fileURL,
                options: [.atomic]
            )
        } catch {
            throw OBDObservationStoreError.persistenceFailed
        }
    }
}
