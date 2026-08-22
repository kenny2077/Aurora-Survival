import Accelerate
import CryptoKit
import Foundation
import Metal

public protocol ExpertQueryEmbeddingProvider: Sendable {
    func embedding(for query: String) async throws -> [Float]
    func passageEmbedding(for text: String) async throws -> [Float]
}

public extension ExpertQueryEmbeddingProvider {
    func passageEmbedding(for text: String) async throws -> [Float] {
        try await embedding(for: text)
    }
}

public enum ExpertVectorAuthority: String, Codable, Sendable {
    case promoted
    case discovery
}

public enum ExpertVectorRecordKind: String, Codable, Sendable {
    case scenario
    case claim
    case sourceChunk = "source_chunk"
}

public struct ExpertVectorRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let scenarioIDs: [String]
    public let kind: ExpertVectorRecordKind
    public let authority: ExpertVectorAuthority
    public let domain: KnowledgeDomain?
    public let jurisdiction: String?
    public let expiresAt: String?
    public let superseded: Bool
    public let unresolvedConflict: Bool
    public let tombstoned: Bool

    public init(
        id: String,
        scenarioIDs: [String],
        kind: ExpertVectorRecordKind,
        authority: ExpertVectorAuthority,
        domain: KnowledgeDomain? = nil,
        jurisdiction: String? = nil,
        expiresAt: String? = nil,
        superseded: Bool = false,
        unresolvedConflict: Bool = false,
        tombstoned: Bool = false
    ) {
        self.id = id
        self.scenarioIDs = scenarioIDs
        self.kind = kind
        self.authority = authority
        self.domain = domain
        self.jurisdiction = jurisdiction
        self.expiresAt = expiresAt
        self.superseded = superseded
        self.unresolvedConflict = unresolvedConflict
        self.tombstoned = tombstoned
    }
}

public struct ExpertVectorShardManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let shardID: String
    public let embeddingIdentity: String
    public let corpusIdentity: String
    public let dimensions: Int
    public let vectorCount: Int
    public let vectorPath: String
    public let vectorSHA256: String
    public let recordsPath: String
    public let recordsSHA256: String
    public let metadataPath: String
    public let metadataSHA256: String

    public init(
        schemaVersion: Int = 3,
        shardID: String,
        embeddingIdentity: String,
        corpusIdentity: String = "test-corpus-v3",
        dimensions: Int,
        vectorCount: Int,
        vectorPath: String,
        vectorSHA256: String,
        recordsPath: String,
        recordsSHA256: String,
        metadataPath: String,
        metadataSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.shardID = shardID
        self.embeddingIdentity = embeddingIdentity
        self.corpusIdentity = corpusIdentity
        self.dimensions = dimensions
        self.vectorCount = vectorCount
        self.vectorPath = vectorPath
        self.vectorSHA256 = vectorSHA256.lowercased()
        self.recordsPath = recordsPath
        self.recordsSHA256 = recordsSHA256.lowercased()
        self.metadataPath = metadataPath
        self.metadataSHA256 = metadataSHA256.lowercased()
    }
}

public enum ExpertVectorIndexIssue: Equatable, Sendable {
    case unreadableShard(String)
    case unsupportedSchema(String)
    case wrongEmbedding(String)
    case wrongDimensions(String)
    case oversizedShard(String)
    case unsafePath(String)
    case checksumMismatch(String)
    case recordCountMismatch(String)
    case invalidVector(String)
}

public struct ExpertVectorSearchResult: Equatable, Sendable {
    public let record: ExpertVectorRecord
    public let score: Double
    public let shardID: String
}

/// Deterministic, memory-mapped exact search for signed float16 vector shards.
/// Corpus builders normalize every row; runtime validation rejects malformed
/// vectors before the shard can contribute to retrieval.
public struct ShardedExpertVectorIndex: Sendable {
    public static let dimensions = 384
    public static let maximumRowsPerShard = 10_000
    public static let manifestFilename = "expert-vector-index.json"

    private let shards: [Shard]
    private let metalScanner: MetalExactVectorScanner?
    public let issues: [ExpertVectorIndexIssue]

