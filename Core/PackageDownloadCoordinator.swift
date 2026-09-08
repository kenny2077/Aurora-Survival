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

public protocol ValidatedRangePackageTransport: ResumablePackageTransport {
    func range(
        from url: URL,
        byteRange: Range<Int64>
    ) async throws -> PackageRangeResponse
}

public struct PackageRangeResponse: Equatable, Sendable {
    public let data: Data
    public let totalByteCount: Int64
    public let validator: String

    public init(data: Data, totalByteCount: Int64, validator: String) {
        self.data = data
        self.totalByteCount = totalByteCount
        self.validator = validator
    }

    public static func validate(
        response: HTTPURLResponse,
        requestedRange: Range<Int64>
    ) throws -> (totalByteCount: Int64, validator: String) {
        guard response.statusCode == 206,
              let value = response.value(forHTTPHeaderField: "Content-Range"),
              let parsed = parseContentRange(value),
              parsed.start == requestedRange.lowerBound,
              parsed.end == requestedRange.upperBound - 1,
              parsed.total >= requestedRange.upperBound,
              let validator = response.value(forHTTPHeaderField: "ETag")
                ?? response.value(forHTTPHeaderField: "Last-Modified"),
              !validator.isEmpty else {
            throw PackageDownloadError.invalidRangeResponse
        }
        return (parsed.total, validator)
    }

    private static func parseContentRange(
        _ value: String
    ) -> (start: Int64, end: Int64, total: Int64)? {
        let components = value.split(separator: " ")
        guard components.count == 2, components[0].lowercased() == "bytes" else {
            return nil
        }
        let boundsAndTotal = components[1].split(separator: "/")
        let bounds = boundsAndTotal.first?.split(separator: "-") ?? []
        guard boundsAndTotal.count == 2, bounds.count == 2,
              let start = Int64(bounds[0]), let end = Int64(bounds[1]),
              let total = Int64(boundsAndTotal[1]) else { return nil }
        return (start, end, total)
    }
}

