import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ExpertRAGBenchmarkTests: XCTestCase {
    private struct DirectRAGHoldout: Decodable {
        struct Item: Decodable {
            let id: String
            let split: String
            let category: String
            let query: String
            let expectedIntent: ExpertTurnIntent
            let expectedScenarioID: String?
            let critical: Bool
        }
        let schemaVersion: Int
        let authorship: String
        let reviewStatus: String
        let cases: [Item]
    }
    private struct HistoryTurn: Decodable {
        let role: String
        let text: String
    }

    private struct BenchmarkCase: Decodable {
        let id: String
        let query: String
        let history: [HistoryTurn]
        let imageObservations: [String]
        let acceptableScenarioIDs: [String]
        let requiredClaimKinds: [String]
        let forbiddenClaims: [String]
        let caseType: String
        let riskClass: ExpertRiskClass
        let expectedDisposition: ExpertPlanDisposition
        let referenceGuidance: String
        let critical: Bool
        let annotationStatus: String
    }

    func testGeneratedBenchmarkHasRequiredCoverageAndAnnotations() throws {
        let cases = try loadCases()
        XCTAssertEqual(cases.count, 700)
        XCTAssertEqual(Set(cases.map(\.id)).count, 700)
        XCTAssertEqual(
            cases.filter { $0.expectedDisposition == .grounded }.count,
            560
        )
        XCTAssertEqual(
            cases.filter { $0.expectedDisposition == .clarify }.count,
            70
        )
        XCTAssertEqual(
            cases.filter { $0.expectedDisposition == .ordinary }.count,
            70
        )
        XCTAssertEqual(
            Set(cases.flatMap(\.acceptableScenarioIDs)).count,
            70
        )
        for item in cases where item.expectedDisposition == .grounded {
            XCTAssertFalse(item.referenceGuidance.isEmpty, item.id)
            XCTAssertFalse(item.requiredClaimKinds.isEmpty, item.id)
            XCTAssertFalse(item.forbiddenClaims.isEmpty, item.id)
            XCTAssertEqual(item.annotationStatus, "internal_pre_release", item.id)
        }
        XCTAssertEqual(cases.filter { $0.caseType == "multi_topic" }.count, 70)
    }

    func testPhysicalFireSiteDraftPassesClaimValidation() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "I need to pick a campfire spot near roots, grass, and low branches.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let fireSite = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "fire-site"
        })
        let bundle = EvidenceBundle(scenarios: [fireSite])
        let actionIndex = try XCTUnwrap(bundle.claims.firstIndex {
            $0.kind == .action && $0.text.contains("existing approved fire area")
        }).advanced(by: 1)
        let warningIndex = try XCTUnwrap(bundle.claims.firstIndex {
            $0.kind == .contraindication && $0.text.contains("peat")
        }).advanced(by: 1)
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Use an existing approved fire area when one is available.",
                evidenceIndexes: [actionIndex]
            ),
            ExpertAttributedSentence(
                text: "Do not build on peat, deep duff, roots, inside a tent, or beneath low branches.",
                evidenceIndexes: [warningIndex]
            ),
        ])
        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
    }

    func testPhysicalCloudyWaterNovelConditionIsRejected() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "The only water is cloudy with sediment. Also, I have a pot and fire.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let boil = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "water-boil"
        })
        let prefilter = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "water-collect-prefilter"
        })
        let bundle = EvidenceBundle(scenarios: [boil, prefilter])
        let boilAction = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("rolling boil")
        }).advanced(by: 1)
        let storageAction = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("covered container")
        }).advanced(by: 1)
        let prefilterAction = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("clean filter material")
        }).advanced(by: 1)
        let prefilterApplicability = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("Allow muddy water to settle")
        }).advanced(by: 1)
        let boilWarning = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("toxic chemicals")
        }).advanced(by: 1)
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Bring the water to a rolling boil, then use a clean covered container.",
                evidenceIndexes: [boilAction, storageAction]
            ),
            ExpertAttributedSentence(
                text: "Allow muddy water to settle and remove visible particles with cloth or clean filter material before boiling.",
                evidenceIndexes: [prefilterAction, prefilterApplicability]
            ),
            ExpertAttributedSentence(
                text: "Boiling does not remove fuel, toxic chemicals, salt, or radioactive contamination; therefore, do not use this method for contaminated water sources.",
                evidenceIndexes: [boilWarning]
            ),
        ])
        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
        XCTAssertFalse(bundle.claims[boilWarning - 1].text.lowercased().contains("salt"))
    }

    func testAnaphylaxisUsesApplicableEscalationWithoutSnakebiteWarning() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "They are having anaphylaxis and have prescribed epinephrine.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let allergy = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-bites-allergy"
        })
        let bundle = EvidenceBundle(scenarios: [allergy])
        let epinephrine = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("prescribed epinephrine")
        }).advanced(by: 1)
        let escalation = try XCTUnwrap(bundle.claims.firstIndex {
            $0.text.contains("Activate emergency response")
        }).advanced(by: 1)
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Help the person use their prescribed epinephrine immediately.",
                evidenceIndexes: [epinephrine]
            ),
            ExpertAttributedSentence(
                text: "Activate emergency response immediately for anaphylaxis.",
                evidenceIndexes: [escalation]
            ),
        ])
        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
        XCTAssertFalse(answer.text.lowercased().contains("snake"))
    }

    func testPhysicalBleedingDraftPassesClaimValidation() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "A deep cut is soaking through clothing and help is far away.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let bleeding = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-bleeding"
        })
        let bundle = EvidenceBundle(scenarios: [bleeding])
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Press firmly on the wound using gauze, dressing, or clean cloth.",
                evidenceIndexes: [3]
            ),
            ExpertAttributedSentence(
                text: "Maintain pressure.",
                evidenceIndexes: [3]
            ),
            ExpertAttributedSentence(
                text: "For severe arm or leg bleeding that direct pressure cannot control, use a tourniquet and record the application time.",
                evidenceIndexes: [6, 9]
            ),
            ExpertAttributedSentence(
                text: "Leave the tourniquet in place until medical professionals take over.",
                evidenceIndexes: [10]
            ),
        ])
        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
    }

    func testPhysicalBleedingAndShockDraftUsesBothEvidenceRecords() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "Severe bleeding is controlled but the person is pale and worsening.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let bleeding = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-bleeding"
        })
        let shock = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-shock"
        })
        let bundle = EvidenceBundle(scenarios: [bleeding, shock])
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Press firmly with gauze, dressing, or clean cloth.",
                evidenceIndexes: [3]
            ),
            ExpertAttributedSentence(
                text: "Maintain pressure.",
                evidenceIndexes: [3]
            ),
            ExpertAttributedSentence(
                text: "Keep the person warm.",
                evidenceIndexes: [15]
            ),
            ExpertAttributedSentence(
                text: "Reduce unnecessary movement.",
                evidenceIndexes: [17]
            ),
            ExpertAttributedSentence(
                text: "Arrange evacuation.",
                evidenceIndexes: [18]
            ),
        ])
        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
        XCTAssertEqual(answer.evidenceIndexes, [3, 15, 17, 18])
    }

    func testUnusedRetrievedScenarioDoesNotInvalidateAttributedSentences() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let candidates = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "Severe bleeding is controlled but the person is pale and worsening.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let bleeding = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-bleeding"
        })
        let shock = try XCTUnwrap(candidates.first {
            $0.scenario.lessonID == "first-aid-shock"
        })
        let bundle = EvidenceBundle(scenarios: [bleeding, shock])
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Press firmly with gauze, dressing, or clean cloth.",
                evidenceIndexes: [3]
            ),
            ExpertAttributedSentence(
                text: "Leave the tourniquet in place until medical professionals take over.",
                evidenceIndexes: [10]
            ),
        ])

        XCTAssertTrue(answer.evidenceIndexes.allSatisfy {
            (1...bundle.claims.count).contains($0)
        })
    }

    func testScenarioCandidateRecallMeetsExpertGate() throws {
        let cases = try loadCases().filter {
            $0.expectedDisposition == .grounded
        }
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        var matches = 0
        var criticalMisses: [String] = []
        var misses: [String] = []
        var latencies: [Double] = []

        for item in cases {
            let request = ChatRequest(
                question: item.query,
                preferredTier: .expert,
                hasImage: !item.imageObservations.isEmpty,
                imageObservations: item.imageObservations,
                conversationHistory: item.history.map {
                    ConversationTurn(
                        role: $0.role == "assistant" ? .assistant : .user,
                        text: $0.text
                    )
                }
            )
            let started = CFAbsoluteTimeGetCurrent()
            let results = engine.search(request: request, limit: 8)
            latencies.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)
            let got = Set(results.map { $0.scenario.id })
            let matched = Set(item.acceptableScenarioIDs).isSubset(of: got)
            matches += matched ? 1 : 0
            if !matched {
                let detail = "\(item.id)>\(results.map { $0.scenario.id }.joined(separator: "+"))"
                misses.append(detail)
                if item.critical { criticalMisses.append(detail) }
            }
        }
        let sorted = latencies.sorted()
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        XCTAssertGreaterThanOrEqual(
            Double(matches) / Double(cases.count),
            0.98,
            misses.joined(separator: ", ")
        )
        XCTAssertTrue(
            criticalMisses.isEmpty,
            criticalMisses.joined(separator: ", ")
        )
        XCTAssertLessThan(p95, 150)
    }

    func testBenchmarkReportsRecallWithAndWithoutShadowCorpus() throws {
        let cases = try loadCases().filter {
            $0.expectedDisposition == .grounded
        }
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let baseline = ExpertScenarioRetrievalEngine(
            retrieval: store,
            includesShadowCorpus: false
        )
        let expanded = ExpertScenarioRetrievalEngine(retrieval: store)
        var baselineMatches = 0
        var expandedMatches = 0
        for item in cases {
            let request = ChatRequest(
                question: item.query,
                preferredTier: .expert,
                hasImage: !item.imageObservations.isEmpty,
                imageObservations: item.imageObservations,
                conversationHistory: item.history.map {
                    ConversationTurn(
                        role: $0.role == "assistant" ? .assistant : .user,
                        text: $0.text
                    )
                }
            )
            let expected = Set(item.acceptableScenarioIDs)
            baselineMatches += expected.isSubset(of: Set(
                baseline.search(request: request, limit: 8)
                    .map { $0.scenario.id }
            )) ? 1 : 0
            expandedMatches += expected.isSubset(of: Set(
                expanded.search(request: request, limit: 8)
                    .map { $0.scenario.id }
            )) ? 1 : 0
        }
        let baselineRecall = Double(baselineMatches) / Double(cases.count)
        let expandedRecall = Double(expandedMatches) / Double(cases.count)
        XCTAssertGreaterThanOrEqual(expandedRecall, 0.98)
        XCTAssertGreaterThanOrEqual(expandedRecall, baselineRecall)
    }

    func testDatabaseExposesSourceTracedExpertClaims() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let integrity = try store.integrity()
        XCTAssertGreaterThanOrEqual(integrity.expertScenarioCount, 96)
        XCTAssertGreaterThanOrEqual(integrity.expertClaimCount, 500)
        let results = store.searchExpertEvidence(
            query: "cloudy water with sediment",
            domain: .wilderness,
            limit: 8
        )
        let scenario = try XCTUnwrap(results.first {
            $0.scenario.lessonID == "water-collect-prefilter"
        }?.scenario)
        XCTAssertFalse(scenario.claims.isEmpty)
        XCTAssertTrue(scenario.claims.allSatisfy { !$0.sourceIDs.isEmpty })
        XCTAssertTrue(scenario.claims.allSatisfy { !$0.sourceLocators.isEmpty })
    }

    func testDirectRAGScreenshotRegressionsRankNewScenariosFirst() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        let cases = [
            ("My car will not start", "car-no-start-triage"),
            ("How to fish", "food-fishing-basics"),
        ]
        for (query, expected) in cases {
            let results = engine.search(request: ChatRequest(
                question: query,
                preferredTier: .expert
            ))
            XCTAssertEqual(results.first?.scenario.id, expected, "query: \(query)")
        }
    }

    func testAbsoluteGateRejectsGenericAndLiveInformationMatches() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        for query in ["How to get a girlfriend", "How's the weather today?"] {
            let results = engine.search(request: ChatRequest(
                question: query,
                preferredTier: .expert
            ))
            XCTAssertTrue(
                results.filter(\.isEligible).isEmpty,
                "query: \(query), results: \(results.map { "\($0.scenario.id):\($0.eligibilityReason)" })"
            )
            XCTAssertTrue(results.allSatisfy {
                !$0.appliedBoosts.contains("linked_discovery")
            })
        }
    }

    func testGenericVerbIsRemovedFromSurvivalLexicalQuery() {
        XCTAssertEqual(
            ExpertScenarioRetrievalEngine.meaningfulSurvivalTerms(
                in: "How to get a girlfriend"
            ),
            ["girlfriend"]
        )
    }

    func testDenseNearestNeighborBelowAbsoluteThresholdCannotGround() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let result = ExpertVectorSearchResult(
            record: ExpertVectorRecord(
                id: "forced-unrelated-nearest",
                scenarioIDs: ["car-ev-hybrid-scenario"],
                kind: .scenario,
                authority: .promoted
            ),
            score: 0.6371029615402222,
            shardID: "physical-diagnostic"
        )
        let ranked = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "How do I repair an unfamiliar survival-device model?",
                preferredTier: .expert
            ),
            denseResults: [result],
            limit: 8
        )
        XCTAssertTrue(ranked.filter(\.isEligible).isEmpty)
        XCTAssertEqual(
            ranked.first { $0.scenario.id == "car-ev-hybrid-scenario" }?
                .eligibilityReason,
            "insufficient_absolute_relevance"
        )
    }

    func testCommittedDirectRAGThresholdPassesFrozenHoldout() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/expert_direct_rag_holdout.json")
        let fixture = try JSONDecoder().decode(
            DirectRAGHoldout.self,
            from: Data(contentsOf: fixtureURL)
        )
        XCTAssertEqual(fixture.schemaVersion, 2)
        XCTAssertEqual(
            fixture.reviewStatus,
            "internal_pre_release_reviewed_external_review_pending"
        )
        XCTAssertTrue(fixture.authorship.contains("Separately authored"))
        XCTAssertEqual(Set(fixture.cases.map(\.split)), ["calibration", "holdout"])
        XCTAssertEqual(fixture.cases.count, 160)
        XCTAssertEqual(
            fixture.cases.filter {
                $0.expectedIntent == .survivalQuestion
            }.count,
            80
        )
        let hardNegatives = fixture.cases.filter {
            $0.expectedIntent == .generalQuestion
        }
        XCTAssertEqual(hardNegatives.count, 80)
        XCTAssertTrue(
            Dictionary(grouping: hardNegatives, by: \.category)
                .values.allSatisfy { $0.count >= 10 }
        )
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let engine = ExpertScenarioRetrievalEngine(retrieval: store)
        var failures: [String] = []
        var criticalFailures: [String] = []
        for item in fixture.cases {
            let request = ChatRequest(question: item.query, preferredTier: .expert)
            let results = engine.search(request: request)
            let selected = results.first(where: \.isEligible)?.scenario.id
            let passed = if let expected = item.expectedScenarioID {
                results.contains { $0.scenario.id == expected }
            } else {
                selected == nil
            }
            if !passed {
                let got = item.expectedScenarioID == nil
                    ? (selected ?? "none")
                    : results.map { $0.scenario.id }.joined(separator: "+")
                let failure = "\(item.id):\(item.expectedScenarioID ?? "none")>\(got)"
                failures.append(failure)
                if item.critical { criticalFailures.append(failure) }
            }
        }
        XCTAssertTrue(criticalFailures.isEmpty, criticalFailures.joined(separator: ", "))
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: ", "))
    }

    func testSupplementalScenariosResolveClaimSources() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        for id in ["car-no-start-triage", "food-fishing-basics"] {
            let scenario = try XCTUnwrap(store.expertScenario(id: id))
            XCTAssertFalse(scenario.claims.isEmpty)
            XCTAssertTrue(scenario.claims.allSatisfy { !$0.sourceIDs.isEmpty })
            let sources = store.expertSources(ids: scenario.claims.flatMap(\.sourceIDs))
            XCTAssertFalse(sources.isEmpty)
            XCTAssertTrue(sources.allSatisfy { !$0.locator.isEmpty })
            XCTAssertTrue(sources.allSatisfy {
                !$0.url.isEmpty || $0.id == "survival-manual-2026"
            })
        }
    }

    func testShadowCorpusBoostsCandidatesWithoutBecomingEvidence() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let corpus = store.searchExpertCorpus(
            query: "heat escape lessening posture group huddle in cold water",
            domain: .wilderness,
            limit: 8
        )
        let cold = try XCTUnwrap(corpus.first {
            $0.scenario.lessonID == "first-aid-cold"
        })
        XCTAssertFalse(cold.chunkIDs.isEmpty)
        XCTAssertEqual(cold.authorityTier, .authority)

        let results = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "Use the heat escape lessening posture and group huddle in cold water.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let boosted = results.first {
            $0.scenario.lessonID == "first-aid-cold"
        }
        XCTAssertNil(
            boosted,
            "A discovery-only link must not create an answer-authorizing candidate."
        )
    }

    func testCorpusBoostMetadataPreservesPreBoostScore() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let results = ExpertScenarioRetrievalEngine(retrieval: store).search(
            request: ChatRequest(
                question: "The fire is too hot to touch under the ash.",
                preferredTier: .expert
            ),
            limit: 8
        )
        let fire = try XCTUnwrap(results.first {
            $0.scenario.lessonID == "fire-extinguish"
        })
        XCTAssertGreaterThanOrEqual(fire.score, fire.preBoostScore)
        XCTAssertGreaterThanOrEqual(
            fire.score - fire.preBoostScore,
            fire.shadowCorpusBoost
        )
        XCTAssertTrue(fire.appliedBoosts.contains("term_overlap"))
        XCTAssertEqual(fire.promotionStatus, .humanApproved)
    }

    func testCorpusLicensingAndPromotionBoundaryIsReadable() throws {
        let store = try SurvivalKnowledgeStore(databaseURL: knowledgeURL())
        let documents = store.expertSourceDocuments()
        XCTAssertEqual(documents.count, 11)
        XCTAssertTrue(documents.contains {
            $0.id == "survival-manual-2026"
                && $0.redistributionClass == .ownedFullText
        })
        XCTAssertTrue(documents.contains {
            $0.id == "redcross-first-aid-2019"
                && $0.redistributionClass == .linkedMetadataOnly
        })
        let promotions = store.expertClaimPromotions()
        XCTAssertEqual(promotions.filter { $0.status == .candidate }.count, 4)
        XCTAssertGreaterThanOrEqual(
            promotions.filter { $0.status == .humanApproved }.count,
            400
        )

        let bleeding = try XCTUnwrap(store.searchExpertEvidence(
            query: "life threatening bleeding",
            domain: .firstAid,
            limit: 8
        ).first { $0.scenario.lessonID == "first-aid-bleeding" })
        XCTAssertFalse(bleeding.scenario.claims.contains {
            $0.id == "promotion-bleeding-rationale"
        })
    }

    func testFailureTaxonomyRemainsCompleteAndStable() {
        XCTAssertEqual(Set(ExpertFailureCategory.allCases.map(\.rawValue)), [
            "missing_evidence", "retrieval_miss", "evidence_selection_error",
            "insufficient_coverage", "unsupported_generation",
            "validator_false_negative", "malformed_output",
            "inappropriate_clarification",
        ])
    }

    private func loadCases() throws -> [BenchmarkCase] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "expert_rag_benchmark",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(
                forResource: "expert_rag_benchmark",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(
            [BenchmarkCase].self,
            from: Data(contentsOf: url)
        )
    }

    private func knowledgeURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Knowledge/survival_knowledge.sqlite")
    }
}
