import Foundation

public enum MapDetailTier: String, Codable, CaseIterable, Comparable, Sendable {
    case scout
    case field
    case expedition

    public static func < (lhs: MapDetailTier, rhs: MapDetailTier) -> Bool {
        let order: [MapDetailTier] = [.scout, .field, .expedition]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }

    public var displayName: String { rawValue.capitalized }
}

public struct GeoCoordinate: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

public struct GeoBounds: Codable, Hashable, Sendable {
    public let southWest: GeoCoordinate
    public let northEast: GeoCoordinate

    public init(southWest: GeoCoordinate, northEast: GeoCoordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }

    public var isValid: Bool {
        southWest.isValid
            && northEast.isValid
            && southWest.latitude < northEast.latitude
            && southWest.longitude < northEast.longitude
    }

    public func contains(_ coordinate: GeoCoordinate) -> Bool {
        guard isValid, coordinate.isValid else { return false }
        return (southWest.latitude...northEast.latitude).contains(coordinate.latitude)
            && (southWest.longitude...northEast.longitude).contains(coordinate.longitude)
    }
}

public struct OfflineMapPack: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let regionCode: String
    public let tier: MapDetailTier
    public let version: String
    public let generatedAt: String
    public let recommendedRefreshAfter: String
    public let bounds: GeoBounds
    public let pmtilesPath: String
    public let stylePath: String
    public let routingGraphPath: String?
    public let byteCount: Int64

    public init(
        id: String,
        name: String,
        regionCode: String,
        tier: MapDetailTier,
        version: String,
        generatedAt: String,
        recommendedRefreshAfter: String,
        bounds: GeoBounds,
        pmtilesPath: String,
        stylePath: String,
        routingGraphPath: String? = nil,
        byteCount: Int64
    ) {
        self.id = id
        self.name = name
        self.regionCode = regionCode
        self.tier = tier
        self.version = version
        self.generatedAt = generatedAt
        self.recommendedRefreshAfter = recommendedRefreshAfter
        self.bounds = bounds
        self.pmtilesPath = pmtilesPath
        self.stylePath = stylePath
        self.routingGraphPath = routingGraphPath
        self.byteCount = byteCount
    }
}

public enum MapReadinessIssue: String, Codable, Hashable, Sendable {
    case invalidBounds
    case mapFileMissing
    case styleFileMissing
    case routingGraphMissing
    case outsideDownloadedRegion
    case detailTierTooLow
    case refreshRecommended
}

public struct MapReadinessResult: Equatable, Sendable {
    public let isReady: Bool
    public let issues: [MapReadinessIssue]

    public init(isReady: Bool, issues: [MapReadinessIssue]) {
        self.isReady = isReady
        self.issues = issues
    }
}

public struct MapReadinessEvaluator: Sendable {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func evaluate(
        pack: OfflineMapPack,
        packageDirectory: URL,
        tripCoordinate: GeoCoordinate?,
        requiredTier: MapDetailTier,
        requiresOfflineRouting: Bool
    ) -> MapReadinessResult {
        var issues: [MapReadinessIssue] = []
        if !pack.bounds.isValid {
            issues.append(.invalidBounds)
        }

        if !Self.regularFileExists(pack.pmtilesPath, in: packageDirectory) {
            issues.append(.mapFileMissing)
        }
        if !Self.regularFileExists(pack.stylePath, in: packageDirectory) {
            issues.append(.styleFileMissing)
        }
        if requiresOfflineRouting {
            guard let path = pack.routingGraphPath,
                  Self.regularFileExists(path, in: packageDirectory)
            else {
                issues.append(.routingGraphMissing)
                return MapReadinessResult(isReady: false, issues: issues)
            }
        }
        if let tripCoordinate, !pack.bounds.contains(tripCoordinate) {
            issues.append(.outsideDownloadedRegion)
        }
        if pack.tier < requiredTier {
            issues.append(.detailTierTooLow)
        }
        if let refreshDate = ISO8601DateFormatter().date(
            from: pack.recommendedRefreshAfter
        ), now() > refreshDate {
            issues.append(.refreshRecommended)
        }
        return MapReadinessResult(isReady: issues.isEmpty, issues: issues)
    }

    private static func regularFileExists(_ relativePath: String, in root: URL) -> Bool {
        guard let url = try? PackageVerifier.safeArtifactURL(path: relativePath, root: root),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        else { return false }
        return values.isRegularFile == true
    }
}
