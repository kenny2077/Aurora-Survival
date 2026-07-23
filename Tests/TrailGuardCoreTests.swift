import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class TrailGuardCoreTests: XCTestCase {
    func testFuelLeakBypassesModel() async {
        let assistant = makeAssistant()
        let result = await assistant.answer(
            request: ChatRequest(question: "I smell gasoline after the crash"),
            device: capableDevice
        )

        XCTAssertTrue(result.usedDeterministicOverride)
        XCTAssertEqual(result.severity, .critical)
        XCTAssertNil(result.modelTier)
        XCTAssertTrue(result.text.contains("Do not restart"))
    }

    func testSevereBleedingBypassesModel() async {
        let assistant = makeAssistant()
        let result = await assistant.answer(
            request: ChatRequest(question: "The bleeding won't stop"),
            device: capableDevice
        )

        XCTAssertTrue(result.usedDeterministicOverride)
        XCTAssertTrue(result.text.contains("direct pressure"))
    }

    func testRetrievalRanksKeywordMatch() {
        let retrieval = RetrievalEngine(articles: sampleArticles)
        let results = retrieval.search(query: "radiator coolant overheating")
        XCTAssertEqual(results.first?.article.id, "overheat")
    }

    func testDomainFilterExcludesVehicleArticle() {
        let retrieval = RetrievalEngine(articles: sampleArticles)
        let results = retrieval.search(query: "water", domain: .wilderness)
        XCTAssertTrue(results.allSatisfy { $0.article.domain == .wilderness })
    }

    func testUnreviewedArticleIsNeverRetrieved() {
        let unsafe = article(
            id: "unsafe",
            domain: .vehicle,
            title: "Overheat shortcut",
            keywords: ["radiator", "coolant"],
            reviewed: false
        )
        let retrieval = RetrievalEngine(articles: sampleArticles + [unsafe])
        XCTAssertFalse(retrieval.search(query: "radiator").contains { $0.article.id == "unsafe" })
    }

    func testVisionRoutesOnCapableDevice() {
        let decision = ModelRouter().route(
            requested: .visionExpert,
            installed: [.essential, .visionExpert],
            device: capableDevice
        )
        XCTAssertEqual(decision.selected, .visionExpert)
        XCTAssertTrue(decision.canAnalyzeImage)
    }

    func testVisionFallsBackDuringThermalPressure() {
        let hot = DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .serious,
            isLowPowerMode: false
        )
        let decision = ModelRouter().route(
            requested: .visionExpert,
            installed: [.essential, .field, .visionExpert],
            device: hot
        )
        XCTAssertEqual(decision.selected, .field)
        XCTAssertFalse(decision.canAnalyzeImage)
        XCTAssertTrue(decision.explanation.contains("thermal"))
    }

    func testVisionFallsBackInLowPowerMode() {
        let lowPower = DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: true
        )
        let decision = ModelRouter().route(
            requested: .visionExpert,
            installed: [.essential, .visionExpert],
            device: lowPower
        )
        XCTAssertEqual(decision.selected, .essential)
        XCTAssertFalse(decision.canAnalyzeImage)
    }

    func testMissingTierFallsBack() {
        let decision = ModelRouter().route(
            requested: .visionExpert,
            installed: [.essential],
            device: capableDevice
        )
        XCTAssertEqual(decision.selected, .essential)
        XCTAssertFalse(decision.canAnalyzeImage)
    }

    func testCitationPolicyRejectsUncitedAnswer() {
        XCTAssertNil(CitationPolicy().validatedText("Turn the cap.", evidenceCount: 1))
    }

    func testCitationPolicyRejectsOutOfRangeCitation() {
        XCTAssertNil(CitationPolicy().validatedText("Do this [2].", evidenceCount: 1))
    }

    func testCitationPolicyAcceptsValidCitation() {
        XCTAssertEqual(
            CitationPolicy().validatedText("Stop and cool the engine [1].", evidenceCount: 1),
            "Stop and cool the engine [1]."
        )
    }

    func testUncitedModelOutputFallsBackToExtractiveAnswer() async {
        let assistant = IncidentAssistant(
            articles: sampleArticles,
            installedTiers: [.essential, .field],
            modelProvider: { tier in
                ClosureBackedLanguageModel(tier: tier) { _, _ in
                    "Invented advice without a citation."
                }
            }
        )
        let result = await assistant.answer(
            request: ChatRequest(question: "engine is overheating", preferredTier: .field),
            device: capableDevice
        )

        XCTAssertTrue(result.text.contains("[1]"))
        XCTAssertTrue(result.notices.contains { $0.contains("citation validation") })
    }

    func testModelFailureFallsBackToReviewedEvidence() async {
        let assistant = IncidentAssistant(
            articles: sampleArticles,
            installedTiers: [.essential],
            modelProvider: { tier in
                ClosureBackedLanguageModel(tier: tier) { _, _ in
                    throw ModelFailure.unavailable
                }
            }
        )
        let result = await assistant.answer(
            request: ChatRequest(question: "how do I treat stream water?"),
            device: capableDevice
        )

        XCTAssertTrue(result.text.contains("Water treatment"))
        XCTAssertEqual(result.modelTier, .essential)
    }

    func testKnowledgeJSONRoundTrip() throws {
        let encoded = try JSONEncoder().encode(sampleArticles)
        let decoded = try KnowledgeStore.decode(data: encoded)
        XCTAssertEqual(decoded.articles, sampleArticles)
    }

    private var capableDevice: DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }

    private func makeAssistant() -> IncidentAssistant {
        IncidentAssistant(articles: sampleArticles)
    }

    private var sampleArticles: [KnowledgeArticle] {
        [
            article(
                id: "overheat",
                domain: .vehicle,
                title: "Engine overheating",
                keywords: ["radiator", "coolant", "overheating"]
            ),
            article(
                id: "water",
                domain: .wilderness,
                title: "Water treatment",
                keywords: ["water", "boil", "filter"]
            )
        ]
    }

    private func article(
        id: String,
        domain: KnowledgeDomain,
        title: String,
        keywords: [String],
        reviewed: Bool = true
    ) -> KnowledgeArticle {
        KnowledgeArticle(
            id: id,
            domain: domain,
            title: title,
            summary: "Reviewed summary for \(title).",
            steps: ["First safe step.", "Second safe step."],
            warnings: ["Stop when conditions are unsafe."],
            keywords: keywords,
            source: SourceReference(
                id: "source-\(id)",
                title: "Source \(id)",
                organization: "Test organization",
                revision: "2026-07"
            ),
            reviewed: reviewed
        )
    }
}
