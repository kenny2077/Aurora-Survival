import CryptoKit
import Foundation

public struct RemotePackageLocation: Codable, Hashable, Sendable {
    public let envelopeURL: URL
    public let artifactBaseURL: URL

    public init(envelopeURL: URL, artifactBaseURL: URL) {
        self.envelopeURL = envelopeURL
        self.artifactBaseURL = artifactBaseURL
    }
}

public protocol PackageTransport: Sendable {
    func data(from url: URL) async throws -> Data
    func download(from url: URL, to destination: URL) async throws
}

public protocol ResumablePackageTransport: PackageTransport {
    func data(from url: URL, byteRange: Range<Int64>) async throws -> Data
}

public protocol BackgroundFilePackageTransport: ResumablePackageTransport {
    func downloadArtifact(
        from url: URL,
        to destination: URL,
        expectedByteCount: Int64,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws
}

public enum PackageDownloadError: Error, Equatable {
    case unexpectedPackage
    case invalidRangeResponse
    case invalidChunkSize(expected: Int, actual: Int)
    case assemblyDidNotAdvance(expectedOffset: Int64, actualOffset: Int64)
}

public struct PackageDownloadExpectation: Equatable, Sendable {
    public let packageID: String
    public let version: String
    public let kind: PackageKind

    public init(packageID: String, version: String, kind: PackageKind) {
        self.packageID = packageID
        self.version = version
        self.kind = kind
    }
}

public struct PackageDownloadProgress: Equatable, Sendable {
    public let packageID: String
    public let artifactPath: String
    public let receivedByteCount: Int64
    public let totalByteCount: Int64

    public init(
        packageID: String,
        artifactPath: String,
        receivedByteCount: Int64,
        totalByteCount: Int64
    ) {
        self.packageID = packageID
        self.artifactPath = artifactPath
        self.receivedByteCount = receivedByteCount
        self.totalByteCount = totalByteCount
    }

    public var fractionCompleted: Double {
        guard totalByteCount > 0 else { return 1 }
        return min(1, Double(receivedByteCount) / Double(totalByteCount))
    }
}

public struct URLSessionPackageTransport: ResumablePackageTransport {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.validate(response)
        return data
    }

