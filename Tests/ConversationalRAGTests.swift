import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ConversationalRAGTests: XCTestCase {
    private let usefulWaterAnswer = "Bring the water to a rolling boil, then keep it boiling for the reviewed time. Let it cool in a clean, covered container before drinking. Avoid sources contaminated by fuel, chemicals, or toxic algae because boiling will not remove those hazards."

    func testChineseLiteBypassesRoutingAndRetrievalAndDisplaysMixedAnswer() async throws {
        let generated = #"{"a":"先寻找流动水源。 Search downhill carefully","e":[]}"#
        let model = ScriptedLanguageModel(steps: [.output(generated)])
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: makeManualArticle(), score: 1),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            retrieval: retrieval,
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "在野外怎么找到水源？",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, "先寻找流动水源。 Search downhill carefully")
        XCTAssertTrue(answer?.sources.isEmpty == true)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        XCTAssertTrue(answer?.notices.isEmpty == true)
        XCTAssertTrue(retrieval.queries.isEmpty)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.purpose, .ordinary)
        XCTAssertTrue(prompts.first?.expertEvidence.isEmpty == true)
        let prompt = try XCTUnwrap(prompts.first)
        let builder = GroundedPromptBuilder()
        let system = builder.systemPrompt(for: prompt, outputMode: .groundedJSON)
        let user = builder.userPrompt(from: prompt, outputMode: .groundedJSON)
        for forbidden in ["CURRENT USER MESSAGE", "REVIEWED", "ROUTING", "English"] {
            XCTAssertFalse(system.contains(forbidden))
            XCTAssertFalse(user.contains(forbidden))
        }
        XCTAssertTrue(user.contains("当前用户消息\n在野外怎么找到水源？"))
    }

    func testChineseExpertUsesOnlyChineseHistoryAndPreservesTruncatedAnswer() async throws {
        let model = ScriptedLanguageModel(steps: [
            .output(#"{"a":"先观察地势并寻找流动水源"#),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "在野外怎么找到水源？",
                preferredTier: .expert,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "Where can I find water?"),
                    ConversationTurn(role: .assistant, text: "Search downhill."),
                    ConversationTurn(role: .user, text: "我还需要净化水。"),
                    ConversationTurn(role: .assistant, text: "先过滤明显沉淀。"),
                ]
            ),
            device: capableExpertDevice()
        )

        XCTAssertEqual(answer?.text, "先观察地势并寻找流动水源")
        XCTAssertTrue(answer?.sourceDisplayNames.isEmpty == true)
        XCTAssertTrue(answer?.notices.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 1)
        let prompt = try XCTUnwrap(prompts.first)
        XCTAssertEqual(prompt.purpose, .ordinary)
        XCTAssertEqual(
            prompt.conversationHistory.map(\.text),
            ["我还需要净化水。", "先过滤明显沉淀。"]
        )
    }

    func testChineseNonemptyMalformedGenerationIsDisplayedRaw() async {
        let model = ScriptedLanguageModel(steps: [.output("模型原始输出")])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(question: "你是谁？", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, "模型原始输出")
        XCTAssertTrue(answer?.notices.isEmpty == true)
    }

    func testChineseGroundedResponsePreservesReviewedEvidenceLink() throws {
        let article = makeManualArticle()
        let evidence = [RetrievedPassage(article: article, score: 1)]
        let answer = "先选择没有燃油、化学品或有毒藻类污染迹象的水源，再过滤明显沉淀并将水持续煮沸。冷却时使用干净且有盖的容器；不要饮用仍有异味、变色或油膜的水。"
        let response = try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(answer)\",\"e\":[1]}",
            evidence: evidence,
            purpose: .grounded,
            tier: .lite,
            responseLanguage: .chinese
        )

        XCTAssertEqual(response.answer, answer)
        XCTAssertEqual(response.evidenceIDs, [article.id])
    }

    func testCodecDoesNotBlockUsefulProseByLanguage() {
        let evidence = [RetrievedPassage(article: makeManualArticle(), score: 1)]
        for answer in [
            "Search streams and springs before moving downhill.",
            "先寻找流动水源。 Search streams and springs before moving downhill.",
        ] {
            XCTAssertNoThrow(
                try GroundedResponseCodec().decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[1]}",
                    evidence: evidence,
                    purpose: .grounded,
                    responseLanguage: .chinese
                )
            )
        }
    }

    func testSpanishPromptUsesAdaptiveLanguageAndPlacesCurrentMessageLast() {
        let question = "¿Cómo puedo construir un refugio temporal?"
        let prompt = ModelPrompt(
            question: question,
            evidence: [],
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: false,
            responseLanguage: ResponseLanguage.detect(in: question),
            purpose: .ordinary
        )
        let builder = GroundedPromptBuilder()
        let system = builder.systemPrompt(for: prompt, outputMode: .groundedJSON)
        let user = builder.userPrompt(from: prompt, outputMode: .groundedJSON)

        XCTAssertTrue(system.contains("Spanish"))
        XCTAssertTrue(user.contains("CURRENT USER MESSAGE\n\(question)"))
        XCTAssertLessThan(
            user.range(of: "RESPONSE CHECK")!.lowerBound,
            user.range(of: "CURRENT USER MESSAGE")!.lowerBound
        )
    }

    func testAuroraChinesePromptUsesLocalizedLiveDataPolicy() {
        let builder = GroundedPromptBuilder()
        let prompt = ModelPrompt(
            question: "你好",
            evidence: [],
            imageObservations: [],
            tier: .lite,
            permitsVisionReasoning: false,
            responseLanguage: .chinese,
            purpose: .ordinary
        )
        let system = builder.systemPrompt(for: prompt, outputMode: .groundedJSON)
        let user = builder.userPrompt(from: prompt, outputMode: .groundedJSON)

        XCTAssertTrue(system.contains("Aurora Survival Agent Lite"))
        XCTAssertTrue(system.contains("只使用清晰、自然的简体中文"))
        XCTAssertTrue(system.contains("只有当用户询问实时天气"))
        XCTAssertTrue(user.contains("当前用户消息\n你好"))
        XCTAssertFalse(system.contains("current message"))
        XCTAssertFalse(user.contains("CURRENT USER MESSAGE"))
        XCTAssertFalse(system.contains("Trail" + "Guard"))
    }

    func testUnsupportedChannelTextIsRejected() {
        XCTAssertThrowsError(try GroundedResponseCodec().decodeConversationalAndValidate(
            #"{"a":"Unsupported channel returned by the local model.","e":[]}"#,
            evidence: [],
            purpose: .ordinary
        ))
    }

    func testExpertGroundedContractAllowsModelLedConciseAnswer() throws {
        let evidence = [RetrievedPassage(article: makeManualArticle(), score: 1)]
        let answer = "Move the container away from visible fuel, chemical sheen, and algae before collecting anything. Prefer the clearest available source, filter out sediment, then bring the water to a rolling boil and keep it there for the reviewed duration. This sequence reduces biological contamination while limiting extra exposure and wasted fuel. Do not rely on boiling for chemicals or fuel; stop using that source and seek a safer supply if odor, color, or sheen remains."

        XCTAssertNoThrow(try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(answer)\",\"e\":[1]}",
            evidence: evidence,
            purpose: .grounded,
            tier: .expert
        ))
        XCTAssertNoThrow(try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1]}",
            evidence: evidence,
            purpose: .grounded,
            tier: .expert
        ))
    }

    func testCodecReturnsNaturalAnswerWithoutRenderingProcedureText() throws {
        let article = makeManualArticle()
        let evidence = [RetrievedPassage(article: article, score: 1)]
        let response = try GroundedResponseCodec()
            .decodeConversationalAndValidate(
                "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1]}",
                evidence: evidence,
                purpose: .grounded
            )

        XCTAssertEqual(
            GroundedResponseCodec().renderConversational(
                response,
                evidence: evidence
            ),
            response.answer
        )
        XCTAssertEqual(response.evidenceIDs, [article.id])
        XCTAssertNil(response.procedureID)
    }

    func testCodecRejectsUnknownDuplicateMissingAndOrdinaryEvidence() {
        let evidence = [RetrievedPassage(article: makeManualArticle(), score: 1)]
        let codec = GroundedResponseCodec()

        XCTAssertThrowsError(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[2]}",
                evidence: evidence,
                purpose: .grounded
            )
        ) { error in
            XCTAssertEqual(error as? GroundedResponseError, .unknownEvidenceIndex(2))
        }
        XCTAssertNoThrow(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1,1]}",
                evidence: evidence,
                purpose: .grounded
            )
        )
        for generated in ["{\"a\":\"\(usefulWaterAnswer)\",\"e\":[]}"] {
            XCTAssertThrowsError(
                try codec.decodeConversationalAndValidate(
                    generated,
                    evidence: evidence,
                    purpose: .grounded
                )
            ) { error in
                XCTAssertEqual(
                    error as? GroundedResponseError,
                    .invalidConversationalEvidence
                )
            }
        }
        XCTAssertThrowsError(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"Hello! How are you doing today?\",\"e\":[1]}",
                evidence: evidence,
                purpose: .ordinary
            )
        )
    }

    func testCodecAcceptsIncompleteProseButRejectsProtocolLeakage() {
        let codec = GroundedResponseCodec()
        XCTAssertNoThrow(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"This answer stops midway\",\"e\":[]}",
                evidence: [],
                purpose: .ordinary
            )
        )
        for answer in [
            "Do not invent steps. Do not put citation markers inside a.",
            "Return exactly the requested JSON object.",
            "Read FIELD MANUAL [1] before continuing.",
        ] {
            XCTAssertThrowsError(
                try codec.decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[]}",
                    evidence: [],
                    purpose: .ordinary
                )
            ) { error in
                XCTAssertEqual(
                    error as? GroundedResponseError,
                    .invalidConversationalAnswer
                )
            }
        }
    }

    func testExpertAttributedCodecRejectsUnbalancedDelimiterEnding() {
        let generated = #"{"s":[{"a":"Cook retained fish to 145 °F (62.","e":[1]},{"a":"Stop if conditions become unsafe.","e":[2]}]}"#

        XCTAssertThrowsError(
            try ExpertAttributedAnswerCodec().decodeAndValidate(
                generated,
                evidenceCount: 2
            )
        ) { error in
            XCTAssertEqual(
                error as? ExpertAttributedAnswerError,
                .invalidSentence(1)
            )
        }
    }

    func testGroundedCodecAcceptsConciseProseAndRejectsOnlyOverlongAnswers() {
        let evidence = [RetrievedPassage(article: makeManualArticle(), score: 1)]
        let codec = GroundedResponseCodec()
        for count in [125, 161, 700] {
            let answer = String(repeating: "a", count: count)
            XCTAssertNoThrow(
                try codec.decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[1]}",
                    evidence: evidence,
                    purpose: .grounded
                )
            )
        }
        let overlong = String(repeating: "a", count: 701)
        XCTAssertThrowsError(try codec.decodeConversationalAndValidate(
            "{\"a\":\"\(overlong)\",\"e\":[1]}",
            evidence: evidence,
            purpose: .grounded
        ))
    }

    func testClarificationKeepsEmptyEvidenceWithoutStyleScoring() throws {
        let answer = "Move away from traffic, smoke, fire, or leaking fluid. What does the car do when you try it? Restate the full situation and visible symptoms."
        let response = try GroundedResponseCodec()
            .decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[]}",
                evidence: [],
                purpose: .clarification
            )
        XCTAssertEqual(response.answer, answer)
        XCTAssertTrue(response.evidenceIDs.isEmpty)

        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"Move away from traffic and describe the complete vehicle problem in more detail before attempting any repair procedure.\",\"e\":[]}",
                evidence: [],
                purpose: .clarification
            )
        )
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"Stay away from traffic, then jump start the battery. What sound happens when you turn the key, and which warning lights remain visible?\",\"e\":[]}",
                evidence: [],
                purpose: .clarification
            )
        )
    }

    func testGreetingUsesIncidentIntakeWithoutManualLinkOrReadyNotice() async {
        let fallback = "Hello. Describe the complete current situation, including your location, observable hazards or injuries, weather, and available equipment, so I can respond to the actual incident."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(fallback)\",\"e\":[]}")
        ])
        let assistant = await makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hello", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, fallback)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertTrue(answer?.sources.isEmpty == true)
        XCTAssertTrue(answer?.notices.isEmpty == true)
    }

    func testBroadCarRequestUsesIncidentFallbackWithoutManualLink() async {
        let article = makeManualArticle(
            id: "car-stuck",
            title: "Recover From Snow, Mud, or Sand",
            chapter: "Car Breakdown",
            summary: "Prevent exhaust poisoning before gentle self-recovery.",
            keywords: ["stuck car", "snow", "mud", "sand", "traction"]
        )
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: article, score: 1)
        ])
        let fallback = "Move away from traffic, smoke, fire, or leaking fluid. Check what happens when you try the car, then describe the sounds, warning lights, smells, and visible damage before attempting a specific repair."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(fallback)\",\"e\":[]}")
        ])
        let assistant = await makeAssistant(retrieval: retrieval, model: model)
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "How to fix my car",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, fallback)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertFalse(answer?.text.localizedCaseInsensitiveContains("snow") == true)
        let prompts = await model.recordedPrompts()
        let prompt = prompts.first
        XCTAssertEqual(prompt?.purpose, .incidentFallback)
        XCTAssertTrue(prompt?.evidence.isEmpty == true)
    }

    func testPossessionIndoorSmokeAndHouseholdWireDoNotFalseGround() async {
        let cases = [
            (
                "I lost my keys",
                makeManualArticle(
                    id: "navigation-stop-mark",
                    title: "Stop and Mark the Last Known Point",
                    chapter: "Navigate When Lost",
                    keywords: ["lost", "last known point"]
                )
            ),
            (
                "I inhaled smoke inside my house",
                makeManualArticle(
                    id: "weather-wildlife-wildfire",
                    title: "Respond to Wildfire and Smoke",
                    chapter: "Weather and Wildlife",
                    keywords: ["wildfire", "smoke"]
                )
            ),
            (
                "A live electrical wire is sparking indoors",
                makeManualArticle(
                    id: "car-fuse",
                    title: "Check Fuses and Basic Electrical Faults",
                    chapter: "Car Breakdown",
                    keywords: ["fuse", "electrical"]
                )
            ),
            (
                "I swallowed household cleaner",
                makeManualArticle(
                    id: "weather-wildlife-wildfire",
                    title: "Respond to Wildfire and Smoke",
                    chapter: "Weather and Wildlife",
                    summary: "Move toward cleaner air and away from wildfire smoke.",
                    keywords: ["wildfire", "forest smoke"]
                )
            ),
            (
                "I have severe chest pain",
                makeManualArticle(
                    id: "navigation-travel-crossing",
                    title: "Travel and Cross Water Safely",
                    chapter: "Navigate When Lost",
                    summary: "Avoid travel in severe weather or when fatigue worsens.",
                    keywords: ["water crossing", "river travel"]
                )
            ),
        ]
        let fallback = "Keep a safe distance from the immediate hazard and prevent others from approaching. Contact the appropriate emergency service, then stop if conditions worsen or you cannot act without additional danger."

        for (question, article) in cases {
            let retrieval = RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1)
            ])
            let model = ScriptedLanguageModel(steps: [
                .output("{\"a\":\"\(fallback)\",\"e\":[]}")
            ])
            let assistant = await makeAssistant(retrieval: retrieval, model: model)
            let answer = await assistant.answer(
                request: ChatRequest(question: question, preferredTier: .lite),
                device: capableDevice()
            )

            XCTAssertEqual(answer?.text, fallback, question)
            XCTAssertTrue(answer?.manualReferences.isEmpty == true, question)
            let prompts = await model.recordedPrompts()
            XCTAssertEqual(prompts.first?.purpose, .incidentFallback, question)
        }
    }

    func testUnmatchedDrunkRequestUsesFallbackWithoutRoleReversalOrLink() async {
        let fallback = "Do not drive, operate equipment, wander off alone, or drink more alcohol. Stay with a sober person, sip water if fully alert, and seek emergency help for vomiting, slow breathing, confusion, collapse, or inability to wake."
        let retrieval = RetrievalRecorder()
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(fallback)\",\"e\":[]}")
        ])
        let assistant = await makeAssistant(retrieval: retrieval, model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "I’m drunk", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, fallback)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertTrue(answer?.sources.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.first?.purpose, .incidentFallback)
    }

    func testExpertPromptCanRetainBoundedHistory() {
        let prompt = ModelPrompt(
            question: "What should I do next?",
            evidence: [],
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: false,
            conversationHistory: [
                ConversationTurn(role: .user, text: "My engine made a strange noise.")
            ]
        )
        let rendered = GroundedPromptBuilder().userPrompt(
            from: prompt,
            outputMode: .groundedJSON
        )

        XCTAssertTrue(rendered.contains("RECENT CONVERSATION"))
        XCTAssertTrue(rendered.contains("My engine made a strange noise."))
    }

    func testExpertGroundedPromptListsOnlyReviewedNumbers() {
        let article = makeManualArticle(
            steps: ["Keep the site clear and stable."],
            warnings: ["Do not use an unsafe site."]
        )
        let prompt = ModelPrompt(
            question: "Where should I do this?",
            evidence: [RetrievedPassage(article: article, score: 1)],
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: false,
            expertEvidence: ArticleBackedExpertEvidenceRetriever(
                retrieval: RetrievalRecorder(results: [
                    RetrievedPassage(article: article, score: 1),
                ])
            ).searchExpertEvidence(query: "site", domain: nil, limit: 1),
            purpose: .grounded
        )
        let rendered = GroundedPromptBuilder().userPrompt(
            from: prompt,
            outputMode: .groundedJSON
        )
        XCTAssertTrue(rendered.contains("ALLOWED NUMBERS: none"))
    }

    func testRuntimeFailureDoesNotRetry() async {
        let model = ScriptedLanguageModel(steps: [.failure(.unavailable)])
        let assistant = await makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hello", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, "Lite couldn’t run right now. Try again in a moment.")
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
    }

    func testCompactPromptContractsIncludeFallbackAndRepairBoundaries() {
        let builder = GroundedPromptBuilder()
        let ordinary = builder.systemPrompt(
            for: .lite,
            purpose: .ordinary,
            outputMode: .groundedJSON
        )
        let grounded = builder.systemPrompt(
            for: .lite,
            purpose: .grounded,
            outputMode: .groundedJSON
        )
        let repair = builder.systemPrompt(
            for: .lite,
            purpose: .grounded,
            attempt: .repair,
            outputMode: .groundedJSON
        )
        let clarification = builder.systemPrompt(
            for: .lite,
            purpose: .clarification,
            outputMode: .groundedJSON
        )
        let fallback = builder.systemPrompt(
            for: .lite,
            purpose: .incidentFallback,
            outputMode: .groundedJSON
        )
        let fallbackRepair = builder.systemPrompt(
            for: .lite,
            purpose: .incidentFallback,
            attempt: .repair,
            outputMode: .groundedJSON
        )
        let intake = builder.systemPrompt(
            for: .lite,
            purpose: .incidentIntake,
            outputMode: .groundedJSON
        )
        let intakeRepair = builder.systemPrompt(
            for: .lite,
            purpose: .incidentIntake,
            attempt: .repair,
            outputMode: .groundedJSON
        )

        XCTAssertTrue(ordinary.contains("Aurora Survival Agent Lite"))
        XCTAssertTrue(ordinary.contains("\"e\":[]"))
        XCTAssertFalse(ordinary.contains("REVIEWED EXCERPTS"))
        XCTAssertTrue(grounded.contains("REVIEWED EXCERPTS"))
        XCTAssertTrue(grounded.contains("useful actions first"))
        XCTAssertTrue(grounded.contains("only when it is relevant and supported"))
        XCTAssertFalse(grounded.contains("exactly three sentences"))
        XCTAssertTrue(repair.contains("complete natural prose"))
        XCTAssertTrue(clarification.contains("too broad"))
        XCTAssertTrue(clarification.contains("\"e\":[]"))
        XCTAssertTrue(fallback.contains("No reviewed offline"))
        XCTAssertTrue(fallback.contains("concise, complete"))
        XCTAssertTrue(fallback.contains("qualified help, or emergency services"))
        XCTAssertTrue(fallback.contains("unidentified cactus"))
        XCTAssertEqual(fallbackRepair, fallback)
        XCTAssertTrue(intake.contains("No actual"))
        XCTAssertTrue(intake.contains("incident was described"))
        XCTAssertTrue(intake.contains("\"e\":[]"))
        XCTAssertTrue(intakeRepair.contains("No incident was described"))
        XCTAssertTrue(repair.count < grounded.count)
    }

    func testIncidentFallbackValidationRejectsRoleReversalAndEvidence() throws {
        let valid = "Do not drive or operate equipment. Stay with a sober person, drink only small amounts of water if fully alert, and seek emergency help for slow breathing, collapse, vomiting, confusion, or inability to wake."
        let response = try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(valid)\",\"e\":[]}",
            evidence: [],
            purpose: .incidentFallback,
            question: "I’m drunk"
        )
        XCTAssertEqual(response.answer, valid)

        let reversed = "I’m feeling a bit drunk and unsteady, so I should sit down somewhere safe. I will avoid driving, stop drinking alcohol, and ask a sober person to stay nearby."
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(reversed)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentFallback,
                question: "I’m drunk"
            )
        )
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(valid)\",\"e\":[1]}",
                evidence: [RetrievedPassage(article: makeManualArticle(), score: 1)],
                purpose: .incidentFallback,
                question: "I’m drunk"
            )
        )
    }

    func testIncidentFallbackAcceptsEmpatheticFirstPersonFraming() {
        let answer = "I understand you’re feeling anxious. Practice slow breathing and move to a quiet, safe place. If anxiety becomes overwhelming or you might harm yourself, contact emergency or crisis support now."
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentFallback,
                question: "I feel anxious"
            )
        )
    }

    func testIncidentFallbackDoesNotUseSubjectiveRoleReversalGate() {
        let answer = "I swallowed household cleaner and inhaled its fumes. I moved to clear air and monitored my breathing. I should avoid more exposure and contact emergency help if symptoms worsen."
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentFallback,
                question: "I swallowed household cleaner"
            )
        )
    }

    func testIncidentFallbackAllowsNegatedUnsafePhraseAndRejectsAffirmativeUse() {
        let safe = "Call Poison Control or emergency services now and keep the product label nearby. Do not induce vomiting or try to neutralize the cleaner. Monitor breathing and consciousness while waiting for professional instructions."
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(safe)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentFallback,
                question: "I swallowed household cleaner"
            )
        )

        let unsafe = "Induce vomiting immediately to remove the cleaner from your stomach. Drink water afterward and watch for irritation. Contact emergency services only if pain or breathing problems become severe."
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(unsafe)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentFallback,
                question: "I swallowed household cleaner"
            )
        )
    }

    func testIncidentIntakeKeepsEmptyEvidenceWithoutStyleScoring() throws {
        let valid = "Hello. Please describe the complete current situation, your location, observable hazards or injuries, weather, and available resources so I can address the actual incident."
        let response = try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(valid)\",\"e\":[]}",
            evidence: [],
            purpose: .incidentIntake,
            question: "Hi"
        )
        XCTAssertEqual(response.answer, valid)

        let invented = "Move away from danger and establish a secure perimeter. Then describe your location and the situation so I can provide more incident guidance."
        XCTAssertNoThrow(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(invented)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentIntake,
                question: "Hi"
            )
        )
    }

    func testIncidentFallbackAcceptsConciseAndRejectsOverlongAnswers() {
        let codec = GroundedResponseCodec()
        let concise = String(repeating: "a", count: 700)
        XCTAssertNoThrow(try codec.decodeConversationalAndValidate(
            "{\"a\":\"\(concise)\",\"e\":[]}",
            evidence: [],
            purpose: .incidentFallback,
            question: "Unknown incident"
        ))
        let overlong = String(repeating: "a", count: 701)
        XCTAssertThrowsError(try codec.decodeConversationalAndValidate(
            "{\"a\":\"\(overlong)\",\"e\":[]}",
            evidence: [],
            purpose: .incidentFallback,
            question: "Unknown incident"
        ))
    }

    func testConversationalAnswerRejectsInlineEvidenceMarkers() {
        let answer = "Apply firm direct pressure to the wound as described in [1]. Keep pressure steady, add clean material without removing soaked layers, and seek emergency evacuation for severe or uncontrolled bleeding."
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[1]}",
                evidence: [RetrievedPassage(article: makeManualArticle(), score: 1)],
                purpose: .grounded,
                question: "How do I stop bleeding?"
            )
        )
    }

    func testConversationalAnswerRejectsReversedUnknownFoodWarning() {
        let answer = "Eat an unknown berry or mushroom, but proceed with caution. Examine it first, discard it if uncertain, and seek poison help if symptoms begin after eating it."
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[1]}",
                evidence: [RetrievedPassage(article: makeManualArticle(), score: 1)],
                purpose: .grounded,
                question: "Can I eat an unknown berry?"
            )
        )
    }

    func testExpertRejectsUnsafeVisualCertaintyAndHandlingClaims() {
        let codec = GroundedResponseCodec()
        let answers = [
            "Yes, it is non-venomous and can move it with a stick safely.",
            "This is likely an edible species, although identification is uncertain.",
            "The tick is not infected yet, but monitor the area for changes.",
            "If it looks and smells normal, it's likely safe to eat.",
        ]
        for answer in answers {
            XCTAssertThrowsError(
                try codec.decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[]}",
                    evidence: [],
                    purpose: .ordinary,
                    tier: .expert
                )
            )
        }
    }

    func testExpertFollowupUsesHistoryToGroundReviewedEvidence() async {
        let article = makeManualArticle(
            id: "basics-stop",
            title: "Stop and Control Panic",
            chapter: "Survival Basics",
            summary: "Stop moving long enough to think clearly and avoid making the emergency larger.",
            keywords: ["stop", "control panic", "stop moving"],
            steps: [
                "Take slow breaths and say out loud what happened.",
                "Move only far enough to escape an immediate threat such as traffic, fire, falling rock, or rising water.",
                "Mark where you stopped and note the time, weather, and last place you were certain of your location.",
            ],
            warnings: [
                "Do not run downhill or follow water just because it appears to lead out.",
            ]
        )
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: article, score: 1),
        ])
        let model = ScriptedLanguageModel(steps: [
            .output(expertAnswerJSON([
                article.steps[0], article.steps[1], article.warnings[0],
            ]))
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: retrieval,
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            expertEmbeddingProvider: DivergentEmbeddingProvider(),
            expertVectorIndex: emptyVectorIndex(),
            modelProvider: { _ in model }
        )
        XCTAssertTrue(IncidentAssistant.matchesExactReviewedIntent(
            query: "Stop and Control Panic What should I do about that now?",
            article: article
        ))
        XCTAssertTrue(IncidentAssistant.matchesExactReviewedIntent(
            query: "STOP",
            article: article
        ))
        XCTAssertFalse(IncidentAssistant.matchesExactReviewedIntent(
            query: "water",
            article: article
        ))
        let fireMaterials = makeManualArticle(
            id: "fire-materials",
            title: "Gather Tinder, Kindling, and Fuel",
            keywords: ["tinder", "kindling", "fuel"]
        )
        XCTAssertTrue(IncidentAssistant.matchesExactReviewedIntent(
            query: "tinder",
            article: fireMaterials
        ))

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What should I do about that now?",
                preferredTier: .expert,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "Stop and Control Panic"),
                ]
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.map(\.purpose), [.expertIntent, .grounded])
    }

    func testExpertExactHistoryMatchOverridesUnsafeOrdinaryDisposition() async {
        let article = makeManualArticle(
            id: "basics-stop",
            title: "Stop and Control Panic",
            chapter: "Survival Basics",
            summary: "Stop moving long enough to think clearly and avoid making the emergency larger.",
            keywords: ["stop", "control panic", "stop moving"],
            steps: [
                "Take slow breaths and say out loud what happened.",
                "Move only far enough to escape an immediate threat such as traffic, fire, falling rock, or rising water.",
                "Mark where you stopped and note the time, weather, and last place you were certain of your location.",
            ],
            warnings: ["Do not run downhill or follow water just because it appears to lead out."]
        )
        let model = ScriptedLanguageModel(steps: [
            .output(expertAnswerJSON([
                article.steps[0], article.steps[1], article.warnings[0],
            ])),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1),
            ]),
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(measuredPeakBytes: [.full: 1])
            ),
            expertEmbeddingProvider: DivergentEmbeddingProvider(),
            expertVectorIndex: emptyVectorIndex(),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What should I do about that now?",
                preferredTier: .expert,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "Stop and Control Panic"),
                ]
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        let purposes = await model.recordedPrompts().map(\.purpose)
        XCTAssertEqual(
            purposes,
            [.expertIntent, .grounded]
        )
    }

    func testExpertStrongReviewedCoverageOverridesInventedClarificationGap() async {
        let article = makeManualArticle(
            id: "fire-site",
            title: "Choose a Safe Fire Site",
            chapter: "Start a Fire",
            summary: "Choose a site that contains heat and keeps flame away from roots, branches, and dry vegetation.",
            keywords: [
                "I need to pick a campfire spot near roots, grass, and low branches.",
                "select ground for a small fire",
            ],
            steps: [
                "Use an existing fire ring where fires are permitted.",
                "Clear loose needles, leaves, grass, and other burnable material from the immediate area.",
                "Keep the fire small and place it on mineral soil away from roots and low branches.",
            ],
            warnings: [
                "Do not light a fire when wind, restrictions, or dry fuels make containment doubtful."
            ]
        )
        let model = ScriptedLanguageModel(steps: [
            .output(expertAnswerJSON([
                article.steps[0], article.steps[1], article.warnings[0],
            ])),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1),
            ]),
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(measuredPeakBytes: [.full: 1])
            ),
            expertEmbeddingProvider: DivergentEmbeddingProvider(),
            expertVectorIndex: emptyVectorIndex(),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "I need to pick a campfire spot near roots, grass, and low branches.",
                preferredTier: .expert
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        let purposes = await model.recordedPrompts().map(\.purpose)
        XCTAssertEqual(
            purposes,
            [.expertIntent, .grounded]
        )
    }

    func testExpertDisplaysGroundedProseWithoutSourcesWhenEnvelopeIsIncomplete() async {
        let article = makeManualArticle()
        let draft = "Keep the container away from the visible fuel sheen. Use a different water source."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(draft)"),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1),
            ]),
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: article.steps[0],
                preferredTier: .expert
            ),
            device: capableExpertDevice()
        )

        XCTAssertEqual(answer?.text, draft)
        XCTAssertNil(answer?.verificationStatus)
        XCTAssertTrue(answer?.verificationIssues.isEmpty == true)
        let promptCount = await model.recordedPrompts().count
        XCTAssertEqual(promptCount, 2)
        XCTAssertTrue(answer?.sources.isEmpty == true)
    }

    func testExpertDoesNotRunSemanticVerificationPass() async {
        let article = makeManualArticle()
        let attributed = expertAnswerJSON([
            article.steps[0], article.steps[1], article.warnings[0],
        ])
        let model = ScriptedLanguageModel(steps: [
            .output(attributed),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1),
            ]),
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            expertEmbeddingProvider: DivergentEmbeddingProvider(),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: article.steps[0],
                preferredTier: .expert
            ),
            device: capableExpertDevice()
        )

        XCTAssertNil(answer?.verificationStatus)
        XCTAssertNil(answer?.supportStatus)
        XCTAssertNil(answer?.coverageStatus)
        XCTAssertTrue(answer?.verificationIssues.isEmpty == true)
        let promptCount = await model.recordedPrompts().count
        XCTAssertEqual(promptCount, 2)
    }

    func testExpertStandaloneTurnCannotGroundFromUnrelatedHistory() async {
        let article = makeManualArticle()
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: article, score: 1),
        ])
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"A quiet character-driven film may be a good choice tonight.\",\"e\":[]}"),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: retrieval,
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "Recommend a movie for tonight.",
                preferredTier: .expert,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "Earlier I asked how to boil water."),
                ]
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.map(\.purpose), [.expertIntent, .ordinary])
    }

    func testExpertNativeVisionUsesOneImageCallAndNoRetrievalOrSources() async {
        let retrieval = RetrievalRecorder()
        let model = ScriptedLanguageModel(steps: [
            .output(#"{"a":"The image is a bow-drill fire instruction diagram showing a spindle, bow, fireboard, and the sequence for producing an ember.","e":[]}"#),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: retrieval,
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(measuredPeakBytes: [.full: 1])
            ),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What is in the picture?",
                preferredTier: .expert,
                hasImage: true,
                imageData: Data([1, 2, 3])
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertTrue(answer?.sources.isEmpty == true)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        XCTAssertTrue(answer?.evidenceIDs.isEmpty == true)
        XCTAssertEqual(answer?.visionWasUsed, true)
        XCTAssertNil(answer?.expertIntent)
        XCTAssertNil(answer?.expertRetrievalStatus)
        XCTAssertTrue(retrieval.queries.isEmpty)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.map(\.purpose), [.nativeVisionAnswer])
        XCTAssertEqual(prompts.first?.imageData, Data([1, 2, 3]))
        XCTAssertEqual(prompts.first?.permitsVisionReasoning, true)
        XCTAssertTrue(prompts.first?.expertEvidence.isEmpty == true)
    }

    func testExpertNativeVisionKeepsCleanStreamedProseFromIncompleteEnvelope() async {
        let model = ScriptedLanguageModel(steps: [
            .output(#"{"a":"This most likely shows an insect resting on a leaf, although the fine species details are unclear.","e":[]"#),
        ])
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            retrieval: RetrievalRecorder(),
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(measuredPeakBytes: [.full: 1])
            ),
            modelProvider: { _ in model }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "Is that a leaf or an insect?",
                preferredTier: .expert,
                hasImage: true,
                imageData: Data([1, 2, 3])
            ),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertEqual(
            answer?.text,
            "This most likely shows an insect resting on a leaf, although the fine species details are unclear."
        )
        XCTAssertEqual(answer?.visionWasUsed, true)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.map(\.purpose), [.nativeVisionAnswer])
    }

    private func makeAssistant(
        retrieval: (any EvidenceRetrieving)? = nil,
        model: ScriptedLanguageModel
    ) async -> IncidentAssistant {
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            retrieval: retrieval,
            expertEmbeddingProvider: DivergentEmbeddingProvider(),
            expertVectorIndex: emptyVectorIndex(),
            modelProvider: { _ in model }
        )
        await assistant.setDebugLiteEvidencePolicy(.legacyTopOne)
        return assistant
    }

    private func emptyVectorIndex() -> ShardedExpertVectorIndex {
        ShardedExpertVectorIndex(
            directories: [],
            expectedEmbeddingIdentity: SharedRAGRuntimeResolver.embeddingIdentity
        )
    }

    private func expertAnswerJSON(_ sentences: [String]) -> String {
        let answer: [String: Any] = [
            "a": sentences.joined(separator: " "),
            "e": [1],
        ]
        return String(
            decoding: try! JSONSerialization.data(
                withJSONObject: answer,
                options: [.sortedKeys]
            ),
            as: UTF8.self
        )
    }

    private func makeManualArticle(
        id: String = "water-1",
        title: String = "Water Purifiers",
        chapter: String = "Water",
        summary: String = "Water can be treated by bringing it to a boil.",
        keywords: [String] = ["water", "boil", "filter"],
        steps: [String] = [
            "Bring clear water to a rolling boil.",
            "Let it cool in a clean, covered container.",
            "Keep dirty hands away from the clean-water opening.",
        ],
        warnings: [String] = [
            "Do not use water contaminated by fuel or toxic chemicals."
        ]
    ) -> KnowledgeArticle {
        let reference = ManualReference(
            chunkID: id,
            chapterNumber: chapter == "Water" ? 2 : 8,
            chapterTitle: chapter,
            sectionTitle: title,
            pageStart: 74,
            pageEnd: 74
        )
        return KnowledgeArticle(
            id: reference.chunkID,
            domain: chapter == "Water" ? .wilderness : .firstAid,
            title: reference.sectionTitle,
            summary: summary,
            steps: steps,
            warnings: warnings,
            keywords: keywords,
            source: SourceReference(
                id: reference.chunkID,
                title: reference.sectionTitle,
                organization: reference.chapterTitle,
                revision: reference.pageLabel
            ),
            reviewed: true,
            manualReference: reference
        )
    }

    private func capableDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }

    private func capableExpertDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
            availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }
}

