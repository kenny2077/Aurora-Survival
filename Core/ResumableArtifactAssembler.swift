import Foundation

public enum ArtifactAssemblyError: Error, Equatable {
    case invalidOffset(expected: Int64, received: Int64)
    case exceedsExpectedSize
    case incompleteArtifact
    case fileOperationFailed
}

public struct ArtifactAssemblyState: Codable, Equatable, Sendable {
    public let expectedByteCount: Int64
    public let receivedByteCount: Int64
    public let isComplete: Bool
}

public actor ResumableArtifactAssembler {
    private let partialURL: URL
    private let expectedByteCount: Int64
    private let fileManager: FileManager

    public init(
        partialURL: URL,
        expectedByteCount: Int64,
        fileManager: FileManager = .default
    ) {
        self.partialURL = partialURL
        self.expectedByteCount = expectedByteCount
        self.fileManager = fileManager
    }

    public func state() throws -> ArtifactAssemblyState {
        let received: Int64
        if fileManager.fileExists(atPath: partialURL.path) {
            do {
                let attributes = try fileManager.attributesOfItem(
                    atPath: partialURL.path
                )
                received = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                throw ArtifactAssemblyError.fileOperationFailed
            }
        } else {
            received = 0
        }
        guard received <= expectedByteCount else {
            throw ArtifactAssemblyError.exceedsExpectedSize
        }
        return ArtifactAssemblyState(
            expectedByteCount: expectedByteCount,
            receivedByteCount: received,
            isComplete: received == expectedByteCount
        )
    }

    public func append(_ data: Data, atOffset offset: Int64) throws {
        let current = try state().receivedByteCount
        guard offset == current else {
            throw ArtifactAssemblyError.invalidOffset(
                expected: current,
                received: offset
            )
        }
        guard current + Int64(data.count) <= expectedByteCount else {
            throw ArtifactAssemblyError.exceedsExpectedSize
        }
        do {
            try fileManager.createDirectory(
                at: partialURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: partialURL.path) {
                fileManager.createFile(atPath: partialURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partialURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            throw ArtifactAssemblyError.fileOperationFailed
        }
    }

    public func finalize(to destination: URL) throws {
        guard try state().isComplete else {
            throw ArtifactAssemblyError.incompleteArtifact
        }
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: partialURL, to: destination)
        } catch {
            throw ArtifactAssemblyError.fileOperationFailed
        }
    }
}
