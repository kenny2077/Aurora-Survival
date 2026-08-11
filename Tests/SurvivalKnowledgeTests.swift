import CryptoKit
import Foundation
import XCTest
#if canImport(SQLite3)
import SQLite3
#endif

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class SurvivalKnowledgeTests: XCTestCase {
    func testBundledKnowledgeHasApprovedStructure() throws {
        let store = try store()
        let integrity = try store.integrity()

        XCTAssertEqual(integrity.schemaVersion, 1)
        XCTAssertEqual(integrity.chapterCount, 10)
        XCTAssertEqual(integrity.lessonCount, 70)
        XCTAssertEqual(integrity.passageCount, 1_050)
        XCTAssertEqual(integrity.indexedPassageCount, 1_050)
        XCTAssertEqual(integrity.legacyAnchorCount, 828)
        XCTAssertGreaterThanOrEqual(integrity.sourceCount, 10)

        XCTAssertEqual(
            store.chapters().map(\.title),
            [
                "Survival Basics", "Find and Treat Water", "Start a Fire",
                "Build a Shelter", "Find Food Safely", "Navigate When Lost",
                "Signal for Rescue", "Wilderness First Aid",
                "Weather and Wildlife", "Car Breakdown",
            ]
        )
    }

    func testEveryLessonIsAConciseActionCard() throws {
        let store = try store()
        let lessons = store.chapters().flatMap { store.lessons(chapterID: $0.id) }

        XCTAssertEqual(lessons.count, 70)
        XCTAssertTrue(lessons.allSatisfy { (3...6).contains($0.actions.count) })
        XCTAssertTrue(lessons.allSatisfy { (1...3).contains($0.warnings.count) })
        XCTAssertTrue(lessons.allSatisfy { !$0.goal.isEmpty && !$0.sources.isEmpty })
        XCTAssertNil(lessons.first { $0.searchableText.localizedCaseInsensitiveContains("identify this mushroom") })
        XCTAssertNil(lessons.first { $0.searchableText.localizedCaseInsensitiveContains("repair the traction battery") })
    }

    func testWeightedSearchReturnsAnswerReadyWaterPassage() throws {
        let results = try store().searchPassages(
            "How do I purify watre by boiling?",
            domain: .wilderness,
            limit: 2
        )

        XCTAssertEqual(results.first?.lessonID, "water-boil")
        XCTAssertLessThanOrEqual(results.first?.answerText.split(whereSeparator: \.isWhitespace).count ?? 999, 120)
        XCTAssertTrue(results.first?.referenceText.localizedCaseInsensitiveContains("boil") == true)
    }

    func testDatabaseSearchNormalizesTireAndBleedingVariants() throws {
        let store = try store()
        let cases = [
            ("flat tire", "car-tire"),
            ("tyre puncture", "car-tire"),
            ("How to stop the bleed", "first-aid-bleeding"),
            ("blood loss hemorrhage", "first-aid-bleeding"),
        ]
        for (query, expectedLessonID) in cases {
            let results = store.searchPassages(query, domain: nil, limit: 2)
            XCTAssertTrue(
                results.contains { $0.lessonID == expectedLessonID },
                "Expected \(query) to match \(expectedLessonID), got \(results.map(\.lessonID))"
            )
        }
    }

    func testPlainLanguageWaterQuestionDoesNotDriftToUnrelatedSafetyAdvice() throws {
        let results = try store().searchPassages(
            "How do I make water safer?",
            domain: .wilderness,
            limit: 2
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.chapterID == "water" })
    }

    func testManualAndRetrieverShareExactPassageAnchor() throws {
        let store = try store()
        let evidence = SurvivalKnowledgeRetriever(store: store).search(
            query: "rolling boil water",
            limit: 2
        )
        let reference = try XCTUnwrap(evidence.first?.article.manualReference)

        guard case .available(let passage) = store.resolve(reference) else {
            return XCTFail("Expected an exact passage")
        }
        XCTAssertEqual(passage.id, reference.passageID)
        XCTAssertEqual(passage.lessonID, "water-boil")
    }

    func testRetrieverExposesFullReviewedLessonBriefing() throws {
        let store = try store()
        let evidence = SurvivalKnowledgeRetriever(store: store).search(
            query: "Where can I find water?",
            limit: 2
        )
        let article = try XCTUnwrap(evidence.first?.article)
        let lessonID = try XCTUnwrap(article.manualReference?.lessonID)
        let lesson = try XCTUnwrap(store.lesson(id: lessonID))

        XCTAssertEqual(article.summary, lesson.goal)
        XCTAssertEqual(article.steps, Array(lesson.actions.prefix(3)))
        XCTAssertEqual(article.warnings, Array(lesson.warnings.prefix(1)))
        XCTAssertTrue(Set(lesson.aliases).isSubset(of: Set(article.keywords)))
        XCTAssertTrue(Set(lesson.keywords).isSubset(of: Set(article.keywords)))
    }

    func testLegacyWaterAnchorRedirectsAndUnrelatedStoryRetires() throws {
        let store = try store()
        let water = ManualReference(
            chunkID: "meateater-2020-water-0112",
            chapterNumber: 2,
            chapterTitle: "Water",
            sectionTitle: "Water Purifiers",
            pageStart: 74,
            pageEnd: 74
        )
        guard case .available(let replacement) = store.resolve(water) else {
            return XCTFail("Expected legacy water redirect")
        }
        XCTAssertEqual(replacement.lessonID, "water-boil")

        let story = ManualReference(
            chunkID: "meateater-2020-the-surprising-dangers-of-s-mores-0001",
            chapterNumber: 0,
            chapterTitle: "The Surprising Dangers of S’mores",
            sectionTitle: "Introduction",
            pageStart: 13,
            pageEnd: 13
        )
        guard case .retired(let replacement, _) = store.resolve(story) else {
            return XCTFail("Expected unrelated story to be retired")
        }
        XCTAssertEqual(replacement.lessonID, "basics-stop")
    }

    func testGeneratedFallbackHasOneCardPerChapter() throws {
        let fallback = try SurvivalFallbackLoader.load(url: resourceURL("survival_fallback", "json"))

        XCTAssertEqual(fallback.schemaVersion, 1)
        XCTAssertEqual(fallback.chapters.count, 10)
        XCTAssertEqual(fallback.cards.count, 10)
        XCTAssertTrue(fallback.cards.allSatisfy { (3...6).contains($0.actions.count) })
    }

    func testRecordedChecksumMatchesDatabase() throws {
        let database = resourceURL("survival_knowledge", "sqlite")
        let expected = try String(
            contentsOf: resourceURL("survival_knowledge", "sha256"),
            encoding: .utf8
        ).split(whereSeparator: \.isWhitespace).first.map(String.init)
        let actual = SHA256.hash(data: try Data(contentsOf: database))
            .map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(actual, expected)
    }

    func testChecksumFailureRejectsDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrailGuardChecksum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = directory.appendingPathComponent("survival_knowledge.sqlite")
        try FileManager.default.copyItem(
            at: resourceURL("survival_knowledge", "sqlite"),
            to: database
        )
        try "not-the-database-checksum\n".write(
            to: directory.appendingPathComponent("survival_knowledge.sha256"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try SurvivalKnowledgeStore(databaseURL: database)) { error in
            XCTAssertEqual(error as? SurvivalKnowledgeError, .invalidChecksum(database.path))
        }
    }

    #if canImport(SQLite3)
    func testSchemaMismatchRejectsDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrailGuardSchema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = directory.appendingPathComponent("survival_knowledge.sqlite")
        try FileManager.default.copyItem(
            at: resourceURL("survival_knowledge", "sqlite"),
            to: database
        )
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(
            sqlite3_exec(
                connection,
                "UPDATE metadata SET value = '2' WHERE key = 'schema_version'",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )

        XCTAssertThrowsError(try SurvivalKnowledgeStore(databaseURL: database)) { error in
            XCTAssertEqual(error as? SurvivalKnowledgeError, .unsupportedSchema(2))
        }
    }
    #endif

    func testBalancedRetrievalBenchmarkMeetsRecallGates() throws {
        let cases: [RetrievalCase] = try fixture(named: "survival_retrieval_benchmark")
        let store = try store()
        var correct = 0
        var criticalCorrect = 0
        let critical = cases.filter(\.critical).count

        for item in cases {
            let results = store.searchPassages(item.query, domain: nil, limit: 2)
            let matched = results.contains { $0.lessonID == item.expectedLessonID }
            if matched { correct += 1 }
            if item.critical && matched { criticalCorrect += 1 }
        }

        XCTAssertEqual(cases.count, 200)
        XCTAssertGreaterThanOrEqual(Double(correct) / Double(cases.count), 0.90)
        XCTAssertGreaterThanOrEqual(Double(criticalCorrect) / Double(critical), 0.95)
    }

    func testLocalSearchStaysWithinBudget() throws {
        let store = try store()
        _ = store.searchPassages("water purifier boiling", domain: nil, limit: 40)
        let iterations = 20
        let started = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = store.searchPassages("water purifier boiling", domain: nil, limit: 40)
        }
        let average = (CFAbsoluteTimeGetCurrent() - started) / Double(iterations)
        XCTAssertLessThan(average, 0.3)
    }

    private func store() throws -> SurvivalKnowledgeStore {
        try SurvivalKnowledgeStore(databaseURL: resourceURL("survival_knowledge", "sqlite"))
    }

    private func resourceURL(_ name: String, _ extensionName: String) -> URL {
        #if !SWIFT_PACKAGE
        if let bundled = Bundle.main.url(forResource: name, withExtension: extensionName) {
            return bundled
        }
        #endif
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("Knowledge")
            .appendingPathComponent("\(name).\(extensionName)")
    }

    private func fixture<T: Decodable>(named name: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: SurvivalKnowledgeTests.self)
        #endif
        let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: name, withExtension: "json")
        return try JSONDecoder().decode(
            T.self,
            from: Data(contentsOf: try XCTUnwrap(url))
        )
    }
}

private struct RetrievalCase: Codable {
    let query: String
    let expectedChapterID: String
    let expectedLessonID: String
    let critical: Bool
}
