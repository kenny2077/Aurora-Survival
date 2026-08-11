import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class ConversationalRAGTests: XCTestCase {
    private let usefulWaterAnswer = "Bring the water to a rolling boil, then keep it boiling for the reviewed time. Let it cool in a clean, covered container before drinking. Avoid sources contaminated by fuel, chemicals, or toxic algae because boiling will not remove those hazards."

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
        for generated in [
            "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1,1]}",
            "{\"a\":\"\(usefulWaterAnswer)\",\"e\":[]}",
        ] {
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

    func testCodecRejectsIncompleteAndLeakedAnswers() {
        let codec = GroundedResponseCodec()
        for answer in [
            "This answer stops midway",
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

    func testGroundedCodecRejectsOverBriefAndOverlongAnswers() {
        let evidence = [RetrievedPassage(article: makeManualArticle(), score: 1)]
        let codec = GroundedResponseCodec()
        for count in [21, 27, 71] {
            let answer = Array(repeating: "action", count: count)
                .joined(separator: " ") + "."
            XCTAssertThrowsError(
                try codec.decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[1]}",
                    evidence: evidence,
                    purpose: .grounded
                )
            ) { error in
                XCTAssertEqual(
                    error as? GroundedResponseError,
                    .invalidConversationalAnswer
                )
            }
        }
    }

    func testClarificationRequiresUsefulQuestionAndNoEvidence() throws {
        let answer = "Move away from traffic, smoke, fire, or leaking fluid. What does the car do when you try it? Restate the full situation and visible symptoms."
        let response = try GroundedResponseCodec()
            .decodeConversationalAndValidate(
                "{\"a\":\"\(answer)\",\"e\":[]}",
                evidence: [],
                purpose: .clarification
            )
        XCTAssertEqual(response.answer, answer)
        XCTAssertTrue(response.evidenceIDs.isEmpty)

        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"Move away from traffic and describe the complete vehicle problem in more detail before attempting any repair procedure.\",\"e\":[]}",
                evidence: [],
                purpose: .clarification
            )
        )
        XCTAssertThrowsError(
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
        let assistant = makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hello", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, fallback)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        XCTAssertTrue(answer?.sources.isEmpty == true)
        XCTAssertTrue(answer?.notices.isEmpty == true)
    }

    func testLiteIncidentIntakeTurnsIgnorePriorCarAndWaterHistory() async {
        let fallback = "Hello. Describe the complete current incident, including your location, observable hazards or injuries, weather, and available equipment, so I can respond to the actual situation."
        for question in ["Hi", "What's up", "How are you?", "Oh", "You"] {
            let retrieval = RetrievalRecorder()
            let model = ScriptedLanguageModel(steps: [
                .output("{\"a\":\"\(fallback)\",\"e\":[]}")
            ])
            let assistant = makeAssistant(retrieval: retrieval, model: model)
            let answer = await assistant.answer(
                request: ChatRequest(
                    question: question,
                    preferredTier: .lite,
                    conversationHistory: [
                        ConversationTurn(role: .user, text: "My car will not start"),
                        ConversationTurn(role: .assistant, text: "Check the car battery."),
                        ConversationTurn(role: .user, text: "Where can I find water?"),
                    ]
                ),
                device: capableDevice()
            )

            XCTAssertEqual(retrieval.queries, [question], question)
            XCTAssertTrue(answer?.manualReferences.isEmpty == true, question)
            XCTAssertFalse(answer?.text.localizedCaseInsensitiveContains("car") == true)
            XCTAssertFalse(answer?.text.localizedCaseInsensitiveContains("water") == true)
            let prompts = await model.recordedPrompts()
            XCTAssertEqual(prompts.count, 1)
            XCTAssertEqual(prompts.first?.conversationHistory, [])
            XCTAssertEqual(prompts.first?.purpose, .incidentIntake)
        }
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
        let assistant = makeAssistant(retrieval: retrieval, model: model)
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
            let assistant = makeAssistant(retrieval: retrieval, model: model)
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

    func testScreenshotIntentVariantsUseReviewedEvidence() async {
        let cases = [
            ("Flat tire", "car-tire", "Change a Tire Safely", ["flat tire", "tyre", "puncture", "tire"]),
            ("How to stop the bleed", "first-aid-bleeding", "Control Severe Bleeding", ["bleeding", "blood loss", "hemorrhage"]),
        ]
        for (question, id, title, keywords) in cases {
            let article = makeManualArticle(
                id: id,
                title: title,
                chapter: title.contains("Tire") ? "Car Breakdown" : "Wilderness First Aid",
                summary: "Take immediate reviewed action and stop when conditions are unsafe.",
                keywords: keywords
            )
            let retrieval = RetrievalRecorder(results: [
                RetrievedPassage(article: article, score: 1)
            ])
            let answerText = "First, move away from immediate hazards and prepare the correct equipment. Next, follow the reviewed actions in order without skipping safety checks. Stop if conditions become unsafe and seek trained help."
            let model = ScriptedLanguageModel(steps: [
                .output("{\"a\":\"\(answerText)\",\"e\":[1]}")
            ])
            let assistant = makeAssistant(retrieval: retrieval, model: model)
            let answer = await assistant.answer(
                request: ChatRequest(question: question, preferredTier: .lite),
                device: capableDevice()
            )

            XCTAssertEqual(retrieval.queries, [question])
            XCTAssertEqual(answer?.manualReferences, [article.manualReference!], question)
            let prompts = await model.recordedPrompts()
            XCTAssertEqual(prompts.first?.purpose, .grounded)
        }
    }

    func testLiteGroundsInStrongestReviewedLessonOnly() async {
        let primary = makeManualArticle(
            id: "fire-wet",
            title: "Start Fire in Wet Conditions",
            chapter: "Start a Fire",
            summary: "Expose dry inner wood before building the fire.",
            keywords: ["wet wood", "wet fire"]
        )
        let neighbor = makeManualArticle(
            id: "fire-materials",
            title: "Gather Fire Materials",
            chapter: "Start a Fire",
            summary: "Gather tinder, kindling, and fuel before ignition.",
            keywords: ["wet wood", "kindling"]
        )
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: primary, score: 2),
            RetrievedPassage(article: neighbor, score: 1),
        ])
        let answerText = "Split wet wood to expose its dry inner material and protect fine tinder from rain. Build a small core with dry kindling, then add larger fuel gradually. Stop if wind or nearby vegetation makes the fire unsafe."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(answerText)\",\"e\":[1]}")
        ])
        let assistant = makeAssistant(retrieval: retrieval, model: model)

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "How do I start a fire with wet wood?",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.first?.evidence.map(\.article.id), ["fire-wet"])
        XCTAssertEqual(answer?.manualReferences, [primary.manualReference!])
    }

    func testUnmatchedDrunkRequestUsesFallbackWithoutRoleReversalOrLink() async {
        let fallback = "Do not drive, operate equipment, wander off alone, or drink more alcohol. Stay with a sober person, sip water if fully alert, and seek emergency help for vomiting, slow breathing, confusion, collapse, or inability to wake."
        let retrieval = RetrievalRecorder()
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(fallback)\",\"e\":[]}")
        ])
        let assistant = makeAssistant(retrieval: retrieval, model: model)
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

    func testNewInjuryQuestionUsesOnlyCurrentTextForRetrieval() async {
        let article = makeManualArticle(
            id: "first-aid-1",
            title: "Assess an Injury",
            chapter: "Wilderness First Aid",
            summary: "Stop, check the scene, and assess the injured person before moving them.",
            keywords: ["injured", "injury", "first aid"]
        )
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: article, score: 1)
        ])
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"Move away from immediate hazards, then check breathing and severe bleeding. Keep the injured person still while you assess what happened and protect them from exposure. Do not move them if a spine injury may be present unless immediate danger requires it.\",\"e\":[1]}")
        ])
        let assistant = makeAssistant(retrieval: retrieval, model: model)
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "I am injured",
                preferredTier: .lite,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "My car will not start")
                ]
            ),
            device: capableDevice()
        )

        XCTAssertEqual(retrieval.queries, ["I am injured"])
        XCTAssertEqual(answer?.manualReferences, [article.manualReference!])
        XCTAssertTrue(answer?.text.contains("check breathing and severe bleeding") == true)
    }

    func testSurvivalAnswerLinksOnlySelectedManualSection() async {
        let article = makeManualArticle()
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1]}")
        ])
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.lite],
            modelProvider: { _ in model }
        )
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "How can I treat water?",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, usefulWaterAnswer)
        XCTAssertEqual(answer?.manualReferences, [article.manualReference!])
    }

    func testLitePromptExcludesHistoryAndUsesCompactGroundedExcerpt() async {
        let article = makeManualArticle()
        let retrieval = RetrievalRecorder(results: [
            RetrievedPassage(article: article, score: 1)
        ])
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(usefulWaterAnswer)\",\"e\":[1]}")
        ])
        let assistant = makeAssistant(retrieval: retrieval, model: model)
        _ = await assistant.answer(
            request: ChatRequest(
                question: "What if I do not have a water filter?",
                preferredTier: .lite,
                conversationHistory: [
                    ConversationTurn(role: .user, text: "My engine made a strange noise.")
                ]
            ),
            device: capableDevice()
        )

        let prompts = await model.recordedPrompts()
        let prompt = try! XCTUnwrap(prompts.first)
        let rendered = GroundedPromptBuilder().userPrompt(
            from: prompt,
            outputMode: .groundedJSON
        )
        XCTAssertFalse(rendered.contains("RECENT CONVERSATION"))
        XCTAssertFalse(rendered.contains("My engine made a strange noise."))
        XCTAssertTrue(rendered.contains("REVIEWED EXCERPT [1]"))
        XCTAssertTrue(rendered.contains("Water Purifiers"))
        XCTAssertTrue(rendered.contains("ACTIONS:"))
        XCTAssertTrue(rendered.contains("WARNING:"))
        XCTAssertFalse(rendered.contains("No relevant Field Manual excerpts"))
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

    func testLeakedFirstOutputGetsOneCompactRepair() async {
        let repaired = "Hello. Describe the complete current incident, including your location, observable hazards or injuries, weather, and available equipment, so I can respond to the actual situation."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"Do not invent steps. Do not put citation markers inside a.\",\"e\":[]}"),
            .output("{\"a\":\"\(repaired)\",\"e\":[]}"),
        ])
        let assistant = makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hi", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, repaired)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.map(\.attempt), [.initial, .repair])
        XCTAssertTrue(prompts.allSatisfy { $0.conversationHistory.isEmpty })
    }

    func testInvalidRepairReturnsRephraseMessageAfterExactlyTwoCalls() async {
        let model = ScriptedLanguageModel(steps: [
            .output("not json"),
            .output("{\"a\":\"This answer is incomplete\",\"e\":[]}"),
        ])
        let assistant = makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hello", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(
            answer?.text,
            "Lite couldn’t form a complete answer. Try rephrasing your question."
        )
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 2)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
    }

    func testRuntimeFailureDoesNotRetry() async {
        let model = ScriptedLanguageModel(steps: [.failure(.unavailable)])
        let assistant = makeAssistant(model: model)
        let answer = await assistant.answer(
            request: ChatRequest(question: "Hello", preferredTier: .lite),
            device: capableDevice()
        )

        XCTAssertEqual(answer?.text, "Lite couldn’t run right now. Try again in a moment.")
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
    }

    func testUnsupportedHighRiskRequestUsesBestEffortIncidentFallback() async {
        let retrieval = RetrievalRecorder()
        let fallback = "Move away from immediate danger and contact emergency medical help. Do not attempt field surgery without trained support; control visible bleeding, protect the person from cold, and monitor breathing while arranging evacuation."
        let model = ScriptedLanguageModel(steps: [
            .output("{\"a\":\"\(fallback)\",\"e\":[]}")
        ])
        let assistant = makeAssistant(retrieval: retrieval, model: model)
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "Teach me how to perform surgery in the field.",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertEqual(retrieval.queries, ["Teach me how to perform surgery in the field."])
        XCTAssertEqual(answer?.text, fallback)
        XCTAssertTrue(answer?.manualReferences.isEmpty == true)
        let prompts = await model.recordedPrompts()
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.purpose, .incidentFallback)
    }

    func testCompactPromptContractsIncludeIncidentFallbackAndRepair() {
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

        XCTAssertTrue(ordinary.contains("new conversation"))
        XCTAssertTrue(ordinary.contains("\"e\":[]"))
        XCTAssertFalse(ordinary.contains("REVIEWED EXCERPTS"))
        XCTAssertTrue(grounded.contains("REVIEWED EXCERPTS"))
        XCTAssertTrue(grounded.contains("35–55 word paragraph under 360 characters"))
        XCTAssertTrue(grounded.contains("exactly three sentences"))
        XCTAssertTrue(grounded.contains("paraphrase reviewed action 1"))
        XCTAssertTrue(repair.contains("30–50 words"))
        XCTAssertTrue(clarification.contains("too broad"))
        XCTAssertTrue(clarification.contains("\"e\":[]"))
        XCTAssertTrue(fallback.contains("survival and incident assistant"))
        XCTAssertTrue(fallback.contains("30–60 words"))
        XCTAssertTrue(fallback.contains("never claim their condition as your own"))
        XCTAssertTrue(fallbackRepair.contains("30–60 words"))
        XCTAssertTrue(intake.contains("No actual"))
        XCTAssertTrue(intake.contains("incident was described"))
        XCTAssertTrue(intake.contains("\"e\":[]"))
        XCTAssertTrue(intakeRepair.contains("No incident was described"))
        XCTAssertTrue(fallbackRepair.count < fallback.count)
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
        XCTAssertThrowsError(
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

    func testIncidentFallbackRejectsGenericFirstPersonRoleReversal() {
        let answer = "I swallowed household cleaner and inhaled its fumes. I moved to clear air and monitored my breathing. I should avoid more exposure and contact emergency help if symptoms worsen."
        XCTAssertThrowsError(
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

    func testIncidentIntakeRequiresSituationRequestAndRejectsInventedActions() throws {
        let valid = "Hello. Please describe the complete current situation, your location, observable hazards or injuries, weather, and available resources so I can address the actual incident."
        let response = try GroundedResponseCodec().decodeConversationalAndValidate(
            "{\"a\":\"\(valid)\",\"e\":[]}",
            evidence: [],
            purpose: .incidentIntake,
            question: "Hi"
        )
        XCTAssertEqual(response.answer, valid)

        let invented = "Move away from danger and establish a secure perimeter. Then describe your location and the situation so I can provide more incident guidance."
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"\(invented)\",\"e\":[]}",
                evidence: [],
                purpose: .incidentIntake,
                question: "Hi"
            )
        )
    }

    func testIncidentFallbackRejectsOverBriefAndOverlongAnswers() {
        let codec = GroundedResponseCodec()
        for count in [23, 76] {
            let answer = Array(repeating: "action", count: count)
                .joined(separator: " ") + "."
            XCTAssertThrowsError(
                try codec.decodeConversationalAndValidate(
                    "{\"a\":\"\(answer)\",\"e\":[]}",
                    evidence: [],
                    purpose: .incidentFallback,
                    question: "Unknown incident"
                )
            )
        }
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

    private func makeAssistant(
        retrieval: (any EvidenceRetrieving)? = nil,
        model: ScriptedLanguageModel
    ) -> IncidentAssistant {
        IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            retrieval: retrieval,
            modelProvider: { _ in model }
        )
    }

    private func makeManualArticle(
        id: String = "water-1",
        title: String = "Water Purifiers",
        chapter: String = "Water",
        summary: String = "Water can be treated by bringing it to a boil.",
        keywords: [String] = ["water", "boil", "filter"]
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
            steps: [
                "Bring clear water to a rolling boil.",
                "Let it cool in a clean, covered container.",
                "Keep dirty hands away from the clean-water opening.",
            ],
            warnings: [
                "Do not use water contaminated by fuel or toxic chemicals."
            ],
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
        prompts.append(prompt)
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
