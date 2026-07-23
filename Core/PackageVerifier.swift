import CryptoKit
import Foundation

public enum PackageVerificationError: Error, Equatable {
    case unsupportedSchema
    case unknownSigningKey
    case invalidPublicKey
    case invalidSignature
    case invalidKeyValidityWindow
    case signingKeyNotCurrentlyValid
    case invalidPackageIdentity
    case emptyPackage
    case duplicateArtifactPath(String)
    case unsafeArtifactPath(String)
    case missingArtifact(String)
    case artifactIsNotRegularFile(String)
    case byteCountMismatch(String)
    case checksumMismatch(String)
}

public struct PackageVerifier: Sendable {
    private let trustedKeys: [String: TrustedPackageKey]
    private let now: @Sendable () -> Date

    public init(
        trustedKeys: [TrustedPackageKey],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.trustedKeys = Dictionary(uniqueKeysWithValues: trustedKeys.map { ($0.id, $0) })
        self.now = now
    }

    public func verify(
        envelope: SignedPackageEnvelope,
        packageDirectory: URL
    ) throws {
        let manifest = envelope.manifest
        guard manifest.schemaVersion == 1 else {
            throw PackageVerificationError.unsupportedSchema
        }
        guard Self.isSafeIdentifier(manifest.packageID),
              Self.isSafeIdentifier(manifest.version)
        else {
            throw PackageVerificationError.invalidPackageIdentity
        }
        guard !manifest.artifacts.isEmpty else {
            throw PackageVerificationError.emptyPackage
        }
        var seenPaths: Set<String> = []
        for artifact in manifest.artifacts {
            guard seenPaths.insert(artifact.path).inserted else {
                throw PackageVerificationError.duplicateArtifactPath(artifact.path)
            }
        }
        guard let trustedKey = trustedKeys[envelope.keyID] else {
            throw PackageVerificationError.unknownSigningKey
        }
        let formatter = ISO8601DateFormatter()
        guard let validFrom = formatter.date(from: trustedKey.validFrom),
              trustedKey.validUntil == nil
                || formatter.date(from: trustedKey.validUntil ?? "") != nil
        else {
            throw PackageVerificationError.invalidKeyValidityWindow
        }
        let validUntil = trustedKey.validUntil.flatMap(formatter.date)
        let currentDate = now()
        if currentDate < validFrom {
            throw PackageVerificationError.signingKeyNotCurrentlyValid
        }
        if let validUntil, currentDate > validUntil {
            throw PackageVerificationError.signingKeyNotCurrentlyValid
        }
        guard let publicKeyData = Data(base64Encoded: trustedKey.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        else {
            throw PackageVerificationError.invalidPublicKey
        }
        guard let signature = Data(base64Encoded: envelope.signature),
              publicKey.isValidSignature(signature, for: manifest.signingPayload)
        else {
            throw PackageVerificationError.invalidSignature
        }

        let root = packageDirectory.standardizedFileURL
        for artifact in manifest.artifacts {
            let fileURL = try Self.safeArtifactURL(path: artifact.path, root: root)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                throw PackageVerificationError.missingArtifact(artifact.path)
            }
            guard !isDirectory.boolValue,
                  let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else {
                throw PackageVerificationError.artifactIsNotRegularFile(artifact.path)
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let actualBytes = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard actualBytes == artifact.byteCount else {
                throw PackageVerificationError.byteCountMismatch(artifact.path)
            }

            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: data)
            let actualHash = digest.map { String(format: "%02x", $0) }.joined()
            guard actualHash == artifact.sha256 else {
                throw PackageVerificationError.checksumMismatch(artifact.path)
            }
        }
    }

    public static func safeArtifactURL(path: String, root: URL) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\0")
        else {
            throw PackageVerificationError.unsafeArtifactPath(path)
        }
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw PackageVerificationError.unsafeArtifactPath(path)
        }

        let candidate = components.reduce(root.standardizedFileURL) {
            $0.appendingPathComponent(String($1), isDirectory: false)
        }.standardizedFileURL
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw PackageVerificationError.unsafeArtifactPath(path)
        }
        return candidate
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}
