import XCTest
#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ExpertOneShotStreamingTests: XCTestCase {
    func testEnvelopeDecoderStreamsOnlyAnswerWords() {
        let decoder = ExpertEnvelopeStreamDecoder()
        let pieces = [
            #"{"s":[{"a":"Check "#,
            #"the battery.","e":[1]},{"a":"Stop if "#,
            #"you smell fuel.","e":[2]}]}"#,
        ]
        let deltas = pieces.flatMap(decoder.append) + decoder.finish()

        XCTAssertEqual(deltas.joined(), "Check the battery. Stop if you smell fuel.")
        XCTAssertTrue(deltas.allSatisfy {
            $0.split(whereSeparator: \.isWhitespace).count <= 1
        })
        XCTAssertFalse(deltas.joined().contains("\"e\""))
        XCTAssertFalse(deltas.joined().contains("{"))
    }

    func testEnvelopeDecoderBuffersSplitUnicode() {
        let decoder = ExpertEnvelopeStreamDecoder()
        let deltas = decoder.append(#"{"a":"Stay warm \u26"#)
            + decoder.append(#"00 now.","e":[]}"#)
            + decoder.finish()

        XCTAssertEqual(deltas.joined(), "Stay warm ☀ now.")
    }

    func testNativeVisionPromptAnswersExactQuestionWithoutHazardRouting() {
        let prompt = ModelPrompt(
            question: "What is in the picture?",
            evidence: [],
            imageData: Data([1, 2, 3]),
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: true,
            purpose: .nativeVisionAnswer
        )
        let builder = GroundedPromptBuilder()
        let system = builder.systemPrompt(for: prompt, outputMode: .groundedJSON)
        let user = builder.userPrompt(from: prompt, outputMode: .groundedJSON)

        XCTAssertTrue(system.contains("exact question"))
        XCTAssertTrue(system.contains("most likely identification"))
        XCTAssertFalse(system.contains("hazard category"))
        XCTAssertTrue(user.contains("VISION CHECK"))
        XCTAssertFalse(user.contains("SELECTED REVIEWED"))
    }

    func testNativeVisionFailureDoesNotLaunchFallbackInference() async {
        let model = FailingVisionModel()
        let retrieval = ExpertRetrievalSpy()
        let assistant = makeAssistant(model: model, retrieval: retrieval)

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What is in this photo?",
                preferredTier: .expert,
                hasImage: true,
                imageData: Data([1, 2, 3])
            ),
            device: Self.capableDevice
        )

        let callCount = await model.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(retrieval.searchCount, 0)
        XCTAssertTrue(answer?.text.contains("couldn’t inspect the photo") == true)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
    }

    func testExpertUsesOneGenerationAndNoVerificationBadge() async {
        let model = OneShotExpertModel(
            intent: .generalQuestion,
            output: #"{"a":"Hello, how can I help?","e":[]}"#
        )
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
        let collector = DeltaCollector()

        let answer = await assistant.answer(
            request: ChatRequest(question: "Hi", preferredTier: .expert),
            device: Self.capableDevice,
            tokenSink: { collector.append($0) }
        )

        let callCount = await model.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(answer?.text, "Hello, how can I help?")
        XCTAssertEqual(collector.text, answer?.text)
        XCTAssertNil(answer?.verificationStatus)
        XCTAssertNil(answer?.supportStatus)
        XCTAssertNil(answer?.coverageStatus)
        XCTAssertTrue(answer?.sourceCards.isEmpty ?? false)
    }

    func testMalformedEnvelopeKeepsCleanStreamedProseWithoutSources() async {
        let model = OneShotExpertModel(
            intent: .generalQuestion,
            output: #"{"a":"Use the safest available route."#
        )
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
                question: "What route should I take?",
                preferredTier: .expert
            ),
            device: Self.capableDevice
        )

        let callCount = await model.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(answer?.text, "Use the safest available route.")
        XCTAssertTrue(answer?.sourceCards.isEmpty ?? false)
        XCTAssertFalse(answer?.notices.contains {
            $0.contains("source envelope was incomplete")
        } ?? true)
    }

    func testGeneralQuestionsSkipSurvivalRetrievalAndSources() async {
        for question in ["How to get a girlfriend", "How's the weather today?"] {
            let model = OneShotExpertModel(
                intent: .generalQuestion,
                output: #"{"a":"I can answer generally, but I do not have access to current live information.","e":[]}"#
            )
            let retrieval = ExpertRetrievalSpy()
            let assistant = makeAssistant(model: model, retrieval: retrieval)

            let answer = await assistant.answer(
                request: ChatRequest(question: question, preferredTier: .expert),
                device: Self.capableDevice
            )

            XCTAssertEqual(retrieval.searchCount, 0, "query: \(question)")
            XCTAssertEqual(answer?.expertIntent, .generalQuestion)
            XCTAssertNil(answer?.expertRetrievalStatus)
            XCTAssertTrue(answer?.sourceCards.isEmpty == true)
            XCTAssertTrue(answer?.evidenceIDs.isEmpty == true)
            let callCount = await model.callCount
            XCTAssertEqual(callCount, 2)
        }
    }

    func testMalformedIntentDefaultsToGeneralWithoutRetrieval() async {
        let model = OneShotExpertModel(
            rawIntent: #"{"t":"maybe"}"#,
            output: #"{"a":"I will answer this as a general offline question.","e":[]}"#
        )
        let retrieval = ExpertRetrievalSpy()
        let answer = await makeAssistant(model: model, retrieval: retrieval).answer(
            request: ChatRequest(
                question: "Tell me something interesting.",
                preferredTier: .expert
            ),
            device: Self.capableDevice
        )

        XCTAssertEqual(answer?.expertIntent, .generalQuestion)
        XCTAssertEqual(retrieval.searchCount, 0)
        let callCount = await model.callCount
        XCTAssertEqual(callCount, 2)
    }

    func testSurvivalWithoutEligibleEvidenceKeepsIntentAndNoSources() async {
        let model = OneShotExpertModel(
            intent: .survivalQuestion,
            output: #"{"a":"Move away from immediate hazards and preserve warmth, water, and communication while you assess the situation. Use only actions you can perform safely with available equipment. Stop and seek emergency help if conditions worsen or anyone becomes confused, unresponsive, or severely injured.","e":[]}"#
        )
        let retrieval = ExpertRetrievalSpy()
        let answer = await makeAssistant(model: model, retrieval: retrieval).answer(
            request: ChatRequest(
                question: "How should I handle an unfamiliar survival problem?",
                preferredTier: .expert
            ),
            device: Self.capableDevice
        )

        XCTAssertEqual(retrieval.searchCount, 0)
        XCTAssertEqual(answer?.expertIntent, .survivalQuestion)
        XCTAssertEqual(answer?.expertRetrievalStatus, .noRelevantEvidence)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        XCTAssertTrue(answer?.notices.contains {
            $0.contains("No matching offline source")
        } == true)
        let callCount = await model.callCount
        let purposes = await model.purposes()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(purposes, [.expertIntent, .incidentFallback])
        let systemPrompt = GroundedPromptBuilder().systemPrompt(
            for: .expert,
            purpose: .incidentFallback,
            outputMode: .groundedJSON
        )
        let compactPrompt = systemPrompt
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        XCTAssertTrue(compactPrompt.contains("No reviewed offline evidence matched"))
        XCTAssertTrue(compactPrompt.contains("Do not invent an exact"))
    }

    func testLiteUsesHiddenIntentAndOneStreamedStatelessAnswer() async {
        let model = OneShotExpertModel(
            tier: .lite,
            intent: .generalQuestion,
            output: #"{"a":"Hello, how can I help?","e":[]}"#
        )
        let retrieval = ExpertRetrievalSpy()
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            expertEvidenceRetrieval: retrieval,
            modelProvider: { _ in model }
        )
        let collector = DeltaCollector()
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "Hi",
                preferredTier: .lite,
                hasImage: true,
                imageData: Data([1, 2, 3]),
                conversationHistory: [
                    ConversationTurn(role: .user, text: "My car will not start")
                ]
            ),
            device: Self.capableDevice,
            tokenSink: { collector.append($0) }
        )

        let callCount = await model.callCount
        let purposes = await model.purposes()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(purposes, [.expertIntent, .ordinary])
        let prompts = await model.prompts()
        XCTAssertTrue(prompts.allSatisfy { $0.tier == .lite })
        XCTAssertTrue(prompts.allSatisfy { $0.conversationHistory.isEmpty })
        XCTAssertTrue(prompts.allSatisfy { $0.imageData == nil })
        XCTAssertEqual(retrieval.searchCount, 0)
        XCTAssertEqual(answer?.text, collector.text)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        XCTAssertTrue(answer?.notices.contains {
            $0.contains("Lite is text-only")
        } == true)
    }

    func testLitePromptsUseCompactEnvelopeAndConservativeIntentExamples() {
        let builder = GroundedPromptBuilder()
        let intent = builder.systemPrompt(
            for: .lite,
            purpose: .expertIntent,
            outputMode: .groundedJSON
        )
        XCTAssertTrue(intent.contains("How do I get a girlfriend?"))
        XCTAssertTrue(intent.contains("When uncertain, choose general"))
        XCTAssertTrue(intent.contains(#"{"t":"general","q":""}"#))
        XCTAssertFalse(intent.contains(#""l""#))

        let grounded = builder.systemPrompt(
            for: .lite,
            purpose: .grounded,
            outputMode: .groundedJSON,
            usesReviewedClaims: true
        )
        XCTAssertTrue(grounded.contains(#"{"a":"best-effort answer","e":[1]}"#))
        XCTAssertFalse(grounded.contains(#"{"s""#))

        let ordinary = builder.systemPrompt(
            for: .lite,
            purpose: .ordinary,
            outputMode: .groundedJSON
        )
        XCTAssertTrue(ordinary.contains("no more than"))
        XCTAssertTrue(ordinary.contains("75 words"))
    }

    func testLiteSharedPackFailureDisablesAllGrounding() async {
        let model = OneShotExpertModel(
            tier: .lite,
            intent: .survivalQuestion,
            output: #"{"a":"Use cautious best-effort steps and stop if conditions worsen.","e":[]}"#
        )
        let retrieval = ExpertRetrievalSpy()
        let assistant = IncidentAssistant(
            articles: [],
            installedTiers: [.lite],
            expertEvidenceRetrieval: retrieval,
            modelProvider: { _ in model }
        )
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "How do I repair an unfamiliar survival-device model?",
                preferredTier: .lite
            ),
            device: Self.capableDevice
        )

        let callCount = await model.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(retrieval.searchCount, 0)
        XCTAssertEqual(answer?.expertIntent, .survivalQuestion)
        XCTAssertEqual(answer?.expertRetrievalStatus, .noRelevantEvidence)
        XCTAssertTrue(answer?.sourceCards.isEmpty == true)
        XCTAssertTrue(answer?.notices.contains {
            $0.contains("Shared semantic retrieval is unavailable")
        } == true)
    }

    private func makeAssistant(
        model: any LocalLanguageModel,
        retrieval: ExpertRetrievalSpy
    ) -> IncidentAssistant {
        IncidentAssistant(
            articles: [],
            installedTiers: [.expert],
            expertEvidenceRetrieval: retrieval,
            expertValidated: true,
            expertContextAssembler: ExpertContextAssembler(
                memoryProfile: ExpertRuntimeMemoryProfile(
                    measuredPeakBytes: [.full: 1]
                )
            ),
            modelProvider: { _ in model }
        )
    }

    private static let capableDevice = DeviceSnapshot(
        physicalMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
        availableMemoryBytes: 4 * 1_024 * 1_024 * 1_024,
        freeStorageBytes: 20_000_000_000,
        thermalCondition: .nominal,
        isLowPowerMode: false
    )
}

private actor FailingVisionModel: LocalLanguageModel {
    nonisolated let tier: ModelTier = .expert
    nonisolated let outputMode: ModelOutputMode = .groundedJSON
    private(set) var callCount = 0

    func generate(prompt: ModelPrompt) async throws -> String {
        callCount += 1
        throw ModelFailure.unavailable
    }
}

private actor OneShotExpertModel: LocalLanguageModel {
    nonisolated let tier: ModelTier
    nonisolated let outputMode: ModelOutputMode = .groundedJSON
    private let output: String
    private let rawIntent: String
    private(set) var callCount = 0
    private var recordedPurposes: [ModelPromptPurpose] = []
    private var recordedPrompts: [ModelPrompt] = []

    init(
        tier: ModelTier = .expert,
        intent: ExpertTurnIntent,
        output: String
    ) {
        self.tier = tier
        rawIntent = intent == .survivalQuestion
            ? #"{"t":"survival","q":"survival guidance"}"#
            : #"{"t":"general","q":""}"#
        self.output = output
    }

    init(
        tier: ModelTier = .expert,
        rawIntent: String,
        output: String
    ) {
        self.tier = tier
        self.rawIntent = rawIntent
        self.output = output
    }

    func generate(prompt: ModelPrompt) async throws -> String {
        callCount += 1
        recordedPurposes.append(prompt.purpose)
        recordedPrompts.append(prompt)
        if prompt.purpose == .expertIntent {
            return rawIntent
        }
        return output
    }

    func purposes() -> [ModelPromptPurpose] { recordedPurposes }
    func prompts() -> [ModelPrompt] { recordedPrompts }
}

private final class ExpertRetrievalSpy: ExpertEvidenceRetrieving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var searchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func searchExpertEvidence(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedEvidenceScenario] {
        lock.lock()
        count += 1
        lock.unlock()
        return []
    }

    func expertScenario(id: String) -> EvidenceScenarioRecord? { nil }
    func expertSources(ids: [String]) -> [SurvivalSource] { [] }
}

private final class DeltaCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ delta: String) {
        lock.lock()
        value += delta
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
