import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class MapAndOBDTests: XCTestCase {
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

    func testOBDPolicyAllowsOnlyReadCommands() throws {
        let policy = OBDCommandPolicy()
        XCTAssertEqual(try policy.validate("01 0C\r"), "010C")
        XCTAssertEqual(try policy.validate("03"), "03")
        XCTAssertThrowsError(try policy.validate("04"))
        XCTAssertThrowsError(try policy.validate("2E1234"))
        XCTAssertThrowsError(try policy.validate("AT SH 7E0"))
    }

    func testOBDParserDecodesDiagnosticTroubleCodes() throws {
        let codes = try ELM327Parser().diagnosticTroubleCodes(
            from: "43 01 33 C1 23 00 00\r>"
        )
        XCTAssertEqual(codes.map(\.code), ["P0133", "U0123"])
    }

    func testOBDParserDecodesRPMAndCoolant() throws {
        let parser = ELM327Parser()
        XCTAssertEqual(
            try parser.scalarValue(from: "41 0C 1A F8\r>", pid: 0x0C),
            1726,
            accuracy: 0.01
        )
        XCTAssertEqual(
            try parser.scalarValue(from: "41 05 7B\r>", pid: 0x05),
            83,
            accuracy: 0.01
        )
    }

    func testReadOnlySessionRejectsRawClearCommandBeforeTransport() async {
        let transport = RecordingOBDTransport()
        let session = ReadOnlyOBDSession(transport: transport)
        do {
            _ = try await session.executeRaw("04")
            XCTFail("Expected command rejection")
        } catch {
            XCTAssertEqual(error as? OBDPolicyError, .commandNotAllowed("04"))
        }
        let calls = await transport.commands
        XCTAssertTrue(calls.isEmpty)
    }
}

private actor RecordingOBDTransport: OBDTransport {
    private(set) var commands: [String] = []

    func exchange(command: String) async throws -> String {
        commands.append(command)
        return "OK\r>"
    }
}
