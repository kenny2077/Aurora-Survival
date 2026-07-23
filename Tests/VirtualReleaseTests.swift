import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class VirtualReleaseTests: XCTestCase {
    func testModelAcceptanceCollectsEveryFailure() {
        let issues = ModelAcceptanceEvaluator().evaluate(
            metrics: ModelBenchmarkMetrics(
                firstTokenMilliseconds: 9_000,
                tokensPerSecond: 1,
                peakMemoryBytes: 9_000_000_000,
                endingThermalCondition: .serious,
                batteryPercentConsumed: 12
            ),
            thresholds: ModelAcceptanceThresholds(
                maximumFirstTokenMilliseconds: 3_000,
                minimumTokensPerSecond: 4,
                maximumPeakMemoryBytes: 6_000_000_000,
                maximumBatteryPercentConsumed: 5
            )
        )
        XCTAssertEqual(
            Set(issues),
            Set([
                .firstTokenTooSlow,
                .generationTooSlow,
                .memoryTooHigh,
                .thermalLimitExceeded,
                .batteryUseTooHigh,
            ])
        )
    }

    func testVirtualReleasePassesOnlyWhenEverySubsystemPasses() {
        let scenario = passingScenario()
        XCTAssertTrue(VirtualReleaseEvaluator().evaluate(scenario).isEmpty)
    }

    func testVirtualReleaseFailsClosedOnAccessibilityContract() {
        let accessibility = AccessibilityAuditSnapshot(
            emergencyControlsHaveLabels: true,
            supportsLargestDynamicType: false,
            logicalVoiceOverOrder: true,
            meaningDoesNotDependOnColor: true,
            motionCanBeReduced: true
        )
        let scenario = VirtualReleaseScenario(
            deterministicSafetyPasses: true,
            bundledCoreRecovers: true,
            installedMapIsReady: true,
            obdWritesAreBlocked: true,
            installedEntitlementsWorkOffline: true,
            accessibility: accessibility,
            incidentModeNetworkIsContained: true
        )
        XCTAssertEqual(
            VirtualReleaseEvaluator().evaluate(scenario),
            [.accessibilityContractFailure]
        )
    }

    func testVirtualReleaseReportsAllSubsystemFailures() {
        let accessibility = AccessibilityAuditSnapshot(
            emergencyControlsHaveLabels: false,
            supportsLargestDynamicType: false,
            logicalVoiceOverOrder: false,
            meaningDoesNotDependOnColor: false,
            motionCanBeReduced: false
        )
        let scenario = VirtualReleaseScenario(
            deterministicSafetyPasses: false,
            bundledCoreRecovers: false,
            installedMapIsReady: false,
            obdWritesAreBlocked: false,
            installedEntitlementsWorkOffline: false,
            accessibility: accessibility,
            incidentModeNetworkIsContained: false
        )
        XCTAssertEqual(VirtualReleaseEvaluator().evaluate(scenario).count, 7)
    }

    func testInterruptedArtifactCanResumeAndFinalize() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("artifact.partial")
        let destination = root.appendingPathComponent("artifact.bin")

        let firstSession = ResumableArtifactAssembler(
            partialURL: partial,
            expectedByteCount: 6
        )
        try await firstSession.append(Data("abc".utf8), atOffset: 0)

        let resumedSession = ResumableArtifactAssembler(
            partialURL: partial,
            expectedByteCount: 6
        )
        XCTAssertEqual(try await resumedSession.state().receivedByteCount, 3)
        try await resumedSession.append(Data("def".utf8), atOffset: 3)
        try await resumedSession.finalize(to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("abcdef".utf8))
    }

    func testArtifactResumeRejectsWrongOffset() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let assembler = ResumableArtifactAssembler(
            partialURL: root.appendingPathComponent("artifact.partial"),
            expectedByteCount: 3
        )
        do {
            try await assembler.append(Data("abc".utf8), atOffset: 1)
            XCTFail("Expected invalid offset")
        } catch {
            XCTAssertEqual(
                error as? ArtifactAssemblyError,
                .invalidOffset(expected: 0, received: 1)
            )
        }
    }

    private func passingScenario() -> VirtualReleaseScenario {
        VirtualReleaseScenario(
            deterministicSafetyPasses: true,
            bundledCoreRecovers: true,
            installedMapIsReady: true,
            obdWritesAreBlocked: true,
            installedEntitlementsWorkOffline: true,
            accessibility: AccessibilityAuditSnapshot(
                emergencyControlsHaveLabels: true,
                supportsLargestDynamicType: true,
                logicalVoiceOverOrder: true,
                meaningDoesNotDependOnColor: true,
                motionCanBeReduced: true
            ),
            incidentModeNetworkIsContained: true
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraVirtual-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
