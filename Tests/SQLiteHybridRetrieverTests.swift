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

#if canImport(SQLite3)
final class SQLiteHybridRetrieverTests: XCTestCase {
    func testLexicalFallbackUsesStableOrderAndAllowedLevels() throws {
        let fixture = try makeFixture(
            records: [
                Record(id: "b", title: "Water safety", level: "limited"),
                Record(id: "a", title: "Water safety", level: "supported"),
                Record(id: "excluded", title: "Water safety", level: "insufficient"),
            ]
        )
        defer { fixture.remove() }

        let results = try retriever(fixture).search(query: "water")

        XCTAssertEqual(results.map(\.article.id), ["a", "b"])
    }

    func testDenseRankingSkipsOutOfBoundsVector() throws {
        let fixture = try makeFixture(
            records: [
                Record(id: "orthogonal", embedding: [0, 1, 0, 0]),
                Record(id: "nearest", embedding: [1, 0, 0, 0]),
                Record(
                    id: "invalid-offset",
                    embedding: [1, 0, 0, 0],
                    vectorOffset: 10_000
                ),
            ]
        )
        defer { fixture.remove() }
        let retriever = try SQLiteHybridRetriever(
            activeKnowledgePackages: [fixture.package],
            embeddingProvider: FixedEmbedding(values: [1, 0, 0, 0])
        )

        let results = retriever.search(query: "zephyr")

        XCTAssertEqual(results.map(\.article.id), ["nearest", "orthogonal"])
    }

    func testRequiredJurisdictionRejectsUnscopedRecord() throws {
        let fixture = try makeFixture(
            records: [
                Record(
                    id: "unscoped",
                    title: "Water safety",
                    applicabilityJSON: #"{"environment":"test"}"#
                )
            ]
        )
        defer { fixture.remove() }

        XCTAssertTrue(
            try retriever(fixture, jurisdiction: "US")
                .search(query: "water")
                .isEmpty
        )
    }

    func testRuntimeBootstrapKeepsBundledEvidenceAndDisablesMissingModelRuntime() async throws {
        let fixture = try makeFixture(
            records: [Record(id: "compiled-water", title: "Compiled water evidence")]
        )
        defer { fixture.remove() }
        let bundled = article(id: "bundled-signal", title: "Emergency signal")
        let snapshot = ActivePackSnapshot(
            models: [],
            knowledge: [fixture.package],
            maps: [],
            installedTiers: [.lite],
            issues: []
        )

        let resolution = IncidentRuntimeBootstrap(
            bundledArticles: [bundled]
        ).resolve(activePacks: snapshot)
        let waterIDs = await resolution.assistant.search("water").map(\.id)
        let signalIDs = await resolution.assistant.search("signal").map(\.id)

        XCTAssertTrue(resolution.usesCompiledKnowledge)
        XCTAssertEqual(resolution.runtimeTiers, [])
        XCTAssertEqual(waterIDs, ["compiled-water"])
        XCTAssertEqual(signalIDs, ["bundled-signal"])
    }

    func testRuntimeBootstrapPrefersBundledEmergencyRevisionForDuplicateID() async throws {
        let fixture = try makeFixture(
            records: [Record(id: "shared-water", title: "Older installed revision")]
        )
        defer { fixture.remove() }
        let bundled = article(
            id: "shared-water",
            title: "Current bundled water emergency revision"
        )
        let snapshot = ActivePackSnapshot(
            models: [],
            knowledge: [fixture.package],
            maps: [],
            installedTiers: [],
            issues: []
        )

        let resolution = IncidentRuntimeBootstrap(
            bundledArticles: [bundled]
        ).resolve(activePacks: snapshot)
        let result = await resolution.assistant.search("water").first

        XCTAssertEqual(result?.id, bundled.id)
        XCTAssertEqual(result?.title, bundled.title)
    }

    func testRankFusionDeduplicatesAndPrefersFirstSourceContent() {
        let active = article(id: "shared", title: "Active pack revision")
        let bundled = article(id: "shared", title: "Bundled revision")
        let retriever = RankFusingRetriever(
            sources: [
                StaticRetriever(articles: [active]),
                StaticRetriever(articles: [bundled]),
            ]
        )

        let results = retriever.search(query: "revision")

        XCTAssertEqual(results.map(\.article.id), ["shared"])
        XCTAssertEqual(results.first?.article.title, "Active pack revision")
    }
}

private extension SQLiteHybridRetrieverTests {
    struct Record {
        let id: String
        let title: String
        let level: String
        let embedding: [Float]
        let applicabilityJSON: String
        let vectorOffset: Int?

        init(
            id: String,
            title: String = "Reviewed evidence",
            level: String = "supported",
            embedding: [Float] = [1, 0, 0, 0],
            applicabilityJSON: String = #"{"jurisdiction":"US"}"#,
            vectorOffset: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.level = level
            self.embedding = embedding
            self.applicabilityJSON = applicabilityJSON
            self.vectorOffset = vectorOffset
        }
    }

