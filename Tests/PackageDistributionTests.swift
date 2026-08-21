import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class PackageDistributionTests: XCTestCase {
    func testBuiltInCatalogIsSignedAndCommitPinned() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envelope = try JSONDecoder().decode(
            SignedPackageCatalogV2.self,
            from: Data(contentsOf: root.appendingPathComponent(
                "Resources/Packages/builtin_model_catalog_v2.json"
            ))
        )
        let keys = try JSONDecoder().decode(
            [TrustedPackageKey].self,
            from: Data(contentsOf: root.appendingPathComponent(
                "Resources/Packages/trusted_package_keys.json"
            ))
        )
        let catalog = try PackageCatalogV2Verifier(
            trustedKeys: keys,
            now: { ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z")! }
        ).verify(envelope)

        XCTAssertEqual(catalog.entries.count, 2)
        XCTAssertEqual(catalog.entries.map(\.totalByteCount), [806_058_240, 1_552_463_168])
        for entry in catalog.entries {
            for artifact in entry.artifacts {
                let url = try artifact.validatedResolverURL()
                XCTAssertTrue(url.absoluteString.contains(artifact.revision))
                XCTAssertFalse(url.absoluteString.contains("/main/"))
                XCTAssertTrue(PackageDistributionConfiguration.huggingFace.permitsInitial(url))
            }
        }
    }

    func testDistributionRejectsMutableRevisionAndForeignRedirect() {
        let source = PackageArtifactSource(
            repository: "ggml-org/gemma-3-1b-it-GGUF",
            revision: "main",
            filename: "model.gguf",
            byteCount: 1,
            sha256: String(repeating: "a", count: 64)
        )
        XCTAssertThrowsError(try source.validatedResolverURL())
        XCTAssertFalse(PackageDistributionConfiguration.huggingFace.permitsRedirect(
            URL(string: "https://example.com/model.gguf")!
        ))
        XCTAssertTrue(PackageDistributionConfiguration.huggingFace.permitsRedirect(
            URL(string: "https://us.aws.cdn.hf.co/model.gguf")!
        ))
    }

    func testPackageManagerPreflightsStorageAndRestoresPausedState() async throws {
        let catalog = try loadCatalog()
        let lite = try XCTUnwrap(catalog.entries.first { $0.tier == .lite })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "aurora-package-manager-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("state.json")
        let manager = PackageManager(stateURL: stateURL)
        try await manager.register(catalog: catalog)

        do {
            try await manager.begin(
                packageID: lite.packageID,
                availableStorageBytes: lite.totalByteCount
            )
            XCTFail("Expected storage preflight failure")
        } catch PackageManagerError.insufficientStorage {
            // Expected before any transfer is created.
        }
        try await manager.begin(
            packageID: lite.packageID,
            availableStorageBytes: lite.totalByteCount + 300_000_000
        )
        try await manager.recordProgress(
            packageID: lite.packageID,
            artifactFilename: lite.artifacts[0].filename,
            receivedByteCount: 8_388_608
        )
        try await manager.pause(packageID: lite.packageID, detail: "network unavailable")

        let restored = PackageManager(stateURL: stateURL)
        let snapshot = await restored.snapshot(for: lite.packageID)
        XCTAssertEqual(snapshot?.phase, .paused)
        XCTAssertEqual(snapshot?.receivedByteCount, 8_388_608)
        XCTAssertEqual(snapshot?.detail, "network unavailable")
    }

    func testPackageManagerKeepsExpertLockedAndCapsRetries() async throws {
        let catalog = try loadCatalog()
        let expert = try XCTUnwrap(catalog.entries.first { $0.tier == .expert })
        let lite = try XCTUnwrap(catalog.entries.first { $0.tier == .lite })
        let manager = PackageManager()
        try await manager.register(catalog: catalog)
        await XCTAssertThrowsErrorAsync {
            try await manager.begin(
                packageID: expert.packageID,
                availableStorageBytes: Int64.max
            )
        }
        try await manager.begin(
            packageID: lite.packageID,
            availableStorageBytes: Int64.max
        )
        try await manager.recordRetryableFailure(
            packageID: lite.packageID,
            detail: "429"
        )
        try await manager.recordRetryableFailure(
            packageID: lite.packageID,
            detail: "503"
        )
        await XCTAssertThrowsErrorAsync {
            try await manager.recordRetryableFailure(
                packageID: lite.packageID,
                detail: "503"
            )
        }
        let exhausted = await manager.snapshot(for: lite.packageID)
        XCTAssertEqual(exhausted?.retryCount, 3)
    }

    private func loadCatalog() throws -> PackageCatalogV2 {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envelope = try JSONDecoder().decode(
            SignedPackageCatalogV2.self,
            from: Data(contentsOf: root.appendingPathComponent(
                "Resources/Packages/builtin_model_catalog_v2.json"
            ))
        )
        let keys = try JSONDecoder().decode(
            [TrustedPackageKey].self,
            from: Data(contentsOf: root.appendingPathComponent(
                "Resources/Packages/trusted_package_keys.json"
            ))
        )
        return try PackageCatalogV2Verifier(
            trustedKeys: keys,
            now: { ISO8601DateFormatter().date(from: "2026-08-13T12:00:00Z")! }
        ).verify(envelope)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
