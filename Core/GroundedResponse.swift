import Foundation

public enum GroundedRiskLevel: String, Codable, Sendable {
    case critical
    case high
    case moderate
    case low
}

public enum ImmediateActionKind: String, Codable, Sendable {
    case stop
    case move
    case sos
    case assess
    case `continue`
}

public enum ObservationSource: String, Codable, Sendable {
    case user
    case photo
    case obd
    case sensor
}

public enum Driveability: String, Codable, Sendable {
    case doNotDrive = "do_not_drive"
    case unknown
    case conditional
    case notApplicable = "not_applicable"
}

public enum AnswerConfidence: String, Codable, Sendable {
    case insufficient
    case limited
    case supported
}

public struct GroundedAction: Codable, Equatable, Sendable {
    public let kind: ImmediateActionKind
    public let evidenceIDs: [String]

    public init(kind: ImmediateActionKind, evidenceIDs: [String]) {
        self.kind = kind
        self.evidenceIDs = evidenceIDs
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case evidenceIDs = "evidence_ids"
    }
}

public struct GroundedQuestion: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let why: String

    public init(id: String, text: String, why: String) {
        self.id = id
        self.text = text
        self.why = why
    }
}

public struct GroundedObservation: Codable, Equatable, Sendable {
    public let fact: String
    public let source: ObservationSource
    public let confidence: Double

    public init(fact: String, source: ObservationSource, confidence: Double) {
        self.fact = fact
        self.source = source
        self.confidence = confidence
    }
}

public struct GroundedStep: Codable, Equatable, Sendable {
    public let stepID: String
    public let evidenceIDs: [String]

    public init(stepID: String, evidenceIDs: [String]) {
        self.stepID = stepID
        self.evidenceIDs = evidenceIDs
    }

    private enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case evidenceIDs = "evidence_ids"
    }
}

public struct GroundedEscalation: Codable, Equatable, Sendable {
    public let reason: String
    public let action: String

    public init(reason: String, action: String) {
        self.reason = reason
        self.action = action
    }
}

public struct GroundedResponse: Codable, Equatable, Sendable {
    public let domain: KnowledgeDomain
    public let riskLevel: GroundedRiskLevel
    public let immediateAction: GroundedAction
    public let questions: [GroundedQuestion]
    public let observations: [GroundedObservation]
    public let procedureID: String?
    public let steps: [GroundedStep]
    public let doNotDo: [String]
    public let driveability: Driveability
    public let escalation: GroundedEscalation
    public let answerConfidence: AnswerConfidence

    public init(
        domain: KnowledgeDomain,
        riskLevel: GroundedRiskLevel,
        immediateAction: GroundedAction,
        questions: [GroundedQuestion],
        observations: [GroundedObservation],
        procedureID: String?,
        steps: [GroundedStep],
        doNotDo: [String],
        driveability: Driveability,
        escalation: GroundedEscalation,
        answerConfidence: AnswerConfidence
    ) {
        self.domain = domain
        self.riskLevel = riskLevel
        self.immediateAction = immediateAction
        self.questions = questions
        self.observations = observations
        self.procedureID = procedureID
        self.steps = steps
        self.doNotDo = doNotDo
        self.driveability = driveability
        self.escalation = escalation
        self.answerConfidence = answerConfidence
    }

    private enum CodingKeys: String, CodingKey {
        case domain
        case riskLevel = "risk_level"
        case immediateAction = "immediate_action"
        case questions
        case observations
        case procedureID = "procedure_id"
        case steps
        case doNotDo = "do_not_do"
        case driveability
        case escalation
        case answerConfidence = "answer_confidence"
    }
}

public enum GroundedResponseError: Error, Equatable {
    case invalidObservationConfidence
    case unknownEvidenceID(String)
    case unapprovedProcedure(String)
    case stepsRequireProcedure
    case supportedAnswerRequiresEvidence
    case highRiskCannotContinue
    case unknownStepID(String)
    case unsupportedWarning(String)
}

public struct GroundedResponseValidator: Sendable {
    public init() {}

    public func validate(
        _ response: GroundedResponse,
        availableEvidenceIDs: Set<String>,
        approvedProcedureIDs: Set<String>,
        approvedStepIDs: Set<String>? = nil,
        approvedWarnings: Set<String>? = nil
    ) throws {
        guard response.observations.allSatisfy({ (0...1).contains($0.confidence) }) else {
            throw GroundedResponseError.invalidObservationConfidence
        }

        let cited = response.immediateAction.evidenceIDs
            + response.steps.flatMap(\.evidenceIDs)
        if let unknown = cited.first(where: { !availableEvidenceIDs.contains($0) }) {
            throw GroundedResponseError.unknownEvidenceID(unknown)
        }

        if !response.steps.isEmpty {
            guard let procedureID = response.procedureID else {
                throw GroundedResponseError.stepsRequireProcedure
            }
            guard approvedProcedureIDs.contains(procedureID) else {
                throw GroundedResponseError.unapprovedProcedure(procedureID)
            }
            if let approvedStepIDs,
               let unknown = response.steps
                .map(\.stepID)
                .first(where: { !approvedStepIDs.contains($0) }) {
                throw GroundedResponseError.unknownStepID(unknown)
            }
        }

        if let approvedWarnings,
           let unsupported = response.doNotDo.first(
               where: { !approvedWarnings.contains($0) }
           ) {
            throw GroundedResponseError.unsupportedWarning(unsupported)
        }

        if response.answerConfidence == .supported && cited.isEmpty {
            throw GroundedResponseError.supportedAnswerRequiresEvidence
        }

        if [.critical, .high].contains(response.riskLevel),
           response.immediateAction.kind == .continue {
            throw GroundedResponseError.highRiskCannotContinue
        }
    }
}
