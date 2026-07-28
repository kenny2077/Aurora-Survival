import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

public protocol QueryEmbeddingProvider: Sendable {
    func embedding(for query: String) throws -> [Float]
}

public enum SQLiteHybridRetrieverError: Error, Equatable {
    case sqliteUnavailable
    case missingDatabase(String)
    case missingVectorIndex(String)
    case invalidDatabase(String)
}

public struct SQLiteHybridRetrievalFilter: Sendable {
    public let locale: String?
    public let jurisdiction: String?
    public let allowedAnswerLevels: Set<String>

    public init(
        locale: String? = nil,
        jurisdiction: String? = nil,
        allowedAnswerLevels: Set<String> = ["supported", "limited"]
    ) {
        self.locale = locale
        self.jurisdiction = jurisdiction
        self.allowedAnswerLevels = allowedAnswerLevels
    }
}

/// Searches verified active knowledge packs using their compiled FTS5 database
/// and precomputed vectors. Lexical and dense ranks are combined with
/// reciprocal-rank fusion; all ties are resolved by stable evidence ID.
///
/// Construct this only from directories returned by `ActivePackRegistry`.
public struct SQLiteHybridRetriever: EvidenceRetrieving, Sendable {
    private let packs: [Pack]
    private let embeddingProvider: (any QueryEmbeddingProvider)?
    private let filter: SQLiteHybridRetrievalFilter

    public init(
        activeKnowledgePackages: [ResolvedActivePackage],
        embeddingProvider: (any QueryEmbeddingProvider)? = nil,
        filter: SQLiteHybridRetrievalFilter = SQLiteHybridRetrievalFilter()
    ) throws {
        #if canImport(SQLite3)
        self.packs = try activeKnowledgePackages.map { package in
            let databaseURL = package.directory.appendingPathComponent(
                "content.sqlite",
                isDirectory: false
            )
            let vectorsURL = package.directory.appendingPathComponent(
                "vectors.bin",
                isDirectory: false
            )
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw SQLiteHybridRetrieverError.missingDatabase(
                    package.manifest.packageID
                )
            }
            guard FileManager.default.fileExists(atPath: vectorsURL.path) else {
                throw SQLiteHybridRetrieverError.missingVectorIndex(
                    package.manifest.packageID
                )
            }
            return Pack(
                packageID: package.manifest.packageID,
                databaseURL: databaseURL,
                vectorsURL: vectorsURL
            )
        }
        self.embeddingProvider = embeddingProvider
        self.filter = filter
        #else
        throw SQLiteHybridRetrieverError.sqliteUnavailable
        #endif
    }

    public func search(
        query: String,
        domain: KnowledgeDomain? = nil,
        vehicle: VehicleProfile? = nil,
        limit: Int = 4
    ) -> [RetrievedPassage] {
        #if canImport(SQLite3)
        let tokens = RetrievalEngine.tokens(in: query).sorted()
        guard !tokens.isEmpty else { return [] }
        let ftsQuery = tokens.map(Self.quotedFTSToken).joined(separator: " OR ")
        let queryVector = try? embeddingProvider?.embedding(for: query)
        var fused: [String: FusedCandidate] = [:]

        for pack in packs {
            guard let metadata = try? readMetadata(pack: pack),
                  metadataMatches(metadata, domain: domain)
            else { continue }

            let lexical = (try? lexicalRows(
                pack: pack,
                ftsQuery: ftsQuery,
                domain: domain,
                vehicle: vehicle
            )) ?? []
            for (offset, row) in lexical.enumerated() {
                var candidate = fused[row.article.id]
                    ?? FusedCandidate(article: row.article, score: 0)
                candidate.score += 1.0 / Double(60 + offset + 1)
                fused[row.article.id] = candidate
            }

            if let queryVector,
               let dense = try? denseRows(
                   pack: pack,
                   queryVector: queryVector,
                   domain: domain,
                   vehicle: vehicle
               ) {
                for (offset, row) in dense.enumerated() {
                    var candidate = fused[row.article.id]
                        ?? FusedCandidate(article: row.article, score: 0)
                    candidate.score += 1.0 / Double(60 + offset + 1)
                    fused[row.article.id] = candidate
                }
            }
        }

        return fused.values
            .sorted {
                if $0.score == $1.score {
                    return $0.article.id < $1.article.id
                }
                return $0.score > $1.score
            }
            .prefix(max(1, limit))
            .map {
                RetrievedPassage(article: $0.article, score: $0.score)
            }
        #else
        return []
        #endif
    }
}

private extension SQLiteHybridRetriever {
    struct Pack: Sendable {
        let packageID: String
        let databaseURL: URL
        let vectorsURL: URL
    }

