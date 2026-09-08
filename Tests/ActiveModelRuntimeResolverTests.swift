import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ActiveModelRuntimeResolverTests: XCTestCase {
    func testExpertRequiresExplicitDevelopmentGate() throws {
        let fixture = try makeExpertFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertNil(resolution.descriptors[.expert])
        XCTAssertEqual(
            resolution.issues,
            [.unsupportedTier(packageID: "model.expert.qwen3vl", tier: .expert)]
        )
    }

    func testVerifiedExpertPairResolvesAdaptiveMemoryProfileInDevelopment() throws {
        let fixture = try makeExpertFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertTrue(resolution.issues.isEmpty)
        let descriptor = try XCTUnwrap(resolution.descriptors[.expert])
        XCTAssertEqual(descriptor.modelURL, fixture.modelURL)
        XCTAssertEqual(descriptor.visionProjectorURL, fixture.projectorURL)
        XCTAssertNil(descriptor.embeddingModelURL)
        XCTAssertEqual(descriptor.contextTokens, 8_192)
        XCTAssertEqual(descriptor.maximumOutputTokens, 256)
        XCTAssertEqual(descriptor.expertMemoryProfileStatus, .retained)
        XCTAssertEqual(
            descriptor.expertMemoryProfile?.measuredPeakBytes[.balanced],
            4_000_000_000
        )
    }

    func testCalibrationExpertIsIsolatedFromNormalRuntimeDescriptors() throws {
        let fixture = try makeExpertFixture(
            memoryProfileStatus: .calibration,
            includesPeakMeasurements: false
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertNil(resolution.descriptors[.expert])
        let descriptor = try XCTUnwrap(resolution.calibrationExpertDescriptor)
        XCTAssertEqual(descriptor.expertMemoryProfileStatus, .calibration)
        XCTAssertNil(descriptor.expertMemoryProfile)
        XCTAssertEqual(descriptor.visionProjectorURL, fixture.projectorURL)
        XCTAssertTrue(resolution.issues.isEmpty)
    }

    func testCalibrationExpertRejectsGuessedPeakMeasurements() throws {
        let fixture = try makeExpertFixture(memoryProfileStatus: .calibration)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertNil(resolution.calibrationExpertDescriptor)
        XCTAssertEqual(
            resolution.issues,
            [.unsupportedConfiguration(packageID: "model.expert.qwen3vl")]
        )
    }

    func testRetainedExpertRequiresAllPeakMeasurements() throws {
        let fixture = try makeExpertFixture(includesPeakMeasurements: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertNil(resolution.descriptors[.expert])
        XCTAssertEqual(
            resolution.issues,
            [.unsupportedConfiguration(packageID: "model.expert.qwen3vl")]
        )
    }

    func testExpertRejectsProjectorNotCoveredByManifest() throws {
        let fixture = try makeExpertFixture(includeProjectorArtifact: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertNil(resolution.descriptors[.expert])
        XCTAssertEqual(
            resolution.issues,
            [.unverifiedProjectorPath(packageID: "model.expert.qwen3vl")]
        )
    }

    func testExpertUsesSharedRAGDependencyWithoutEmbeddedEmbeddingArtifact() throws {
        let fixture = try makeExpertFixture(includeEmbeddingArtifact: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver(
            allowDevelopmentExpert: true
        ).resolve(activePacks: snapshot(package: fixture.package))

        XCTAssertNotNil(resolution.descriptors[.expert])
        XCTAssertTrue(resolution.issues.isEmpty)
    }

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
        XCTAssertEqual(descriptor.maximumOutputTokens, 256)
    }

    func testLegacyLiteTokenLimitRemainsLoadable() throws {
        let fixture = try makeFixture(maximumOutputTokens: "160")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let resolution = ActiveModelRuntimeResolver().resolve(
            activePacks: snapshot(package: fixture.package)
        )

        XCTAssertTrue(resolution.issues.isEmpty)
        XCTAssertEqual(resolution.descriptors[.lite]?.maximumOutputTokens, 160)
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
            installedTiers: [.lite],
            issues: []
        )
    }

    private func makeFixture(
        modelPath: String = "weights/model.gguf",
        artifactPath: String = "weights/model.gguf",
        contextTokens: String = "2048",
        modelIdentity: String = ActiveModelRuntimeResolver.acceptedLiteModelIdentity,
        maximumOutputTokens: String = "256"
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
                "maximum_output_tokens": maximumOutputTokens,
                "required_rag_package_id": "knowledge.shared-survival-rag-v3",
                "required_rag_contract": "3",
            ]
        )
        return (
            root,
            modelURL,
            ResolvedActivePackage(manifest: manifest, directory: root)
        )
    }

    private func makeExpertFixture(
        includeProjectorArtifact: Bool = true,
        includeEmbeddingArtifact: Bool = true,
        memoryProfileStatus: ExpertMemoryProfileStatus = .retained,
        includesPeakMeasurements: Bool = true
    ) throws -> (
        root: URL,
        modelURL: URL,
        projectorURL: URL,
        embeddingURL: URL,
        package: ResolvedActivePackage
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraExpertRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        let modelPath = "weights/model.gguf"
        let projectorPath = "weights/mmproj.gguf"
        let embeddingPath = "weights/bge-small-en-v1.5-q8_0.gguf"
        let modelURL = root.appendingPathComponent(modelPath)
        let projectorURL = root.appendingPathComponent(projectorPath)
        let embeddingURL = root.appendingPathComponent(embeddingPath)
        try FileManager.default.createDirectory(
            at: modelURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("model".utf8).write(to: modelURL)
        try Data("projector".utf8).write(to: projectorURL)
        try Data("embedding".utf8).write(to: embeddingURL)
        var artifacts = [
            PackageArtifact(
                path: modelPath,
                byteCount: ActiveModelRuntimeResolver.acceptedExpertModelBytes,
                sha256: ActiveModelRuntimeResolver.acceptedExpertModelSHA256
            ),
        ]
        if includeProjectorArtifact {
            artifacts.append(PackageArtifact(
                path: projectorPath,
                byteCount: ActiveModelRuntimeResolver.acceptedExpertProjectorBytes,
                sha256: ActiveModelRuntimeResolver.acceptedExpertProjectorSHA256
            ))
        }
        if includeEmbeddingArtifact {
            artifacts.append(PackageArtifact(
                path: embeddingPath,
                byteCount: 9,
                sha256: String(repeating: "1", count: 64)
            ))
        }
        var metadata = [
            "model_tier": ModelTier.expert.rawValue,
            "model_path": modelPath,
            "model_identity": ActiveModelRuntimeResolver.acceptedExpertModelIdentity,
            "model_family": "qwen3vl",
            "quantization": "Q4_K_M",
            "vision_projector_path": projectorPath,
            "vision_projector_identity": ActiveModelRuntimeResolver.acceptedExpertProjectorIdentity,
            "vision_projector_quantization": "Q8_0",
            "embedding_model_path": embeddingPath,
            "embedding_model_identity": ActiveModelRuntimeResolver.acceptedExpertEmbeddingIdentity,
            "embedding_quantization": "Q8_0",
            "embedding_dimensions": "384",
            "embedding_context_tokens": "512",
            "embedding_artifact_bytes": "9",
            "embedding_artifact_sha256": String(repeating: "1", count: 64),
            "vector_index_schema": "3",
            "knowledge_index_schema": "3",
            "corpus_package_schema": "3",
            "runtime_release": "b9637",
            "runtime_commit": ActiveModelRuntimeResolver.acceptedRuntimeCommit,
            "chat_template": "embedded",
            "context_tokens": "8192",
            "maximum_output_tokens": "256",
            "required_rag_package_id": "knowledge.shared-survival-rag-v3",
            "required_rag_contract": "3",
            "memory_profile_status": memoryProfileStatus.rawValue,
        ]
        if includesPeakMeasurements {
            metadata["peak_memory_full_bytes"] = "5000000000"
            metadata["peak_memory_balanced_bytes"] = "4000000000"
            metadata["peak_memory_constrained_bytes"] = "3000000000"
        }
        let manifest = PackageManifest(
            packageID: "model.expert.qwen3vl",
            version: "0.1.0-dev",
            kind: .model,
            createdAt: "2026-08-11T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "Apache-2.0",
            displayName: "Expert test model",
            artifacts: artifacts,
            metadata: metadata
        )
        return (
            root,
            modelURL,
            projectorURL,
            embeddingURL,
            ResolvedActivePackage(manifest: manifest, directory: root)
        )
    }
}
