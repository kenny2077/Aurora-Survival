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

    func testVehicleSpecificArticleRequiresProfile() {
        let specific = vehicleArticle(make: "Toyota", model: "4Runner", yearFrom: 2020, yearThrough: 2024)
        let retrieval = RetrievalEngine(articles: [specific])

        XCTAssertTrue(retrieval.search(query: "jack point").isEmpty)
    }

    func testWrongVehicleArticleIsExcluded() {
        let specific = vehicleArticle(make: "Toyota", model: "4Runner", yearFrom: 2020, yearThrough: 2024)
        let retrieval = RetrievalEngine(articles: [specific])
        let wrongVehicle = VehicleProfile(
            make: "Ford",
            model: "Bronco",
            modelYear: 2023,
            market: "US",
            powertrain: .gasoline,
            documentID: "toyota-4runner-2023-us"
        )

        XCTAssertTrue(
            retrieval.search(
                query: "jack point",
                domain: .vehicle,
                vehicle: wrongVehicle
            ).isEmpty
        )
    }

    func testExactVehicleAndDocumentCanRetrieveArticle() {
        let specific = vehicleArticle(make: "Toyota", model: "4Runner", yearFrom: 2020, yearThrough: 2024)
        let retrieval = RetrievalEngine(articles: [specific])
        let correctVehicle = VehicleProfile(
            make: "toyota",
            model: "4runner",
            modelYear: 2023,
            market: "us",
            powertrain: .gasoline,
            documentID: "TOYOTA-4RUNNER-2023-US"
        )

        XCTAssertEqual(
            retrieval.search(
                query: "jack point",
                domain: .vehicle,
                vehicle: correctVehicle
            ).first?.article.id,
            "vehicle-specific"
        )
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

    private func vehicleArticle(
        make: String,
        model: String,
        yearFrom: Int,
        yearThrough: Int
    ) -> KnowledgeArticle {
        KnowledgeArticle(
            id: "vehicle-specific",
            domain: .vehicle,
            title: "Exact jack point",
            summary: "Vehicle-specific jacking procedure.",
            steps: ["Use only the documented point."],
            warnings: ["Do not use this procedure for another vehicle."],
            keywords: ["jack", "point"],
            source: SourceReference(
                id: "toyota-4runner-2023-us",
                title: "2023 4Runner owner manual",
                organization: "Vehicle manufacturer",
                revision: "2023"
            ),
            reviewed: true,
            vehicleApplicability: VehicleApplicability(
                makes: [make],
                models: [model],
                yearFrom: yearFrom,
                yearThrough: yearThrough,
                markets: ["US"],
                powertrains: [.gasoline],
                documentIDs: ["toyota-4runner-2023-us"]
            )
        )
    }
}
