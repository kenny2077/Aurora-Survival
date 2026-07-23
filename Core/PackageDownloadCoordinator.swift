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

public struct URLSessionPackageTransport: PackageTransport {
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
    private let transport: any PackageTransport
    private let installer: PackageInstaller

    public init(
        stagingRoot: URL,
        transport: any PackageTransport = URLSessionPackageTransport(),
        installer: PackageInstaller
    ) {
        self.stagingRoot = stagingRoot
        self.transport = transport
        self.installer = installer
    }

    @discardableResult
    public func downloadAndInstall(
        from location: RemotePackageLocation
    ) async throws -> InstalledPackageVersion {
        let envelopeData = try await transport.data(from: location.envelopeURL)
        let envelope = try JSONDecoder().decode(
            SignedPackageEnvelope.self,
            from: envelopeData
        )

        let staging = stagingRoot.appendingPathComponent(
            UUID().uuidString,
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
                let remoteURL = artifact.path
                    .split(separator: "/")
                    .reduce(location.artifactBaseURL) {
                        $0.appendingPathComponent(String($1), isDirectory: false)
                    }
                try await transport.download(from: remoteURL, to: destination)
            }
            return try await installer.install(
                envelope: envelope,
                stagedDirectory: staging
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
