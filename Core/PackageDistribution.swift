import CryptoKit
import Foundation

public enum PackageArtifactSourceError: Error, Equatable {
    case invalidRepository
    case invalidRevision
    case invalidFilename
    case invalidDigest
    case invalidByteCount
    case disallowedURL
}

public struct PackageArtifactSource: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(repository)/\(revision)/\(filename)" }
    public let repository: String
    public let revision: String
    public let filename: String
    public let byteCount: Int64
    public let sha256: String

    public init(
        repository: String,
        revision: String,
        filename: String,
        byteCount: Int64,
        sha256: String
    ) {
        self.repository = repository
        self.revision = revision
        self.filename = filename
        self.byteCount = byteCount
        self.sha256 = sha256.lowercased()
    }

    public func validatedResolverURL(
        configuration: PackageDistributionConfiguration = .huggingFace
    ) throws -> URL {
        guard configuration.approvedRepositories.contains(repository) else {
            throw PackageArtifactSourceError.invalidRepository
        }
        guard revision.count == 40,
              revision.allSatisfy({ $0.isHexDigit }) else {
            throw PackageArtifactSourceError.invalidRevision
        }
        guard !filename.isEmpty,
              !filename.contains("/"),
              filename != ".", filename != ".." else {
            throw PackageArtifactSourceError.invalidFilename
        }
        guard byteCount > 0 else { throw PackageArtifactSourceError.invalidByteCount }
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else {
            throw PackageArtifactSourceError.invalidDigest
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.resolverHost
        components.path = "/\(repository)/resolve/\(revision)/\(filename)"
        guard let url = components.url else {
            throw PackageArtifactSourceError.disallowedURL
        }
        return url
    }
}

public struct PackageDistributionConfiguration: Codable, Hashable, Sendable {
    public let resolverHost: String
    public let approvedRepositories: Set<String>
    public let redirectHostSuffix: String

    public init(
        resolverHost: String,
        approvedRepositories: Set<String>,
        redirectHostSuffix: String
    ) {
        self.resolverHost = resolverHost
        self.approvedRepositories = approvedRepositories
        self.redirectHostSuffix = redirectHostSuffix
    }

    public static let huggingFace = PackageDistributionConfiguration(
        resolverHost: "huggingface.co",
        approvedRepositories: [
            "ggml-org/gemma-3-1b-it-GGUF",
            "Qwen/Qwen3-VL-2B-Instruct-GGUF",
        ],
        redirectHostSuffix: ".hf.co"
    )

    public func permitsInitial(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == resolverHost else { return false }
        return approvedRepositories.contains { url.path.hasPrefix("/\($0)/resolve/") }
    }

    public func permitsRedirect(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host.hasSuffix(redirectHostSuffix)
    }
}

public struct PackageCatalogV2Entry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(packageID)@\(version)" }
    public let packageID: String
    public let version: String
    public let displayName: String
    public let summary: String
    public let tier: ModelTier
    public let modality: String
    public let licenseIdentifier: String
    public let minimumRuntimeCommit: String
    public let artifacts: [PackageArtifactSource]
    public let envelope: SignedPackageEnvelope
    public let expertLocked: Bool

    public var totalByteCount: Int64 {
        artifacts.reduce(0) { $0 + $1.byteCount }
    }
}

public struct PackageCatalogV2: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let entries: [PackageCatalogV2Entry]

    public var signingPayload: Data {
        var values = ["schema", String(schemaVersion), "generated", generatedAt]
        for entry in entries.sorted(by: { $0.id < $1.id }) {
            values += [
                "package", entry.packageID, "version", entry.version,
                "display", entry.displayName, "summary", entry.summary,
                "tier", entry.tier.rawValue, "modality", entry.modality,
                "license", entry.licenseIdentifier,
                "runtime", entry.minimumRuntimeCommit,
                "locked", String(entry.expertLocked),
                "envelopeKey", entry.envelope.keyID,
                "envelopeSignature", entry.envelope.signature,
            ]
            for artifact in entry.artifacts.sorted(by: { $0.filename < $1.filename }) {
                values += [
                    "repository", artifact.repository,
                    "revision", artifact.revision,
                    "filename", artifact.filename,
                    "bytes", String(artifact.byteCount),
                    "sha256", artifact.sha256,
                ]
            }
        }
        return Data(values.map { "\($0.utf8.count):\($0)" }.joined(separator: "\n").utf8)
    }
}

public struct SignedPackageCatalogV2: Codable, Hashable, Sendable {
    public let catalog: PackageCatalogV2
    public let keyID: String
    public let signature: String
}

