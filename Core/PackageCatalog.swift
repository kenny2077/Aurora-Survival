import CryptoKit
import Foundation

public struct PackageCatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(packageID)@\(version)" }

    public let packageID: String
    public let version: String
    public let kind: PackageKind
    public let displayName: String
    public let summary: String
    public let totalByteCount: Int64
    public let envelopePath: String
    public let artifactBasePath: String
    public let metadata: [String: String]

    public init(
        packageID: String,
        version: String,
        kind: PackageKind,
        displayName: String,
        summary: String,
        totalByteCount: Int64,
        envelopePath: String,
        artifactBasePath: String,
        metadata: [String: String] = [:]
    ) {
        self.packageID = packageID
        self.version = version
        self.kind = kind
        self.displayName = displayName
        self.summary = summary
        self.totalByteCount = totalByteCount
        self.envelopePath = envelopePath
        self.artifactBasePath = artifactBasePath
        self.metadata = metadata
    }

    public func remoteLocation(
        relativeTo catalogURL: URL
    ) throws -> RemotePackageLocation {
        guard Self.isSafeRelativePath(envelopePath),
              Self.isSafeRelativePath(artifactBasePath)
        else {
            throw PackageCatalogError.unsafeRemotePath
        }
        let base = catalogURL.deletingLastPathComponent()
        return RemotePackageLocation(
            envelopeURL: Self.appending(envelopePath, to: base),
            artifactBaseURL: Self.appending(artifactBasePath, to: base)
        )
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\0"),
              URL(string: path)?.scheme == nil
        else { return false }
        let components = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private static func appending(_ path: String, to base: URL) -> URL {
        path.split(separator: "/").reduce(base) {
            $0.appendingPathComponent(String($1), isDirectory: false)
        }
    }
}

public struct PackageCatalog: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let entries: [PackageCatalogEntry]

    public init(
        schemaVersion: Int = 1,
        generatedAt: String,
        entries: [PackageCatalogEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.entries = entries
    }

    public var signingPayload: Data {
        var fields = [
            "schema", String(schemaVersion),
            "generated", generatedAt,
        ]
        for entry in entries.sorted(by: {
            ($0.packageID, $0.version) < ($1.packageID, $1.version)
        }) {
            fields.append(contentsOf: [
                "package", entry.packageID,
                "version", entry.version,
                "kind", entry.kind.rawValue,
                "display", entry.displayName,
                "summary", entry.summary,
                "bytes", String(entry.totalByteCount),
                "envelope", entry.envelopePath,
                "artifacts", entry.artifactBasePath,
            ])
            for key in entry.metadata.keys.sorted() {
                fields.append(contentsOf: [
                    "metadata", key, entry.metadata[key] ?? "",
                ])
            }
        }
        let canonical = fields
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "\n")
        return Data(canonical.utf8)
    }
}

public struct SignedPackageCatalog: Codable, Hashable, Sendable {
    public let catalog: PackageCatalog
    public let keyID: String
    public let signature: String

    public init(catalog: PackageCatalog, keyID: String, signature: String) {
        self.catalog = catalog
        self.keyID = keyID
        self.signature = signature
    }
}

public enum PackageCatalogError: Error, Equatable {
    case unsupportedSchema
    case emptyCatalog
    case duplicateEntry
    case invalidEntry
    case unsafeRemotePath
    case unknownSigningKey
    case invalidPublicKey
    case invalidSignature
    case invalidKeyValidityWindow
    case signingKeyNotCurrentlyValid
}

public enum PackageCatalogInstallStatus: Equatable, Sendable {
    case available
    case installed(active: Bool)
    case updateAvailable(installedVersion: String, availableVersion: String)
}

public struct SemanticPackageVersion: Comparable, Equatable, Sendable {
    private let core: [Int]
    private let prerelease: [String]?

