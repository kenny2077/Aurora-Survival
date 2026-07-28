import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class GoldMatrixExecutionTests: XCTestCase {
    func testAll120GoldIncidentsExerciseExpectedControlPath() async throws {
        let cases: [GoldIncidentCase] = try fixture(named: "gold_incidents")
        XCTAssertEqual(cases.count, 120)
        let articles = cases.map(makeArticle)
        let assistant = IncidentAssistant(
            articles: articles,
            installedTiers: [.essential]
        )

        for testCase in cases {
            let answer = await assistant.answer(
                request: ChatRequest(
                    question: testCase.input,
                    domain: testCase.domain,
                    preferredTier: .essential,
                    imageObservations: testCase.inputChannel == "ocr_observation"
                        ? [testCase.input]
                        : []
                ),
                device: device(for: testCase.deviceCondition)
            )
            let expectsOverride = [
                "deterministic_override",
                "refuse_and_escalate",
            ].contains(testCase.expectedControl)
            XCTAssertEqual(
                answer.usedDeterministicOverride,
                expectsOverride,
                "Unexpected path for \(testCase.id)"
            )
            if expectsOverride {
                XCTAssertFalse(
                    answer.notices.filter { $0.hasPrefix("Policy:") }.isEmpty,
                    "Missing policy for \(testCase.id)"
                )
            } else {
                XCTAssertFalse(
                    answer.sources.isEmpty,
                    "Missing reviewed evidence for \(testCase.id)"
                )
            }
        }
    }

    func testAll30MapAssetCasesExerciseReadinessResult() throws {
        let cases: [MapAssetCase] = try fixture(named: "map_asset_cases")
        XCTAssertEqual(cases.count, 30)
        for testCase in cases {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            if testCase.condition != "missing_map" {
                try Data("map".utf8).write(
                    to: root.appendingPathComponent("region.pmtiles")
                )
            }
            if testCase.condition != "missing_style" {
                try Data("style".utf8).write(
                    to: root.appendingPathComponent("style.json")
                )
            }
            if testCase.condition != "missing_routing" {
                try Data("route".utf8).write(
                    to: root.appendingPathComponent("routing.graph")
                )
            }
            let pack = makeMapPack(testCase)
            let coordinate = testCase.condition == "outside_bounds"
                ? GeoCoordinate(latitude: 10, longitude: 10)
                : GeoCoordinate(latitude: 0.5, longitude: 0.5)
            let result = MapReadinessEvaluator {
                ISO8601DateFormatter().date(
                    from: "2026-07-23T00:00:00Z"
                )!
            }.evaluate(
                pack: pack,
                packageDirectory: root,
                tripCoordinate: coordinate,
                requiredTier: testCase.tier,
                requiresOfflineRouting: true
            )
            XCTAssertEqual(
                result.isReady,
                testCase.expectedReady,
                "Unexpected readiness for \(testCase.id)"
            )
        }
    }

    private func makeArticle(_ testCase: GoldIncidentCase) -> KnowledgeArticle {
        KnowledgeArticle(
            id: "article.\(testCase.id)",
            domain: testCase.domain,
            title: testCase.input,
            summary: "Synthetic reviewed control-path evidence.",
            steps: ["Use the reviewed synthetic control path."],
            warnings: ["Synthetic evaluation fixture only."],
            keywords: testCase.input.split(separator: " ").map(String.init),
            source: SourceReference(
                id: "source.\(testCase.id)",
                title: "Synthetic evaluation source",
                organization: "TrailGuard Tests",
                revision: "1"
            ),
            reviewed: true
        )
    }

    private func device(for condition: String) -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8_000_000_000,
            freeStorageBytes: condition == "low_storage"
                ? 1_000_000_000
                : 20_000_000_000,
            thermalCondition: condition == "thermal_serious"
                ? .serious
                : .nominal,
            isLowPowerMode: condition == "low_power"
        )
    }

    private func makeMapPack(_ testCase: MapAssetCase) -> OfflineMapPack {
        OfflineMapPack(
            id: testCase.id,
            name: "Synthetic Map",
            regionCode: "TEST",
            tier: testCase.tier,
            version: "1",
            generatedAt: "2026-01-01T00:00:00Z",
            recommendedRefreshAfter: testCase.condition == "expired"
                ? "2026-01-02T00:00:00Z"
                : "2027-01-01T00:00:00Z",
            bounds: GeoBounds(
                southWest: GeoCoordinate(latitude: 0, longitude: 0),
                northEast: GeoCoordinate(latitude: 1, longitude: 1)
            ),
            pmtilesPath: "region.pmtiles",
            stylePath: "style.json",
            routingGraphPath: "routing.graph",
            byteCount: 13
        )
    }

    private func fixture<T: Decodable>(named name: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "json")
        #else
        let bundle = Bundle(for: GoldMatrixExecutionTests.self)
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "json")
        #endif
        return try JSONDecoder().decode(
            T.self,
            from: Data(contentsOf: try XCTUnwrap(url))
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardGold-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}

private struct GoldIncidentCase: Decodable {
    let id: String
    let input: String
    let domain: KnowledgeDomain
    let inputChannel: String
    let deviceCondition: String
    let expectedControl: String

    private enum CodingKeys: String, CodingKey {
        case id
        case input
        case domain
        case inputChannel = "input_channel"
        case deviceCondition = "device_condition"
        case expectedControl = "expected_control"
    }
}

private struct MapAssetCase: Decodable {
    let id: String
    let tier: MapDetailTier
    let condition: String
    let expectedReady: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case tier
        case condition
        case expectedReady = "expected_ready"
    }
}
