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

public enum PackageDownloadError: Error, Equatable {
    case incidentModeDenied
    case invalidRangeResponse
    case invalidChunkSize(expected: Int, actual: Int)
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
    private let networkPolicy: IncidentNetworkPolicy
    private let chunkByteCount: Int64

    public init(
        stagingRoot: URL,
        transport: any ResumablePackageTransport = URLSessionPackageTransport(),
        installer: PackageInstaller,
        networkPolicy: IncidentNetworkPolicy = IncidentNetworkPolicy(
            incidentModeEnabled: false
        ),
        chunkByteCount: Int64 = 1_048_576
    ) {
        self.stagingRoot = stagingRoot
        self.transport = transport
        self.installer = installer
        self.networkPolicy = networkPolicy
        self.chunkByteCount = max(1, chunkByteCount)
    }

    @discardableResult
    public func downloadAndInstall(
        from location: RemotePackageLocation
    ) async throws -> InstalledPackageVersion {
        guard networkPolicy.permits(.packageDownload) else {
            throw PackageDownloadError.incidentModeDenied
        }
        let envelopeData = try await transport.data(from: location.envelopeURL)
        let envelope = try JSONDecoder().decode(
            SignedPackageEnvelope.self,
            from: envelopeData
        )

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
            for artifact in envelope.manifest.artifacts {
                let destination = try PackageVerifier.safeArtifactURL(
                    path: artifact.path,
                    root: staging
                )
                if Self.fileSize(at: destination) == artifact.byteCount {
                    continue
                }
                let partial = destination.appendingPathExtension("partial")
                let assembler = ResumableArtifactAssembler(
                    partialURL: partial,
                    expectedByteCount: artifact.byteCount
                )
                let remoteURL = artifact.path
                    .split(separator: "/")
                    .reduce(location.artifactBaseURL) {
                        $0.appendingPathComponent(String($1), isDirectory: false)
                    }
                if artifact.byteCount == 0 {
                    try await assembler.append(Data(), atOffset: 0)
                }
                while !(try await assembler.state()).isComplete {
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
                }
                try await assembler.finalize(to: destination)
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
