import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class ProductionControlTests: XCTestCase {
    func testGroundedResponseAcceptsApprovedEvidenceAndProcedure() throws {
        let response = makeGroundedResponse()
        XCTAssertNoThrow(
            try GroundedResponseValidator().validate(
                response,
                availableEvidenceIDs: ["evidence.1"],
                approvedProcedureIDs: ["procedure.1"]
            )
        )
    }

    func testGroundedResponseRejectsUnknownEvidence() {
        XCTAssertThrowsError(
            try GroundedResponseValidator().validate(
                makeGroundedResponse(),
                availableEvidenceIDs: [],
                approvedProcedureIDs: ["procedure.1"]
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .unknownEvidenceID("evidence.1")
            )
        }
    }

    func testGroundedResponseRejectsUnapprovedProcedure() {
        XCTAssertThrowsError(
            try GroundedResponseValidator().validate(
                makeGroundedResponse(),
                availableEvidenceIDs: ["evidence.1"],
                approvedProcedureIDs: []
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .unapprovedProcedure("procedure.1")
            )
        }
    }

    func testHighRiskResponseCannotContinue() {
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .critical,
            immediateAction: GroundedAction(
                kind: .continue,
                evidenceIDs: ["evidence.1"]
            ),
            questions: [],
            observations: [],
            procedureID: nil,
            steps: [],
            doNotDo: [],
            driveability: .doNotDrive,
            escalation: GroundedEscalation(reason: "Hazard", action: "Use SOS"),
            answerConfidence: .supported
        )
        XCTAssertThrowsError(
            try GroundedResponseValidator().validate(
                response,
                availableEvidenceIDs: ["evidence.1"],
                approvedProcedureIDs: []
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .highRiskCannotContinue
            )
        }
    }

    func testGroundedResponseUsesSchemaSnakeCase() throws {
        let encoded = try JSONEncoder().encode(makeGroundedResponse())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(object["risk_level"])
        XCTAssertNotNil(object["immediate_action"])
        XCTAssertNotNil(object["answer_confidence"])
        let action = try XCTUnwrap(object["immediate_action"] as? [String: Any])
        XCTAssertNotNil(action["evidence_ids"])
    }

    func testIncidentModeDeniesNonessentialNetworkOperations() {
        let policy = IncidentNetworkPolicy(incidentModeEnabled: true)
        XCTAssertTrue(policy.permits(.emergencyContact))
        XCTAssertTrue(policy.permits(.modelInference))
        XCTAssertTrue(policy.permits(.knowledgeRetrieval))
        XCTAssertTrue(policy.permits(.mapUse))
        XCTAssertFalse(policy.permits(.telemetry))
        XCTAssertFalse(policy.permits(.packageDownload))
        XCTAssertFalse(policy.permits(.purchase))
        XCTAssertFalse(policy.permits(.entitlementRefresh))
    }

    func testCachedEntitlementKeepsInstalledPackAvailableOffline() {
        let resolver = OfflineEntitlementResolver()
        let cached = EntitlementSnapshot(
            productID: "trailguard.vision",
            verified: true,
            verifiedAt: "2026-07-23T00:00:00Z"
        )
        XCTAssertTrue(
            resolver.canLaunch(
                productID: "trailguard.vision",
                packageIsInstalled: true,
                cachedEntitlements: [cached]
            )
        )
        XCTAssertFalse(
            resolver.canLaunch(
                productID: "trailguard.vision",
                packageIsInstalled: false,
                cachedEntitlements: [cached]
            )
        )
        XCTAssertFalse(
            resolver.canLaunch(
                productID: "trailguard.other",
                packageIsInstalled: true,
                cachedEntitlements: [cached]
            )
        )
    }

    func testEmergencyCoreFirstLaunchPersistsBundledCore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try JSONEncoder().encode(makeEmergencyCore())
        let result = try EmergencyCoreStore(
            rootDirectory: root,
            bundledData: data
        ).loadOrRecover()
        XCTAssertEqual(result.origin, .bundledFirstLaunch)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("emergency-core.json").path
            )
        )
    }

    func testEmergencyCoreCorruptionRestoresBundledCore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(
            to: root.appendingPathComponent("emergency-core.json")
        )
        let data = try JSONEncoder().encode(makeEmergencyCore())
        let result = try EmergencyCoreStore(
            rootDirectory: root,
            bundledData: data
        ).loadOrRecover()
        XCTAssertEqual(result.origin, .bundledRecovery)
        XCTAssertEqual(result.bundle.version, "1.0.0")
    }

    func testDeterministicSafetyAnswerIncludesPolicySource() async {
        let assistant = IncidentAssistant(articles: [])
        let answer = await assistant.answer(
            request: ChatRequest(question: "There is a fuel leak"),
            device: DeviceSnapshot(
                physicalMemoryBytes: 8_000_000_000,
                freeStorageBytes: 20_000_000_000,
                thermalCondition: .nominal,
                isLowPowerMode: false
            )
        )
        XCTAssertTrue(answer.usedDeterministicOverride)
        XCTAssertEqual(answer.sources.first?.id, "trailguard.safety-policy")
        XCTAssertTrue(answer.notices.contains { $0.contains("vehicle.fire-fuel") })
    }

    private func makeGroundedResponse() -> GroundedResponse {
        GroundedResponse(
            domain: .vehicle,
            riskLevel: .moderate,
            immediateAction: GroundedAction(
                kind: .assess,
                evidenceIDs: ["evidence.1"]
            ),
            questions: [],
            observations: [
                GroundedObservation(
                    fact: "Engine is off",
                    source: .user,
                    confidence: 1
                )
            ],
            procedureID: "procedure.1",
            steps: [
                GroundedStep(stepID: "step.1", evidenceIDs: ["evidence.1"])
            ],
            doNotDo: ["Do not restart"],
            driveability: .unknown,
            escalation: GroundedEscalation(
                reason: "Cause unknown",
                action: "Seek a mechanic"
            ),
            answerConfidence: .supported
        )
    }

    private func makeEmergencyCore() -> EmergencyCoreBundle {
        let source = SourceReference(
            id: "source.1",
            title: "Reviewed fixture",
            organization: "TrailGuard Tests",
            revision: "1"
        )
        let article = KnowledgeArticle(
            id: "article.1",
            domain: .wilderness,
            title: "Fixture",
            summary: "Development-only reviewed fixture.",
            steps: ["Stop"],
            warnings: ["Fixture only"],
            keywords: ["fixture"],
            source: source,
            reviewed: true
        )
        return EmergencyCoreBundle(
            version: "1.0.0",
            policyVersion: "1.0.0",
            articles: [article]
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardControls-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
