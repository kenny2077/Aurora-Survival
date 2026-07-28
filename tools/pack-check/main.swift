import Foundation
import AuroraCore

enum PackCheckError: Error {
    case usage
    case invalidSnapshot(String)
}

@main
struct AuroraPackCheck {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            FileHandle.standardError.write(
                Data(
                    "usage: trailguard-pack-check <keyring.json> <pack-v1> <pack-v2>\n".utf8
                )
            )
            throw PackCheckError.usage
        }

        let decoder = JSONDecoder()
        let keyringURL = URL(fileURLWithPath: arguments[1])
        let sourceV1 = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let sourceV2 = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let keys = try decoder.decode(
            [TrustedPackageKey].self,
            from: Data(contentsOf: keyringURL)
        )
        let verifier = PackageVerifier(trustedKeys: keys)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraDevelopmentLifecycle-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let installer = PackageInstaller(
            rootDirectory: root,
            verifier: verifier,
            now: { Date(timeIntervalSince1970: 1_753_660_800) }
        )
        let envelopeV1 = try loadEnvelope(from: sourceV1, decoder: decoder)
        let envelopeV2 = try loadEnvelope(from: sourceV2, decoder: decoder)

        try await install(
            envelope: envelopeV1,
            source: sourceV1,
            stagingName: "stage-v1",
            root: root,
            installer: installer
        )
        try await assertActive(
            version: "1.0.0",
            root: root,
            verifier: verifier
        )

        try await install(
            envelope: envelopeV2,
            source: sourceV2,
            stagingName: "stage-v2",
            root: root,
            installer: installer
        )
        try await assertActive(
            version: "1.1.0",
            root: root,
            verifier: verifier
        )

        let rolledBack = try await installer.rollback(
            packageID: envelopeV1.manifest.packageID
        )
        guard rolledBack == "1.0.0" else {
            throw PackCheckError.invalidSnapshot("rollback did not select v1")
        }

        try await installer.activate(
            packageID: envelopeV1.manifest.packageID,
            version: "1.1.0"
        )
        let replacement = try await installer.recall(
            packageID: envelopeV1.manifest.packageID,
            version: "1.1.0"
        )
        guard replacement == "1.0.0" else {
            throw PackCheckError.invalidSnapshot("recall did not fail over to v1")
        }
        try await assertActive(
            version: "1.0.0",
            root: root,
            verifier: verifier
        )

        guard let activeDirectory = try await installer.activePackageDirectory(
            packageID: envelopeV1.manifest.packageID
        ) else {
            throw PackCheckError.invalidSnapshot("active package directory missing")
        }
        let contentURL = activeDirectory.appendingPathComponent("content.sqlite")
        let handle = try FileHandle(forWritingTo: contentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        let rejected = await registry(root: root, verifier: verifier).resolve(
            cachedEntitlements: [],
            device: capableDevice
        )
        guard rejected.knowledge.isEmpty,
              rejected.issues.contains(
                .verificationFailed(packageID: envelopeV1.manifest.packageID)
              )
        else {
            throw PackCheckError.invalidSnapshot("tampered active pack was not rejected")
        }

        print(
            "PASS: signed development knowledge lifecycle "
                + "(install v1/v2, activation, rollback, recall, tamper rejection)"
        )
    }

    private static func loadEnvelope(
        from directory: URL,
        decoder: JSONDecoder
    ) throws -> SignedPackageEnvelope {
        try decoder.decode(
            SignedPackageEnvelope.self,
            from: Data(
                contentsOf: directory.appendingPathComponent("envelope.json")
            )
        )
    }

    private static func install(
        envelope: SignedPackageEnvelope,
        source: URL,
        stagingName: String,
        root: URL,
        installer: PackageInstaller
    ) async throws {
        let staging = root.appendingPathComponent(stagingName, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: staging)
        try await installer.install(
            envelope: envelope,
            stagedDirectory: staging
        )
    }

    private static func assertActive(
        version: String,
        root: URL,
        verifier: PackageVerifier
    ) async throws {
        let snapshot = await registry(root: root, verifier: verifier).resolve(
            cachedEntitlements: [],
            device: capableDevice
        )
        guard snapshot.knowledge.map(\.manifest.version) == [version],
              snapshot.issues.isEmpty
        else {
            throw PackCheckError.invalidSnapshot(
                "expected active knowledge version \(version)"
            )
        }
    }

    private static func registry(
        root: URL,
        verifier: PackageVerifier
    ) -> ActivePackRegistry {
        ActivePackRegistry(
            rootDirectory: root,
            verifier: verifier,
            appVersion: "1.0.0",
            expectedPolicyVersion: "deterministic-policy-v1",
            allowDevelopmentKnowledge: true
        )
    }

    private static let capableDevice = DeviceSnapshot(
        physicalMemoryBytes: 8_000_000_000,
        freeStorageBytes: 20_000_000_000,
        thermalCondition: .nominal,
        isLowPowerMode: false
    )
}
