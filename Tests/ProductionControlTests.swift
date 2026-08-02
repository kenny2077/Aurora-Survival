import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
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

    func testGroundedPromptDefinesConversationalDecisionContract() {
        let prompt = GroundedPromptBuilder().systemPrompt(
            for: .lite,
            outputMode: .groundedJSON
        )

        for required in [
            "{\"a\":",
            "\"e\":",
            "\"p\":",
            "\"q\":",
            "four keys in that order",
            "extra keys",
            "natural conversational answer",
            "EVIDENCE number",
            "NO REVIEWED",
            "reviewed procedure",
        ] {
            XCTAssertTrue(prompt.contains(required), "Missing prompt contract: \(required)")
        }

        let article = makeArticle()
        let userPrompt = GroundedPromptBuilder().userPrompt(
            from: ModelPrompt(
                question: "What should I do?",
                evidence: [RetrievedPassage(article: article, score: 1)],
                imageObservations: [],
                tier: .lite,
                permitsVisionReasoning: false,
                conversationHistory: [
                    ConversationTurn(
                        role: .user,
                        text: "My engine made a strange noise."
                    )
                ]
            ),
            outputMode: .groundedJSON
        )
        XCTAssertTrue(userPrompt.contains("Domain: vehicle"))
        XCTAssertTrue(userPrompt.contains("RECENT CONVERSATION"))
        XCTAssertTrue(userPrompt.contains("My engine made a strange noise."))
        XCTAssertTrue(userPrompt.contains("Reviewed steps:"))
        XCTAssertTrue(userPrompt.contains("Reviewed warnings:"))

        let emptyEvidencePrompt = GroundedPromptBuilder().userPrompt(
            from: ModelPrompt(
                question: "Unsupported request",
                evidence: [],
                imageObservations: [],
                tier: .lite,
                permitsVisionReasoning: false
            ),
            outputMode: .groundedJSON
        )
        XCTAssertTrue(emptyEvidencePrompt.contains("NO REVIEWED EVIDENCE"))
    }

    func testInsufficientAnswerCannotSelectProcedure() {
        let original = makeGroundedResponse()
        let response = GroundedResponse(
            domain: original.domain,
            riskLevel: original.riskLevel,
            immediateAction: original.immediateAction,
            questions: original.questions,
            observations: original.observations,
            procedureID: original.procedureID,
            steps: [],
            doNotDo: [],
            driveability: original.driveability,
            escalation: original.escalation,
            answerConfidence: .insufficient
        )
        XCTAssertThrowsError(
            try GroundedResponseValidator().validate(
                response,
                availableEvidenceIDs: ["evidence.1"],
                approvedProcedureIDs: ["procedure.1"]
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .insufficientAnswerCannotSelectProcedure
            )
        }
    }

    func testGroundedAnswerRequiresProcedure() {
        let original = makeGroundedResponse()
        let response = GroundedResponse(
            domain: original.domain,
            riskLevel: original.riskLevel,
            immediateAction: original.immediateAction,
            questions: original.questions,
            observations: original.observations,
            procedureID: nil,
            steps: [],
            doNotDo: [],
            driveability: original.driveability,
            escalation: original.escalation,
            answerConfidence: .limited
        )
        XCTAssertThrowsError(
            try GroundedResponseValidator().validate(
                response,
                availableEvidenceIDs: ["evidence.1"],
                approvedProcedureIDs: ["procedure.1"]
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .groundedAnswerRequiresProcedure
            )
        }
    }

    func testGroundedCodecRendersOnlyApprovedStepText() throws {
        let article = makeArticle()
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .moderate,
            immediateAction: GroundedAction(
                kind: .assess,
                evidenceIDs: [article.id]
            ),
            questions: [],
            observations: [],
            procedureID: article.id,
            steps: [],
            doNotDo: [],
            driveability: .unknown,
            escalation: GroundedEscalation(
                reason: "Cause unknown",
                action: "Ignored in favor of fixed escalation text"
            ),
            answerConfidence: .supported
        )
        let encoded = try JSONEncoder().encode(response)
        let rendered = try GroundedResponseCodec().decodeValidateAndRender(
            String(decoding: encoded, as: UTF8.self),
            evidence: [RetrievedPassage(article: article, score: 1)]
        )
        XCTAssertTrue(rendered.contains(article.steps[0]))
        XCTAssertTrue(rendered.contains(article.warnings[0]))
        XCTAssertFalse(rendered.contains(response.escalation.action))
    }

    func testGroundedCodecExpandsCompactDecisionFromReviewedEvidence() throws {
        let article = makeArticle()
        let generated = """
        {"d":"vehicle","p":1}
        """
        let rendered = try GroundedResponseCodec().decodeValidateAndRender(
            generated,
            evidence: [RetrievedPassage(article: article, score: 1)]
        )
        XCTAssertTrue(rendered.contains(article.steps[0]))
        XCTAssertTrue(rendered.contains(article.warnings[0]))
    }

    func testGroundedCodecRejectsCompactDecisionDomainMismatch() throws {
        let article = makeArticle()
        let generated = """
        {"d":"wilderness","p":1}
        """
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeValidateAndRender(
                generated,
                evidence: [RetrievedPassage(article: article, score: 1)]
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .procedureDomainMismatch(article.id)
            )
        }
    }

    func testGroundedCodecRejectsInventedStepID() throws {
        let article = makeArticle()
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .moderate,
            immediateAction: GroundedAction(
                kind: .assess,
                evidenceIDs: [article.id]
            ),
            questions: [],
            observations: [],
            procedureID: article.id,
            steps: [
                GroundedStep(
                    stepID: "invented#step-99",
                    evidenceIDs: [article.id]
                )
            ],
            doNotDo: article.warnings,
            driveability: .unknown,
            escalation: GroundedEscalation(reason: "", action: ""),
            answerConfidence: .supported
        )
        let encoded = try JSONEncoder().encode(response)
        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeValidateAndRender(
                String(decoding: encoded, as: UTF8.self),
                evidence: [RetrievedPassage(article: article, score: 1)]
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .unknownStepID("invented#step-99")
            )
        }
    }

    func testIncidentAssistantUsesValidatedStructuredModelOutput() async throws {
        let article = makeArticle()
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .moderate,
            immediateAction: GroundedAction(
                kind: .assess,
                evidenceIDs: [article.id]
            ),
            questions: [],
            observations: [],
            procedureID: article.id,
            steps: [
                GroundedStep(
                    stepID: "\(article.id)#step-1",
                    evidenceIDs: [article.id]
                )
            ],
            doNotDo: article.warnings,
            driveability: .unknown,
            escalation: GroundedEscalation(reason: "", action: ""),
            answerConfidence: .supported
        )
        let generated = String(
            decoding: try JSONEncoder().encode(response),
            as: UTF8.self
        )
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .field],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, _ in
                    generated
                }
            }
        )
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "fixture engine inspection",
                preferredTier: .field
            ),
            device: capableDevice()
        )
        XCTAssertEqual(answer.modelTier, .field)
        XCTAssertTrue(answer.text.contains(article.steps[0]))
        XCTAssertFalse(answer.notices.contains {
            $0.contains("failed evidence validation")
        })
    }

    func testStructuredOutputFallsBackWhenWarningIsInvented() async throws {
        let article = makeArticle()
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .moderate,
            immediateAction: GroundedAction(
                kind: .assess,
                evidenceIDs: [article.id]
            ),
            questions: [],
            observations: [],
            procedureID: nil,
            steps: [],
            doNotDo: ["Invented warning"],
            driveability: .unknown,
            escalation: GroundedEscalation(reason: "", action: ""),
            answerConfidence: .supported
        )
        let generated = String(
            decoding: try JSONEncoder().encode(response),
            as: UTF8.self
        )
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .field],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, _ in generated }
            }
        )
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "fixture engine inspection",
                preferredTier: .field
            ),
            device: capableDevice()
        )
        XCTAssertTrue(answer.text.contains(article.steps[0]))
        XCTAssertTrue(answer.notices.contains {
            $0.contains("failed evidence validation")
        })
    }

    func testVisionObservationCanTriggerPostModelSafetyOverride() async throws {
        let article = makeArticle()
        let response = GroundedResponse(
            domain: .vehicle,
            riskLevel: .critical,
            immediateAction: GroundedAction(
                kind: .sos,
                evidenceIDs: [article.id]
            ),
            questions: [],
            observations: [
                GroundedObservation(
                    fact: "The image appears to show a fuel leak.",
                    source: .photo,
                    confidence: 0.8
                )
            ],
            procedureID: article.id,
            steps: [],
            doNotDo: article.warnings,
            driveability: .doNotDrive,
            escalation: GroundedEscalation(reason: "", action: ""),
            answerConfidence: .limited
        )
        let generated = String(
            decoding: try JSONEncoder().encode(response),
            as: UTF8.self
        )
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .visionExpert],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, _ in generated }
            }
        )
        let answer = await assistant.answer(
            request: ChatRequest(
                question: "fixture engine inspection",
                preferredTier: .visionExpert,
                hasImage: true,
                imageData: Data("image".utf8)
            ),
            device: capableDevice()
        )
        XCTAssertTrue(answer.usedDeterministicOverride)
        XCTAssertTrue(answer.visionWasUsed)
        XCTAssertEqual(answer.text.components(separatedBy: "\n").first, "Fire or fuel hazard")
        XCTAssertTrue(answer.notices.contains {
            $0.contains("model observation triggered")
        })
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

    func testNewerBundledEmergencyCoreUpgradesExistingInstall() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let active = makeEmergencyCore(version: "1.0.0")
        try JSONEncoder().encode(active).write(
            to: root.appendingPathComponent("emergency-core.json")
        )
        let bundled = makeEmergencyCore(version: "1.1.0")

        let result = try EmergencyCoreStore(
            rootDirectory: root,
            bundledData: try JSONEncoder().encode(bundled)
        ).loadOrRecover()

        XCTAssertEqual(result.origin, .bundledUpgrade)
        XCTAssertEqual(result.bundle.version, "1.1.0")
        let persisted = try JSONDecoder().decode(
            EmergencyCoreBundle.self,
            from: Data(
                contentsOf: root.appendingPathComponent("emergency-core.json")
            )
        )
        XCTAssertEqual(persisted.version, "1.1.0")
    }

    func testOlderBundledEmergencyCoreDoesNotDowngradeActiveInstall() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let active = makeEmergencyCore(version: "2.0.0")
        try JSONEncoder().encode(active).write(
            to: root.appendingPathComponent("emergency-core.json")
        )

        let result = try EmergencyCoreStore(
            rootDirectory: root,
            bundledData: try JSONEncoder().encode(
                makeEmergencyCore(version: "1.1.0")
            )
        ).loadOrRecover()

        XCTAssertEqual(result.origin, .active)
        XCTAssertEqual(result.bundle.version, "2.0.0")
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

    private func makeEmergencyCore(
        version: String = "1.0.0"
    ) -> EmergencyCoreBundle {
        let source = SourceReference(
            id: "source.1",
            title: "Reviewed fixture",
            organization: "Aurora Tests",
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
            version: version,
            policyVersion: "1.0.0",
            articles: [article]
        )
    }

    private func makeArticle() -> KnowledgeArticle {
        KnowledgeArticle(
            id: "vehicle.fixture",
            domain: .vehicle,
            title: "Fixture engine inspection",
            summary: "Development-only inspection fixture.",
            steps: ["Switch the fixture engine off."],
            warnings: ["Do not restart the fixture engine."],
            keywords: ["fixture", "engine", "inspection"],
            source: SourceReference(
                id: "source.fixture",
                title: "Fixture source",
                organization: "Aurora Tests",
                revision: "1"
            ),
            reviewed: true
        )
    }

    private func capableDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraControls-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
