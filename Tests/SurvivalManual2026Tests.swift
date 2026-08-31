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

    func testRetrievalFacetsSplitNormalizeDeduplicateAndBoundCompounds() throws {
        let compound = try XCTUnwrap(
            ExpertScenarioRetrievalEngine.requestFacets(
                in: "Can I find water in the desert? Can I eat cactus?"
            )
        )
        XCTAssertEqual(compound.count, 2)
        XCTAssertEqual(compound[0].operationConcepts, Set(["locate"]))
        XCTAssertEqual(compound[1].operationConcepts, Set(["eat"]))

        let deduplicated = try XCTUnwrap(
            ExpertScenarioRetrievalEngine.requestFacets(
                in: "How to build a shelter? How to construct a shelter?"
            )
        )
        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated[0].operationConcepts, Set(["build"]))
        XCTAssertNil(ExpertScenarioRetrievalEngine.requestFacets(in: "How can I help?"))
        XCTAssertNil(ExpertScenarioRetrievalEngine.requestFacets(
            in: "Find water. Build shelter. Start fire. Hunt rabbits."
        ))
    }

    func testDenseAuthorizationRequiresStrongSubjectAndOperationAlignment() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        let dense = [
            ExpertVectorSearchResult(
                record: ExpertVectorRecord(
                    id: "irrelevant-water",
                    scenarioIDs: ["water-locate-scenario"],
                    kind: .scenario,
                    authority: .promoted
                ),
                score: 0.91,
                shardID: "test"
            ),
            ExpertVectorSearchResult(
                record: ExpertVectorRecord(
                    id: "moderate-shelter",
                    scenarioIDs: ["shelter-tarp-scenario"],
                    kind: .scenario,
                    authority: .promoted
                ),
                score: 0.60,
                shardID: "test"
            ),
        ]
        let results = engine.search(
            request: ChatRequest(
                question: "How to build a shelter",
                preferredTier: .expert
            ),
            denseResults: dense,
            limit: 16
        )
        XCTAssertFalse(try XCTUnwrap(results.first {
            $0.scenario.id == "water-locate-scenario"
        }).isEligible)
        XCTAssertFalse(try XCTUnwrap(results.first {
            $0.scenario.id == "shelter-tarp-scenario"
        }).isEligible)
    }

    func testFullFacetCoverageHonorsLiteAndExpertScenarioBudgets() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let facets = try XCTUnwrap(ExpertScenarioRetrievalEngine.requestFacets(
            in: "Find water. Build a shelter. Start a fire."
        ))
        let scenarioIDs = [
            "water-locate-scenario", "shelter-site-scenario", "fire-site-scenario",
        ]
        let candidates = try scenarioIDs.map { id in
            [RetrievedEvidenceScenario(
                scenario: try XCTUnwrap(store.expertScenario(id: id)),
                score: 1,
                isEligible: true
            )]
        }
        let lite = IncidentAssistant.coverageDecision(
            facets: facets,
            candidatesByFacet: candidates,
            tier: .lite
        )
        XCTAssertFalse(lite.coversCompleteRequest)
        XCTAssertTrue(lite.selectedEvidence.isEmpty)

        let expert = IncidentAssistant.coverageDecision(
            facets: facets,
            candidatesByFacet: candidates,
            tier: .expert
        )
        XCTAssertTrue(expert.coversCompleteRequest)
        XCTAssertEqual(expert.selectedEvidence.count, 3)

        let partial = IncidentAssistant.coverageDecision(
            facets: Array(facets.prefix(2)),
            candidatesByFacet: [candidates[0], []],
            tier: .expert
        )
        XCTAssertFalse(partial.coversCompleteRequest)
        XCTAssertTrue(partial.selectedEvidence.isEmpty)
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

    func testLiteAndExpertUseSameOrderingWithDifferentScenarioCaps() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let ids = [
            "first-aid-cold-scenario",
            "navigation-stop-mark-scenario",
            "basics-first-night-scenario",
        ]
        let candidates = try ids.enumerated().map { index, id in
            RetrievedEvidenceScenario(
                scenario: try XCTUnwrap(store.expertScenario(id: id)),
                score: Double(ids.count - index)
            )
        }
        let question = "I am soaked, shivering, lost, and nearing darkness."
        let lite = IncidentAssistant.selectEligibleEvidence(
            candidates,
            tier: .lite,
            question: question
        )
        let expert = IncidentAssistant.selectEligibleEvidence(
            candidates,
            tier: .expert,
            question: question
        )

        XCTAssertEqual(lite.count, 2)
        XCTAssertEqual(lite.first?.scenario.id, expert.first?.scenario.id)
        XCTAssertLessThanOrEqual(expert.count, 3)
    }

    func testLiteOperationAwareWaterAndCookingRanking() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        let dense = [
            ("water-locate-scenario", 0.79),
            ("water-choose-source-scenario", 0.78),
            ("food-cook-scenario", 0.77),
        ].enumerated().map { offset, value in
            ExpertVectorSearchResult(
                record: ExpertVectorRecord(
                    id: "lite-ranking-\(offset)",
                    scenarioIDs: [value.0],
                    kind: .scenario,
                    authority: .promoted
                ),
                score: value.1,
                shardID: "test"
            )
        }

        for question in [
            "How to find water sources.",
            "Where can I find a water source?",
        ] {
            let ranked = engine.search(
                request: ChatRequest(question: question, preferredTier: .lite),
                denseResults: dense,
                limit: 10,
                rankingMode: .liteOperationAware
            )
            XCTAssertEqual(
                Array(ranked.prefix(2).map(\.scenario.id)),
                ["water-locate-scenario", "water-choose-source-scenario"]
            )
            XCTAssertEqual(ranked.first?.operationConcepts, ["locate"])
            XCTAssertEqual(ranked.first?.candidatePoolPosition, 1)
        }

        let cooking = engine.search(
            request: ChatRequest(
                question: "How to cook raw meat outdoors.",
                preferredTier: .lite
            ),
            denseResults: dense,
            limit: 10,
            rankingMode: .liteOperationAware
        )
        XCTAssertEqual(cooking.first?.scenario.id, "food-cook-scenario")
        XCTAssertEqual(cooking.first?.operationConcepts, ["cook"])
    }

    func testReviewedSidecarLeavesNoPromotedClaimFragments() throws {
        let reportURL = repositoryRoot().appendingPathComponent(
            "Reports/survival-manual-2026/corpus-import-report.json"
        )
        let report = try JSONSerialization.jsonObject(
            with: Data(contentsOf: reportURL)
        ) as? [String: Any]
        XCTAssertEqual(report?["reviewedClaimSidecarCount"] as? Int, 1)
        XCTAssertEqual(
            report?["unresolvedPromotedClaimFragmentCount"] as? Int,
            0
        )

        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        for id in [
            "water-locate-scenario", "water-choose-source-scenario",
            "food-cook-scenario",
        ] {
            let scenario = try XCTUnwrap(store.expertScenario(id: id))
            XCTAssertTrue(scenario.claims.allSatisfy {
                IncidentAssistant.isStandaloneClaim($0)
            })
        }
    }

    func testLiteTopTwoClaimAndPromptBudgets() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = try [
            "water-locate-scenario", "water-choose-source-scenario",
            "water-boil-scenario",
        ].enumerated().map { offset, id in
            RetrievedEvidenceScenario(
                scenario: try XCTUnwrap(store.expertScenario(id: id)),
                score: Double(10 - offset),
                subjectAlignment: 1,
                operationAlignment: offset == 0 ? 1 : 0,
                coveredQueryConcepts: offset == 0 ? 2 : 1
            )
        }
        let selected = IncidentAssistant.selectEligibleEvidence(
            candidates,
            tier: .lite,
            question: "Where can I find a water source?"
        )
        XCTAssertEqual(
            selected.map { $0.scenario.id },
            ["water-locate-scenario", "water-choose-source-scenario"]
        )
        XCTAssertLessThanOrEqual(selected[0].scenario.claims.count, 6)
        XCTAssertLessThanOrEqual(selected[1].scenario.claims.count, 4)
        XCTAssertLessThanOrEqual(
            selected.flatMap { $0.scenario.claims }.count,
            10
        )

        let prompt = ModelPrompt(
            question: "Where can I find a water source?",
            evidence: selected.map { candidate in
                RetrievedPassage(article: KnowledgeArticle(
                    id: candidate.scenario.id,
                    domain: .wilderness,
                    title: candidate.scenario.title,
                    summary: candidate.scenario.applicability,
                    steps: candidate.scenario.claims.map { $0.text },
                    warnings: candidate.scenario.safetyClaims.map { $0.text },
                    keywords: [],
                    source: SourceReference(
                        id: "survival-manual-2026",
                        title: "Survival Manual 2026",
                        organization: "",
                        revision: "2026-08-20"
                    ),
                    reviewed: true,
                    manualReference: candidate.scenario.manualReference
                ), score: candidate.score)
            },
            imageObservations: [],
            tier: .lite,
            permitsVisionReasoning: false,
            expertEvidence: selected,
            purpose: .grounded
        )
        let builder = GroundedPromptBuilder()
        let rendered = builder.systemPrompt(
            for: prompt,
            outputMode: .groundedJSON
        ) + builder.userPrompt(from: prompt, outputMode: .groundedJSON)
        XCTAssertLessThanOrEqual((rendered.count + 2) / 3, 1_400)
        XCTAssertTrue(rendered.contains("REVIEWED SCENARIO [1]"))
        XCTAssertTrue(rendered.contains("REVIEWED SCENARIO [2]"))
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