private final class RetrievalRecorder: EvidenceRetrieving, @unchecked Sendable {
    private(set) var queries: [String] = []
    let results: [RetrievedPassage]

    init(results: [RetrievedPassage] = []) {
        self.results = results
    }

    func search(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedPassage] {
        queries.append(query)
        return Array(results.prefix(limit))
    }
}

private enum ScriptedStep: Sendable {
    case output(String)
    case failure(ModelFailure)
}

private actor ScriptedLanguageModel: LocalLanguageModel {
    nonisolated let tier: ModelTier = .lite
    nonisolated let outputMode: ModelOutputMode = .groundedJSON
    private var steps: [ScriptedStep]
    private var prompts: [ModelPrompt] = []

    init(steps: [ScriptedStep]) {
        self.steps = steps
    }

    func generate(prompt: ModelPrompt) async throws -> String {
        if prompt.tier != .lite || prompt.purpose != .expertIntent {
            prompts.append(prompt)
        }
        if prompt.purpose == .expertIntent {
            let lower = prompt.question.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let exactGreetings: Set<String> = ["hi", "hello", "wassup"]
            let generalTopics = [
                "movie", "software", "girlfriend", "weather today", "what's up",
            ]
            let intent = exactGreetings.contains(lower)
                || generalTopics.contains(where: lower.contains)
                ? "general" : "survival"
            let query = intent == "survival"
                ? prompt.question.replacingOccurrences(of: "\"", with: "")
                : ""
            return "{\"t\":\"\(intent)\",\"q\":\"\(query)\"}"
        }
        guard !steps.isEmpty else { throw ModelFailure.unavailable }
        switch steps.removeFirst() {
        case .output(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func recordedPrompts() -> [ModelPrompt] {
        prompts
    }
}

private struct DivergentEmbeddingProvider: ExpertQueryEmbeddingProvider {
    func embedding(for query: String) async throws -> [Float] {
        vector(at: 0)
    }

    func passageEmbedding(for text: String) async throws -> [Float] {
        vector(at: 1)
    }

    private func vector(at index: Int) -> [Float] {
        var value = [Float](
            repeating: 0,
            count: ShardedExpertVectorIndex.dimensions
        )
        value[index] = 1
        return value
    }
}
