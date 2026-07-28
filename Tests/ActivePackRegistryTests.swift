import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ActivePackRegistryTests: XCTestCase {
    func testVerifiedEligibleModelBecomesActive() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let registry = ActivePackRegistry(
            rootDirectory: fixture.root,
            verifier: AcceptingVerifier(),
            appVersion: "1.2.0",
            expectedPolicyVersion: "1.0.0"
        )
        let snapshot = await registry.resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.models.map(\.id), ["model.field@1.0.0"])
        XCTAssertEqual(snapshot.installedTiers, [.essential, .field])
        XCTAssertTrue(snapshot.issues.isEmpty)
    }

    func testPolicyMismatchFailsClosedToEssential() async throws {
        let fixture = try makeFixture(policyVersion: "2.0.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let registry = ActivePackRegistry(
            rootDirectory: fixture.root,
            verifier: AcceptingVerifier(),
            appVersion: "1.2.0",
            expectedPolicyVersion: "1.0.0"
        )
        let snapshot = await registry.resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [.essential])
        XCTAssertEqual(
            snapshot.issues,
            [.policyMismatch(packageID: "model.field")]
        )
    }

    func testRecalledActiveVersionFailsClosed() async throws {
        let fixture = try makeFixture(recalled: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let registry = ActivePackRegistry(
            rootDirectory: fixture.root,
            verifier: AcceptingVerifier(),
            appVersion: "1.2.0",
            expectedPolicyVersion: "1.0.0"
        )
        let snapshot = await registry.resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [.essential])
        XCTAssertEqual(
            snapshot.issues,
            [.recalled(packageID: "model.field", version: "1.0.0")]
        )
    }

    func testPaidModelRequiresCachedVerifiedEntitlement() async throws {
        let fixture = try makeFixture(productID: "trailguard.field")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let registry = ActivePackRegistry(
            rootDirectory: fixture.root,
            verifier: AcceptingVerifier(),
            appVersion: "1.2.0",
            expectedPolicyVersion: "1.0.0"
        )
        let denied = await registry.resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )
        XCTAssertEqual(denied.installedTiers, [.essential])

        let allowed = await registry.resolve(
            cachedEntitlements: [
                EntitlementSnapshot(
                    productID: "trailguard.field",
                    verified: true,
                    verifiedAt: "2026-07-23T00:00:00Z"
                )
            ],
            device: capableDevice()
        )
        XCTAssertTrue(allowed.installedTiers.contains(.field))
    }

    private func makeFixture(
        policyVersion: String = "1.0.0",
        productID: String? = nil,
        recalled: Bool = false
    ) throws -> (root: URL, packageDirectory: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraActivePack-\(UUID().uuidString)",
            isDirectory: true
        )
        let packageDirectory = root
            .appendingPathComponent("packages", isDirectory: true)
            .appendingPathComponent("model.field@1.0.0", isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageDirectory,
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(
            to: packageDirectory.appendingPathComponent("model.gguf")
        )

        var metadata = [
            "model_tier": "field",
            "model_path": "model.gguf",
            "policy_version": policyVersion,
        ]
        if let productID {
            metadata["product_id"] = productID
        }
        let manifest = PackageManifest(
            packageID: "model.field",
            version: "1.0.0",
            kind: .model,
            createdAt: "2026-07-23T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "Test-Only",
            displayName: "Field test model",
            artifacts: [
                PackageArtifact(
                    path: "model.gguf",
                    byteCount: 5,
                    sha256: String(repeating: "0", count: 64)
                )
            ],
            metadata: metadata
        )
        let envelope = SignedPackageEnvelope(
            manifest: manifest,
            keyID: "test",
            signature: ""
        )
        try JSONEncoder.trailGuard.encode(envelope).write(
            to: packageDirectory.appendingPathComponent("envelope.json")
        )

        let record = InstalledPackageVersion(
            packageID: "model.field",
            version: "1.0.0",
            kind: .model,
            displayName: "Field test model",
            installedAt: "2026-07-23T00:00:00Z",
            directoryName: "model.field@1.0.0"
        )
        let index = PackageActivationIndex(
            activeVersions: ["model.field": "1.0.0"],
            installed: [record],
            recalledVersions: recalled
                ? ["model.field": ["1.0.0"]]
                : [:]
        )
        try JSONEncoder.trailGuard.encode(index).write(
            to: root.appendingPathComponent("activation-index.json")
        )
        return (root, packageDirectory)
    }

    private func capableDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }
}

private struct AcceptingVerifier: PackageEnvelopeVerifying {
    func verify(
        envelope: SignedPackageEnvelope,
        packageDirectory: URL
    ) throws {}
}
