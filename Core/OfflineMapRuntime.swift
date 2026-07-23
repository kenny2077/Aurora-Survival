import Foundation

public struct OfflineMapSession: Equatable, Sendable {
    public let packID: String
    public let packVersion: String
    public let bounds: GeoBounds
    public let detailTier: MapDetailTier
    public let supportsRouting: Bool

    public init(
        packID: String,
        packVersion: String,
        bounds: GeoBounds,
        detailTier: MapDetailTier,
        supportsRouting: Bool
    ) {
        self.packID = packID
        self.packVersion = packVersion
        self.bounds = bounds
        self.detailTier = detailTier
        self.supportsRouting = supportsRouting
    }
}

public enum OfflineMapRuntimeError: Error, Equatable {
    case notReady([MapReadinessIssue])
}

public protocol OfflineMapRuntime: Sendable {
    func open(
        pack: OfflineMapPack,
        packageDirectory: URL,
        tripCoordinate: GeoCoordinate?,
        requiredTier: MapDetailTier,
        requiresOfflineRouting: Bool
    ) throws -> OfflineMapSession
}

/// A dependency-free runtime boundary used before MapLibre is linked. It opens
/// only verified local artifacts and performs no network requests.
public struct FileBackedOfflineMapRuntime: OfflineMapRuntime {
    private let readiness: MapReadinessEvaluator

    public init(readiness: MapReadinessEvaluator = MapReadinessEvaluator()) {
        self.readiness = readiness
    }

    public func open(
        pack: OfflineMapPack,
        packageDirectory: URL,
        tripCoordinate: GeoCoordinate?,
        requiredTier: MapDetailTier,
        requiresOfflineRouting: Bool
    ) throws -> OfflineMapSession {
        let result = readiness.evaluate(
            pack: pack,
            packageDirectory: packageDirectory,
            tripCoordinate: tripCoordinate,
            requiredTier: requiredTier,
            requiresOfflineRouting: requiresOfflineRouting
        )
        guard result.isReady else {
            throw OfflineMapRuntimeError.notReady(result.issues)
        }
        return OfflineMapSession(
            packID: pack.id,
            packVersion: pack.version,
            bounds: pack.bounds,
            detailTier: pack.tier,
            supportsRouting: pack.routingGraphPath != nil
        )
    }
}
