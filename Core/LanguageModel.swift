import Foundation

public struct ModelPrompt: Sendable {
    public let question: String
    public let evidence: [RetrievedPassage]
    public let imageData: Data?
    public let imageObservations: [String]
    public let tier: ModelTier
    public let permitsVisionReasoning: Bool
    public let conversationHistory: [ConversationTurn]

    public init(
        question: String,
        evidence: [RetrievedPassage],
        imageData: Data? = nil,
        imageObservations: [String],
        tier: ModelTier,
        permitsVisionReasoning: Bool,
        conversationHistory: [ConversationTurn] = []
    ) {
        self.question = question
        self.evidence = evidence
        self.imageData = imageData
        self.imageObservations = imageObservations
        self.tier = tier
        self.permitsVisionReasoning = permitsVisionReasoning
        self.conversationHistory = conversationHistory
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

/// A zero-dependency fallback that keeps the app useful before model weights are installed.
/// It is intentionally extractive: it only formats reviewed knowledge, never invents steps.
public struct ExtractiveLanguageModel: LocalLanguageModel {
    public let tier: ModelTier
    public let outputMode: ModelOutputMode = .citationText

    public init(tier: ModelTier = .essential) {
        self.tier = tier
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        guard !prompt.evidence.isEmpty else {
            return "I do not have a reviewed offline procedure that matches this question. "
                + "Move to a safe location, use Emergency SOS if there is immediate danger, "
                + "and avoid actions you cannot safely reverse."
        }

        var sections: [String] = []
        for (index, passage) in prompt.evidence.prefix(1).enumerated() {
            let article = passage.article
            var block = "\(article.title) [\(index + 1)]\n\(article.summary)"
            if !article.steps.isEmpty {
                block += "\n" + article.steps.prefix(5).enumerated()
                    .map { "\($0.offset + 1). \($0.element)" }
                    .joined(separator: "\n")
            }
            if let warning = article.warnings.first {
                block += "\nWarning: \(warning)"
            }
            sections.append(block)
        }
        return sections.joined(separator: "\n\n")
    }
}
