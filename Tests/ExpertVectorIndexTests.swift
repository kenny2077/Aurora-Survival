import CryptoKit
import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ExpertVectorIndexTests: XCTestCase {
    func testExactFloat16SearchIsStableAndFiltersDiscoveryState() throws {
        let root = try makeShard(records: [
            ExpertVectorRecord(
                id: "promoted-nearest",
                scenarioIDs: ["water-boil-scenario"],
                kind: .claim,
                authority: .promoted,
                domain: .wilderness
            ),
            ExpertVectorRecord(
                id: "discovery-second",
                scenarioIDs: ["water-prefilter-scenario"],
                kind: .sourceChunk,
                authority: .discovery,
                domain: .wilderness
            ),
            ExpertVectorRecord(
                id: "tombstoned",
                scenarioIDs: ["retired"],
                kind: .sourceChunk,
                authority: .discovery,
                tombstoned: true
            ),
        ], vectors: [
            unitVector(0),
            normalized([0.8, 0.6]),
            unitVector(0),
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let index = ShardedExpertVectorIndex(
            directories: [root],
            expectedEmbeddingIdentity: "bge-test"
        )
        XCTAssertTrue(index.issues.isEmpty)
        XCTAssertEqual(index.recordCount, 3)
        let results = index.search(
            queryVector: unitVector(0),
            domain: .wilderness
        )
        XCTAssertEqual(results.map(\.record.id), [
            "promoted-nearest", "discovery-second",
        ])
        XCTAssertEqual(results.first?.score ?? 0, 1, accuracy: 0.002)
    }

    func testInvalidShardIsQuarantinedWhileValidShardSearches() throws {
        let valid = try makeShard(
            shardID: "valid",
            records: [ExpertVectorRecord(
                id: "claim",
                scenarioIDs: ["scenario"],
                kind: .claim,
                authority: .promoted
            )],
            vectors: [unitVector(1)]
        )
        let corrupt = try makeShard(
            shardID: "corrupt",
            records: [ExpertVectorRecord(
                id: "other",
                scenarioIDs: ["other"],
                kind: .claim,
                authority: .promoted
            )],
            vectors: [unitVector(2)]
        )
        try Data("tampered".utf8).write(
            to: corrupt.appendingPathComponent("vectors.f16")
        )
        defer {
            try? FileManager.default.removeItem(at: valid)
            try? FileManager.default.removeItem(at: corrupt)
        }

        let index = ShardedExpertVectorIndex(
            directories: [corrupt, valid],
            expectedEmbeddingIdentity: "bge-test"
        )
        XCTAssertEqual(index.recordCount, 1)
        XCTAssertEqual(index.issues, [.checksumMismatch("corrupt")])
        XCTAssertEqual(
            index.search(queryVector: unitVector(1)).first?.record.id,
            "claim"
        )
    }

    func testWrongEmbeddingAndWrongQueryDimensionFailClosed() throws {
        let root = try makeShard(
            records: [ExpertVectorRecord(
                id: "claim",
                scenarioIDs: ["scenario"],
                kind: .claim,
                authority: .promoted
            )],
            vectors: [unitVector(0)]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let index = ShardedExpertVectorIndex(
            directories: [root],
            expectedEmbeddingIdentity: "different"
        )
        XCTAssertTrue(index.isEmpty)
        XCTAssertEqual(index.issues, [.wrongEmbedding("shard-000")])
        XCTAssertTrue(index.search(queryVector: [1]).isEmpty)
    }

    private func makeShard(
        shardID: String = "shard-000",
        records: [ExpertVectorRecord],
        vectors: [[Float]]
    ) throws -> URL {
        XCTAssertEqual(records.count, vectors.count)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraVectorShard-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let recordsData = try JSONEncoder().encode(records)
        let vectorData = vectors.reduce(into: Data()) { data, vector in
            XCTAssertEqual(vector.count, ShardedExpertVectorIndex.dimensions)
            for value in vector {
                var bits = Float16(value).bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        let recordsURL = root.appendingPathComponent("records.json")
        let vectorsURL = root.appendingPathComponent("vectors.f16")
        let metadataData = Data("SQLite format 3\0test".utf8)
        let metadataURL = root.appendingPathComponent("metadata.sqlite")
        try recordsData.write(to: recordsURL)
        try vectorData.write(to: vectorsURL)
        try metadataData.write(to: metadataURL)
        let manifest = ExpertVectorShardManifest(
            shardID: shardID,
            embeddingIdentity: "bge-test",
            dimensions: ShardedExpertVectorIndex.dimensions,
            vectorCount: records.count,
            vectorPath: "vectors.f16",
            vectorSHA256: sha256(vectorData),
            recordsPath: "records.json",
            recordsSHA256: sha256(recordsData),
            metadataPath: "metadata.sqlite",
            metadataSHA256: sha256(metadataData)
        )
        try JSONEncoder().encode(manifest).write(
            to: root.appendingPathComponent(
                ShardedExpertVectorIndex.manifestFilename
            )
        )
        return root
    }

    private func unitVector(_ index: Int) -> [Float] {
        var vector = [Float](
            repeating: 0,
            count: ShardedExpertVectorIndex.dimensions
        )
        vector[index] = 1
        return vector
    }

    private func normalized(_ prefix: [Float]) -> [Float] {
        let magnitude = sqrt(prefix.reduce(0) { $0 + $1 * $1 })
        return prefix.map { $0 / magnitude }
            + [Float](
                repeating: 0,
                count: ShardedExpertVectorIndex.dimensions - prefix.count
            )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
