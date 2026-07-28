import Foundation

public struct PreparationState: Codable, Equatable, Sendable {
    public let vehicleProfile: VehicleProfile?
    public let completedReadinessIDs: Set<String>
    public let preferredTier: ModelTier

    public init(
        vehicleProfile: VehicleProfile?,
        completedReadinessIDs: Set<String>,
        preferredTier: ModelTier
    ) {
        self.vehicleProfile = vehicleProfile
        self.completedReadinessIDs = completedReadinessIDs
        self.preferredTier = preferredTier
    }
}

public enum PreparationStateStoreError: Error, Equatable {
    case invalidData
    case persistenceFailed
}

public struct PreparationStateStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> PreparationState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(
                PreparationState.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            throw PreparationStateStoreError.invalidData
        }
    }

    public func save(_ state: PreparationState) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder.trailGuard.encode(state).write(
                to: fileURL,
                options: [.atomic]
            )
        } catch {
            throw PreparationStateStoreError.persistenceFailed
        }
    }
}