    public init?(_ value: String) {
        let pieces = value.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = pieces[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == pieces[0].split(separator: ".").count,
              (2...3).contains(numbers.count) else { return nil }
        core = numbers + Array(repeating: 0, count: 3 - numbers.count)
        prerelease = pieces.count == 2
            ? pieces[1].split(separator: ".").map(String.init)
            : nil
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.core != rhs.core {
            return lhs.core.lexicographicallyPrecedes(rhs.core)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (.some(left), .some(right)):
            for (a, b) in zip(left, right) where a != b {
                if let aNumber = Int(a), let bNumber = Int(b) {
                    return aNumber < bNumber
                }
                if Int(a) != nil { return true }
                if Int(b) != nil { return false }
                return a < b
            }
            return left.count < right.count
        }
    }
}

public struct PackageCatalogInstallStatusResolver: Sendable {
    public init() {}

    public func resolve(
        entry: PackageCatalogEntry,
        index: PackageActivationIndex
    ) -> PackageCatalogInstallStatus {
        if index.installed.contains(where: {
            $0.packageID == entry.packageID && $0.version == entry.version
        }) {
            return .installed(
                active: index.activeVersions[entry.packageID] == entry.version
            )
        }
        if let installedVersion = index.activeVersions[entry.packageID],
           installedVersion != entry.version {
            if let installed = SemanticPackageVersion(installedVersion),
               let available = SemanticPackageVersion(entry.version),
               available > installed {
                return .updateAvailable(
                    installedVersion: installedVersion,
                    availableVersion: entry.version
                )
            }
            return .installed(active: true)
        }
        return .available
    }
}

public struct PackageCatalogVerifier: Sendable {
    private let trustedKeys: [String: TrustedPackageKey]
    private let now: @Sendable () -> Date

    public init(
        trustedKeys: [TrustedPackageKey],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.trustedKeys = Dictionary(
            uniqueKeysWithValues: trustedKeys.map { ($0.id, $0) }
        )
        self.now = now
    }

    public func verify(_ envelope: SignedPackageCatalog) throws -> PackageCatalog {
        let catalog = envelope.catalog
        guard catalog.schemaVersion == 1 else {
            throw PackageCatalogError.unsupportedSchema
        }
        guard !catalog.entries.isEmpty else {
            throw PackageCatalogError.emptyCatalog
        }
        var identities: Set<String> = []
        for entry in catalog.entries {
            guard Self.isSafeIdentifier(entry.packageID),
                  Self.isSafeIdentifier(entry.version),
                  !entry.displayName.isEmpty,
                  entry.totalByteCount >= 0
            else {
                throw PackageCatalogError.invalidEntry
            }
            guard identities.insert(entry.id).inserted else {
                throw PackageCatalogError.duplicateEntry
            }
            _ = try entry.remoteLocation(
                relativeTo: URL(string: "https://catalog.invalid/catalog.json")!
            )
        }
        guard let trustedKey = trustedKeys[envelope.keyID] else {
            throw PackageCatalogError.unknownSigningKey
        }
        let formatter = ISO8601DateFormatter()
        guard let validFrom = formatter.date(from: trustedKey.validFrom),
              trustedKey.validUntil == nil
                || formatter.date(from: trustedKey.validUntil ?? "") != nil
        else {
            throw PackageCatalogError.invalidKeyValidityWindow
        }
        let validUntil = trustedKey.validUntil.flatMap(formatter.date)
        let currentDate = now()
        guard currentDate >= validFrom,
              validUntil.map({ currentDate <= $0 }) ?? true
        else {
            throw PackageCatalogError.signingKeyNotCurrentlyValid
        }
        guard let publicKeyData = Data(
            base64Encoded: trustedKey.publicKeyBase64
        ),
              let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
              )
        else {
            throw PackageCatalogError.invalidPublicKey
        }
        guard let signature = Data(base64Encoded: envelope.signature),
              publicKey.isValidSignature(
                signature,
                for: catalog.signingPayload
              )
        else {
            throw PackageCatalogError.invalidSignature
        }
        return catalog
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
