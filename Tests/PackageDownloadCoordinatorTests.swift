import CryptoKit
import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class PackageDownloadCoordinatorTests: XCTestCase {
    func testInvalidManifestSignatureRejectsBeforeArtifactRequests() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let invalid = SignedPackageEnvelope(
            manifest: fixture.envelope.manifest,
            keyID: fixture.envelope.keyID,
            signature: Data(repeating: 0, count: 64).base64EncodedString()
        )
        let transport = MemoryResumableTransport(
            envelopeURL: fixture.location.envelopeURL,
            envelopeData: try JSONEncoder().encode(invalid),
            artifactData: fixture.artifactData
        )
        let coordinator = PackageDownloadCoordinator(
            stagingRoot: fixture.root.appendingPathComponent("staging"),
            transport: transport,
            installer: fixture.installer
        )
        do {
            _ = try await coordinator.downloadAndInstall(from: fixture.location)
            XCTFail("Expected invalid signature rejection")
        } catch {
            XCTAssertEqual(error as? PackageVerificationError, .invalidSignature)
        }
        let count = await transport.totalRequestCount()
        XCTAssertEqual(count, 1)
    }

    func testInterruptedPackageDownloadResumesFromPartialOffset() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transport = MemoryResumableTransport(
            envelopeURL: fixture.location.envelopeURL,
            envelopeData: try JSONEncoder().encode(fixture.envelope),
            artifactData: fixture.artifactData,
            failOnRangeRequest: 2
        )
        let coordinator = PackageDownloadCoordinator(
            stagingRoot: fixture.root.appendingPathComponent("staging"),
            transport: transport,
            installer: fixture.installer,
            chunkByteCount: 3
        )
        let progress = ProgressRecorder()

        do {
            _ = try await coordinator.downloadAndInstall(
                from: fixture.location,
                progress: { await progress.record($0) }
            )
            XCTFail("Expected simulated interruption")
        } catch {
            XCTAssertEqual(
                (error as? URLError)?.code,
                .networkConnectionLost,
                "Unexpected error: \(error)"
            )
        }

        await transport.clearFailure()
        let installed = try await coordinator.downloadAndInstall(
            from: fixture.location,
            progress: { await progress.record($0) }
        )
        XCTAssertEqual(installed.packageID, "knowledge.fixture")
        let ranges = await transport.requestedRanges()
        XCTAssertEqual(ranges, [0..<3, 3..<6, 3..<6])
        let lastProgress = await progress.last()
        XCTAssertEqual(lastProgress?.receivedByteCount, 6)
        XCTAssertEqual(lastProgress?.totalByteCount, 6)
        XCTAssertEqual(lastProgress?.fractionCompleted, 1)
    }

    func testCatalogExpectationRejectsDifferentSignedPackageBeforeArtifacts() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transport = MemoryResumableTransport(
            envelopeURL: fixture.location.envelopeURL,
            envelopeData: try JSONEncoder().encode(fixture.envelope),
            artifactData: fixture.artifactData
        )
        let coordinator = PackageDownloadCoordinator(
            stagingRoot: fixture.root.appendingPathComponent("staging"),
            transport: transport,
            installer: fixture.installer,
            chunkByteCount: 3
        )

        do {
            _ = try await coordinator.downloadAndInstall(
                from: fixture.location,
                expecting: PackageDownloadExpectation(
                    packageID: "model.unexpected",
                    version: "1.0.0",
                    kind: .model
                )
            )
            XCTFail("Expected identity rejection")
        } catch {
            XCTAssertEqual(
                error as? PackageDownloadError,
                .unexpectedPackage
            )
        }
        let requestCount = await transport.totalRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testDownloadReportsFinalizationPhasesAfterBytesComplete() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transport = MemoryResumableTransport(
            envelopeURL: fixture.location.envelopeURL,
            envelopeData: try JSONEncoder().encode(fixture.envelope),
            artifactData: fixture.artifactData
        )
        let coordinator = PackageDownloadCoordinator(
            stagingRoot: fixture.root.appendingPathComponent("staging"),
            transport: transport,
            installer: fixture.installer,
            chunkByteCount: 3
        )
        let phases = PhaseRecorder()

        _ = try await coordinator.downloadAndInstall(
            from: fixture.location,
            phase: { await phases.record($0) }
        )

        let recordedPhases = await phases.values()
        XCTAssertEqual(recordedPhases, [.downloading, .verifying, .installing])
    }

    func testRangeResponseRequiresExactBoundsTotalAndValidator() throws {
        let url = URL(string: "https://example.invalid/artifact.bin")!
        let valid = HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Range": "bytes 16-31/64",
                "ETag": "fixture-v1",
            ]
        )!
        let metadata = try PackageRangeResponse.validate(
            response: valid,
            requestedRange: 16..<32
        )
        XCTAssertEqual(metadata.totalByteCount, 64)
        XCTAssertEqual(metadata.validator, "fixture-v1")

        let wrongBounds = HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Range": "bytes 0-15/64",
                "ETag": "fixture-v1",
            ]
        )!
        XCTAssertThrowsError(try PackageRangeResponse.validate(
            response: wrongBounds,
            requestedRange: 16..<32
        ))
    }

    func testChangedRemoteValidatorDiscardsOnlyArtifactPartial() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let transport = ChangingValidatorTransport(
            envelopeURL: fixture.location.envelopeURL,
            envelopeData: try JSONEncoder().encode(fixture.envelope),
            artifactData: fixture.artifactData
        )
        let coordinator = PackageDownloadCoordinator(
            stagingRoot: fixture.root.appendingPathComponent("staging"),
            transport: transport,
            installer: fixture.installer,
            chunkByteCount: 3
        )

        do {
            _ = try await coordinator.downloadAndInstall(from: fixture.location)
            XCTFail("Expected interruption")
        } catch {
            XCTAssertEqual(
                (error as? URLError)?.code,
                .networkConnectionLost,
                "Unexpected error: \(error)"
            )
        }
        await transport.changeRemoteVersion()
        do {
            _ = try await coordinator.downloadAndInstall(from: fixture.location)
            XCTFail("Expected validator rejection")
        } catch {
            XCTAssertEqual(
                error as? PackageDownloadError,
                .remoteArtifactChanged,
                "Unexpected error: \(error)"
            )
        }

        let partials = try FileManager.default.subpathsOfDirectory(
            atPath: fixture.root.path
        ).filter { $0.hasSuffix(".partial") }
        XCTAssertTrue(partials.isEmpty)
    }

    private struct Fixture {
        let root: URL
        let envelope: SignedPackageEnvelope
        let artifactData: Data
        let location: RemotePackageLocation
        let installer: PackageInstaller
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraDownload-\(UUID().uuidString)",
            isDirectory: true
        )
        let artifactData = Data("abcdef".utf8)
        let hash = SHA256.hash(data: artifactData)
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = PackageManifest(
            packageID: "knowledge.fixture",
            version: "1.0.0",
            kind: .knowledge,
            createdAt: "2026-07-23T00:00:00Z",
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "LicenseRef-Test",
            displayName: "Fixture",
            artifacts: [
                PackageArtifact(
                    path: "content/data.bin",
                    byteCount: Int64(artifactData.count),
                    sha256: hash
                )
            ]
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let envelope = SignedPackageEnvelope(
            manifest: manifest,
            keyID: "test-key",
            signature: try privateKey.signature(
                for: manifest.signingPayload
            ).base64EncodedString()
        )
        let trusted = TrustedPackageKey(
            id: "test-key",
            publicKeyBase64: privateKey.publicKey.rawRepresentation
                .base64EncodedString(),
            validFrom: "2026-01-01T00:00:00Z"
        )
        let installer = PackageInstaller(
            rootDirectory: root.appendingPathComponent("packages"),
            verifier: PackageVerifier(trustedKeys: [trusted])
        )
        return Fixture(
            root: root,
            envelope: envelope,
            artifactData: artifactData,
            location: RemotePackageLocation(
                envelopeURL: URL(string: "https://example.invalid/envelope.json")!,
                artifactBaseURL: URL(string: "https://example.invalid/artifacts/")!
            ),
            installer: installer
        )
    }
}

