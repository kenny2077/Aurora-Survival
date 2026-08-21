import Foundation

public enum PackageInstallError: Error, Equatable {
    case insufficientSpace(required: Int64, available: Int64)
    case packageAlreadyInstalled
    case packageNotInstalled
    case cannotRollback
    case invalidIndex
    case recalledPackage
    case fileOperationFailed
}

public struct InstalledPackageVersion: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(packageID)@\(version)" }
    public let packageID: String
    public let version: String
    public let kind: PackageKind
    public let displayName: String
    public let installedAt: String
    public let directoryName: String

    public init(
        packageID: String,
        version: String,
        kind: PackageKind,
        displayName: String,
        installedAt: String,
        directoryName: String
    ) {
        self.packageID = packageID
        self.version = version
        self.kind = kind
        self.displayName = displayName
        self.installedAt = installedAt
        self.directoryName = directoryName
    }
}

public struct PackageActivationIndex: Codable, Equatable, Sendable {
    public var activeVersions: [String: String]
    public var installed: [InstalledPackageVersion]
    public var recalledVersions: [String: Set<String>]

    public init(
        activeVersions: [String: String] = [:],
        installed: [InstalledPackageVersion] = [],
        recalledVersions: [String: Set<String>] = [:]
    ) {
        self.activeVersions = activeVersions
        self.installed = installed
        self.recalledVersions = recalledVersions
    }

    private enum CodingKeys: String, CodingKey {
        case activeVersions
        case installed
        case recalledVersions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeVersions = try container.decodeIfPresent(
            [String: String].self,
            forKey: .activeVersions
        ) ?? [:]
        installed = try container.decodeIfPresent(
            [InstalledPackageVersion].self,
            forKey: .installed
        ) ?? []
        recalledVersions = try container.decodeIfPresent(
            [String: Set<String>].self,
            forKey: .recalledVersions
        ) ?? [:]
    }
}

