import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class FieldGuideTests: XCTestCase {
    func testBundledGuideIntegrityAndRepresentativeSearches() throws {
        let store = try FieldGuideStore.load(url: resourceURL())

        XCTAssertEqual(store.book.chapters.count, 6)
        XCTAssertEqual(store.book.chapters.flatMap(\.skills).count, 35)
        XCTAssertEqual(store.book.visuals.count, 19)
        XCTAssertEqual(store.book.chapters.map(\.order), Array(1...6))
        XCTAssertTrue(store.book.visuals.allSatisfy { !$0.altText.isEmpty })

        XCTAssertEqual(store.search("wet fire").first?.skill.id, "fire.wet_conditions")
        XCTAssertEqual(store.search("broken bone splint").first?.skill.id, "first_aid.fracture")
        XCTAssertEqual(store.search("north at night").first?.skill.id, "navigation.polaris")
    }

    func testSourceDisplayNamesArePlainDeduplicatedTitles() {
        let source = SourceReference(
            id: "army",
            title: "Survival Manual 2026",
            organization: "Army",
            revision: "2026"
        )
        let card = AnswerSourceCard(
            id: "army-card",
            title: "Survival Manual 2026",
            url: "https://example.invalid",
            locator: "Chapter 1",
            publishedAt: "2026-01-01",
            updatedAt: "2026-01-01",
            reviewedAt: "2026-01-01",
            jurisdiction: "global",
            reviewStatus: "reviewed"
        )
        let reference = ManualReference(
            passageID: "p1",
            lessonID: "l1",
            chapterID: "fire",
            chapterNumber: 1,
            chapterTitle: "Fire",
            sectionTitle: "Basic Fire",
            sourceLabel: "Reviewed"
        )
        let answer = AssistantAnswer(
            text: "Test",
            severity: .informational,
            sources: [source],
            manualReferences: [reference],
            modelTier: .lite,
            visionWasUsed: false,
            notices: [],
            sourceCards: [card]
        )

        XCTAssertEqual(answer.sourceDisplayNames, ["Survival Manual 2026"])
    }

    func testModelTierCannotActivateWithoutLoadedSharedRAG() {
        let snapshot = ActivePackSnapshot(
            models: [],
            knowledge: [],
            maps: [],
            installedTiers: [.lite, .expert],
            issues: []
        )

        let result = IncidentRuntimeBootstrap(bundledArticles: []).resolve(
            activePacks: snapshot,
            availableModelTiers: [.lite, .expert]
        )

        XCTAssertTrue(result.runtimeTiers.isEmpty)
        XCTAssertFalse(result.usesCompiledKnowledge)
    }

    private func resourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Manual/field_guide.json")
    }
}