    public init(
        directories: [URL],
        expectedEmbeddingIdentity: String
    ) {
        var accepted: [Shard] = []
        var rejected: [ExpertVectorIndexIssue] = []
        for directory in directories.sorted(by: { $0.path < $1.path }) {
            do {
                accepted.append(try Self.loadShard(
                    directory: directory,
                    expectedEmbeddingIdentity: expectedEmbeddingIdentity
                ))
            } catch let error as LoadError {
                rejected.append(error.issue)
            } catch {
                rejected.append(.unreadableShard(directory.lastPathComponent))
            }
        }
        shards = accepted.sorted { $0.manifest.shardID < $1.manifest.shardID }
        metalScanner = MetalExactVectorScanner()
        issues = rejected
    }

    public var isEmpty: Bool { shards.isEmpty }
    public var recordCount: Int { shards.reduce(0) { $0 + $1.records.count } }
    public var corpusIdentities: Set<String> {
        Set(shards.map { $0.manifest.corpusIdentity })
    }

    public func search(
        queryVector: [Float],
        domain: KnowledgeDomain? = nil,
        jurisdiction: String? = nil,
        perShardLimit: Int = 64,
        globalLimit: Int = 128,
        now: Date = Date()
    ) -> [ExpertVectorSearchResult] {
        guard queryVector.count == Self.dimensions,
              queryVector.allSatisfy(\.isFinite)
        else { return [] }
        let magnitude = sqrt(queryVector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0, magnitude.isFinite else { return [] }
        let normalized = queryVector.map { $0 / magnitude }
        var merged: [ExpertVectorSearchResult] = []
        for shard in shards {
            var local: [ExpertVectorSearchResult] = []
            let localLimit = max(1, perShardLimit)
            local.reserveCapacity(localLimit * 2)
            let scores = metalScanner?.scores(
                vectors: shard.vectors,
                rowCount: shard.records.count,
                query: normalized
            ) ?? Self.exactScores(
                vectors: shard.vectors,
                rowCount: shard.records.count,
                query: normalized
            )
            for row in shard.records.indices {
                let record = shard.records[row]
                guard Self.includes(
                    record,
                    domain: domain,
                    jurisdiction: jurisdiction,
                    now: now
                ), scores[row].isFinite else { continue }
                Self.retainTop(ExpertVectorSearchResult(
                    record: record,
                    score: Double(scores[row]),
                    shardID: shard.manifest.shardID
                ), in: &local, limit: localLimit)
            }
            local.sort(by: Self.ranksBefore)
            merged.append(contentsOf: local.prefix(localLimit))
        }
        return merged.sorted(by: Self.ranksBefore)
            .prefix(max(1, globalLimit)).map { $0 }
    }
}

private final class MetalExactVectorScanner: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue()
        else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void exact_dot(
            const device half *vectors [[buffer(0)]],
            const device float *query [[buffer(1)]],
            device float *scores [[buffer(2)]],
            constant uint &dimensions [[buffer(3)]],
            uint row [[thread_position_in_grid]]) {
            float sum = 0.0f;
            uint offset = row * dimensions;
            for (uint column = 0; column < dimensions; ++column) {
                sum += float(vectors[offset + column]) * query[column];
            }
            scores[row] = sum;
        }
        """
        guard let library = try? device.makeLibrary(
            source: source,
            options: nil
        ),
              let function = library.makeFunction(name: "exact_dot"),
              let pipeline = try? device.makeComputePipelineState(
                function: function
              )
        else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func scores(
        vectors: Data,
        rowCount: Int,
        query: [Float]
    ) -> [Float]? {
        vectors.withUnsafeBytes { vectorBytes -> [Float]? in
            guard let vectorAddress = vectorBytes.baseAddress else { return nil }
            let vectorBuffer = device.makeBuffer(
                    bytesNoCopy: UnsafeMutableRawPointer(
                        mutating: vectorAddress
                    ),
                    length: vectors.count,
                    options: .storageModeShared,
                    deallocator: nil
                  ) ?? device.makeBuffer(
                    bytes: vectorAddress,
                    length: vectors.count,
                    options: .storageModeShared
                  )
            let queryBytes = query.count * MemoryLayout<Float>.size
            guard let vectorBuffer, let queryBuffer = device.makeBuffer(
                bytes: query,
                length: queryBytes,
                options: .storageModeShared
            ), let scoreBuffer = device.makeBuffer(
                length: rowCount * MemoryLayout<Float>.size,
                options: .storageModeShared
            ), let commandBuffer = queue.makeCommandBuffer(),
               let encoder = commandBuffer.makeComputeCommandEncoder()
            else { return nil }
            var dimensions = UInt32(ShardedExpertVectorIndex.dimensions)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(vectorBuffer, offset: 0, index: 0)
            encoder.setBuffer(queryBuffer, offset: 0, index: 1)
            encoder.setBuffer(scoreBuffer, offset: 0, index: 2)
            encoder.setBytes(
                &dimensions,
                length: MemoryLayout<UInt32>.size,
                index: 3
            )
            let width = min(
                pipeline.maxTotalThreadsPerThreadgroup,
                max(1, pipeline.threadExecutionWidth * 4)
            )
            encoder.dispatchThreads(
                MTLSize(width: rowCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(
                    width: width,
                    height: 1,
                    depth: 1
                )
            )
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            guard commandBuffer.status == .completed else { return nil }
            let pointer = scoreBuffer.contents().bindMemory(
                to: Float.self,
                capacity: rowCount
            )
            return Array(UnsafeBufferPointer(start: pointer, count: rowCount))
        }
    }
}

private extension ShardedExpertVectorIndex {
    static func retainTop(
        _ candidate: ExpertVectorSearchResult,
        in heap: inout [ExpertVectorSearchResult],
        limit: Int
    ) {
        if heap.count < limit {
            heap.append(candidate)
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard ranksBefore(heap[parent], heap[child]) else { break }
                heap.swapAt(parent, child)
                child = parent
            }
            return
        }
        guard ranksBefore(candidate, heap[0]) else { return }
        heap[0] = candidate
        var parent = 0
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worse = left
            if right < heap.count, ranksBefore(heap[left], heap[right]) {
                worse = right
            }
            guard ranksBefore(heap[parent], heap[worse]) else { return }
            heap.swapAt(parent, worse)
            parent = worse
        }
    }

    static func exactScores(
        vectors: Data,
        rowCount: Int,
        query: [Float]
    ) -> [Float] {
        var matrix = [Float](
            repeating: 0,
            count: rowCount * dimensions
        )
        var scores = [Float](repeating: 0, count: rowCount)
        vectors.withUnsafeBytes { sourceBytes in
            matrix.withUnsafeMutableBytes { destinationBytes in
                var source = vImage_Buffer(
                    data: UnsafeMutableRawPointer(
                        mutating: sourceBytes.baseAddress!
                    ),
                    height: vImagePixelCount(rowCount),
                    width: vImagePixelCount(dimensions),
                    rowBytes: dimensions * MemoryLayout<UInt16>.size
                )
                var destination = vImage_Buffer(
                    data: destinationBytes.baseAddress!,
                    height: vImagePixelCount(rowCount),
                    width: vImagePixelCount(dimensions),
                    rowBytes: dimensions * MemoryLayout<Float>.size
                )
                vImageConvert_Planar16FtoPlanarF(
                    &source,
                    &destination,
                    vImage_Flags(kvImageNoFlags)
                )
            }
        }
        matrix.withUnsafeBufferPointer { matrixValues in
            query.withUnsafeBufferPointer { queryValues in
                scores.withUnsafeMutableBufferPointer { scoreValues in
                    vDSP_mmul(
                        matrixValues.baseAddress!,
                        1,
                        queryValues.baseAddress!,
                        1,
                        scoreValues.baseAddress!,
                        1,
                        vDSP_Length(rowCount),
                        1,
                        vDSP_Length(dimensions)
                    )
                }
            }
        }
        return scores
    }

    struct Shard: @unchecked Sendable {
        let manifest: ExpertVectorShardManifest
        let records: [ExpertVectorRecord]
        let vectors: Data
    }

    struct LoadError: Error {
        let issue: ExpertVectorIndexIssue
    }

    static func loadShard(
        directory: URL,
        expectedEmbeddingIdentity: String
    ) throws -> Shard {
        let label = directory.lastPathComponent
        let manifestURL = directory.appendingPathComponent(manifestFilename)
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                ExpertVectorShardManifest.self,
                from: manifestData
              )
        else { throw LoadError(issue: .unreadableShard(label)) }
        guard manifest.schemaVersion == 3, !manifest.corpusIdentity.isEmpty else {
            throw LoadError(issue: .unsupportedSchema(manifest.shardID))
        }
        guard manifest.embeddingIdentity == expectedEmbeddingIdentity else {
            throw LoadError(issue: .wrongEmbedding(manifest.shardID))
        }
        guard manifest.dimensions == dimensions else {
            throw LoadError(issue: .wrongDimensions(manifest.shardID))
        }
        guard (1...maximumRowsPerShard).contains(manifest.vectorCount) else {
            throw LoadError(issue: .oversizedShard(manifest.shardID))
        }
        let vectorURL: URL
        let recordsURL: URL
        let metadataURL: URL
        do {
            vectorURL = try PackageVerifier.safeArtifactURL(
                path: manifest.vectorPath,
                root: directory
            )
            recordsURL = try PackageVerifier.safeArtifactURL(
                path: manifest.recordsPath,
                root: directory
            )
            metadataURL = try PackageVerifier.safeArtifactURL(
                path: manifest.metadataPath,
                root: directory
            )
        } catch {
            throw LoadError(issue: .unsafePath(manifest.shardID))
        }
        guard Self.sha256(vectorURL) == manifest.vectorSHA256,
              Self.sha256(recordsURL) == manifest.recordsSHA256,
              Self.sha256(metadataURL) == manifest.metadataSHA256,
              Self.hasSQLiteHeader(metadataURL)
        else { throw LoadError(issue: .checksumMismatch(manifest.shardID)) }
        guard let recordsData = try? Data(contentsOf: recordsURL),
              let records = try? JSONDecoder().decode(
                [ExpertVectorRecord].self,
                from: recordsData
              ),
              records.count == manifest.vectorCount,
              Set(records.map(\.id)).count == records.count
        else { throw LoadError(issue: .recordCountMismatch(manifest.shardID)) }
        let expectedBytes = manifest.vectorCount * dimensions * MemoryLayout<UInt16>.size
        guard let vectors = try? Data(contentsOf: vectorURL, options: [.mappedIfSafe]),
              vectors.count == expectedBytes
        else { throw LoadError(issue: .invalidVector(manifest.shardID)) }
        var invalid = false
        vectors.withUnsafeBytes { bytes in
            let words = bytes.bindMemory(to: UInt16.self)
            for row in 0..<manifest.vectorCount where !invalid {
                var norm: Float = 0
                let offset = row * dimensions
                for column in 0..<dimensions {
                    let value = Float(Float16(bitPattern: UInt16(littleEndian: words[offset + column])))
                    if !value.isFinite { invalid = true; break }
                    norm += value * value
                }
                if !(0.90...1.10).contains(norm) { invalid = true }
            }
        }
        guard !invalid else {
            throw LoadError(issue: .invalidVector(manifest.shardID))
        }
        return Shard(manifest: manifest, records: records, vectors: vectors)
    }

    static func includes(
        _ record: ExpertVectorRecord,
        domain: KnowledgeDomain?,
        jurisdiction: String?,
        now: Date
    ) -> Bool {
        guard !record.superseded,
              !record.unresolvedConflict,
              !record.tombstoned,
              domain == nil || record.domain == nil || record.domain == domain
        else { return false }
        if let jurisdiction,
           let recordJurisdiction = record.jurisdiction,
           !recordJurisdiction.isEmpty,
           recordJurisdiction.caseInsensitiveCompare(jurisdiction) != .orderedSame {
            return false
        }
        if let raw = record.expiresAt,
           let expiry = ISO8601DateFormatter().date(from: raw),
           expiry <= now {
            return false
        }
        return true
    }

    static func ranksBefore(
        _ lhs: ExpertVectorSearchResult,
        _ rhs: ExpertVectorSearchResult
    ) -> Bool {
        if lhs.score == rhs.score {
            if lhs.record.id == rhs.record.id { return lhs.shardID < rhs.shardID }
            return lhs.record.id < rhs.record.id
        }
        return lhs.score > rhs.score
    }

    static func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hasSQLiteHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16))
            == Data("SQLite format 3\0".utf8)
    }
}