public actor PackageInstaller {
    private let rootDirectory: URL
    private let verifier: PackageVerifier
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    public init(
        rootDirectory: URL,
        verifier: PackageVerifier,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.rootDirectory = rootDirectory
        self.verifier = verifier
        self.fileManager = fileManager
        self.now = now
    }

    public func index() throws -> PackageActivationIndex {
        try ensureRoot()
        let url = indexURL
        guard fileManager.fileExists(atPath: url.path) else {
            return PackageActivationIndex()
        }
        do {
            return try JSONDecoder().decode(
                PackageActivationIndex.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw PackageInstallError.invalidIndex
        }
    }

    /// Installs a verified directory. The caller owns `stagedDirectory` until
    /// verification passes; after success it is atomically moved into the store.
    @discardableResult
    public func install(
        envelope: SignedPackageEnvelope,
        stagedDirectory: URL,
        activate: Bool = true
    ) throws -> InstalledPackageVersion {
        try ensureRoot()
        try verifier.verify(envelope: envelope, packageDirectory: stagedDirectory)

        let manifest = envelope.manifest
        let required = manifest.artifacts.reduce(Int64(0)) { $0 + $1.byteCount }
        let available = try rootDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage ?? 0
        let reserve = max(256_000_000, required / 10)
        guard available >= required + reserve else {
            throw PackageInstallError.insufficientSpace(
                required: required + reserve,
                available: available
            )
        }

        let directoryName = "\(manifest.packageID)@\(manifest.version)"
        let destination = packagesDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw PackageInstallError.packageAlreadyInstalled
        }
        var current = try index()
        guard !(current.recalledVersions[manifest.packageID] ?? []).contains(
            manifest.version
        ) else {
            throw PackageInstallError.recalledPackage
        }

        do {
            let envelopeData = try JSONEncoder.trailGuard.encode(envelope)
            try envelopeData.write(
                to: stagedDirectory.appendingPathComponent("envelope.json"),
                options: [.atomic]
            )
            try fileManager.moveItem(at: stagedDirectory, to: destination)
            try? (destination as NSURL).setResourceValue(
                true,
                forKey: .isExcludedFromBackupKey
            )
#if os(iOS)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
#endif

            let record = InstalledPackageVersion(
                packageID: manifest.packageID,
                version: manifest.version,
                kind: manifest.kind,
                displayName: manifest.displayName,
                installedAt: ISO8601DateFormatter().string(from: now()),
                directoryName: directoryName
            )
            current.installed.removeAll { $0.id == record.id }
            current.installed.append(record)
            if activate {
                current.activeVersions[manifest.packageID] = manifest.version
            }
            try writeIndex(current)
            return record
        } catch let error as PackageInstallError {
            throw error
        } catch {
            try? fileManager.removeItem(at: destination)
            throw PackageInstallError.fileOperationFailed
        }
    }

    public func activate(packageID: String, version: String) throws {
        var current = try index()
        guard !(current.recalledVersions[packageID] ?? []).contains(version) else {
            throw PackageInstallError.recalledPackage
        }
        guard current.installed.contains(where: {
            $0.packageID == packageID && $0.version == version
        }) else {
            throw PackageInstallError.packageNotInstalled
        }
        current.activeVersions[packageID] = version
        try writeIndex(current)
    }

    public func rollback(packageID: String) throws -> String {
        var current = try index()
        guard let active = current.activeVersions[packageID] else {
            throw PackageInstallError.cannotRollback
        }
        let candidates = current.installed
            .filter {
                $0.packageID == packageID
                    && $0.version != active
                    && !(current.recalledVersions[packageID] ?? []).contains($0.version)
            }
            .sorted { $0.installedAt > $1.installedAt }
        guard let previous = candidates.first else {
            throw PackageInstallError.cannotRollback
        }
        current.activeVersions[packageID] = previous.version
        try writeIndex(current)
        return previous.version
    }

    /// Marks a version unusable and immediately fails over to the newest
    /// non-recalled installed version. The recalled files remain for audit
    /// until a separate inactive-package removal is requested.
    @discardableResult
    public func recall(packageID: String, version: String) throws -> String? {
        var current = try index()
        guard current.installed.contains(where: {
            $0.packageID == packageID && $0.version == version
        }) else {
            throw PackageInstallError.packageNotInstalled
        }
        current.recalledVersions[packageID, default: []].insert(version)

        var replacement: String?
        if current.activeVersions[packageID] == version {
            replacement = current.installed
                .filter {
                    $0.packageID == packageID
                        && $0.version != version
                        && !(current.recalledVersions[packageID] ?? []).contains($0.version)
                }
                .sorted { $0.installedAt > $1.installedAt }
                .first?
                .version
            if let replacement {
                current.activeVersions[packageID] = replacement
            } else {
                current.activeVersions.removeValue(forKey: packageID)
            }
        }
        try writeIndex(current)
        return replacement
    }

    public func removeInactive(packageID: String, version: String) throws {
        var current = try index()
        guard current.activeVersions[packageID] != version else {
            throw PackageInstallError.cannotRollback
        }
        guard let record = current.installed.first(where: {
            $0.packageID == packageID && $0.version == version
        }) else {
            throw PackageInstallError.packageNotInstalled
        }
        let target = packagesDirectory.appendingPathComponent(
            record.directoryName,
            isDirectory: true
        )
        do {
            try fileManager.removeItem(at: target)
            current.installed.removeAll { $0.id == record.id }
            try writeIndex(current)
        } catch {
            throw PackageInstallError.fileOperationFailed
        }
    }

    public func activePackageDirectory(packageID: String) throws -> URL? {
        let current = try index()
        guard let version = current.activeVersions[packageID],
              !(current.recalledVersions[packageID] ?? []).contains(version),
              let record = current.installed.first(where: {
                  $0.packageID == packageID && $0.version == version
              })
        else { return nil }
        return packagesDirectory.appendingPathComponent(
            record.directoryName,
            isDirectory: true
        )
    }

    private var packagesDirectory: URL {
        rootDirectory.appendingPathComponent("packages", isDirectory: true)
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent("activation-index.json")
    }

    private func ensureRoot() throws {
        do {
            try fileManager.createDirectory(
                at: packagesDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw PackageInstallError.fileOperationFailed
        }
    }

    private func writeIndex(_ index: PackageActivationIndex) throws {
        do {
            let data = try JSONEncoder.trailGuard.encode(index)
            try data.write(to: indexURL, options: [.atomic])
        } catch {
            throw PackageInstallError.fileOperationFailed
        }
    }
}

extension JSONEncoder {
    static var trailGuard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
