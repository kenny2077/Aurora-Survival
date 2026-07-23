import Foundation

public enum PackageKind: String, Codable, CaseIterable, Sendable {
    case model
    case knowledge
    case map
}

public struct PackageArtifact: Codable, Hashable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String

    public init(path: String, byteCount: Int64, sha256: String) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256.lowercased()
    }
}

public struct PackageManifest: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let packageID: String
    public let version: String
    public let kind: PackageKind
    public let createdAt: String
    public let minimumAppVersion: String
    public let licenseIdentifier: String
    public let displayName: String
    public let artifacts: [PackageArtifact]
    public let metadata: [String: String]

    public init(
        schemaVersion: Int = 1,
        packageID: String,
        version: String,
        kind: PackageKind,
        createdAt: String,
        minimumAppVersion: String,
        licenseIdentifier: String,
        displayName: String,
        artifacts: [PackageArtifact],
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.version = version
        self.kind = kind
        self.createdAt = createdAt
        self.minimumAppVersion = minimumAppVersion
        self.licenseIdentifier = licenseIdentifier
        self.displayName = displayName
        self.artifacts = artifacts
        self.metadata = metadata
    }

    /// A deliberately small canonical format prevents JSON key-order differences
    /// from changing the signed bytes. Fields are length-prefixed to avoid
    /// delimiter ambiguity.
    public var signingPayload: Data {
        var fields = [
            "schema", String(schemaVersion),
            "package", packageID,
            "version", version,
            "kind", kind.rawValue,
            "created", createdAt,
            "minimumApp", minimumAppVersion,
            "license", licenseIdentifier,
            "display", displayName
        ]

        for artifact in artifacts.sorted(by: { $0.path < $1.path }) {
            fields.append(contentsOf: [
                "artifact", artifact.path,
                "bytes", String(artifact.byteCount),
                "sha256", artifact.sha256
            ])
        }
        for key in metadata.keys.sorted() {
            fields.append(contentsOf: ["metadata", key, metadata[key] ?? ""])
        }

        let canonical = fields
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "\n")
        return Data(canonical.utf8)
    }
}

public struct SignedPackageEnvelope: Codable, Hashable, Sendable {
    public let manifest: PackageManifest
    public let keyID: String
    public let signature: String

    public init(manifest: PackageManifest, keyID: String, signature: String) {
        self.manifest = manifest
        self.keyID = keyID
        self.signature = signature
    }
}

public struct TrustedPackageKey: Codable, Hashable, Sendable {
    public let id: String
    public let publicKeyBase64: String
    public let validFrom: String
    public let validUntil: String?

    public init(
        id: String,
        publicKeyBase64: String,
        validFrom: String,
        validUntil: String? = nil
    ) {
        self.id = id
        self.publicKeyBase64 = publicKeyBase64
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}