private actor ProgressRecorder {
    private var values: [PackageDownloadProgress] = []

    func record(_ progress: PackageDownloadProgress) {
        values.append(progress)
    }

    func last() -> PackageDownloadProgress? {
        values.last
    }
}

private actor PhaseRecorder {
    private var recorded: [PackageTransferPhase] = []

    func record(_ phase: PackageTransferPhase) {
        recorded.append(phase)
    }

    func values() -> [PackageTransferPhase] {
        recorded
    }
}

private actor MemoryResumableTransport: ResumablePackageTransport {
    let envelopeURL: URL
    let envelopeData: Data
    let artifactData: Data
    var failOnRangeRequest: Int?
    var ranges: [Range<Int64>] = []
    var requestCount = 0

    init(
        envelopeURL: URL,
        envelopeData: Data,
        artifactData: Data,
        failOnRangeRequest: Int? = nil
    ) {
        self.envelopeURL = envelopeURL
        self.envelopeData = envelopeData
        self.artifactData = artifactData
        self.failOnRangeRequest = failOnRangeRequest
    }

    func data(from url: URL) async throws -> Data {
        requestCount += 1
        guard url == envelopeURL else { throw URLError(.badURL) }
        return envelopeData
    }

    func download(from url: URL, to destination: URL) async throws {
        requestCount += 1
        try artifactData.write(to: destination)
    }

    func data(
        from url: URL,
        byteRange: Range<Int64>
    ) async throws -> Data {
        requestCount += 1
        ranges.append(byteRange)
        if failOnRangeRequest == ranges.count {
            throw URLError(.networkConnectionLost)
        }
        return artifactData.subdata(
            in: Int(byteRange.lowerBound)..<Int(byteRange.upperBound)
        )
    }

    func clearFailure() {
        failOnRangeRequest = nil
    }

    func requestedRanges() -> [Range<Int64>] {
        ranges
    }

    func totalRequestCount() -> Int {
        requestCount
    }
}