    struct Fixture {
        let root: URL
        let package: ResolvedActivePackage

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func retriever(
        _ fixture: Fixture,
        jurisdiction: String? = nil
    ) throws -> SQLiteHybridRetriever {
        try SQLiteHybridRetriever(
            activeKnowledgePackages: [fixture.package],
            filter: SQLiteHybridRetrievalFilter(
                locale: "en-US",
                jurisdiction: jurisdiction
            )
        )
    }

    func makeFixture(
        domain: KnowledgeDomain = .wilderness,
        records: [Record]
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardSQLiteRetriever-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let databaseURL = root.appendingPathComponent("content.sqlite")
        let vectorsURL = root.appendingPathComponent("vectors.bin")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK,
              let database
        else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }

        try execute(
            database,
            """
            CREATE TABLE pack_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE evidence (
                evidence_id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                steps_json TEXT NOT NULL,
                warnings_json TEXT NOT NULL,
                keywords_json TEXT NOT NULL,
                source_json TEXT NOT NULL,
                applicability_json TEXT NOT NULL,
                supported_answer_level TEXT NOT NULL,
                vector_offset INTEGER NOT NULL,
                vector_dimensions INTEGER NOT NULL
            );
            CREATE VIRTUAL TABLE evidence_fts USING fts5(
                evidence_id UNINDEXED,
                title,
                summary,
                steps,
                warnings,
                keywords
            );
            """
        )
        try insert(
            database,
            sql: "INSERT INTO pack_metadata VALUES (?, ?)",
            rows: [
                ["domain", domain.rawValue],
                ["expires_at", ""],
                ["locale", "en-US"],
            ]
        )

        var vectors = Data()
        for record in records.sorted(by: { $0.id < $1.id }) {
            let offset = record.vectorOffset ?? vectors.count
            let source = """
            {"source_id":"source.\(record.id)","title":"Test source","owner":"TrailGuard","revision":"1.0"}
            """
            try insert(
                database,
                sql: "INSERT INTO evidence VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                rows: [[
                    record.id,
                    record.title,
                    "Reviewed summary",
                    #"["Reviewed step"]"#,
                    #"["Reviewed warning"]"#,
                    #"["water","jack","point"]"#,
                    source,
                    record.applicabilityJSON,
                    record.level,
                    String(offset),
                    String(record.embedding.count),
                ]]
            )
            try insert(
                database,
                sql: "INSERT INTO evidence_fts VALUES (?, ?, ?, ?, ?, ?)",
                rows: [[
                    record.id,
                    record.title,
                    "Reviewed summary",
                    "Reviewed step",
                    "Reviewed warning",
                    "water jack point",
                ]]
            )
            for value in record.embedding {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) {
                    vectors.append(contentsOf: $0)
                }
            }
        }
        try vectors.write(to: vectorsURL)

        let manifest = PackageManifest(
            packageID: "knowledge.test",
            version: "1.0.0",
            kind: .knowledge,
            createdAt: "2026-07-28T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "Test-Only",
            displayName: "Retriever fixture",
            artifacts: []
        )
        return Fixture(
            root: root,
            package: ResolvedActivePackage(
                manifest: manifest,
                directory: root
            )
        )
    }

    func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
    }

    func insert(
        _ database: OpaquePointer,
        sql: String,
        rows: [[String]]
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
              let statement
        else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (offset, value) in row.enumerated() {
                guard sqlite3_bind_text(
                    statement,
                    Int32(offset + 1),
                    value,
                    -1,
                    transient
                ) == SQLITE_OK else {
                    throw FixtureError.sqlite
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw FixtureError.sqlite
            }
        }
    }

    enum FixtureError: Error {
        case sqlite
    }

    func article(id: String, title: String) -> KnowledgeArticle {
        KnowledgeArticle(
            id: id,
            domain: .wilderness,
            title: title,
            summary: "Reviewed test evidence.",
            steps: ["Reviewed step."],
            warnings: ["Reviewed warning."],
            keywords: title.lowercased().split(separator: " ").map(String.init),
            source: SourceReference(
                id: "source.\(id)",
                title: "Test source",
                organization: "TrailGuard",
                revision: "1.0"
            ),
            reviewed: true
        )
    }
}

private struct FixedEmbedding: QueryEmbeddingProvider {
    let values: [Float]

    func embedding(for query: String) throws -> [Float] {
        values
    }
}

private struct StaticRetriever: EvidenceRetrieving {
    let articles: [KnowledgeArticle]

    func search(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedPassage] {
        articles.prefix(limit).enumerated().map {
            RetrievedPassage(
                article: $0.element,
                score: Double(articles.count - $0.offset)
            )
        }
    }
}
#endif
