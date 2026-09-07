import Foundation
import XCTest
@testable import AuroraCore

final class SpeciesPackResolverTests: XCTestCase {
    func testResolvesVerifiedSpeciesArtifacts() throws {
        let fixture = try makePackage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = SpeciesPackResolver().resolve(activePacks: ActivePackSnapshot(
            models: [],
            knowledge: [],
            maps: [],
            species: [fixture.package],
            installedTiers: [],
            issues: []
        ))

        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.descriptor?.speciesCount, 504)
        XCTAssertEqual(result.descriptor?.modelIdentity, "imageomics/bioclip-2@revision")
        XCTAssertEqual(result.descriptor?.encoderSHA256, String(repeating: "a", count: 64))
    }

    func testRejectsUnsupportedContract() throws {
        let fixture = try makePackage(contract: "2")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = SpeciesPackResolver().resolve(activePacks: ActivePackSnapshot(
            models: [], knowledge: [], maps: [], species: [fixture.package],
            installedTiers: [], issues: []
        ))

        XCTAssertNil(result.descriptor)
        XCTAssertEqual(result.issues, [.unsupportedContract("species.bioclip2.aurora-504")])
    }

    func testRejectsDuplicateSpeciesPackages() throws {
        let first = try makePackage()
        let second = try makePackage()
        defer {
            try? FileManager.default.removeItem(at: first.directory)
            try? FileManager.default.removeItem(at: second.directory)
        }

        let result = SpeciesPackResolver().resolve(activePacks: ActivePackSnapshot(
            models: [], knowledge: [], maps: [], species: [first.package, second.package],
            installedTiers: [], issues: []
        ))

        XCTAssertNil(result.descriptor)
        XCTAssertEqual(result.issues, [.duplicatePackage])
    }

    func testSpeciesPackageNeverEntersLanguageModelRouting() throws {
        let fixture = try makePackage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let snapshot = ActivePackSnapshot(
            models: [], knowledge: [], maps: [], species: [fixture.package],
            installedTiers: [], issues: []
        )

        let runtime = ActiveModelRuntimeResolver().resolve(activePacks: snapshot)

        XCTAssertTrue(runtime.descriptors.isEmpty)
    }

    private func makePackage(
        contract: String = "1"
    ) throws -> (package: ResolvedActivePackage, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let encoder = directory.appendingPathComponent("BioCLIP2-ImageEncoder.mlpackage")
        try FileManager.default.createDirectory(at: encoder, withIntermediateDirectories: true)
        let weight = encoder.appendingPathComponent("weight.bin")
        let table = directory.appendingPathComponent("species_table.json")
        let embeddings = directory.appendingPathComponent("species_embeddings.f16.bin")
        try Data([1]).write(to: weight)
        try Data([2]).write(to: table)
        try Data([3]).write(to: embeddings)
        let manifest = PackageManifest(
            packageID: "species.bioclip2.aurora-504",
            version: "1.0.0",
            kind: .species,
            createdAt: "2026-09-07T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "MIT",
            displayName: "Species ID",
            artifacts: [
                PackageArtifact(
                    path: "BioCLIP2-ImageEncoder.mlpackage/weight.bin",
                    byteCount: 1,
                    sha256: String(repeating: "a", count: 64)
                ),
                PackageArtifact(
                    path: "species_table.json",
                    byteCount: 1,
                    sha256: String(repeating: "b", count: 64)
                ),
                PackageArtifact(
                    path: "species_embeddings.f16.bin",
                    byteCount: 1,
                    sha256: String(repeating: "c", count: 64)
                ),
            ],
            metadata: [
                "species_contract": contract,
                "input_side": "224",
                "embedding_dimensions": "768",
                "softmax_temperature": "100",
                "model_identity": "imageomics/bioclip-2@revision",
                "encoder_path": "BioCLIP2-ImageEncoder.mlpackage",
                "species_table_path": "species_table.json",
                "embeddings_path": "species_embeddings.f16.bin",
                "encoder_digest_artifact_path": "BioCLIP2-ImageEncoder.mlpackage/weight.bin",
                "species_count": "504",
            ]
        )
        return (ResolvedActivePackage(manifest: manifest, directory: directory), directory)
    }
}
