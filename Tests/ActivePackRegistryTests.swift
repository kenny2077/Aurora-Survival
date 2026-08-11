import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class ActivePackRegistryTests: XCTestCase {
    func testVerifiedEligibleLiteModelBecomesActive() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: iPhone13ClassDevice()
        )

        XCTAssertEqual(snapshot.models.map(\.id), ["model.lite@1.0.0"])
        XCTAssertEqual(snapshot.installedTiers, [.lite])
        XCTAssertTrue(snapshot.issues.isEmpty)
    }

    func testPolicyMismatchLeavesNoModel() async throws {
        let fixture = try makeFixture(policyVersion: "2.0.0")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [])
        XCTAssertEqual(snapshot.issues, [.policyMismatch(packageID: "model.lite")])
    }

    func testRecalledActiveVersionLeavesNoModel() async throws {
        let fixture = try makeFixture(recalled: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [])
        XCTAssertEqual(
            snapshot.issues,
            [.recalled(packageID: "model.lite", version: "1.0.0")]
        )
    }

    func testPaidLiteRequiresCachedVerifiedEntitlement() async throws {
        let fixture = try makeFixture(productID: "trailguard.lite")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let registry = registry(for: fixture.root)

        let denied = await registry.resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )
        XCTAssertEqual(denied.installedTiers, [])

        let allowed = await registry.resolve(
            cachedEntitlements: [
                EntitlementSnapshot(
                    productID: "trailguard.lite",
                    verified: true,
                    verifiedAt: "2026-07-23T00:00:00Z"
                )
            ],
            device: capableDevice()
        )
        XCTAssertEqual(allowed.installedTiers, [.lite])
    }

    func testLitePackageFailsClosedBelowMemoryGate() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: DeviceSnapshot(
                physicalMemoryBytes: 3_000_000_000,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )

        XCTAssertEqual(snapshot.installedTiers, [])
        XCTAssertEqual(
            snapshot.issues,
            [.deviceIneligible(packageID: "model.lite", tier: .lite)]
        )
    }

    func testExpertPackageRemainsValidationLocked() async throws {
        let fixture = try makeFixture(rawTier: ModelTier.expert.rawValue)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [])
        XCTAssertEqual(
            snapshot.issues,
            [.deviceIneligible(packageID: "model.vision_expert", tier: .expert)]
        )
    }

    func testLegacyFieldPackageIsRejected() async throws {
        let fixture = try makeFixture(rawTier: "field")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let snapshot = await registry(for: fixture.root).resolve(
            cachedEntitlements: [],
            device: capableDevice()
        )

        XCTAssertEqual(snapshot.installedTiers, [])
        XCTAssertEqual(snapshot.issues, [.invalidModelTier(packageID: "model.field")])
    }

    private func registry(for root: URL) -> ActivePackRegistry {
        ActivePackRegistry(
            rootDirectory: root,
            verifier: AcceptingVerifier(),
            appVersion: "1.2.0",
            expectedPolicyVersion: "1.0.0"
        )
    }

    private func makeFixture(
        policyVersion: String = "1.0.0",
        productID: String? = nil,
        recalled: Bool = false,
        rawTier: String = ModelTier.lite.rawValue
    ) throws -> (root: URL, packageDirectory: URL) {
        let packageID = "model.\(rawTier)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardActivePack-\(UUID().uuidString)",
            isDirectory: true
        )
        let packageDirectory = root
            .appendingPathComponent("packages", isDirectory: true)
            .appendingPathComponent("\(packageID)@1.0.0", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: packageDirectory.appendingPathComponent("model.gguf"))

        var metadata = [
            "model_tier": rawTier,
            "model_path": "model.gguf",
            "policy_version": policyVersion,
        ]
        if let productID { metadata["product_id"] = productID }
        let manifest = PackageManifest(
            packageID: packageID,
            version: "1.0.0",
            kind: .model,
            createdAt: "2026-07-23T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "Test-Only",
            displayName: "Test model",
            artifacts: [
                PackageArtifact(
                    path: "model.gguf",
                    byteCount: 5,
                    sha256: String(repeating: "0", count: 64)
                )
            ],
            metadata: metadata
        )
        try JSONEncoder.trailGuard.encode(
            SignedPackageEnvelope(manifest: manifest, keyID: "test", signature: "")
        ).write(to: packageDirectory.appendingPathComponent("envelope.json"))

        let record = InstalledPackageVersion(
            packageID: packageID,
            version: "1.0.0",
            kind: .model,
            displayName: "Test model",
            installedAt: "2026-07-23T00:00:00Z",
            directoryName: "\(packageID)@1.0.0"
        )
        let index = PackageActivationIndex(
            activeVersions: [packageID: "1.0.0"],
            installed: [record],
            recalledVersions: recalled ? [packageID: ["1.0.0"]] : [:]
        )
        try JSONEncoder.trailGuard.encode(index).write(
            to: root.appendingPathComponent("activation-index.json")
        )
        return (root, packageDirectory)
    }

    private func iPhone13ClassDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 4_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }

    private func capableDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 12_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }
}

private struct AcceptingVerifier: PackageEnvelopeVerifying {
    func verify(envelope: SignedPackageEnvelope, packageDirectory: URL) throws {}
}
