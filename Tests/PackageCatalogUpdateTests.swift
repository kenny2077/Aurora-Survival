import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class PackageCatalogUpdateTests: XCTestCase {
    func testSemanticVersionComparisonHandlesPrereleasesAndNumericComponents() {
        XCTAssertLessThan(
            SemanticPackageVersion("1.2.0-beta.1")!,
            SemanticPackageVersion("1.2.0")!
        )
        XCTAssertLessThan(
            SemanticPackageVersion("1.9.0")!,
            SemanticPackageVersion("1.10.0")!
        )
        XCTAssertNil(SemanticPackageVersion("release-next"))
    }

    func testPromotedVersionIsOptionalUpdateWhileOldVersionRemainsActive() {
        let entry = PackageCatalogEntry(
            packageID: "model.lite",
            version: "2.0.0",
            kind: .model,
            displayName: "Lite",
            summary: "Updated model",
            totalByteCount: 10,
            envelopePath: "model.lite/2.0.0/envelope.json",
            artifactBasePath: "model.lite/2.0.0"
        )
        let installed = InstalledPackageVersion(
            packageID: "model.lite",
            version: "1.0.0",
            kind: .model,
            displayName: "Lite",
            installedAt: "2026-08-27T00:00:00Z",
            directoryName: "model.lite@1.0.0"
        )
        let index = PackageActivationIndex(
            activeVersions: ["model.lite": "1.0.0"],
            installed: [installed]
        )

        XCTAssertEqual(
            PackageCatalogInstallStatusResolver().resolve(
                entry: entry,
                index: index
            ),
            .updateAvailable(
                installedVersion: "1.0.0",
                availableVersion: "2.0.0"
            )
        )
        XCTAssertEqual(index.activeVersions["model.lite"], "1.0.0")
    }

    func testOlderCatalogVersionDoesNotOfferDowngrade() {
        let entry = PackageCatalogEntry(
            packageID: "model.lite", version: "1.1.0", kind: .model,
            displayName: "Lite", summary: "", totalByteCount: 1,
            envelopePath: "model/envelope.json", artifactBasePath: "model"
        )
        let index = PackageActivationIndex(
            activeVersions: ["model.lite": "1.2.0"],
            installed: [InstalledPackageVersion(
                packageID: "model.lite", version: "1.2.0", kind: .model,
                displayName: "Lite",
                installedAt: "2026-08-27T00:00:00Z",
                directoryName: "model.lite@1.2.0"
            )]
        )
        XCTAssertEqual(
            PackageCatalogInstallStatusResolver().resolve(entry: entry, index: index),
            .installed(active: true)
        )
    }
}