public enum PackageDownloadError: Error, Equatable {
    case unexpectedPackage
    case invalidRangeResponse
    case invalidChunkSize(expected: Int, actual: Int)
    case assemblyDidNotAdvance(expectedOffset: Int64, actualOffset: Int64)
    case remoteArtifactChanged
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
        ) async -> Void = { _ in },
        phase: @escaping @MainActor @Sendable (
            PackageTransferPhase
        ) async -> Void = { _ in }
    ) async throws -> InstalledPackageVersion {
        await phase(.downloading)
        let envelopeData = try await transport.data(from: location.envelopeURL)
        let envelope = try JSONDecoder().decode(
            SignedPackageEnvelope.self,
            from: envelopeData
        )
        try await installer.verifyManifest(envelope)
        if let expectation,
           envelope.manifest.packageID != expectation.packageID
            || envelope.manifest.version != expectation.version
            || envelope.manifest.kind != expectation.kind {
            throw PackageDownloadError.unexpectedPackage
        }

        let current = try await installer.index()
        if let installed = current.installed.first(where: {
            $0.packageID == envelope.manifest.packageID
                && $0.version == envelope.manifest.version
        }) {
            try await installer.activate(
                packageID: installed.packageID,
                version: installed.version
            )
            await phase(.active)
            return installed
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
        let transferIdentity = "\(envelope.manifest.packageID)@\(envelope.manifest.version)"
        try Data(transferIdentity.utf8).write(
            to: staging.appendingPathComponent(".package-identity"),
            options: [.atomic]
        )
        let transferStore = PackageManager(
            stateURL: stagingRoot.appendingPathComponent("transfer-state.json")
        )

        do {
            let totalByteCount = envelope.manifest.artifacts.reduce(Int64(0)) {
                $0 + $1.byteCount
            }
            let alreadyStaged = try envelope.manifest.artifacts.reduce(Int64(0)) {
                let destination = try PackageVerifier.safeArtifactURL(
                    path: $1.path,
                    root: staging
                )
                if Self.fileSize(at: destination) == $1.byteCount {
                    return $0 + $1.byteCount
                }
                let partial = destination.appendingPathExtension("partial")
                return $0 + min(Self.fileSize(at: partial) ?? 0, $1.byteCount)
            }
            try Self.preflightStorage(
                at: stagingRoot,
                remainingByteCount: totalByteCount - alreadyStaged,
                packageByteCount: totalByteCount
            )
            try await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .downloading,
                receivedByteCount: alreadyStaged,
                totalByteCount: totalByteCount
            ))
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
                let partial = destination.appendingPathExtension("partial")
                let validatorURL = partial.appendingPathExtension("validator")
                try? FileManager.default.removeItem(
                    at: destination.appendingPathExtension("resume-data")
                )
                try? FileManager.default.removeItem(
                    at: destination.appendingPathExtension("resume-progress")
                )
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
                    let requestedRange = state.receivedByteCount..<end
                    let chunk: Data
                    if let validated = transport as? any ValidatedRangePackageTransport {
                        let response = try await validated.range(
                            from: remoteURL,
                            byteRange: requestedRange
                        )
                        guard response.totalByteCount == artifact.byteCount else {
                            throw PackageDownloadError.invalidRangeResponse
                        }
                        if let existing = try? String(
                            contentsOf: validatorURL,
                            encoding: .utf8
                        ), existing != response.validator {
                            try? FileManager.default.removeItem(at: partial)
                            try? FileManager.default.removeItem(at: validatorURL)
                            throw PackageDownloadError.remoteArtifactChanged
                        }
                        if !FileManager.default.fileExists(atPath: validatorURL.path) {
                            try FileManager.default.createDirectory(
                                at: validatorURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            try Data(response.validator.utf8).write(
                                to: validatorURL,
                                options: [.atomic]
                            )
                        }
                        chunk = response.data
                    } else {
                        chunk = try await transport.data(
                            from: remoteURL,
                            byteRange: requestedRange
                        )
                    }
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
                    try await transferStore.record(PackageTransferSnapshot(
                        packageID: transferIdentity,
                        phase: .downloading,
                        receivedByteCount: completedByteCount + updated.receivedByteCount,
                        totalByteCount: totalByteCount,
                        artifactFilename: artifact.path
                    ))
                }
                try await assembler.finalize(to: destination)
                try? FileManager.default.removeItem(at: validatorURL)
                completedByteCount += artifact.byteCount
            }
            try Task.checkCancellation()
            await phase(.verifying)
            try await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .verifying,
                receivedByteCount: totalByteCount,
                totalByteCount: totalByteCount
            ))
            try await installer.verifyStagedPackage(
                envelope: envelope,
                stagedDirectory: staging
            )
            try Task.checkCancellation()
            try? FileManager.default.removeItem(
                at: staging.appendingPathComponent(".package-identity")
            )
            await phase(.installing)
            try await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .installing,
                receivedByteCount: totalByteCount,
                totalByteCount: totalByteCount
            ))
            let installed = try await installer.installVerified(
                envelope: envelope,
                stagedDirectory: staging
            )
            try await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .active,
                receivedByteCount: totalByteCount,
                totalByteCount: totalByteCount
            ))
            return installed
        } catch is CancellationError {
            try? await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .paused,
                receivedByteCount: Self.stagedByteCount(
                    for: envelope.manifest,
                    under: staging
                ),
                totalByteCount: envelope.manifest.artifacts.reduce(0) { $0 + $1.byteCount },
                detail: "Paused"
            ))
            throw CancellationError()
        } catch let error as PackageVerificationError {
            try? FileManager.default.removeItem(at: staging)
            throw error
        } catch PackageInstallError.packageAlreadyInstalled {
            let current = try await installer.index()
            guard let installed = current.installed.first(where: {
                $0.packageID == envelope.manifest.packageID
                    && $0.version == envelope.manifest.version
            }) else {
                throw PackageInstallError.packageAlreadyInstalled
            }
            try await installer.activate(
                packageID: installed.packageID,
                version: installed.version
            )
            try? FileManager.default.removeItem(at: staging)
            try? await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .active,
                receivedByteCount: envelope.manifest.artifacts.reduce(0) {
                    $0 + $1.byteCount
                },
                totalByteCount: envelope.manifest.artifacts.reduce(0) {
                    $0 + $1.byteCount
                }
            ))
            await phase(.active)
            return installed
        } catch let error as PackageInstallError {
            switch error {
            case .insufficientSpace, .fileOperationFailed:
                break
            default:
                try? FileManager.default.removeItem(at: staging)
            }
            try? await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .failed,
                receivedByteCount: Self.stagedByteCount(
                    for: envelope.manifest,
                    under: staging
                ),
                totalByteCount: envelope.manifest.artifacts.reduce(0) { $0 + $1.byteCount },
                detail: String(describing: error)
            ))
            throw error
        } catch let error as ArtifactAssemblyError {
            if error != .fileOperationFailed {
                try? FileManager.default.removeItem(at: staging)
            }
            try? await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .failed,
                receivedByteCount: Self.stagedByteCount(
                    for: envelope.manifest,
                    under: staging
                ),
                totalByteCount: envelope.manifest.artifacts.reduce(0) { $0 + $1.byteCount },
                detail: String(describing: error)
            ))
            throw error
        } catch {
            try? await transferStore.record(PackageTransferSnapshot(
                packageID: transferIdentity,
                phase: .failed,
                receivedByteCount: Self.stagedByteCount(
                    for: envelope.manifest,
                    under: staging
                ),
                totalByteCount: envelope.manifest.artifacts.reduce(0) { $0 + $1.byteCount },
                detail: String(describing: error)
            ))
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

    private static func preflightStorage(
        at url: URL,
        remainingByteCount: Int64,
        packageByteCount: Int64
    ) throws {
        let available = try url.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage ?? 0
        let reserve = max(256_000_000, packageByteCount / 10)
        let required = remainingByteCount + reserve
        guard available >= required else {
            throw PackageInstallError.insufficientSpace(
                required: required,
                available: available
            )
        }
    }

    private static func stagedByteCount(
        for manifest: PackageManifest,
        under root: URL
    ) -> Int64 {
        manifest.artifacts.reduce(0) { total, artifact in
            guard let destination = try? PackageVerifier.safeArtifactURL(
                path: artifact.path,
                root: root
            ) else { return total }
            let complete = fileSize(at: destination) == artifact.byteCount
                ? artifact.byteCount : 0
            let partial = min(
                fileSize(at: destination.appendingPathExtension("partial")) ?? 0,
                artifact.byteCount
            )
            return total + max(complete, partial)
        }
    }
}
