import Foundation

/// Adapter seam for a llama.cpp, LiteRT-LM, or Apple Foundation Models runtime.
/// Production adapters must remain offline and return text for citation validation.
public struct ClosureBackedLanguageModel: LocalLanguageModel {
    public let tier: ModelTier
    public let outputMode: ModelOutputMode
    private let generator: @Sendable (String, String) async throws -> String

    public init(
        tier: ModelTier,
        outputMode: ModelOutputMode = .citationText,
        generator: @escaping @Sendable (String, String) async throws -> String
    ) {
        self.tier = tier
        self.outputMode = outputMode
        self.generator = generator
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        let builder = GroundedPromptBuilder()
        return try await generator(
            builder.systemPrompt(for: tier, outputMode: outputMode),
            builder.userPrompt(from: prompt, outputMode: outputMode)
        )
    }
}
