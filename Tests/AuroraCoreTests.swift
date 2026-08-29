import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class AuroraCoreTests: XCTestCase {
    func testRetrievalRanksKeywordMatch() {
        let retrieval = RetrievalEngine(articles: sampleArticles)
        XCTAssertEqual(
            retrieval.search(query: "radiator coolant overheating").first?.article.id,
            "overheat"
        )
    }

    func testDomainFilterKeepsGeneralVehicleKnowledge() {
        let retrieval = RetrievalEngine(articles: sampleArticles)
        let results = retrieval.search(query: "coolant", domain: .vehicle)
        XCTAssertTrue(results.allSatisfy { $0.article.domain == .vehicle })
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

    func testOnlyLiteAndExpertAreCustomerModelTiers() {
        XCTAssertEqual(ModelTier.allCases, [.lite, .expert])
        XCTAssertEqual(ModelTier.expert.rawValue, "vision_expert")
        XCTAssertTrue(ModelTier.expert.supportsVision)
        XCTAssertFalse(ModelTier.lite.supportsVision)
    }

    func testExplicitLiteSelectsLiteOnIPhone13ClassDevice() {
        let decision = ModelRouter().route(
            preference: .lite,
            installed: [.lite],
            device: iPhone13ClassDevice
        )
        XCTAssertEqual(decision.selected, .lite)
        XCTAssertEqual(decision.availability, .ready)
        XCTAssertFalse(decision.canAnalyzeImage)
    }

    func testExpertStaysValidationLockedWithoutFallback() {
        let decision = ModelRouter().route(
            preference: .expert,
            installed: [.lite, .expert],
            expertValidated: false,
            device: capableDevice
        )
        XCTAssertNil(decision.selected)
        XCTAssertEqual(decision.availability, .validationLocked)
        XCTAssertFalse(decision.canAnalyzeImage)
    }

    func testValidatedExpertRoutesOnCapableDevice() {
        let decision = ModelRouter().route(
            preference: .expert,
            installed: [.lite, .expert],
            expertValidated: true,
            device: capableDevice
        )
        XCTAssertEqual(decision.selected, .expert)
        XCTAssertEqual(decision.availability, .ready)
        XCTAssertTrue(decision.canAnalyzeImage)
    }

    func testExpertDoesNotFallBackUnderThermalPressure() {
        let hot = DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .serious,
            isLowPowerMode: false
        )
        let decision = ModelRouter().route(
            preference: .expert,
            installed: [.lite, .expert],
            expertValidated: true,
            device: hot
        )
        XCTAssertNil(decision.selected)
        XCTAssertEqual(decision.availability, .temporarilyIneligible)
    }

    func testNoInstalledModelReturnsUnavailableDecision() {
        let decision = ModelRouter().route(
            preference: .lite,
            installed: [],
            device: capableDevice
        )
        XCTAssertNil(decision.selected)
        XCTAssertEqual(decision.availability, .missing)
    }

    func testAssistantReturnsNilWithoutModel() async {
        let assistant = IncidentAssistant(articles: sampleArticles)
        let result = await assistant.answer(
            request: ChatRequest(question: "How do I treat stream water?"),
            device: capableDevice
        )
        XCTAssertNil(result)
    }

    func testModelFailureDoesNotExposeExtractiveFallback() async {
        let assistant = IncidentAssistant(
            articles: sampleArticles,
            installedTiers: [.lite],
            modelProvider: { tier in
                ClosureBackedLanguageModel(tier: tier) { _, _ in
                    throw ModelFailure.unavailable
                }
            }
        )
        let result = await assistant.answer(
            request: ChatRequest(question: "How do I treat stream water?"),
            device: capableDevice
        )
        XCTAssertEqual(
            result?.text,
            "Lite couldn’t run right now. Try again in a moment."
        )
        XCTAssertTrue(result?.manualReferences.isEmpty == true)
    }

    func testKnowledgeJSONRoundTrip() throws {
        let encoded = try JSONEncoder().encode(sampleArticles)
        XCTAssertEqual(try KnowledgeStore.decode(data: encoded).articles, sampleArticles)
    }

    private var iPhone13ClassDevice: DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 4_000_000_000,
            freeStorageBytes: 10_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }

    private var capableDevice: DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
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
            ),
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
            summary: "Reviewed survival information for \(title.lowercased()).",
            steps: ["Stop and assess."],
            warnings: [],
            keywords: keywords,
            source: SourceReference(
                id: "source.\(id)",
                title: title,
                organization: "Aurora",
                revision: "2026"
            ),
            reviewed: reviewed
        )
    }
}
