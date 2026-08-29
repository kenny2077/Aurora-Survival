import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ExpertContextTests: XCTestCase {
    func testTurnResolverDropsIncidentHistoryForGreetings() {
        let history = [
            ConversationTurn(role: .user, text: "My car will not start"),
            ConversationTurn(
                role: .assistant,
                text: "Check the vehicle safely.",
                evidenceIDs: ["car-no-start-triage"]
            ),
        ]
        for greeting in ["Hi", "Wassup"] {
            let resolved = ExpertTurnResolver().resolve(ChatRequest(
                question: greeting,
                preferredTier: .expert,
                conversationHistory: history
            ))
            XCTAssertTrue(resolved.relevantHistory.isEmpty)
            XCTAssertTrue(resolved.priorEvidenceIDs.isEmpty)
        }
    }

    func testTurnResolverCarriesOnlyRelevantFollowupContext() {
        let history = [
            ConversationTurn(role: .user, text: "How can I find food?"),
            ConversationTurn(
                role: .assistant,
                text: "Protect water and warmth first.",
                evidenceIDs: ["food-energy-scenario"]
            ),
        ]
        let topic = ExpertTurnResolver().resolve(ChatRequest(
            question: "How to fish?",
            preferredTier: .expert,
            conversationHistory: history
        ))
        XCTAssertTrue(topic.relevantHistory.isEmpty)

        let answerFocused = ExpertTurnResolver().resolve(ChatRequest(
            question: "Why?",
            preferredTier: .expert,
            conversationHistory: history
        ))
        XCTAssertEqual(answerFocused.relevantHistory.map(\.text), history.map(\.text))
        XCTAssertEqual(answerFocused.priorEvidenceIDs, ["food-energy-scenario"])
    }

    func testNormalizedPhrasePreservesOrderAndAppliesAliases() {
        XCTAssertEqual(
            ExpertRetrievalEngine.normalizedPhrase("Boil the watre correctly"),
            "boil water correctly"
        )
        XCTAssertEqual(
            ExpertRetrievalEngine.normalizedPhrase("Correctly boil water"),
            "correctly boil water"
        )
    }

    func testTurnRoutingCodecAcceptsStrictBilingualEnvelope() throws {
        let codec = TurnRoutingDecisionCodec()
        XCTAssertEqual(
            try codec.decodeAndValidate(
                #"{"t":"survival","l":"zh","q":"find and purify water outdoors"}"#
            ),
            TurnRoutingDecision(
                intent: .survivalQuestion,
                responseLanguage: .chinese,
                retrievalQuery: "find and purify water outdoors"
            )
        )
        XCTAssertEqual(
            try codec.decodeAndValidate(#"{"t":"general","l":"en","q":""}"#),
            TurnRoutingDecision(
                intent: .generalQuestion,
                responseLanguage: .english,
                retrievalQuery: ""
            )
        )
        XCTAssertThrowsError(try codec.decodeAndValidate(
            #"{"t":"general","l":"zh","q":"weather"}"#
        ))
        XCTAssertThrowsError(try codec.decodeAndValidate(
            #"{"t":"survival","l":"fr","q":"water"}"#
        ))
        XCTAssertThrowsError(try codec.decodeAndValidate(
            #"{"t":"general","l":"en","q":"","x":1}"#
        ))
    }

    func testResponseLanguageDetectsEnglishAndChinese() {
        XCTAssertEqual(ResponseLanguage.detect(in: "Hello"), .english)
        XCTAssertEqual(ResponseLanguage.detect(in: "如何净化野外水源？"), .chinese)
    }

    func testExpertEvidencePlanAcceptsBoundedMultiRecordSelection() throws {
        let candidates = makeEvidenceCandidates()
        let plan = try ExpertEvidencePlanCodec().decodeAndValidate(
            #"{"d":"grounded","r":"critical","e":[1,2],"c":"sufficient","q":""}"#,
            candidates: candidates,
            requiresSafetyResponse: true,
            requiresClarification: false,
            requiredCandidateIndexes: [1]
        )
        XCTAssertEqual(plan.evidenceIndexes, [1, 2])
        XCTAssertEqual(plan.coverage, .sufficient)
        XCTAssertThrowsError(try ExpertEvidencePlanCodec().decodeAndValidate(
            #"{"d":"ordinary","r":"low","e":[],"c":"not_needed","q":""}"#,
            candidates: candidates,
            requiresSafetyResponse: true,
            requiresClarification: false
        ))
    }

    func testAttributedAnswerRejectsUnknownEvidenceIndex() {
        XCTAssertThrowsError(try ExpertAttributedAnswerCodec().decodeAndValidate(
            #"{"s":[{"a":"Apply reviewed pressure to the wound.","e":[1]},{"a":"Do not remove material controlling bleeding.","e":[2]}]}"#,
            evidenceCount: 1
        ))
    }

    func testClaimAwareValidatorRejectsUnsupportedNonnumericProcedure() throws {
        let candidates = makeEvidenceCandidates()
        let bundle = EvidenceBundle(scenarios: [candidates[0]])
        let answer = ExpertAttributedAnswer(sentences: [
            ExpertAttributedSentence(
                text: "Apply firm direct pressure to the bleeding.",
                evidenceIndexes: [2]
            ),
            ExpertAttributedSentence(
                text: "Apply a tourniquet and manage the airway immediately.",
                evidenceIndexes: [2]
            ),
            ExpertAttributedSentence(
                text: "Do not remove material already controlling the bleeding.",
                evidenceIndexes: [4]
            ),
        ])
        XCTAssertThrowsError(try ExpertAnswerSafetyValidator().validate(
            answer: answer,
            bundle: bundle
        )) { error in
            guard case ExpertAnswerSafetyError.unsupportedClaim(
                sentence: 2,
                terms: let terms,
                permittedClaims: _
            ) = error else { return XCTFail("unexpected error: \(error)") }
            XCTAssertTrue(terms.contains("tourniquet"))
        }
    }

    func testExpertSafetyValidatorRejectsUnsupportedNumber() {
        let passage = RetrievedPassage(article: article(
            id: "wildlife",
            lessonID: "wildlife",
            title: "Avoid Wildlife Contact",
            summary: "Keep away from wildlife and prevent close contact.",
            keywords: ["wildlife", "avoid"],
            steps: ["Back away slowly and give the animal space."],
            warnings: ["Do not touch or feed wildlife."]
        ), score: 1)
        let validator = ExpertAnswerSafetyValidator()
        XCTAssertThrowsError(try validator.validate(
            answer: "Back away slowly for 20 metres and give the animal space. Warning: Do not touch or feed wildlife.",
            passage: passage
        ))
    }

    private let mib: UInt64 = 1_024 * 1_024

    func testAssemblerSelectsHighestProfileWithRetainedHeadroom() throws {
        let assembler = makeAssembler(full: 5_000, balanced: 4_000, constrained: 3_000)

        let full = try XCTUnwrap(assembler.assemble(
            question: "How should I stop this bleeding?",
            conversationHistory: [],
            availableMemoryBytes: 5_768 * mib
        ))
        XCTAssertEqual(full.profile, .full)
        XCTAssertEqual(full.inputTokenBudget, 8_192 - 384 - 512)

        let balanced = try XCTUnwrap(assembler.assemble(
            question: "What now?",
            conversationHistory: [],
            availableMemoryBytes: 4_800 * mib
        ))
        XCTAssertEqual(balanced.profile, .balanced)
        XCTAssertEqual(balanced.maximumImageDimension, 768)
    }

    func testAssemblerFailsClosedWhenNoProfileHasHeadroom() {
        let assembler = makeAssembler(full: 5_000, balanced: 4_000, constrained: 3_000)
        XCTAssertNil(assembler.assemble(
            question: "What now?",
            conversationHistory: [],
            availableMemoryBytes: 3_767 * mib
        ))
        XCTAssertNil(assembler.assemble(
            question: "What now?",
            conversationHistory: [],
            availableMemoryBytes: nil
        ))
    }

    func testAssemblerRetainsNewestWholeMessagesWithinProfileLimit() throws {
        let assembler = makeAssembler(full: 9_000, balanced: 8_000, constrained: 1_000)
        let history = (0..<5).map {
            ConversationTurn(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "turn-\($0)")
        }
        let assembly = try XCTUnwrap(assembler.assemble(
            question: "And now?",
            conversationHistory: history,
            availableMemoryBytes: 1_800 * mib
        ))

        XCTAssertEqual(assembly.profile, .constrained)
        XCTAssertEqual(assembly.conversationHistory.map(\.text), ["turn-3", "turn-4"])
    }

    func testExpertRetrievalFusesAndDeduplicatesLessonsDeterministically() {
        let bleedingPrimary = article(
            id: "bleeding-primary",
            lessonID: "bleeding",
            title: "Control Severe Bleeding",
            keywords: ["bleeding", "pressure"]
        )
        let bleedingDuplicate = article(
            id: "bleeding-neighbor",
            lessonID: "bleeding",
            title: "Bleeding Follow-up",
            keywords: ["bleeding"]
        )
        let shock = article(
            id: "shock",
            lessonID: "shock",
            title: "Prevent Shock",
            keywords: ["shock", "bleeding"]
        )
        let retriever = FixedRetriever(passages: [
            RetrievedPassage(article: shock, score: 10),
            RetrievedPassage(article: bleedingPrimary, score: 9),
            RetrievedPassage(article: bleedingDuplicate, score: 8),
        ])
        let request = ChatRequest(
            question: "The bleeding is still severe; what now?",
            domain: .firstAid,
            preferredTier: .expert,
            imageObservations: ["dark blood on bandage"],
            conversationHistory: [
                ConversationTurn(role: .user, text: "I cut my lower leg."),
            ]
        )

        let first = ExpertRetrievalEngine(retrieval: retriever).search(request: request)
        let second = ExpertRetrievalEngine(retrieval: retriever).search(request: request)

        XCTAssertEqual(first.map { $0.article.id }, second.map { $0.article.id })
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(Set(first.compactMap { $0.article.manualReference?.lessonID }).count, 2)
        XCTAssertEqual(first.first?.article.id, "bleeding-primary")
    }

    func testScenarioFusionCountsBestDenseRecordOnlyOnce() throws {
        let bleeding = article(
            id: "bleeding-primary",
            lessonID: "bleeding",
            title: "Control Severe Bleeding",
            keywords: ["severe bleeding", "direct pressure"]
        )
        let retriever = ArticleBackedExpertEvidenceRetriever(retrieval: FixedRetriever(
            passages: [RetrievedPassage(article: bleeding, score: 1)]
        ))
        let scenario = try XCTUnwrap(
            retriever.searchExpertEvidence(query: "severe bleeding", domain: nil, limit: 8)
                .first?.scenario
        )
        let dense = (0..<3).map { rank in
            ExpertVectorSearchResult(
                record: ExpertVectorRecord(
                    id: "dense-\(rank)",
                    scenarioIDs: [scenario.id],
                    kind: .claim,
                    authority: .promoted
                ),
                score: 1 - Double(rank) * 0.1,
                shardID: "test"
            )
        }
        let result = try XCTUnwrap(ExpertScenarioRetrievalEngine(
            retrieval: retriever,
            includesShadowCorpus: false
        ).search(
            request: ChatRequest(question: "severe bleeding", preferredTier: .expert),
            denseResults: dense,
            limit: 8
        ).first)

        XCTAssertEqual(result.lexicalRank, 0)
        XCTAssertEqual(result.denseRank, 0)
        XCTAssertEqual(result.preBoostScore, 2.0 / 61.0, accuracy: 0.000_001)
    }

    private func makeAssembler(
        full: UInt64,
        balanced: UInt64,
        constrained: UInt64
    ) -> ExpertContextAssembler {
        ExpertContextAssembler(memoryProfile: ExpertRuntimeMemoryProfile(
            measuredPeakBytes: [
                .full: full * mib,
                .balanced: balanced * mib,
                .constrained: constrained * mib,
            ]
        ))
    }

    private func makeEvidenceCandidates() -> [RetrievedEvidenceScenario] {
        let bleeding = article(
            id: "bleeding",
            lessonID: "bleeding",
            title: "Control Severe Bleeding",
            summary: "Control life-threatening external bleeding promptly.",
            keywords: ["bleeding", "pressure"],
            steps: [
                "Apply firm direct pressure to the bleeding.",
                "Keep the person still while monitoring the bleeding.",
            ],
            warnings: [
                "Do not remove material already controlling the bleeding.",
            ]
        )
        let shock = article(
            id: "shock",
            lessonID: "shock",
            title: "Treat for Shock",
            keywords: ["shock", "injury"]
        )
        return ArticleBackedExpertEvidenceRetriever(retrieval: FixedRetriever(
            passages: [
                RetrievedPassage(article: bleeding, score: 2),
                RetrievedPassage(article: shock, score: 1),
            ]
        )).searchExpertEvidence(query: "bleeding", domain: nil, limit: 2)
    }

    private func article(
        id: String,
        lessonID: String,
        title: String,
        summary: String = "Reviewed action card.",
        keywords: [String],
        steps: [String] = ["Apply the reviewed action."],
        warnings: [String] = ["Stop if the condition worsens."]
    ) -> KnowledgeArticle {
        KnowledgeArticle(
            id: id,
            domain: .firstAid,
            title: title,
            summary: summary,
            steps: steps,
            warnings: warnings,
            keywords: keywords,
            source: SourceReference(
                id: "source-\(id)",
                title: "Reviewed Source",
                organization: "Aurora",
                revision: "1"
            ),
            reviewed: true,
            manualReference: ManualReference(
                passageID: id,
                lessonID: lessonID,
                chapterID: "medical",
                chapterNumber: 1,
                chapterTitle: "Medical",
                sectionTitle: title,
                sourceLabel: "Reviewed Source"
            )
        )
    }
}

private struct FixedRetriever: EvidenceRetrieving {
    let passages: [RetrievedPassage]

    func search(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedPassage] {
        Array(passages.prefix(limit))
    }
}
