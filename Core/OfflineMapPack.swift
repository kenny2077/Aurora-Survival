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
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let regionCode: String
    public let tier: MapDetailTier
    public let version: String
    public let generatedAt: String
    public let recommendedRefreshAfter: String
    public let bounds: GeoBounds
    public let pmtilesPath: String
    public let sourcePaths: [String: String]
    public let stylePath: String
    public let stylePaths: [OfflineMapLayer: String]
    public let availableLayers: [OfflineMapLayer]
    public let minimumZoom: Int
    public let maximumZoom: Int
    public let sourceDate: String
    public let compressedByteCount: Int64
    public let unpackedByteCount: Int64
    public let minimumFreeStorageBytes: Int64
    public let glyphsDirectoryPath: String?
    public let routingGraphPath: String?
    public let byteCount: Int64

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        regionCode: String,
        tier: MapDetailTier,
        version: String,
        generatedAt: String,
        recommendedRefreshAfter: String,
        bounds: GeoBounds,
        pmtilesPath: String,
        sourcePaths: [String: String] = [:],
        stylePath: String,
        stylePaths: [OfflineMapLayer: String] = [:],
        availableLayers: [OfflineMapLayer] = [.legacy],
        minimumZoom: Int = 3,
        maximumZoom: Int = 16,
        sourceDate: String = "",
        compressedByteCount: Int64? = nil,
        unpackedByteCount: Int64? = nil,
        minimumFreeStorageBytes: Int64 = 0,
        glyphsDirectoryPath: String? = nil,
        routingGraphPath: String? = nil,
        byteCount: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.regionCode = regionCode
        self.tier = tier
        self.version = version
        self.generatedAt = generatedAt
        self.recommendedRefreshAfter = recommendedRefreshAfter
        self.bounds = bounds
        self.pmtilesPath = pmtilesPath
        self.sourcePaths = sourcePaths.isEmpty ? ["protomaps": pmtilesPath] : sourcePaths
        self.stylePath = stylePath
        self.stylePaths = stylePaths
        self.availableLayers = availableLayers.isEmpty ? [.legacy] : availableLayers
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
        self.sourceDate = sourceDate.isEmpty ? generatedAt : sourceDate
        self.compressedByteCount = compressedByteCount ?? byteCount
        self.unpackedByteCount = unpackedByteCount ?? byteCount
        self.minimumFreeStorageBytes = minimumFreeStorageBytes
        self.glyphsDirectoryPath = glyphsDirectoryPath
        self.routingGraphPath = routingGraphPath
        self.byteCount = byteCount
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, regionCode, tier, version, generatedAt
        case recommendedRefreshAfter, bounds, pmtilesPath, sourcePaths, stylePath, stylePaths
        case availableLayers, minimumZoom, maximumZoom, sourceDate
        case compressedByteCount, unpackedByteCount, minimumFreeStorageBytes
        case glyphsDirectoryPath, routingGraphPath, byteCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let regionCode = try container.decode(String.self, forKey: .regionCode)
        let tier = try container.decode(MapDetailTier.self, forKey: .tier)
        let version = try container.decode(String.self, forKey: .version)
        let generatedAt = try container.decode(String.self, forKey: .generatedAt)
        let byteCount = try container.decode(Int64.self, forKey: .byteCount)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            id: id,
            name: name,
            regionCode: regionCode,
            tier: tier,
            version: version,
            generatedAt: generatedAt,
            recommendedRefreshAfter: try container.decode(String.self, forKey: .recommendedRefreshAfter),
            bounds: try container.decode(GeoBounds.self, forKey: .bounds),
            pmtilesPath: try container.decode(String.self, forKey: .pmtilesPath),
            sourcePaths: try container.decodeIfPresent([String: String].self, forKey: .sourcePaths) ?? [:],
            stylePath: try container.decode(String.self, forKey: .stylePath),
            stylePaths: try container.decodeIfPresent([String: String].self, forKey: .stylePaths)?.reduce(into: [:]) {
                if let layer = OfflineMapLayer(rawValue: $1.key) { $0[layer] = $1.value }
            } ?? [:],
            availableLayers: try container.decodeIfPresent([OfflineMapLayer].self, forKey: .availableLayers) ?? [.legacy],
            minimumZoom: try container.decodeIfPresent(Int.self, forKey: .minimumZoom) ?? 3,
            maximumZoom: try container.decodeIfPresent(Int.self, forKey: .maximumZoom) ?? 16,
            sourceDate: try container.decodeIfPresent(String.self, forKey: .sourceDate) ?? generatedAt,
            compressedByteCount: try container.decodeIfPresent(Int64.self, forKey: .compressedByteCount) ?? byteCount,
            unpackedByteCount: try container.decodeIfPresent(Int64.self, forKey: .unpackedByteCount) ?? byteCount,
            minimumFreeStorageBytes: try container.decodeIfPresent(Int64.self, forKey: .minimumFreeStorageBytes) ?? 0,
            glyphsDirectoryPath: try container.decodeIfPresent(String.self, forKey: .glyphsDirectoryPath),
            routingGraphPath: try container.decodeIfPresent(String.self, forKey: .routingGraphPath),
            byteCount: byteCount
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(regionCode, forKey: .regionCode)
        try container.encode(tier, forKey: .tier)
        try container.encode(version, forKey: .version)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(recommendedRefreshAfter, forKey: .recommendedRefreshAfter)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(pmtilesPath, forKey: .pmtilesPath)
        try container.encode(sourcePaths, forKey: .sourcePaths)
        try container.encode(stylePath, forKey: .stylePath)
        try container.encode(
            Dictionary(uniqueKeysWithValues: stylePaths.map { ($0.key.rawValue, $0.value) }),
            forKey: .stylePaths
        )
        try container.encode(availableLayers, forKey: .availableLayers)
        try container.encode(minimumZoom, forKey: .minimumZoom)
        try container.encode(maximumZoom, forKey: .maximumZoom)
        try container.encode(sourceDate, forKey: .sourceDate)
        try container.encode(compressedByteCount, forKey: .compressedByteCount)
        try container.encode(unpackedByteCount, forKey: .unpackedByteCount)
        try container.encode(minimumFreeStorageBytes, forKey: .minimumFreeStorageBytes)
        try container.encodeIfPresent(glyphsDirectoryPath, forKey: .glyphsDirectoryPath)
        try container.encodeIfPresent(routingGraphPath, forKey: .routingGraphPath)
        try container.encode(byteCount, forKey: .byteCount)
    }
}

public enum MapReadinessIssue: String, Codable, Hashable, Sendable {
    case invalidBounds
    case mapFileMissing
    case styleFileMissing
    case glyphAssetsMissing
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
        if let glyphsDirectoryPath = pack.glyphsDirectoryPath,
           !Self.directoryExists(glyphsDirectoryPath, in: packageDirectory) {
            issues.append(.glyphAssetsMissing)
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

    private static func directoryExists(_ relativePath: String, in root: URL) -> Bool {
        guard let url = try? PackageVerifier.safeArtifactURL(
            path: relativePath,
            root: root
        ),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        else { return false }
        return values.isDirectory == true
    }
}
