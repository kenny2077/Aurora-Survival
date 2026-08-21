import Foundation
import CryptoKit
#if canImport(SQLite3)
import SQLite3
#endif

public enum SurvivalKnowledgeError: Error, Equatable, Sendable {
    case sqliteUnavailable
    case missingDatabase(String)
    case invalidDatabase(String)
    case invalidChecksum(String)
    case unsupportedSchema(Int)
}

public struct SurvivalKnowledgeIntegrity: Equatable, Sendable {
    public let schemaVersion: Int
    public let chapterCount: Int
    public let lessonCount: Int
    public let passageCount: Int
    public let indexedPassageCount: Int
    public let sourceCount: Int
    public let legacyAnchorCount: Int
    public let expertScenarioCount: Int
    public let expertClaimCount: Int
}

public enum ManualTheme: String, Codable, Hashable, Sendable {
    case forest
    case earth
    case water
    case fire
    case sky
    case rescue
    case wildlife
    case road
}

public struct ManualCourseChapter: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let purpose: String
    public let overview: String
    public let symbol: String
    public let theme: ManualTheme
}

public struct SurvivalSource: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let organization: String
    public let url: String
    public let publishedAt: String
    public let updatedAt: String
    public let reviewedAt: String
    public let locator: String
    public let jurisdiction: String
    public let licenseStatus: String
    public let reviewLevel: String
}

public struct ManualLesson: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let chapterID: String
    public let title: String
    public let goal: String
    public let actions: [String]
    public let warnings: [String]
    public let keywords: [String]
    public let aliases: [String]
    public let sources: [SurvivalSource]
    public let reviewedAt: String

    public var searchableText: String {
        ([title, goal] + actions + warnings + keywords + aliases)
            .joined(separator: " ")
    }
}

public struct SurvivalPassage: Hashable, Sendable, Identifiable {
    public let id: String
    public let lessonID: String
    public let chapterID: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let lessonTitle: String
    public let title: String
    public let answerText: String
    public let referenceText: String
    public let kind: String
    public let reviewedAt: String
    public let sources: [SurvivalSource]
    public let score: Double

    public var manualReference: ManualReference {
        ManualReference(
            passageID: id,
            lessonID: lessonID,
            chapterID: chapterID,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            sectionTitle: lessonTitle,
            sourceLabel: "Reviewed \(reviewedAt)"
        )
    }
}

public struct SurvivalManualSection: Hashable, Sendable, Identifiable {
    public let passageID: String
    public let lessonID: String
    public let chapterID: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let title: String
    public let summary: String
    public let reviewedAt: String

    public var id: String { passageID }

    public var manualReference: ManualReference {
        ManualReference(
            passageID: passageID,
            lessonID: lessonID,
            chapterID: chapterID,
            chapterNumber: chapterNumber,
            chapterTitle: chapterTitle,
            sectionTitle: title,
            sourceLabel: "Reviewed \(reviewedAt)"
        )
    }
}

public enum ManualPassageResolution: Hashable, Sendable {
    case available(SurvivalPassage)
    case retired(replacement: ManualReference, note: String)
    case unavailable
}

public enum ManualRoute: Hashable, Sendable {
    case chapter(String)
    case lesson(String)
    case reference(ManualReference)
}

public struct SurvivalFallbackBundle: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let reviewDate: String
    public let chapters: [ManualCourseChapter]
    public let cards: [SurvivalFallbackCard]
}

public struct SurvivalFallbackCard: Codable, Hashable, Sendable, Identifiable {
    public let chapterID: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let lessonID: String
    public let title: String
    public let goal: String
    public let actions: [String]
    public let warnings: [String]
    public let reviewedAt: String

    public var id: String { lessonID }

    public func lesson() -> ManualLesson {
        ManualLesson(
            id: lessonID,
            chapterID: chapterID,
            title: title,
            goal: goal,
            actions: actions,
            warnings: warnings,
            keywords: [],
            aliases: [],
            sources: [],
            reviewedAt: reviewedAt
        )
    }
}

public enum SurvivalFallbackLoader {
    public static func load(url: URL) throws -> SurvivalFallbackBundle {
        try JSONDecoder().decode(
            SurvivalFallbackBundle.self,
            from: Data(contentsOf: url)
        )
    }
}

public protocol SurvivalKnowledgeReading: Sendable {
    func integrity() throws -> SurvivalKnowledgeIntegrity
    func chapters() -> [ManualCourseChapter]
    func lessons(chapterID: String) -> [ManualLesson]
    func lesson(id: String) -> ManualLesson?
    func searchLessons(_ query: String, limit: Int) -> [ManualLesson]
    func referenceSections(chapterID: String) -> [SurvivalManualSection]
    func searchReferences(_ query: String, limit: Int) -> [SurvivalManualSection]
    func resolve(_ reference: ManualReference) -> ManualPassageResolution
    func searchPassages(_ query: String, domain: KnowledgeDomain?, limit: Int) -> [SurvivalPassage]
}

