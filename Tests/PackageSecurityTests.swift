import CryptoKit
import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class PackageSecurityTests: XCTestCase {
    func testValidSignedPackagePassesVerification() throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertNoThrow(
            try fixture.verifier.verify(
                envelope: fixture.envelope,
                packageDirectory: fixture.staging
            )
        )
    }

    func testTamperedArtifactFailsChecksum() throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("tampered".utf8).write(
            to: fixture.staging.appendingPathComponent("weights/model.gguf")
        )

        XCTAssertThrowsError(
            try fixture.verifier.verify(
                envelope: fixture.envelope,
                packageDirectory: fixture.staging
            )
        ) { error in
            XCTAssertTrue(
                error == PackageVerificationError.byteCountMismatch("weights/model.gguf")
                    || error == PackageVerificationError.checksumMismatch("weights/model.gguf")
            )
        }
    }

    func testInvalidSignatureIsRejected() throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let invalid = SignedPackageEnvelope(
            manifest: fixture.envelope.manifest,
            keyID: fixture.envelope.keyID,
            signature: Data(repeating: 0, count: 64).base64EncodedString()
        )

        XCTAssertThrowsError(
            try fixture.verifier.verify(
                envelope: invalid,
                packageDirectory: fixture.staging
            )
        ) { error in
            XCTAssertEqual(error as? PackageVerificationError, .invalidSignature)
        }
    }

    func testExpiredSigningKeyIsRejected() throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let expiredKey = TrustedPackageKey(
            id: fixture.envelope.keyID,
            publicKeyBase64: fixture.privateKey.publicKey.rawRepresentation.base64EncodedString(),
            validFrom: "2025-01-01T00:00:00Z",
            validUntil: "2025-12-31T23:59:59Z"
        )
        let verifier = PackageVerifier(trustedKeys: [expiredKey]) {
            ISO8601DateFormatter().date(from: "2026-07-23T00:00:00Z")!
        }

        XCTAssertThrowsError(
            try verifier.verify(
                envelope: fixture.envelope,
                packageDirectory: fixture.staging
            )
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .signingKeyNotCurrentlyValid
            )
        }
    }

    func testDuplicateArtifactPathIsRejected() throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = try XCTUnwrap(fixture.envelope.manifest.artifacts.first)
        let manifest = PackageManifest(
            packageID: fixture.envelope.manifest.packageID,
            version: fixture.envelope.manifest.version,
            kind: fixture.envelope.manifest.kind,
            createdAt: fixture.envelope.manifest.createdAt,
            minimumAppVersion: fixture.envelope.manifest.minimumAppVersion,
            licenseIdentifier: fixture.envelope.manifest.licenseIdentifier,
            displayName: fixture.envelope.manifest.displayName,
            artifacts: [original, original]
        )
        let signature = try fixture.privateKey.signature(for: manifest.signingPayload)
        let duplicate = SignedPackageEnvelope(
            manifest: manifest,
            keyID: fixture.envelope.keyID,
            signature: signature.base64EncodedString()
        )

        XCTAssertThrowsError(
            try fixture.verifier.verify(
                envelope: duplicate,
                packageDirectory: fixture.staging
            )
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .duplicateArtifactPath(original.path)
            )
        }
    }

    func testTraversalPathIsRejected() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try PackageVerifier.safeArtifactURL(path: "../escape.gguf", root: root)
        ) { error in
            XCTAssertEqual(
                error as? PackageVerificationError,
                .unsafeArtifactPath("../escape.gguf")
            )
        }
    }

    func testInstallActivatesAndRollbackReturnsPreviousVersion() async throws {
        let first = try makeFixture(version: "1.0.0", content: Data("v1".utf8))
        defer { try? FileManager.default.removeItem(at: first.root) }
        let store = first.root.appendingPathComponent("store", isDirectory: true)
        let installer = PackageInstaller(
            rootDirectory: store,
            verifier: first.verifier,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        _ = try await installer.install(
            envelope: first.envelope,
            stagedDirectory: first.staging
        )

        let secondStaging = first.root.appendingPathComponent("stage-v2", isDirectory: true)
        let second = try makeSignedPackage(
            staging: secondStaging,
            packageID: "model.field",
            version: "2.0.0",
            content: Data("v2".utf8),
            keyID: first.envelope.keyID,
            privateKey: first.privateKey
        )
        _ = try await installer.install(
            envelope: second,
            stagedDirectory: secondStaging
        )

        var index = try await installer.index()
        XCTAssertEqual(index.activeVersions["model.field"], "2.0.0")

        let rolledBack = try await installer.rollback(packageID: "model.field")
        XCTAssertEqual(rolledBack, "1.0.0")
        index = try await installer.index()
        XCTAssertEqual(index.activeVersions["model.field"], "1.0.0")
    }

    func testCannotDeleteActiveVersion() async throws {
        let fixture = try makeFixture(version: "1.0.0", content: Data("model".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let installer = PackageInstaller(
            rootDirectory: fixture.root.appendingPathComponent("store"),
            verifier: fixture.verifier
        )
        _ = try await installer.install(
            envelope: fixture.envelope,
            stagedDirectory: fixture.staging
        )

        do {
            try await installer.removeInactive(packageID: "model.field", version: "1.0.0")
            XCTFail("Expected active-version deletion to be blocked")
        } catch {
            XCTAssertEqual(error as? PackageInstallError, .cannotRollback)
        }
    }

    func testRecallFailsOverAndBlocksReactivation() async throws {
        let first = try makeFixture(version: "1.0.0", content: Data("v1".utf8))
        defer { try? FileManager.default.removeItem(at: first.root) }
        let installer = PackageInstaller(
            rootDirectory: first.root.appendingPathComponent("store"),
            verifier: first.verifier,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        _ = try await installer.install(
            envelope: first.envelope,
            stagedDirectory: first.staging
        )

        let secondStaging = first.root.appendingPathComponent("stage-v2", isDirectory: true)
        let second = try makeSignedPackage(
            staging: secondStaging,
            packageID: "model.field",
            version: "2.0.0",
            content: Data("v2".utf8),
            keyID: first.envelope.keyID,
            privateKey: first.privateKey
        )
        _ = try await installer.install(
            envelope: second,
            stagedDirectory: secondStaging
        )

        let replacement = try await installer.recall(
            packageID: "model.field",
            version: "2.0.0"
        )
        XCTAssertEqual(replacement, "1.0.0")
        let index = try await installer.index()
        XCTAssertEqual(index.activeVersions["model.field"], "1.0.0")
        XCTAssertTrue(index.recalledVersions["model.field"]?.contains("2.0.0") == true)

        do {
            try await installer.activate(packageID: "model.field", version: "2.0.0")
            XCTFail("Expected recalled package activation to fail")
        } catch {
            XCTAssertEqual(error as? PackageInstallError, .recalledPackage)
        }
    }

    func testLegacyActivationIndexDecodesWithoutRecallField() throws {
        let data = Data(
            #"{"activeVersions":{},"installed":[]}"#.utf8
        )
        let index = try JSONDecoder().decode(PackageActivationIndex.self, from: data)
        XCTAssertTrue(index.recalledVersions.isEmpty)
    }

    private struct Fixture {
        let root: URL
        let staging: URL
        let envelope: SignedPackageEnvelope
        let privateKey: Curve25519.Signing.PrivateKey
        let verifier: PackageVerifier
    }

    private func makeFixture(version: String, content: Data) throws -> Fixture {
        let root = temporaryDirectory()
        let staging = root.appendingPathComponent("stage-\(version)", isDirectory: true)
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyID = "test-key"
        let envelope = try makeSignedPackage(
            staging: staging,
            packageID: "model.field",
            version: version,
            content: content,
            keyID: keyID,
            privateKey: privateKey
        )
        let key = TrustedPackageKey(
            id: keyID,
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            validFrom: "2026-01-01T00:00:00Z"
        )
        return Fixture(
            root: root,
            staging: staging,
            envelope: envelope,
            privateKey: privateKey,
            verifier: PackageVerifier(trustedKeys: [key])
        )
    }

    private func makeSignedPackage(
        staging: URL,
        packageID: String,
        version: String,
        content: Data,
        keyID: String,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> SignedPackageEnvelope {
        let artifactPath = "weights/model.gguf"
        let artifactURL = staging.appendingPathComponent(artifactPath)
        try FileManager.default.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: artifactURL)
        let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let manifest = PackageManifest(
            packageID: packageID,
            version: version,
            kind: .model,
            createdAt: "2026-07-23T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "Apache-2.0",
            displayName: "Field Model",
            artifacts: [
                PackageArtifact(
                    path: artifactPath,
                    byteCount: Int64(content.count),
                    sha256: hash
                )
            ],
            metadata: ["tier": "field"]
        )
        let signature = try privateKey.signature(for: manifest.signingPayload)
        return SignedPackageEnvelope(
            manifest: manifest,
            keyID: keyID,
            signature: signature.base64EncodedString()
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
