import Foundation
import TrailGuardCore

enum PackCheckError: Error {
    case usage
    case invalidSnapshot(String)
}

@main
struct TrailGuardPackCheck {
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.count == 4, arguments[1] == "model" {
            try await checkModel(
                keyringURL: URL(fileURLWithPath: arguments[2]),
                source: URL(fileURLWithPath: arguments[3], isDirectory: true)
            )
            return
        }
        if arguments.count == 4, arguments[1] == "catalog" {
            try checkCatalog(
                keyringURL: URL(fileURLWithPath: arguments[2]),
                catalogURL: URL(fileURLWithPath: arguments[3])
            )
            return
        }
        guard arguments.count == 4 else {
            FileHandle.standardError.write(
                Data(
                    (
                        "usage: trailguard-pack-check <keyring.json> <pack-v1> <pack-v2>\n"
                            + "   or: trailguard-pack-check model <keyring.json> <model-pack>\n"
                            + "   or: trailguard-pack-check catalog <keyring.json> <catalog.json>\n"
                    ).utf8
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
            "TrailGuardDevelopmentLifecycle-\(UUID().uuidString)",
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

    private static func checkCatalog(
        keyringURL: URL,
        catalogURL: URL
    ) throws {
        let decoder = JSONDecoder()
        let keys = try decoder.decode(
            [TrustedPackageKey].self,
            from: Data(contentsOf: keyringURL)
        )
        let signed = try decoder.decode(
            SignedPackageCatalog.self,
            from: Data(contentsOf: catalogURL)
        )
        let catalog = try PackageCatalogVerifier(
            trustedKeys: keys
        ).verify(signed)
        let verifier = PackageVerifier(trustedKeys: keys)
        for entry in catalog.entries {
            let location = try entry.remoteLocation(relativeTo: catalogURL)
            let envelope = try decoder.decode(
                SignedPackageEnvelope.self,
                from: Data(contentsOf: location.envelopeURL)
            )
            guard envelope.manifest.packageID == entry.packageID,
                  envelope.manifest.version == entry.version,
                  envelope.manifest.kind == entry.kind,
                  envelope.manifest.artifacts.reduce(Int64(0), {
                      $0 + $1.byteCount
                  }) == entry.totalByteCount
            else {
                throw PackCheckError.invalidSnapshot(
                    "catalog identity mismatch for \(entry.id)"
                )
            }
            try verifier.verify(
                envelope: envelope,
                packageDirectory: location.artifactBaseURL
            )
        }
        print(
            "PASS: signed product catalog and \(catalog.entries.count) package payloads"
        )
    }

    private static func checkModel(
        keyringURL: URL,
        source: URL
    ) async throws {
        let decoder = JSONDecoder()
        let keys = try decoder.decode(
            [TrustedPackageKey].self,
            from: Data(contentsOf: keyringURL)
        )
        let verifier = PackageVerifier(trustedKeys: keys)
        let envelope = try loadEnvelope(from: source, decoder: decoder)
        guard envelope.manifest.kind == .model else {
            throw PackCheckError.invalidSnapshot("expected a model package")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardModelLifecycle-\(UUID().uuidString)",
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
        try await install(
            envelope: envelope,
            source: source,
            stagingName: "stage-model",
            root: root,
            installer: installer
        )

        let snapshot = await registry(root: root, verifier: verifier).resolve(
            cachedEntitlements: [],
            device: DeviceSnapshot(
                physicalMemoryBytes: 4_000_000_000,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )
        let runtime = ActiveModelRuntimeResolver().resolve(activePacks: snapshot)
        let expectedID = "\(envelope.manifest.packageID)@\(envelope.manifest.version)"
        guard snapshot.models.map(\.id) == [expectedID],
              snapshot.installedTiers == [.essential, .lite],
              snapshot.issues.isEmpty,
              runtime.descriptors[.lite] != nil,
              runtime.issues.isEmpty else {
            throw PackCheckError.invalidSnapshot(
                "model package did not reach the verified Lite runtime boundary"
            )
        }

        print(
            "PASS: signed Lite model lifecycle "
                + "(verification, install, activation, registry, runtime gate)"
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
