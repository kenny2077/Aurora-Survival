import CryptoKit
import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class PackageCatalogTests: XCTestCase {
    func testSignedCatalogVerifiesAndResolvesSameHostLocations() throws {
        let fixture = try makeFixture()
        let verified = try fixture.verifier.verify(fixture.envelope)

        let entry = try XCTUnwrap(verified.entries.first)
        let location = try entry.remoteLocation(
            relativeTo: URL(string: "http://192.168.1.8:8765/catalog.json")!
        )
        XCTAssertEqual(
            location.envelopeURL.absoluteString,
            "http://192.168.1.8:8765/packages/model-lite/envelope.json"
        )
        XCTAssertEqual(
            location.artifactBaseURL.absoluteString,
            "http://192.168.1.8:8765/packages/model-lite/artifacts"
        )
    }

    func testCatalogSignatureRejectsTamperedEntry() throws {
        let fixture = try makeFixture()
        let original = try XCTUnwrap(fixture.envelope.catalog.entries.first)
        let tampered = PackageCatalogEntry(
            packageID: original.packageID,
            version: original.version,
            kind: original.kind,
            displayName: original.displayName,
            summary: original.summary,
            totalByteCount: original.totalByteCount + 1,
            envelopePath: original.envelopePath,
            artifactBasePath: original.artifactBasePath,
            metadata: original.metadata
        )
        let envelope = SignedPackageCatalog(
            catalog: PackageCatalog(
                generatedAt: fixture.envelope.catalog.generatedAt,
                entries: [tampered]
            ),
            keyID: fixture.envelope.keyID,
            signature: fixture.envelope.signature
        )

        XCTAssertThrowsError(try fixture.verifier.verify(envelope)) { error in
            XCTAssertEqual(error as? PackageCatalogError, .invalidSignature)
        }
    }

    func testCatalogRejectsTraversalBeforeSignatureAcceptance() throws {
        let fixture = try makeFixture(envelopePath: "../envelope.json")

        XCTAssertThrowsError(try fixture.verifier.verify(fixture.envelope)) { error in
            XCTAssertEqual(error as? PackageCatalogError, .unsafeRemotePath)
        }
    }

    private struct Fixture {
        let envelope: SignedPackageCatalog
        let verifier: PackageCatalogVerifier
    }

    private func makeFixture(
        envelopePath: String = "packages/model-lite/envelope.json"
    ) throws -> Fixture {
        let catalog = PackageCatalog(
            generatedAt: "2026-07-31T00:00:00Z",
            entries: [
                PackageCatalogEntry(
                    packageID: "model.lite.gemma3-1b-q4km",
                    version: "1.0.0",
                    kind: .model,
                    displayName: "Lite Offline Intelligence",
                    summary: "Gemma 3 1B release candidate for iPhone 13.",
                    totalByteCount: 806_058_240,
                    envelopePath: envelopePath,
                    artifactBasePath: "packages/model-lite/artifacts",
                    metadata: ["tier": "lite"]
                )
            ]
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let envelope = SignedPackageCatalog(
            catalog: catalog,
            keyID: "test-key",
            signature: try privateKey.signature(
                for: catalog.signingPayload
            ).base64EncodedString()
        )
        let trustedKey = TrustedPackageKey(
            id: "test-key",
            publicKeyBase64: privateKey.publicKey.rawRepresentation
                .base64EncodedString(),
            validFrom: "2026-01-01T00:00:00Z"
        )
        return Fixture(
            envelope: envelope,
            verifier: PackageCatalogVerifier(
                trustedKeys: [trustedKey],
                now: {
                    ISO8601DateFormatter().date(
                        from: "2026-07-31T00:00:00Z"
                    )!
                }
            )
        )
    }
}
