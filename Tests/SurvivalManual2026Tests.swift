import CryptoKit
import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class SurvivalManual2026Tests: XCTestCase {
    private struct Fixture: Decodable {
        let schemaVersion: Int
        let corpusVersion: String
        let cases: [Case]

        struct Case: Decodable {
            let id: String
            let question: String
            let expectedIntent: String
            let expectedScenarioIDs: [String]
            let expectSources: Bool
            let expectNoRelevantEvidence: Bool
        }
    }

    func testCanonicalSourceMatchesManifestAndIsPreserved() throws {
        let root = repositoryRoot()
        let folder = root.appendingPathComponent(
            "Resources/Knowledge/CorpusSources/survival-manual-2026"
        )
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        ) as? [String: Any]
        let source = try Data(contentsOf: folder.appendingPathComponent("source.md"))
        let digest = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(manifest?["schemaVersion"] as? Int, 3)
        XCTAssertEqual(manifest?["documentID"] as? String, "survival-manual-2026")
        XCTAssertEqual(manifest?["sourceSHA256"] as? String, digest)
        XCTAssertEqual(source.count, 82_183)
    }

    func testCorpusV3CanonicalScenariosHaveClaimAndLocatorTraceability() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let boil = try XCTUnwrap(store.expertScenario(id: "water-boil-scenario"))
        XCTAssertFalse(boil.claims.isEmpty)
        XCTAssertTrue(boil.claims.allSatisfy {
            $0.sourceIDs == ["survival-manual-2026"]
                && $0.sourceLocators.allSatisfy { $0.contains("Chapter Watercraft") }
        })

        let solarStill = try XCTUnwrap(
            store.expertScenario(id: "sm26-water-solar-still")
        )
        XCTAssertNil(solarStill.manualReference)
        XCTAssertEqual(solarStill.evidenceLocator?.documentID, "survival-manual-2026")
        XCTAssertTrue(solarStill.evidenceLocator?.sectionPath.contains("Solar Still") == true)

        let source = try XCTUnwrap(
            store.expertSources(ids: ["survival-manual-2026"]).first
        )
        XCTAssertEqual(source.title, "Survival Manual 2026")
        XCTAssertTrue(source.organization.isEmpty)
        XCTAssertTrue(source.url.isEmpty)
    }

    func testExactTwentyCaseFixtureAndGroundedRetrievalTargets() throws {
        let fixture: Fixture = try decodeFixture()
        XCTAssertEqual(fixture.schemaVersion, 3)
        XCTAssertEqual(fixture.corpusVersion, "survival-manual-2026.1")
        XCTAssertEqual(fixture.cases.count, 20)
        XCTAssertEqual(Set(fixture.cases.map(\.id)).count, 20)

        let engine = ExpertScenarioRetrievalEngine(
            retrieval: try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        )
        for item in fixture.cases where !item.expectedScenarioIDs.isEmpty {
            let found = Set(engine.search(
                request: ChatRequest(
                    question: item.question,
                    preferredTier: .expert
                ),
                limit: 8
            ).map { $0.scenario.id })
            XCTAssertFalse(
                found.isDisjoint(with: item.expectedScenarioIDs),
                "\(item.id): expected \(item.expectedScenarioIDs), found \(found.sorted())"
            )
        }
        XCTAssertEqual(
            fixture.cases.filter { $0.expectedIntent == "generalQuestion" }.count,
            2
        )
        XCTAssertEqual(fixture.cases.filter(\.expectNoRelevantEvidence).count, 1)
    }

    func testDefiniteSurvivalIntentGuardIsNarrow() {
        let survival = [
            "Apply the STOP method when lost.",
            "How do I take and follow a compass bearing?",
            "Can I eat this unknown mushroom?",
            "How do I repair an unfamiliar survival-device model?",
        ]
        let general = [
            "How do I get a girlfriend?",
            "How's the weather today?",
            "How do I implement a compass widget in software?",
        ]
        XCTAssertTrue(survival.allSatisfy(IncidentAssistant.hasDefiniteSurvivalIntent))
        XCTAssertTrue(general.allSatisfy { !IncidentAssistant.hasDefiniteSurvivalIntent($0) })
    }

    func testSharedPlantAndMushroomScenarioRetainsMushroomWarnings() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let scenario = try XCTUnwrap(
            store.expertScenario(id: "food-unknown-plants-scenario")
        )
        let text = scenario.claims.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("severe poisoning"))
        XCTAssertTrue(text.contains("animal feeding"))
    }

    func testSharedScenarioPrioritizesClaimsForCurrentSkill() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let scenario = try XCTUnwrap(
            store.expertScenario(id: "food-unknown-plants-scenario")
        )
        let candidate = RetrievedEvidenceScenario(scenario: scenario, score: 1)
        let mushroom = IncidentAssistant.prioritizeClaims(
            in: candidate,
            for: "Can I eat this unknown mushroom if animals have bitten it?"
        )
        XCTAssertTrue(
            mushroom.scenario.claims.prefix(4).contains {
                $0.text.lowercased().contains("severe poisoning")
            }
        )
        XCTAssertTrue(
            mushroom.scenario.claims.prefix(4).contains {
                $0.text.lowercased().contains("animal feeding")
            }
        )
    }

    func testMultiHazardSelectionCoversMedicalAndNavigationNeeds() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let ids = [
            "weather-wildlife-cold-scenario", "first-aid-cold-scenario",
            "basics-first-night-scenario", "navigation-stop-mark-scenario",
        ]
        let candidates = try ids.enumerated().map { index, id in
            RetrievedEvidenceScenario(
                scenario: try XCTUnwrap(store.expertScenario(id: id)),
                score: Double(ids.count - index)
            )
        }
        let prioritized = IncidentAssistant.prioritizeScenarioCoverage(
            candidates,
            for: "I am soaked, shivering, lost, and nearing darkness."
        )
        XCTAssertEqual(
            prioritized.prefix(2).map(\.scenario.chapterID),
            ["first-aid", "navigation"]
        )
        XCTAssertEqual(
            IncidentAssistant.semanticRetrievalQueries(
                base: "combined",
                question: "I am soaked, shivering, lost, and nearing darkness."
            ).count,
            3
        )
    }

    private func decodeFixture<T: Decodable>() throws -> T {
        let url = repositoryRoot().appendingPathComponent(
            "Tests/Fixtures/survival_manual_2026_cases.json"
        )
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func knowledgeURL() -> URL {
        repositoryRoot().appendingPathComponent(
            "Resources/Knowledge/survival_knowledge.sqlite"
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
