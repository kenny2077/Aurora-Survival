import Foundation

public enum ModelPromptPurpose: Equatable, Sendable {
    case ordinary
    case grounded
    case clarification
    case incidentFallback
    case incidentIntake
    case expertIntent
    case nativeVisionAnswer
}

public enum ModelPromptAttempt: Equatable, Sendable {
    case initial
    case repair
}

public struct ModelPrompt: Sendable {
    public let question: String
    public let evidence: [RetrievedPassage]
    public let imageData: Data?
    public let imageObservations: [String]
    public let tier: ModelTier
    public let permitsVisionReasoning: Bool
    public let conversationHistory: [ConversationTurn]
    public let expertContextProfile: ExpertContextProfile?
    public let maximumImageDimension: Int?
    public let expertEvidence: [RetrievedEvidenceScenario]
    public let repairFeedback: [String]
    public let purpose: ModelPromptPurpose
    public let attempt: ModelPromptAttempt

    public init(
        question: String,
        evidence: [RetrievedPassage],
        imageData: Data? = nil,
        imageObservations: [String],
        tier: ModelTier,
        permitsVisionReasoning: Bool,
        conversationHistory: [ConversationTurn] = [],
        expertContextProfile: ExpertContextProfile? = nil,
        maximumImageDimension: Int? = nil,
        expertEvidence: [RetrievedEvidenceScenario] = [],
        repairFeedback: [String] = [],
        purpose: ModelPromptPurpose? = nil,
        attempt: ModelPromptAttempt = .initial
    ) {
        self.question = question
        self.evidence = evidence
        self.imageData = imageData
        self.imageObservations = imageObservations
        self.tier = tier
        self.permitsVisionReasoning = permitsVisionReasoning
        self.conversationHistory = conversationHistory
        self.expertContextProfile = expertContextProfile
        self.maximumImageDimension = maximumImageDimension
        self.expertEvidence = expertEvidence
        self.repairFeedback = repairFeedback
        self.purpose = purpose ?? (evidence.isEmpty ? .ordinary : .grounded)
        self.attempt = attempt
    }

    public func repairing(feedback: [String] = []) -> ModelPrompt {
        ModelPrompt(
            question: question,
            evidence: evidence,
            imageData: imageData,
            imageObservations: imageObservations,
            tier: tier,
            permitsVisionReasoning: permitsVisionReasoning,
            conversationHistory: conversationHistory,
            expertContextProfile: expertContextProfile,
            maximumImageDimension: maximumImageDimension,
            expertEvidence: expertEvidence,
            repairFeedback: feedback,
            purpose: purpose,
            attempt: .repair
        )
    }
}

public protocol LocalLanguageModel: Sendable {
    var tier: ModelTier { get }
    var outputMode: ModelOutputMode { get }
    func generate(prompt: ModelPrompt) async throws -> String
    func generate(
        prompt: ModelPrompt,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> String
}

public enum ModelOutputMode: String, Codable, Sendable {
    case citationText = "citation_text"
    case groundedJSON = "grounded_json"
}

public extension LocalLanguageModel {
    var outputMode: ModelOutputMode { .citationText }

    func generate(
        prompt: ModelPrompt,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let output = try await generate(prompt: prompt)
        tokenSink?(output)
        return output
    }
}

public enum ModelFailure: Error, Equatable {
    case unavailable
    case invalidOutput
}

public struct UnavailableLanguageModel: LocalLanguageModel {
    public let tier: ModelTier

    public init(tier: ModelTier = .lite) {
        self.tier = tier
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        throw ModelFailure.unavailable
    }
}