    public func download(from url: URL, to destination: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try Self.validate(response)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    public func data(
        from url: URL,
        byteRange: Range<Int64>
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(
            "bytes=\(byteRange.lowerBound)-\(byteRange.upperBound - 1)",
            forHTTPHeaderField: "Range"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              let contentRange = http.value(
                  forHTTPHeaderField: "Content-Range"
              ),
              contentRange.hasPrefix("bytes \(byteRange.lowerBound)-")
        else {
            throw PackageDownloadError.invalidRangeResponse
        }
        return data
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
    }
}

public actor PackageDownloadCoordinator {
    private let stagingRoot: URL
    private let transport: any ResumablePackageTransport
    private let installer: PackageInstaller
    private let chunkByteCount: Int64

    public init(
        stagingRoot: URL,
        transport: any ResumablePackageTransport = URLSessionPackageTransport(),
        installer: PackageInstaller,
        chunkByteCount: Int64 = 1_048_576
    ) {
        self.stagingRoot = stagingRoot
        self.transport = transport
        self.installer = installer
        self.chunkByteCount = max(1, chunkByteCount)
    }

    @discardableResult
    public func downloadAndInstall(
        from location: RemotePackageLocation,
        expecting expectation: PackageDownloadExpectation? = nil,
        progress: @escaping @MainActor @Sendable (
            PackageDownloadProgress
        ) async -> Void = { _ in }
    ) async throws -> InstalledPackageVersion {
        let envelopeData = try await transport.data(from: location.envelopeURL)
        let envelope = try JSONDecoder().decode(
            SignedPackageEnvelope.self,
            from: envelopeData
        )
        if let expectation,
           envelope.manifest.packageID != expectation.packageID
            || envelope.manifest.version != expectation.version
            || envelope.manifest.kind != expectation.kind {
            throw PackageDownloadError.unexpectedPackage
        }

        let stagingKey = SHA256.hash(
            data: envelope.manifest.signingPayload
        ).prefix(12).map {
            String(format: "%02x", $0)
        }.joined()
        let staging = stagingRoot.appendingPathComponent(
            "download-\(stagingKey)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )

        do {
            let totalByteCount = envelope.manifest.artifacts.reduce(Int64(0)) {
                $0 + $1.byteCount
            }
            var completedByteCount: Int64 = 0
            for artifact in envelope.manifest.artifacts {
                let destination = try PackageVerifier.safeArtifactURL(
                    path: artifact.path,
                    root: staging
                )
                if Self.fileSize(at: destination) == artifact.byteCount {
                    completedByteCount += artifact.byteCount
                    await progress(
                        PackageDownloadProgress(
                            packageID: envelope.manifest.packageID,
                            artifactPath: artifact.path,
                            receivedByteCount: completedByteCount,
                            totalByteCount: totalByteCount
                        )
                    )
                    continue
                }
                let remoteURL = artifact.path
                    .split(separator: "/")
                    .reduce(location.artifactBaseURL) {
                        $0.appendingPathComponent(String($1), isDirectory: false)
                    }
                if let backgroundTransport = transport as? any BackgroundFilePackageTransport {
                    let completedBeforeArtifact = completedByteCount
                    try await backgroundTransport.downloadArtifact(
                        from: remoteURL,
                        to: destination,
                        expectedByteCount: artifact.byteCount,
                        progress: { artifactBytes in
                            await progress(
                                PackageDownloadProgress(
                                    packageID: envelope.manifest.packageID,
                                    artifactPath: artifact.path,
                                    receivedByteCount: completedBeforeArtifact + artifactBytes,
                                    totalByteCount: totalByteCount
                                )
                            )
                        }
                    )
                    completedByteCount += artifact.byteCount
                    continue
                }

                let partial = destination.appendingPathExtension("partial")
                let assembler = ResumableArtifactAssembler(
                    partialURL: partial,
                    expectedByteCount: artifact.byteCount
                )
                if artifact.byteCount == 0 {
                    try await assembler.append(Data(), atOffset: 0)
                }
                let initial = try await assembler.state()
                await progress(
                    PackageDownloadProgress(
                        packageID: envelope.manifest.packageID,
                        artifactPath: artifact.path,
                        receivedByteCount: completedByteCount
                            + initial.receivedByteCount,
                        totalByteCount: totalByteCount
                    )
                )
                while !(try await assembler.state()).isComplete {
                    try Task.checkCancellation()
                    let state = try await assembler.state()
                    let end = min(
                        artifact.byteCount,
                        state.receivedByteCount + chunkByteCount
                    )
                    let expected = Int(end - state.receivedByteCount)
                    let chunk = try await transport.data(
                        from: remoteURL,
                        byteRange: state.receivedByteCount..<end
                    )
                    guard chunk.count == expected else {
                        throw PackageDownloadError.invalidChunkSize(
                            expected: expected,
                            actual: chunk.count
                        )
                    }
                    try await assembler.append(
                        chunk,
                        atOffset: state.receivedByteCount
                    )
                    let updated = try await assembler.state()
                    guard updated.receivedByteCount == end else {
                        throw PackageDownloadError.assemblyDidNotAdvance(
                            expectedOffset: end,
                            actualOffset: updated.receivedByteCount
                        )
                    }
                    await progress(
                        PackageDownloadProgress(
                            packageID: envelope.manifest.packageID,
                            artifactPath: artifact.path,
                            receivedByteCount: completedByteCount
                                + updated.receivedByteCount,
                            totalByteCount: totalByteCount
                        )
                    )
                }
                try await assembler.finalize(to: destination)
                completedByteCount += artifact.byteCount
            }
            return try await installer.install(
                envelope: envelope,
                stagedDirectory: staging
            )
        } catch let error as PackageVerificationError {
            try? FileManager.default.removeItem(at: staging)
            throw error
        } catch let error as PackageInstallError {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ),
              values.isRegularFile == true,
              let size = values.fileSize
        else {
            return nil
        }
        return Int64(size)
    }
}