    struct PackMetadata {
        let domain: KnowledgeDomain
        let locale: String?
        let expiresAt: Date?
    }

    struct RankedRow {
        let article: KnowledgeArticle
        let vectorOffset: Int
        let vectorDimensions: Int
        let denseScore: Double
    }

    struct FusedCandidate {
        let article: KnowledgeArticle
        var score: Double
    }

    static func quotedFTSToken(_ token: String) -> String {
        "\"\(token.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func metadataMatches(
        _ metadata: PackMetadata,
        domain: KnowledgeDomain?
    ) -> Bool {
        if let domain, metadata.domain != domain {
            return false
        }
        if let locale = filter.locale,
           metadata.locale?.caseInsensitiveCompare(locale) != .orderedSame {
            return false
        }
        if let expiresAt = metadata.expiresAt, expiresAt <= Date() {
            return false
        }
        return true
    }
}

#if canImport(SQLite3)
private extension SQLiteHybridRetriever {
    func open(_ pack: Pack) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            pack.databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteHybridRetrieverError.invalidDatabase(pack.packageID)
        }
        return database
    }

    func readMetadata(pack: Pack) throws -> PackMetadata {
        let database = try open(pack)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT key, value FROM pack_metadata ORDER BY key",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteHybridRetrieverError.invalidDatabase(pack.packageID)
        }
        defer { sqlite3_finalize(statement) }

        var values: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            values[columnText(statement, index: 0)] = columnText(
                statement,
                index: 1
            )
        }
        guard let rawDomain = values["domain"],
              let domain = KnowledgeDomain(rawValue: rawDomain)
        else {
            throw SQLiteHybridRetrieverError.invalidDatabase(pack.packageID)
        }
        return PackMetadata(
            domain: domain,
            locale: values["locale"],
            expiresAt: values["expires_at"].flatMap(
                ISO8601DateFormatter().date
            )
        )
    }

    func lexicalRows(
        pack: Pack,
        ftsQuery: String,
        domain: KnowledgeDomain?,
        vehicle: VehicleProfile?
    ) throws -> [RankedRow] {
        let sql = """
        SELECT e.evidence_id, e.title, e.summary, e.steps_json,
               e.warnings_json, e.keywords_json, e.source_json,
               e.applicability_json, e.supported_answer_level,
               e.vector_offset, e.vector_dimensions
        FROM evidence_fts
        JOIN evidence e ON e.evidence_id = evidence_fts.evidence_id
        WHERE evidence_fts MATCH ?
        ORDER BY bm25(evidence_fts), e.evidence_id
        LIMIT 64
        """
        return try rows(
            pack: pack,
            sql: sql,
            binding: ftsQuery,
            domain: domain,
            vehicle: vehicle
        )
    }

    func denseRows(
        pack: Pack,
        queryVector: [Float],
        domain: KnowledgeDomain?,
        vehicle: VehicleProfile?
    ) throws -> [RankedRow] {
        let sql = """
        SELECT evidence_id, title, summary, steps_json, warnings_json,
               keywords_json, source_json, applicability_json,
               supported_answer_level, vector_offset, vector_dimensions
        FROM evidence
        ORDER BY evidence_id
        """
        let vectors = try Data(contentsOf: pack.vectorsURL, options: [.mappedIfSafe])
        return try rows(
            pack: pack,
            sql: sql,
            binding: nil,
            domain: domain,
            vehicle: vehicle
        )
        .compactMap { row in
            guard row.vectorDimensions == queryVector.count,
                  let stored = Self.vector(
                      data: vectors,
                      offset: row.vectorOffset,
                      dimensions: row.vectorDimensions
                  )
            else { return nil }
            return RankedRow(
                article: row.article,
                vectorOffset: row.vectorOffset,
                vectorDimensions: row.vectorDimensions,
                denseScore: Self.cosine(queryVector, stored)
            )
        }
        .sorted {
            if $0.denseScore == $1.denseScore {
                return $0.article.id < $1.article.id
            }
            return $0.denseScore > $1.denseScore
        }
        .prefix(64)
        .map { $0 }
    }

    func rows(
        pack: Pack,
        sql: String,
        binding: String?,
        domain: KnowledgeDomain?,
        vehicle: VehicleProfile?
    ) throws -> [RankedRow] {
        let metadata = try readMetadata(pack: pack)
        if let domain, metadata.domain != domain {
            return []
        }
        let database = try open(pack)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteHybridRetrieverError.invalidDatabase(pack.packageID)
        }
        defer { sqlite3_finalize(statement) }
        if let binding {
            let transient = unsafeBitCast(
                -1,
                to: sqlite3_destructor_type.self
            )
            guard sqlite3_bind_text(
                statement,
                1,
                binding,
                -1,
                transient
            ) == SQLITE_OK else {
                throw SQLiteHybridRetrieverError.invalidDatabase(pack.packageID)
            }
        }

        var result: [RankedRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let row = decodeRow(
                statement,
                domain: metadata.domain,
                vehicle: vehicle
            ) {
                result.append(row)
            }
        }
        return result
    }

    func decodeRow(
        _ statement: OpaquePointer,
        domain: KnowledgeDomain,
        vehicle: VehicleProfile?
    ) -> RankedRow? {
        let level = columnText(statement, index: 8)
        guard filter.allowedAnswerLevels.contains(level) else {
            return nil
        }
        let applicabilityData = Data(
            columnText(statement, index: 7).utf8
        )
        if !applicabilityMatches(
            applicabilityData,
            domain: domain,
            vehicle: vehicle
        ) {
            return nil
        }
        guard let steps = stringArray(columnText(statement, index: 3)),
              let warnings = stringArray(columnText(statement, index: 4)),
              let keywords = stringArray(columnText(statement, index: 5)),
              let source = sourceReference(columnText(statement, index: 6))
        else { return nil }

        let applicability: VehicleApplicability?
        if domain == .vehicle {
            applicability = try? JSONDecoder().decode(
                VehicleApplicability.self,
                from: applicabilityData
            )
            guard applicability != nil else { return nil }
        } else {
            applicability = nil
        }
        return RankedRow(
            article: KnowledgeArticle(
                id: columnText(statement, index: 0),
                domain: domain,
                title: columnText(statement, index: 1),
                summary: columnText(statement, index: 2),
                steps: steps,
                warnings: warnings,
                keywords: keywords,
                source: source,
                reviewed: true,
                vehicleApplicability: applicability
            ),
            vectorOffset: Int(sqlite3_column_int64(statement, 9)),
            vectorDimensions: Int(sqlite3_column_int(statement, 10)),
            denseScore: 0
        )
    }

    func applicabilityMatches(
        _ data: Data,
        domain: KnowledgeDomain,
        vehicle: VehicleProfile?
    ) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return false }
        if let requiredJurisdiction = filter.jurisdiction,
           let recordJurisdiction = dictionary["jurisdiction"] as? String,
           recordJurisdiction.caseInsensitiveCompare(requiredJurisdiction)
                != .orderedSame {
            return false
        }
        guard domain == .vehicle else { return true }
        guard let vehicle,
              let applicability = try? JSONDecoder().decode(
                  VehicleApplicability.self,
                  from: data
              )
        else { return false }
        return applicability.matches(vehicle)
    }

    func stringArray(_ value: String) -> [String]? {
        try? JSONDecoder().decode([String].self, from: Data(value.utf8))
    }

    func sourceReference(_ value: String) -> SourceReference? {
        guard let decoded = try? JSONSerialization.jsonObject(
            with: Data(value.utf8)
        ),
              let object = decoded as? [String: Any],
              let id = object["source_id"] as? String,
              let title = object["title"] as? String,
              let owner = object["owner"] as? String,
              let revision = object["revision"] as? String
        else { return nil }
        let locator = object["locator"] as? String
        let url = locator.flatMap {
            URL(string: $0)?.scheme == nil ? nil : $0
        }
        return SourceReference(
            id: id,
            title: title,
            organization: owner,
            revision: revision,
            url: url
        )
    }

    func columnText(_ statement: OpaquePointer, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: text)
    }

    static func vector(
        data: Data,
        offset: Int,
        dimensions: Int
    ) -> [Float]? {
        let byteCount = dimensions * MemoryLayout<UInt32>.size
        guard offset >= 0, dimensions > 0, offset + byteCount <= data.count else {
            return nil
        }
        return data.withUnsafeBytes { rawBuffer in
            (0..<dimensions).map { index in
                let start = offset + index * 4
                let bits = UInt32(rawBuffer[start])
                    | UInt32(rawBuffer[start + 1]) << 8
                    | UInt32(rawBuffer[start + 2]) << 16
                    | UInt32(rawBuffer[start + 3]) << 24
                return Float(bitPattern: bits)
            }
        }
    }

    static func cosine(_ left: [Float], _ right: [Float]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return -1 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for index in left.indices {
            let a = Double(left[index])
            let b = Double(right[index])
            dot += a * b
            leftNorm += a * a
            rightNorm += b * b
        }
        guard leftNorm > 0, rightNorm > 0 else { return -1 }
        return dot / (leftNorm.squareRoot() * rightNorm.squareRoot())
    }
}
#endif
