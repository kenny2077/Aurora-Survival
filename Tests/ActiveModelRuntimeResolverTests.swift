import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ActiveModelRuntimeResolverTests: XCTestCase {
    func testVerifiedLiteArtifactResolvesConservativeRuntime() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.issues.isEmpty)
        let descriptor = try XCTUnwrap(resolution.descriptors[.lite])
        XCTAssertEqual(descriptor.modelURL, fixture.modelURL)
        XCTAssertEqual(descriptor.contextTokens, 2_048)
        XCTAssertEqual(descriptor.maximumOutputTokens, 128)
    }

    func testMetadataCannotSelectUnverifiedArtifact() throws {
        let fixture = try makeFixture(
            modelPath: "weights/unverified.gguf",
            artifactPath: "weights/verified.gguf"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.descriptors.isEmpty)
        XCTAssertEqual(
            resolution.issues,
            [.unverifiedModelPath(packageID: "model.lite.gemma3-1b-q4km")]
        )
    }

    func testUnsupportedLiteConfigurationFailsClosed() throws {
        let fixture = try makeFixture(contextTokens: "4096")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.descriptors.isEmpty)
        XCTAssertEqual(
            resolution.issues,
            [.unsupportedConfiguration(packageID: "model.lite.gemma3-1b-q4km")]
        )
    }

    func testFormerPhiLitePackageFailsClosed() throws {
        let fixture = try makeFixture(
            modelIdentity: "bartowski/Phi-3.5-mini-instruct-GGUF@6d70da17"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.descriptors.isEmpty)
        XCTAssertEqual(
            resolution.issues,
            [.unsupportedConfiguration(packageID: "model.lite.gemma3-1b-q4km")]
        )
    }

    func testUnsafeModelPathFailsClosed() throws {
        let unsafeName = "AuroraOutside-\(UUID().uuidString).gguf"
        let fixture = try makeFixture(
            modelPath: "../\(unsafeName)",
            artifactPath: "../\(unsafeName)"
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.root)
            try? FileManager.default.removeItem(at: fixture.modelURL)
        }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.descriptors.isEmpty)
        XCTAssertEqual(
            resolution.issues,
            [.unsafeModelPath(packageID: "model.lite.gemma3-1b-q4km")]
        )
    }

    private func snapshot(
        package: ResolvedActivePackage
    ) -> ActivePackSnapshot {
        ActivePackSnapshot(
            models: [package],
            knowledge: [],
            maps: [],
            installedTiers: [.essential, .lite],
            issues: []
        )
    }

    private func makeFixture(
        modelPath: String = "weights/model.gguf",
        artifactPath: String = "weights/model.gguf",
        contextTokens: String = "2048",
        modelIdentity: String = ActiveModelRuntimeResolver.acceptedLiteModelIdentity
    ) throws -> (
        root: URL,
        modelURL: URL,
        package: ResolvedActivePackage
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraModelRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        let modelURL = root.appendingPathComponent(modelPath)
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: modelURL)
        let manifest = PackageManifest(
            packageID: "model.lite.gemma3-1b-q4km",
            version: "1.0.0",
            kind: .model,
            createdAt: "2026-07-30T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "LicenseRef-Gemma-Terms-2026-04-01",
            displayName: "Lite test model",
            artifacts: [
                PackageArtifact(
                    path: artifactPath,
                    byteCount: 5,
                    sha256: String(repeating: "0", count: 64)
                )
            ],
            metadata: [
                "model_tier": "lite",
                "model_path": modelPath,
                "model_identity": modelIdentity,
                "model_family": "gemma3",
                "quantization": "Q4_K_M",
                "runtime_release": "b9637",
                "chat_template": "embedded",
                "context_tokens": contextTokens,
                "maximum_output_tokens": "128",
            ]
        )
        return (
            root,
            modelURL,
            ResolvedActivePackage(manifest: manifest, directory: root)
        )
    }
}