public enum PackageCatalogV2Error: Error, Equatable {
    case unsupportedSchema
    case emptyCatalog
    case duplicateEntry
    case invalidArtifact
    case unknownSigningKey
    case invalidKey
    case invalidKeyValidity
    case invalidSignature
}

public struct PackageCatalogV2Verifier: Sendable {
    private let keys: [String: TrustedPackageKey]
    private let now: @Sendable () -> Date

    public init(
        trustedKeys: [TrustedPackageKey],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        keys = Dictionary(uniqueKeysWithValues: trustedKeys.map { ($0.id, $0) })
        self.now = now
    }

    public func verify(_ envelope: SignedPackageCatalogV2) throws -> PackageCatalogV2 {
        let catalog = envelope.catalog
        guard catalog.schemaVersion == 2 else { throw PackageCatalogV2Error.unsupportedSchema }
        guard !catalog.entries.isEmpty else { throw PackageCatalogV2Error.emptyCatalog }
        guard Set(catalog.entries.map(\.id)).count == catalog.entries.count else {
            throw PackageCatalogV2Error.duplicateEntry
        }
        do {
            for entry in catalog.entries {
                guard !entry.artifacts.isEmpty else { throw PackageCatalogV2Error.invalidArtifact }
                for artifact in entry.artifacts {
                    _ = try artifact.validatedResolverURL()
                }
                guard entry.envelope.manifest.packageID == entry.packageID,
                      entry.envelope.manifest.version == entry.version,
                      entry.envelope.manifest.licenseIdentifier == entry.licenseIdentifier,
                      entry.envelope.manifest.artifacts == entry.artifacts.map({
                          PackageArtifact(
                              path: $0.filename,
                              byteCount: $0.byteCount,
                              sha256: $0.sha256
                          )
                      }) else {
                    throw PackageCatalogV2Error.invalidArtifact
                }
            }
        } catch {
            throw PackageCatalogV2Error.invalidArtifact
        }
        guard let trusted = keys[envelope.keyID] else {
            throw PackageCatalogV2Error.unknownSigningKey
        }
        let formatter = ISO8601DateFormatter()
        guard let validFrom = formatter.date(from: trusted.validFrom),
              let validUntil = trusted.validUntil.flatMap(formatter.date),
              now() >= validFrom, now() <= validUntil else {
            throw PackageCatalogV2Error.invalidKeyValidity
        }
        guard let raw = Data(base64Encoded: trusted.publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            throw PackageCatalogV2Error.invalidKey
        }
        guard let signature = Data(base64Encoded: envelope.signature),
              key.isValidSignature(signature, for: catalog.signingPayload) else {
            throw PackageCatalogV2Error.invalidSignature
        }
        return catalog
    }
}

public enum PackageTransferPhase: String, Codable, CaseIterable, Sendable {
    case unavailable
    case available
    case downloading
    case paused
    case verifying
    case installing
    case installed
    case active
    case updateAvailable = "update_available"
    case incompatible
    case recalled
    case expertLocked = "expert_locked"
    case failed
}

public struct PackageTransferSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: String { packageID }
    public let packageID: String
    public let phase: PackageTransferPhase
    public let receivedByteCount: Int64
    public let totalByteCount: Int64
    public let artifactFilename: String?
    public let retryCount: Int
    public let detail: String?

    public var fractionCompleted: Double {
        guard totalByteCount > 0 else { return 0 }
        return min(1, Double(receivedByteCount) / Double(totalByteCount))
    }

    public init(
        packageID: String,
        phase: PackageTransferPhase,
        receivedByteCount: Int64,
        totalByteCount: Int64,
        artifactFilename: String? = nil,
        retryCount: Int = 0,
        detail: String? = nil
    ) {
        self.packageID = packageID
        self.phase = phase
        self.receivedByteCount = receivedByteCount
        self.totalByteCount = totalByteCount
        self.artifactFilename = artifactFilename
        self.retryCount = retryCount
        self.detail = detail
    }
}

public enum PackageManagerError: Error, Equatable, Sendable {
    case unknownPackage
    case insufficientStorage(required: Int64, available: Int64)
    case deviceIneligible
    case expertLocked
    case invalidProgress
    case retriesExhausted
}