private actor ChangingValidatorTransport: ValidatedRangePackageTransport {
    let envelopeURL: URL
    let envelopeData: Data
    let artifactData: Data
    private var validator = "v1"
    private var rangeCalls = 0
    private var shouldInterrupt = true

    init(envelopeURL: URL, envelopeData: Data, artifactData: Data) {
        self.envelopeURL = envelopeURL
        self.envelopeData = envelopeData
        self.artifactData = artifactData
    }

    func data(from url: URL) async throws -> Data {
        guard url == envelopeURL else { throw URLError(.badURL) }
        return envelopeData
    }

    func download(from url: URL, to destination: URL) async throws {
        try artifactData.write(to: destination)
    }

    func data(from url: URL, byteRange: Range<Int64>) async throws -> Data {
        try await range(from: url, byteRange: byteRange).data
    }

    func range(
        from url: URL,
        byteRange: Range<Int64>
    ) async throws -> PackageRangeResponse {
        rangeCalls += 1
        if shouldInterrupt && rangeCalls == 2 {
            throw URLError(.networkConnectionLost)
        }
        return PackageRangeResponse(
            data: artifactData.subdata(
                in: Int(byteRange.lowerBound)..<Int(byteRange.upperBound)
            ),
            totalByteCount: Int64(artifactData.count),
            validator: validator
        )
    }

    func changeRemoteVersion() {
        validator = "v2"
        shouldInterrupt = false
    }
}