public struct SurvivalKnowledgeStore: SurvivalKnowledgeReading, Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw SurvivalKnowledgeError.missingDatabase(databaseURL.path)
        }
        let checksumURL = databaseURL.deletingPathExtension().appendingPathExtension("sha256")
        if FileManager.default.fileExists(atPath: checksumURL.path) {
            let expected = try String(contentsOf: checksumURL, encoding: .utf8)
                .split(whereSeparator: \.isWhitespace)
                .first.map(String.init) ?? ""
            let digest = SHA256.hash(data: try Data(contentsOf: databaseURL))
                .map { String(format: "%02x", $0) }
                .joined()
            guard !expected.isEmpty, expected == digest else {
                throw SurvivalKnowledgeError.invalidChecksum(databaseURL.path)
            }
        }
        self.databaseURL = databaseURL
        let result = try integrity()
        guard result.schemaVersion == 3 else {
            throw SurvivalKnowledgeError.unsupportedSchema(result.schemaVersion)
        }
        guard result.chapterCount == 10,
              result.lessonCount == 70,
              result.passageCount >= 1_000,
              result.passageCount == result.indexedPassageCount,
              result.sourceCount > 0,
              result.legacyAnchorCount == 828,
              result.expertScenarioCount >= 96,
              result.expertClaimCount >= 500
        else {
            throw SurvivalKnowledgeError.invalidDatabase(databaseURL.path)
        }
    }

    public func integrity() throws -> SurvivalKnowledgeIntegrity {
        #if canImport(SQLite3)
        let database = try open()
        defer { sqlite3_close(database) }
        return SurvivalKnowledgeIntegrity(
            schemaVersion: try scalar(
                database,
                "SELECT CAST(value AS INTEGER) FROM metadata WHERE key='schema_version'"
            ),
            chapterCount: try scalar(database, "SELECT COUNT(*) FROM chapters"),
            lessonCount: try scalar(database, "SELECT COUNT(*) FROM lessons"),
            passageCount: try scalar(database, "SELECT COUNT(*) FROM passages"),
            indexedPassageCount: try scalar(database, "SELECT COUNT(*) FROM passages_fts"),
            sourceCount: try scalar(database, "SELECT COUNT(*) FROM sources"),
            legacyAnchorCount: try scalar(database, "SELECT COUNT(*) FROM legacy_anchors"),
            expertScenarioCount: try scalar(database, "SELECT COUNT(*) FROM expert_scenarios"),
            expertClaimCount: try scalar(database, "SELECT COUNT(*) FROM expert_claims")
        )
        #else
        throw SurvivalKnowledgeError.sqliteUnavailable
        #endif
    }

    public func chapters() -> [ManualCourseChapter] {
        #if canImport(SQLite3)
        guard let database = try? open(),
              let statement = try? prepare(
                database,
                "SELECT chapter_id, chapter_no, title, purpose, overview, symbol, theme FROM chapters ORDER BY chapter_no"
              )
        else { return [] }
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        var result: [ManualCourseChapter] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let theme = ManualTheme(rawValue: text(statement, 6)) else { continue }
            result.append(
                ManualCourseChapter(
                    id: text(statement, 0),
                    number: int(statement, 1),
                    title: text(statement, 2),
                    purpose: text(statement, 3),
                    overview: text(statement, 4),
                    symbol: text(statement, 5),
                    theme: theme
                )
            )
        }
        return result
        #else
        return []
        #endif
    }

    public func lessons(chapterID: String) -> [ManualLesson] {
        readLessons(
            sql: "SELECT lesson_id FROM lessons WHERE chapter_id=? ORDER BY display_order",
            binding: chapterID,
            limit: nil
        )
    }

    public func lesson(id: String) -> ManualLesson? {
        readLessons(
            sql: "SELECT lesson_id FROM lessons WHERE lesson_id=?",
            binding: id,
            limit: 1
        ).first
    }

    public func searchLessons(_ query: String, limit: Int = 30) -> [ManualLesson] {
        let terms = Self.normalizedTerms(query)
        guard !terms.isEmpty else { return [] }
        let fts = Self.ftsQuery(terms, prefix: false)
        #if canImport(SQLite3)
        guard let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let sql = """
        SELECT DISTINCT p.lesson_id, MIN(bm25(passages_fts, 0, 8, 12, 12, 10, 6, 2, 8)) AS rank
        FROM passages_fts
        JOIN passages p ON p.passage_id=passages_fts.passage_id
        WHERE passages_fts MATCH ? AND p.review_status='primary-source-verified'
        GROUP BY p.lesson_id ORDER BY rank LIMIT ?
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(fts, to: statement, index: 1),
              sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 100)))) == SQLITE_OK
        else { return [] }
        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { ids.append(text(statement, 0)) }
        if ids.isEmpty, terms.count > 0 {
            return searchLessonsWithPrefix(terms, limit: limit)
        }
        return ids.compactMap { lesson(id: $0) }
        #else
        return []
        #endif
    }

    public func referenceSections(chapterID: String) -> [SurvivalManualSection] {
        readSections(
            sql: """
            SELECT p.passage_id, p.lesson_id, p.chapter_id, c.chapter_no,
                   c.title, l.title, p.answer_text, p.reviewed_at
            FROM passages p JOIN chapters c ON c.chapter_id=p.chapter_id
            JOIN lessons l ON l.lesson_id=p.lesson_id
            WHERE p.chapter_id=? AND p.kind='overview'
            ORDER BY l.display_order
            """,
            binding: chapterID,
            limit: nil
        )
    }

    public func searchReferences(_ query: String, limit: Int = 40) -> [SurvivalManualSection] {
        let passages = searchPassages(query, domain: nil, limit: max(limit * 3, limit))
        var seen: Set<String> = []
        return passages.compactMap { passage in
            guard seen.insert(passage.lessonID).inserted else { return nil }
            return SurvivalManualSection(
                passageID: passage.id,
                lessonID: passage.lessonID,
                chapterID: passage.chapterID,
                chapterNumber: passage.chapterNumber,
                chapterTitle: passage.chapterTitle,
                title: passage.lessonTitle,
                summary: passage.answerText,
                reviewedAt: passage.reviewedAt
            )
        }.prefix(max(1, limit)).map { $0 }
    }

    public func resolve(_ reference: ManualReference) -> ManualPassageResolution {
        if let passage = passage(id: reference.passageID) {
            return .available(passage)
        }
        #if canImport(SQLite3)
        guard let database = try? open() else { return .unavailable }
        defer { sqlite3_close(database) }
        let sql = "SELECT status, replacement_passage_id, note FROM legacy_anchors WHERE legacy_chunk_id=?"
        guard let statement = try? prepare(database, sql) else { return .unavailable }
        defer { sqlite3_finalize(statement) }
        guard bind(reference.passageID, to: statement, index: 1),
              sqlite3_step(statement) == SQLITE_ROW
        else { return .unavailable }
        let status = text(statement, 0)
        let replacementID = text(statement, 1)
        let note = text(statement, 2)
        guard let replacement = passage(id: replacementID) else { return .unavailable }
        if status == "retired" {
            return .retired(replacement: replacement.manualReference, note: note)
        }
        return .available(replacement)
        #else
        return .unavailable
        #endif
    }

    public func searchPassages(
        _ query: String,
        domain: KnowledgeDomain? = nil,
        limit: Int = 2
    ) -> [SurvivalPassage] {
        let terms = Self.normalizedTerms(query)
        guard !terms.isEmpty else { return [] }
        let initial = runPassageSearch(
            terms: terms,
            domain: domain,
            limit: max(limit * 8, 20),
            prefix: false
        )
        let candidates = initial.isEmpty
            ? runPassageSearch(
                terms: terms,
                domain: domain,
                limit: max(limit * 8, 20),
                prefix: true
              )
            : initial
        var seenLessons: Set<String> = []
        return candidates.filter { seenLessons.insert($0.lessonID).inserted }
            .prefix(max(1, min(limit, 100))).map { $0 }
    }

    public func searchExpertEvidence(
        query: String,
        domain: KnowledgeDomain? = nil,
        limit: Int = 8
    ) -> [RetrievedEvidenceScenario] {
        let expertGenericTerms: Set<String> = [
            "about", "action", "find", "get", "go", "have", "identify",
            "make", "need", "now", "problem", "safe", "safety", "take",
            "that", "use",
        ]
        let normalized = Self.normalizedTerms(query)
        let filtered = normalized.filter { !expertGenericTerms.contains($0) }
        let terms = filtered.isEmpty ? normalized : filtered
        guard !terms.isEmpty else { return [] }
        let initial = runExpertSearch(
            terms: terms,
            domain: domain,
            limit: max(8, min(limit, 128)),
            prefix: false
        )
        return (initial.isEmpty
            ? runExpertSearch(
                terms: terms,
                domain: domain,
                limit: max(8, min(limit, 128)),
                prefix: true
              )
            : initial
        ).prefix(max(1, min(limit, 128))).map { $0 }
    }

    public func expertScenario(id: String) -> EvidenceScenarioRecord? {
        #if canImport(SQLite3)
        guard let database = try? open() else { return nil }
        defer { sqlite3_close(database) }
        return expertScenario(id: id, database: database)
        #else
        return nil
        #endif
    }

    public func expertSources(ids: [String]) -> [SurvivalSource] {
        #if canImport(SQLite3)
        let uniqueIDs = Array(Set(ids)).sorted()
        guard !uniqueIDs.isEmpty, let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let placeholders = uniqueIDs.map { _ in "?" }.joined(separator: ",")
        let sql = """
        SELECT source_id, title, organization, url, published_at, updated_at,
               reviewed_at, locator, jurisdiction, license_status, review_level
        FROM sources WHERE source_id IN (\(placeholders))
        ORDER BY organization, title, source_id
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        for (offset, id) in uniqueIDs.enumerated() {
            guard bind(id, to: statement, index: Int32(offset + 1)) else {
                return []
            }
        }
        var result: [SurvivalSource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(SurvivalSource(
                id: text(statement, 0), title: text(statement, 1),
                organization: text(statement, 2), url: text(statement, 3),
                publishedAt: text(statement, 4), updatedAt: text(statement, 5),
                reviewedAt: text(statement, 6), locator: text(statement, 7),
                jurisdiction: text(statement, 8), licenseStatus: text(statement, 9),
                reviewLevel: text(statement, 10)
            ))
        }
        return result
        #else
        return []
        #endif
    }

    public func searchExpertCorpus(
        query: String,
        domain: KnowledgeDomain? = nil,
        limit: Int = 8
    ) -> [ExpertCorpusCandidate] {
        #if canImport(SQLite3)
        let terms = Self.normalizedTerms(query)
        guard !terms.isEmpty, let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let allowed = Self.chapterIDs(for: domain)
        let placeholders = allowed.map { _ in "?" }.joined(separator: ",")
        let domainClause = allowed.isEmpty
            ? ""
            : " AND s.chapter_id IN (\(placeholders))"
        let sql = """
        SELECT s.scenario_id, ch.chunk_id, d.authority_tier,
               bm25(expert_source_chunks_fts, 8, 3, 4)
        FROM expert_source_chunks_fts
        JOIN expert_source_chunks ch
          ON ch.rowid=expert_source_chunks_fts.rowid
        JOIN expert_source_documents d ON d.document_id=ch.document_id
        JOIN expert_chunk_scenarios cs ON cs.chunk_id=ch.chunk_id
        JOIN expert_scenarios s ON s.scenario_id=cs.scenario_id
        WHERE expert_source_chunks_fts MATCH ?
          AND d.redistribution_class NOT IN ('linked_metadata_only','development_only')
          AND d.superseded_by_document_id IS NULL
          AND s.review_status IN ('primary-source-verified','humanApproved')\(domainClause)
        ORDER BY bm25(expert_source_chunks_fts, 8, 3, 4),
                 CASE d.authority_tier
                   WHEN 'authority' THEN 0 WHEN 'corroboration' THEN 1 ELSE 2
                 END,
                 s.scenario_id, ch.chunk_id
        LIMIT ?
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        let queryText = Self.ftsQuery(terms, prefix: false)
        guard bind(queryText, to: statement, index: 1) else { return [] }
        var bindIndex: Int32 = 2
        for chapterID in allowed {
            guard bind(chapterID, to: statement, index: bindIndex) else {
                return []
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(
            statement,
            bindIndex,
            Int32(max(1, min(limit * 4, 64)))
        ) == SQLITE_OK else { return [] }
        var grouped: [String: (
            scenario: EvidenceScenarioRecord,
            chunks: Set<String>,
            score: Double,
            authority: ExpertSourceAuthorityTier
        )] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let scenarioID = text(statement, 0)
            guard let scenario = grouped[scenarioID]?.scenario
                    ?? expertScenario(id: scenarioID, database: database),
                  let authority = ExpertSourceAuthorityTier(
                    rawValue: text(statement, 2)
                  )
            else { continue }
            var item = grouped[scenarioID] ?? (
                scenario, [], 0, authority
            )
            item.chunks.insert(text(statement, 1))
            item.score += max(0, -sqlite3_column_double(statement, 3))
            if authority == .authority { item.authority = .authority }
            else if authority == .corroboration,
                    item.authority == .discovery {
                item.authority = .corroboration
            }
            grouped[scenarioID] = item
        }
        return grouped.values.map {
            ExpertCorpusCandidate(
                scenario: $0.scenario,
                chunkIDs: Array($0.chunks).sorted(),
                score: $0.score,
                authorityTier: $0.authority
            )
        }.sorted {
            if $0.score == $1.score { return $0.scenarioID < $1.scenarioID }
            return $0.score > $1.score
        }.prefix(max(1, min(limit, 128))).map { $0 }
        #else
        return []
        #endif
    }

    public func expertSourceDocuments() -> [ExpertSourceDocument] {
        #if canImport(SQLite3)
        guard let database = try? open(), let statement = try? prepare(
            database,
            """
            SELECT document_id, title, organization, url, authority_tier,
                   redistribution_class, jurisdiction, published_at,
                   updated_at, reviewed_at, license_evidence, content_hash,
                   superseded_by_document_id
            FROM expert_source_documents ORDER BY document_id
            """
        ) else { return [] }
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        var result: [ExpertSourceDocument] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let authority = ExpertSourceAuthorityTier(
                rawValue: text(statement, 4)
            ), let redistribution = ExpertRedistributionClass(
                rawValue: text(statement, 5)
            ) else { continue }
            let superseded = sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil : text(statement, 12)
            result.append(ExpertSourceDocument(
                id: text(statement, 0), title: text(statement, 1),
                organization: text(statement, 2), url: text(statement, 3),
                authorityTier: authority,
                redistributionClass: redistribution,
                jurisdiction: text(statement, 6), publishedAt: text(statement, 7),
                updatedAt: text(statement, 8), reviewedAt: text(statement, 9),
                licenseEvidence: text(statement, 10),
                contentHash: text(statement, 11),
                supersededByDocumentID: superseded
            ))
        }
        return result
        #else
        return []
        #endif
    }

    public func expertClaimPromotions() -> [ExpertClaimPromotionRecord] {
        #if canImport(SQLite3)
        guard let database = try? open(), let statement = try? prepare(
            database,
            """
            SELECT promotion_id, scenario_id, kind, text,
                   source_document_ids_json, source_locators_json,
                   benchmark_gap_ids_json, status, extractor_review_id,
                   critic_review_id, human_reviewer_id
            FROM expert_claim_promotions ORDER BY promotion_id
            """
        ) else { return [] }
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        let strings: (String) -> [String] = {
            (try? JSONDecoder().decode([String].self, from: Data($0.utf8))) ?? []
        }
        var result: [ExpertClaimPromotionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kind = ReviewedClaimKind(rawValue: text(statement, 2)),
                  let status = ExpertClaimPromotionStatus(
                    rawValue: text(statement, 7)
                  ) else { continue }
            let reviewer = sqlite3_column_type(statement, 10) == SQLITE_NULL
                ? nil : text(statement, 10)
            result.append(ExpertClaimPromotionRecord(
                id: text(statement, 0), scenarioID: text(statement, 1),
                kind: kind, text: text(statement, 3),
                sourceDocumentIDs: strings(text(statement, 4)),
                sourceLocators: strings(text(statement, 5)),
                benchmarkGapIDs: strings(text(statement, 6)), status: status,
                extractorReviewID: text(statement, 8),
                criticReviewID: text(statement, 9), humanReviewerID: reviewer
            ))
        }
        return result
        #else
        return []
        #endif
    }
}

extension SurvivalKnowledgeStore: ExpertEvidenceRetrieving {}
extension SurvivalKnowledgeStore: ExpertCorpusReading {}

public struct SurvivalKnowledgeRetriever: EvidenceRetrieving, Sendable {
    private let store: SurvivalKnowledgeStore

    public init(store: SurvivalKnowledgeStore) {
        self.store = store
    }

    public func search(
        query: String,
        domain: KnowledgeDomain? = nil,
        limit: Int = 2
    ) -> [RetrievedPassage] {
        store.searchPassages(query, domain: domain, limit: min(100, max(1, limit)))
            .map { passage in
                let lesson = store.lesson(id: passage.lessonID)
                let source = passage.sources.first
                return RetrievedPassage(
                    article: KnowledgeArticle(
                        id: passage.id,
                        domain: Self.domain(for: passage.chapterID),
                        title: passage.lessonTitle,
                        summary: lesson?.goal ?? passage.answerText,
                        steps: lesson.map { Array($0.actions.prefix(3)) } ?? [],
                        warnings: lesson.map { Array($0.warnings.prefix(1)) } ?? [],
                        keywords: (lesson?.aliases ?? []) + (lesson?.keywords ?? []),
                        source: SourceReference(
                            id: source?.id ?? passage.id,
                            title: source?.title ?? passage.lessonTitle,
                            organization: passage.chapterTitle,
                            revision: passage.manualReference.sourceLabel,
                            url: source?.url
                        ),
                        reviewed: true,
                        manualReference: passage.manualReference
                    ),
                    score: passage.score
                )
            }
    }

    private static func domain(for chapterID: String) -> KnowledgeDomain {
        switch chapterID {
        case "car": return .vehicle
        case "first-aid": return .firstAid
        case "navigation", "signal": return .navigation
        default: return .wilderness
        }
    }
}

#if canImport(SQLite3)
private extension SurvivalKnowledgeStore {
    func open() throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SurvivalKnowledgeError.invalidDatabase(databaseURL.path)
        }
        return database
    }

    func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { throw SurvivalKnowledgeError.invalidDatabase(databaseURL.path) }
        return statement
    }

    func scalar(_ database: OpaquePointer, _ sql: String) throws -> Int {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SurvivalKnowledgeError.invalidDatabase(databaseURL.path)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func bind(_ value: String, to statement: OpaquePointer, index: Int32) -> Bool {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        return sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK
    }

    func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    func int(_ statement: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int(statement, index))
    }

    func decodedStrings(_ value: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
    }

    func readLessons(sql: String, binding: String, limit: Int?) -> [ManualLesson] {
        guard let database = try? open(),
              let statement = try? prepare(database, sql)
        else { return [] }
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        guard bind(binding, to: statement, index: 1) else { return [] }
        var result: [ManualLesson] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let lesson = readLesson(id: text(statement, 0), database: database) {
                result.append(lesson)
                if let limit, result.count >= limit { break }
            }
        }
        return result
    }

    func readLesson(id: String, database: OpaquePointer) -> ManualLesson? {
        let sql = """
        SELECT chapter_id, title, goal, keywords_json, aliases_json, reviewed_at
        FROM lessons WHERE lesson_id=?
        """
        guard let statement = try? prepare(database, sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard bind(id, to: statement, index: 1), sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        return ManualLesson(
            id: id,
            chapterID: text(statement, 0),
            title: text(statement, 1),
            goal: text(statement, 2),
            actions: strings(
                database,
                sql: "SELECT text FROM lesson_actions WHERE lesson_id=? ORDER BY display_order",
                binding: id
            ),
            warnings: strings(
                database,
                sql: "SELECT text FROM lesson_warnings WHERE lesson_id=? ORDER BY display_order",
                binding: id
            ),
            keywords: decodedStrings(text(statement, 3)),
            aliases: decodedStrings(text(statement, 4)),
            sources: sources(lessonID: id, database: database),
            reviewedAt: text(statement, 5)
        )
    }

    func strings(_ database: OpaquePointer, sql: String, binding: String) -> [String] {
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(binding, to: statement, index: 1) else { return [] }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(text(statement, 0)) }
        return result
    }

    func sources(lessonID: String, database: OpaquePointer) -> [SurvivalSource] {
        let sql = """
        SELECT DISTINCT s.source_id, s.title, s.organization, s.url,
               s.published_at, s.updated_at, s.reviewed_at, s.locator,
               s.jurisdiction, s.license_status, s.review_level
        FROM sources s JOIN passage_sources ps ON ps.source_id=s.source_id
        JOIN passages p ON p.passage_id=ps.passage_id
        WHERE p.lesson_id=? ORDER BY s.organization, s.title
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(lessonID, to: statement, index: 1) else { return [] }
        var result: [SurvivalSource] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                SurvivalSource(
                    id: text(statement, 0), title: text(statement, 1),
                    organization: text(statement, 2), url: text(statement, 3),
                    publishedAt: text(statement, 4), updatedAt: text(statement, 5),
                    reviewedAt: text(statement, 6), locator: text(statement, 7),
                    jurisdiction: text(statement, 8), licenseStatus: text(statement, 9),
                    reviewLevel: text(statement, 10)
                )
            )
        }
        return result
    }

    func readSections(sql: String, binding: String, limit: Int?) -> [SurvivalManualSection] {
        guard let database = try? open(), let statement = try? prepare(database, sql)
        else { return [] }
        defer { sqlite3_finalize(statement); sqlite3_close(database) }
        guard bind(binding, to: statement, index: 1) else { return [] }
        if let limit, sqlite3_bind_int(statement, 2, Int32(limit)) != SQLITE_OK {
            return []
        }
        var result: [SurvivalManualSection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                SurvivalManualSection(
                    passageID: text(statement, 0), lessonID: text(statement, 1),
                    chapterID: text(statement, 2), chapterNumber: int(statement, 3),
                    chapterTitle: text(statement, 4), title: text(statement, 5),
                    summary: text(statement, 6), reviewedAt: text(statement, 7)
                )
            )
        }
        return result
    }

    func searchLessonsWithPrefix(_ terms: [String], limit: Int) -> [ManualLesson] {
        let query = terms.map { "\($0)*" }.joined(separator: " OR ")
        #if canImport(SQLite3)
        guard let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let sql = """
        SELECT DISTINCT p.lesson_id, MIN(bm25(passages_fts, 0, 8, 12, 12, 10, 6, 2, 8)) AS rank
        FROM passages_fts JOIN passages p ON p.passage_id=passages_fts.passage_id
        WHERE passages_fts MATCH ? GROUP BY p.lesson_id ORDER BY rank LIMIT ?
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(query, to: statement, index: 1),
              sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 100)))) == SQLITE_OK
        else { return [] }
        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW { ids.append(text(statement, 0)) }
        return ids.compactMap { lesson(id: $0) }
        #else
        return []
        #endif
    }

    func runPassageSearch(
        terms: [String],
        domain: KnowledgeDomain?,
        limit: Int,
        prefix: Bool
    ) -> [SurvivalPassage] {
        #if canImport(SQLite3)
        guard let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let allowed = Self.chapterIDs(for: domain)
        let placeholders = allowed.map { _ in "?" }.joined(separator: ",")
        let domainClause = allowed.isEmpty ? "" : " AND p.chapter_id IN (\(placeholders))"
        let sql = """
        SELECT p.passage_id, p.lesson_id, p.chapter_id, c.chapter_no, c.title,
               l.title, p.title, p.answer_text, p.reference_text, p.kind,
               p.reviewed_at, bm25(passages_fts, 0, 8, 12, 12, 10, 6, 2, 8)
        FROM passages_fts JOIN passages p ON p.passage_id=passages_fts.passage_id
        JOIN chapters c ON c.chapter_id=p.chapter_id
        JOIN lessons l ON l.lesson_id=p.lesson_id
        WHERE passages_fts MATCH ? AND p.review_status='primary-source-verified'\(domainClause)
        ORDER BY bm25(passages_fts, 0, 8, 12, 12, 10, 6, 2, 8),
                 CASE p.kind WHEN 'overview' THEN 0 WHEN 'action' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
                 c.chapter_no, l.display_order, p.display_order LIMIT ?
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        let query = Self.ftsQuery(terms, prefix: prefix)
        guard bind(query, to: statement, index: 1) else { return [] }
        var bindIndex: Int32 = 2
        for chapterID in allowed {
            guard bind(chapterID, to: statement, index: bindIndex) else { return [] }
            bindIndex += 1
        }
        guard sqlite3_bind_int(statement, bindIndex, Int32(max(1, min(limit, 200)))) == SQLITE_OK
        else { return [] }
        var result: [SurvivalPassage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let lessonID = text(statement, 1)
            result.append(
                SurvivalPassage(
                    id: text(statement, 0), lessonID: lessonID,
                    chapterID: text(statement, 2), chapterNumber: int(statement, 3),
                    chapterTitle: text(statement, 4), lessonTitle: text(statement, 5),
                    title: text(statement, 6), answerText: text(statement, 7),
                    referenceText: text(statement, 8), kind: text(statement, 9),
                    reviewedAt: text(statement, 10),
                    sources: sources(lessonID: lessonID, database: database),
                    score: -sqlite3_column_double(statement, 11)
                )
            )
        }
        return result
        #else
        return []
        #endif
    }

    func runExpertSearch(
        terms: [String],
        domain: KnowledgeDomain?,
        limit: Int,
        prefix: Bool
    ) -> [RetrievedEvidenceScenario] {
        guard let database = try? open() else { return [] }
        defer { sqlite3_close(database) }
        let allowed = Self.chapterIDs(for: domain)
        let placeholders = allowed.map { _ in "?" }.joined(separator: ",")
        let domainClause = allowed.isEmpty
            ? ""
            : " AND s.chapter_id IN (\(placeholders))"
        let sql = """
        SELECT s.scenario_id,
               bm25(expert_scenarios_fts, 0, 3, 12, 9, 11, 7, 8)
        FROM expert_scenarios_fts
        JOIN expert_scenarios s
          ON s.scenario_id=expert_scenarios_fts.scenario_id
        WHERE expert_scenarios_fts MATCH ?
          AND s.review_status IN ('primary-source-verified','humanApproved')\(domainClause)
        ORDER BY bm25(expert_scenarios_fts, 0, 3, 12, 9, 11, 7, 8),
                 s.scenario_id
        LIMIT ?
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(Self.ftsQuery(terms, prefix: prefix), to: statement, index: 1)
        else { return [] }
        var bindIndex: Int32 = 2
        for chapterID in allowed {
            guard bind(chapterID, to: statement, index: bindIndex) else {
                return []
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int(
            statement,
            bindIndex,
            Int32(max(1, min(limit, 80)))
        ) == SQLITE_OK else { return [] }
        var result: [RetrievedEvidenceScenario] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let scenario = expertScenario(
                id: text(statement, 0),
                database: database
            ) else { continue }
            result.append(RetrievedEvidenceScenario(
                scenario: scenario,
                score: -sqlite3_column_double(statement, 1)
            ))
        }
        return result
    }

    func expertScenario(
        id: String,
        database: OpaquePointer
    ) -> EvidenceScenarioRecord? {
        let sql = """
        SELECT s.scenario_id, s.lesson_id, s.chapter_id, c.chapter_no,
               c.title, s.title, s.applicability, s.observable_cues_json,
               s.prerequisites_json, s.risk_class, s.jurisdiction, s.units,
               s.related_scenario_ids_json, s.reviewed_at,
               l.document_id, l.chunk_id, l.section_path, l.locator
        FROM expert_scenarios s
        JOIN chapters c ON c.chapter_id=s.chapter_id
        LEFT JOIN corpus_scenario_locators l ON l.scenario_id=s.scenario_id
        WHERE s.scenario_id=?
        """
        guard let statement = try? prepare(database, sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard bind(id, to: statement, index: 1),
              sqlite3_step(statement) == SQLITE_ROW,
              let riskClass = ExpertRiskClass(rawValue: text(statement, 9))
        else { return nil }
        let decodeStrings: (String) -> [String] = { value in
            (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
        }
        let scenarioID = text(statement, 0)
        let lessonID = sqlite3_column_type(statement, 1) == SQLITE_NULL
            ? "" : text(statement, 1)
        let reviewedAt = text(statement, 13)
        let evidenceLocator: ExpertEvidenceLocator? =
            sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil
            : ExpertEvidenceLocator(
                documentID: text(statement, 14),
                chunkID: text(statement, 15),
                sectionPath: text(statement, 16),
                locator: text(statement, 17)
            )
        return EvidenceScenarioRecord(
            id: scenarioID,
            lessonID: lessonID,
            chapterID: text(statement, 2),
            title: text(statement, 5),
            applicability: text(statement, 6),
            observableCues: decodeStrings(text(statement, 7)),
            prerequisites: decodeStrings(text(statement, 8)),
            riskClass: riskClass,
            jurisdiction: text(statement, 10),
            units: text(statement, 11),
            relatedScenarioIDs: decodeStrings(text(statement, 12)),
            claims: expertClaims(scenarioID: scenarioID, database: database),
            manualReference: lessonID.isEmpty ? nil : ManualReference(
                passageID: "\(lessonID)-p01",
                lessonID: lessonID,
                chapterID: text(statement, 2),
                chapterNumber: int(statement, 3),
                chapterTitle: text(statement, 4),
                sectionTitle: text(statement, 5),
                sourceLabel: "Reviewed \(reviewedAt)"
            ),
            evidenceLocator: evidenceLocator
        )
    }

    func expertClaims(
        scenarioID: String,
        database: OpaquePointer
    ) -> [ReviewedClaim] {
        let sql = """
        SELECT claim_id, kind, text, applicability, requirement_class
        FROM expert_claims
        WHERE scenario_id=?
        ORDER BY display_order
        """
        guard let statement = try? prepare(database, sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        guard bind(scenarioID, to: statement, index: 1) else { return [] }
        var result: [ReviewedClaim] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let claimID = text(statement, 0)
            guard let kind = ReviewedClaimKind(rawValue: text(statement, 1))
            else { continue }
            let sourceSQL = """
            SELECT source_id, locator FROM expert_claim_sources
            WHERE claim_id=? ORDER BY source_id
            """
            guard let sourceStatement = try? prepare(database, sourceSQL) else {
                continue
            }
            var sourceIDs: [String] = []
            var locators: [String] = []
            if bind(claimID, to: sourceStatement, index: 1) {
                while sqlite3_step(sourceStatement) == SQLITE_ROW {
                    sourceIDs.append(text(sourceStatement, 0))
                    locators.append(text(sourceStatement, 1))
                }
            }
            sqlite3_finalize(sourceStatement)
            let numericSQL = """
            SELECT token FROM expert_numeric_facts
            WHERE claim_id=? ORDER BY token
            """
            var facts: [AllowedNumericFact] = []
            if let numericStatement = try? prepare(database, numericSQL) {
                if bind(claimID, to: numericStatement, index: 1) {
                    while sqlite3_step(numericStatement) == SQLITE_ROW {
                        facts.append(AllowedNumericFact(
                            token: text(numericStatement, 0),
                            sourceClaimID: claimID
                        ))
                    }
                }
                sqlite3_finalize(numericStatement)
            }
            result.append(ReviewedClaim(
                id: claimID,
                kind: kind,
                text: text(statement, 2),
                applicability: text(statement, 3),
                requirementClass: ReviewedClaimRequirementClass(
                    rawValue: text(statement, 4)
                ),
                sourceIDs: sourceIDs,
                sourceLocators: locators,
                allowedNumericFacts: facts
            ))
        }
        return result
    }

    func passage(id: String) -> SurvivalPassage? {
        #if canImport(SQLite3)
        guard let database = try? open() else { return nil }
        defer { sqlite3_close(database) }
        let sql = """
        SELECT p.passage_id, p.lesson_id, p.chapter_id, c.chapter_no, c.title,
               l.title, p.title, p.answer_text, p.reference_text, p.kind, p.reviewed_at
        FROM passages p JOIN chapters c ON c.chapter_id=p.chapter_id
        JOIN lessons l ON l.lesson_id=p.lesson_id WHERE p.passage_id=?
        """
        guard let statement = try? prepare(database, sql) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard bind(id, to: statement, index: 1), sqlite3_step(statement) == SQLITE_ROW
        else { return nil }
        let lessonID = text(statement, 1)
        return SurvivalPassage(
            id: text(statement, 0), lessonID: lessonID,
            chapterID: text(statement, 2), chapterNumber: int(statement, 3),
            chapterTitle: text(statement, 4), lessonTitle: text(statement, 5),
            title: text(statement, 6), answerText: text(statement, 7),
            referenceText: text(statement, 8), kind: text(statement, 9),
            reviewedAt: text(statement, 10),
            sources: sources(lessonID: lessonID, database: database), score: 0
        )
        #else
        return nil
        #endif
    }

    static func normalizedTerms(_ query: String) -> [String] {
        let raw = RetrievalEngine.tokens(in: query)
        let stopwords: Set<String> = [
            "a", "an", "and", "are", "can", "could", "do", "for", "how",
            "i", "is", "it", "make", "my", "of", "on", "please", "safer",
            "should", "the", "this", "to", "what", "when", "where", "with",
        ]
        let expansions: [String: [String]] = [
            "watre": ["water"],
            "firre": ["fire"],
            "sheltr": ["shelter"],
            "compas": ["compass"],
            "bleading": ["bleeding"],
            "bled": ["bleeding", "blood"],
            "bleed": ["bleeding", "blood"],
            "bleeds": ["bleeding", "blood"],
            "ligthning": ["lightning"],
            "overhet": ["overheating"],
            "dehydraton": ["dehydration"],
            "purify": ["water", "filter", "boil"],
            "purifier": ["water", "filter", "boil"],
            "wont": ["no", "start"],
            "stranded": ["lost", "car"],
            "injured": ["assessment", "first", "aid"],
            "injury": ["assessment", "first", "aid"],
            "freezing": ["cold", "hypothermia"],
            "thirsty": ["water", "dehydration"],
            "mushrooms": ["mushroom", "unknown", "food"],
            "campfire": ["fire"],
            "punctured": ["puncture", "tire"],
            "tires": ["tire"],
            "tyre": ["tire"],
            "tyres": ["tire"],
            "wounded": ["wound"],
            "wounds": ["wound"],
        ]
        var result = raw.subtracting(stopwords)
        if result.isEmpty { result = raw }
        for token in raw { result.formUnion(expansions[token] ?? []) }
        return result.sorted()
    }

    static func ftsQuery(_ terms: [String], prefix: Bool) -> String {
        terms.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return prefix ? "\"\(escaped)\"*" : "\"\(escaped)\""
        }.joined(separator: " OR ")
    }

    static func chapterIDs(for domain: KnowledgeDomain?) -> [String] {
        switch domain {
        case .vehicle: return ["car"]
        case .firstAid: return ["first-aid"]
        case .navigation: return ["navigation", "signal"]
        case .wilderness, .none: return []
        }
    }
}
#endif