public actor PackageManager {
    private var snapshots: [String: PackageTransferSnapshot] = [:]
    private var entries: [String: PackageCatalogV2Entry] = [:]
    private let stateURL: URL?
    private let fileManager: FileManager

    public init(
        stateURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.stateURL = stateURL
        self.fileManager = fileManager
        if let stateURL,
           let data = try? Data(contentsOf: stateURL),
           let restored = try? JSONDecoder().decode(
                [String: PackageTransferSnapshot].self,
                from: data
           ) {
            snapshots = restored
        }
    }

    public func register(catalog: PackageCatalogV2) throws {
        entries = Dictionary(uniqueKeysWithValues: catalog.entries.map {
            ($0.packageID, $0)
        })
        for entry in catalog.entries where snapshots[entry.packageID] == nil {
            snapshots[entry.packageID] = PackageTransferSnapshot(
                packageID: entry.packageID,
                phase: entry.expertLocked ? .expertLocked : .available,
                receivedByteCount: 0,
                totalByteCount: entry.totalByteCount
            )
        }
        try persist()
    }

    public func snapshot(for packageID: String) -> PackageTransferSnapshot? {
        snapshots[packageID]
    }

    public func allSnapshots() -> [PackageTransferSnapshot] {
        snapshots.values.sorted { $0.packageID < $1.packageID }
    }

    public func begin(
        packageID: String,
        availableStorageBytes: Int64,
        deviceEligible: Bool = true
    ) throws {
        guard let entry = entries[packageID] else {
            throw PackageManagerError.unknownPackage
        }
        guard !entry.expertLocked else { throw PackageManagerError.expertLocked }
        guard deviceEligible else { throw PackageManagerError.deviceIneligible }
        let reserve = max(256_000_000, entry.totalByteCount / 10)
        let required = entry.totalByteCount + reserve
        guard availableStorageBytes >= required else {
            throw PackageManagerError.insufficientStorage(
                required: required,
                available: availableStorageBytes
            )
        }
        snapshots[packageID] = PackageTransferSnapshot(
            packageID: packageID,
            phase: .downloading,
            receivedByteCount: snapshots[packageID]?.receivedByteCount ?? 0,
            totalByteCount: entry.totalByteCount,
            retryCount: snapshots[packageID]?.retryCount ?? 0
        )
        try persist()
    }

    public func recordProgress(
        packageID: String,
        artifactFilename: String,
        receivedByteCount: Int64
    ) throws {
        guard let current = snapshots[packageID],
              current.phase == .downloading,
              receivedByteCount >= current.receivedByteCount,
              receivedByteCount <= current.totalByteCount else {
            throw PackageManagerError.invalidProgress
        }
        snapshots[packageID] = PackageTransferSnapshot(
            packageID: packageID,
            phase: .downloading,
            receivedByteCount: receivedByteCount,
            totalByteCount: current.totalByteCount,
            artifactFilename: artifactFilename,
            retryCount: current.retryCount
        )
        try persist()
    }

    public func pause(packageID: String, detail: String? = nil) throws {
        try transition(packageID: packageID, phase: .paused, detail: detail)
    }

    public func markVerifying(packageID: String) throws {
        try transition(packageID: packageID, phase: .verifying)
    }

    public func markInstalled(packageID: String, active: Bool) throws {
        try transition(packageID: packageID, phase: active ? .active : .installed)
    }

    public func recordRetryableFailure(
        packageID: String,
        detail: String
    ) throws {
        guard let current = snapshots[packageID] else {
            throw PackageManagerError.unknownPackage
        }
        let retries = current.retryCount + 1
        snapshots[packageID] = PackageTransferSnapshot(
            packageID: packageID,
            phase: .paused,
            receivedByteCount: current.receivedByteCount,
            totalByteCount: current.totalByteCount,
            artifactFilename: current.artifactFilename,
            retryCount: retries,
            detail: detail
        )
        try persist()
        if retries >= 3 { throw PackageManagerError.retriesExhausted }
    }

    public func record(_ snapshot: PackageTransferSnapshot) throws {
        snapshots[snapshot.packageID] = snapshot
        try persist()
    }

    private func transition(
        packageID: String,
        phase: PackageTransferPhase,
        detail: String? = nil
    ) throws {
        guard let current = snapshots[packageID] else {
            throw PackageManagerError.unknownPackage
        }
        snapshots[packageID] = PackageTransferSnapshot(
            packageID: packageID,
            phase: phase,
            receivedByteCount: current.receivedByteCount,
            totalByteCount: current.totalByteCount,
            artifactFilename: current.artifactFilename,
            retryCount: current.retryCount,
            detail: detail
        )
        try persist()
    }

    private func persist() throws {
        guard let stateURL else { return }
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.trailGuard.encode(snapshots)
        try data.write(to: stateURL, options: [.atomic])
    }
}
