import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class MapTests: XCTestCase {
    func testBoundsContainTripCoordinate() {
        let bounds = GeoBounds(
            southWest: GeoCoordinate(latitude: 35, longitude: -120),
            northEast: GeoCoordinate(latitude: 38, longitude: -116)
        )
        XCTAssertTrue(bounds.contains(GeoCoordinate(latitude: 36, longitude: -118)))
        XCTAssertFalse(bounds.contains(GeoCoordinate(latitude: 40, longitude: -118)))
    }

    func testMapReadinessRequiresFilesCoverageTierAndFreshness() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraMapTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("pmtiles".utf8).write(to: directory.appendingPathComponent("region.pmtiles"))
        try Data("style".utf8).write(to: directory.appendingPathComponent("style.json"))
        try Data("graph".utf8).write(to: directory.appendingPathComponent("routing.graph"))

        let pack = OfflineMapPack(
            id: "test-region-field",
            name: "Test Region",
            regionCode: "TEST",
            tier: .field,
            version: "1",
            generatedAt: "2026-01-01T00:00:00Z",
            recommendedRefreshAfter: "2027-01-01T00:00:00Z",
            bounds: GeoBounds(
                southWest: GeoCoordinate(latitude: 35, longitude: -120),
                northEast: GeoCoordinate(latitude: 38, longitude: -116)
            ),
            pmtilesPath: "region.pmtiles",
            stylePath: "style.json",
            routingGraphPath: "routing.graph",
            byteCount: 18
        )
        let evaluator = MapReadinessEvaluator {
            ISO8601DateFormatter().date(from: "2026-07-23T00:00:00Z")!
        }
        let result = evaluator.evaluate(
            pack: pack,
            packageDirectory: directory,
            tripCoordinate: GeoCoordinate(latitude: 36, longitude: -118),
            requiredTier: .field,
            requiresOfflineRouting: true
        )

        XCTAssertTrue(result.isReady)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMapReadinessFlagsOutsideCoverage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraMapTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("region.pmtiles"))
        try Data().write(to: directory.appendingPathComponent("style.json"))
        let pack = OfflineMapPack(
            id: "test",
            name: "Test",
            regionCode: "TEST",
            tier: .scout,
            version: "1",
            generatedAt: "2026-01-01T00:00:00Z",
            recommendedRefreshAfter: "2026-02-01T00:00:00Z",
            bounds: GeoBounds(
                southWest: GeoCoordinate(latitude: 0, longitude: 0),
                northEast: GeoCoordinate(latitude: 1, longitude: 1)
            ),
            pmtilesPath: "region.pmtiles",
            stylePath: "style.json",
            byteCount: 0
        )

        let result = MapReadinessEvaluator {
            ISO8601DateFormatter().date(from: "2026-07-23T00:00:00Z")!
        }.evaluate(
            pack: pack,
            packageDirectory: directory,
            tripCoordinate: GeoCoordinate(latitude: 10, longitude: 10),
            requiredTier: .field,
            requiresOfflineRouting: false
        )

        XCTAssertFalse(result.isReady)
        XCTAssertTrue(result.issues.contains(.outsideDownloadedRegion))
        XCTAssertTrue(result.issues.contains(.detailTierTooLow))
        XCTAssertTrue(result.issues.contains(.refreshRecommended))
    }

    func testOfflineMapResolverExposesOnlySafeReadyArtifacts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraResolvedMapTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("maps", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("style", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("pmtiles".utf8).write(
            to: directory.appendingPathComponent("maps/region.pmtiles")
        )
        try Data("{}".utf8).write(
            to: directory.appendingPathComponent("style/style.json")
        )
        let pack = OfflineMapPack(
            id: "map.test",
            name: "Test Offline Map",
            regionCode: "TEST",
            tier: .scout,
            version: "1.0.0",
            generatedAt: "2026-01-01T00:00:00Z",
            recommendedRefreshAfter: "2099-01-01T00:00:00Z",
            bounds: GeoBounds(
                southWest: GeoCoordinate(latitude: 44, longitude: -94),
                northEast: GeoCoordinate(latitude: 46, longitude: -92)
            ),
            pmtilesPath: "maps/region.pmtiles",
            stylePath: "style/style.json",
            byteCount: 7
        )
        try JSONEncoder().encode(pack).write(
            to: directory.appendingPathComponent("map.json")
        )
        let manifest = PackageManifest(
            packageID: "map.test",
            version: "1.0.0",
            kind: .map,
            createdAt: "2026-01-01T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "ODbL-1.0",
            displayName: "Test Offline Map",
            artifacts: [],
            metadata: [
                "map_manifest_path": "map.json",
                "attribution": "© OpenStreetMap contributors",
            ]
        )
        let active = ResolvedActivePackage(
            manifest: manifest,
            directory: directory
        )

        let resolution = OfflineMapRuntimeResolver().resolve(
            activePacks: ActivePackSnapshot(
                models: [],
                knowledge: [],
                maps: [active],
                installedTiers: [],
                issues: []
            )
        )

        XCTAssertTrue(resolution.issues.isEmpty)
        XCTAssertEqual(resolution.maps.map(\.id), ["map.test"])
        XCTAssertEqual(
            resolution.maps.first?.pmtilesURL,
            directory.appendingPathComponent("maps/region.pmtiles")
        )
    }

    func testOfflineMapResolverRejectsEscapingManifestPath() {
        let manifest = PackageManifest(
            packageID: "map.bad",
            version: "1.0.0",
            kind: .map,
            createdAt: "2026-01-01T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "ODbL-1.0",
            displayName: "Bad Map",
            artifacts: [],
            metadata: ["map_manifest_path": "../map.json"]
        )
        let resolution = OfflineMapRuntimeResolver().resolve(
            activePacks: ActivePackSnapshot(
                models: [],
                knowledge: [],
                maps: [
                    ResolvedActivePackage(
                        manifest: manifest,
                        directory: URL(fileURLWithPath: "/tmp/package")
                    )
                ],
                installedTiers: [],
                issues: []
            )
        )

        XCTAssertEqual(
            resolution.issues,
            [.unsafeArtifactPath(packageID: "map.bad")]
        )
        XCTAssertTrue(resolution.maps.isEmpty)
    }

    func testOfflineStyleAssemblerUsesOnlyLocalPackageResources() throws {
        let template = Data(
            """
            {"version":8,"glyphs":"aurora://glyphs","sources":{"protomaps":{"type":"vector","url":"aurora://pmtiles"}},"layers":[]}
            """.utf8
        )
        let mapURL = URL(fileURLWithPath: "/tmp/map.pmtiles")
        let glyphsURL = URL(fileURLWithPath: "/tmp/fonts", isDirectory: true)

        let data = try OfflineMapStyleAssembler().assemble(
            templateData: template,
            pmtilesURL: mapURL,
            glyphsDirectoryURL: glyphsURL
        )
        let style = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let sources = try XCTUnwrap(style["sources"] as? [String: Any])
        let source = try XCTUnwrap(sources["protomaps"] as? [String: Any])

        XCTAssertEqual(source["url"] as? String, "pmtiles://file:///tmp/map.pmtiles")
        XCTAssertEqual(
            style["glyphs"] as? String,
            "file:///tmp/fonts/{fontstack}/{range}.pbf"
        )
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("http"))
    }

}
