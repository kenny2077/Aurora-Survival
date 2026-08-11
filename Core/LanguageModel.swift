import Foundation

public enum ModelPromptPurpose: Equatable, Sendable {
    case ordinary
    case grounded
    case clarification
    case incidentFallback
    case incidentIntake
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
        self.purpose = purpose ?? (evidence.isEmpty ? .ordinary : .grounded)
        self.attempt = attempt
    }

    public func repairing() -> ModelPrompt {
        ModelPrompt(
            question: question,
            evidence: evidence,
            imageData: imageData,
            imageObservations: imageObservations,
            tier: tier,
            permitsVisionReasoning: permitsVisionReasoning,
            conversationHistory: conversationHistory,
            purpose: purpose,
            attempt: .repair
        )
    }
}

public protocol LocalLanguageModel: Sendable {
    var tier: ModelTier { get }
    var outputMode: ModelOutputMode { get }
    func generate(prompt: ModelPrompt) async throws -> String
}

public enum ModelOutputMode: String, Codable, Sendable {
    case citationText = "citation_text"
    case groundedJSON = "grounded_json"
}

public extension LocalLanguageModel {
    var outputMode: ModelOutputMode { .citationText }
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
