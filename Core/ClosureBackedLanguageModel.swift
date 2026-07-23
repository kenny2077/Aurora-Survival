import Foundation

/// Adapter seam for a llama.cpp, LiteRT-LM, or Apple Foundation Models runtime.
/// Production adapters must remain offline and return text for citation validation.
public struct ClosureBackedLanguageModel: LocalLanguageModel {
    public let tier: ModelTier
    private let generator: @Sendable (String, String) async throws -> String

    public init(
        tier: ModelTier,
        generator: @escaping @Sendable (String, String) async throws -> String
    ) {
        self.tier = tier
        self.generator = generator
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        let builder = GroundedPromptBuilder()
        return try await generator(
            builder.systemPrompt(for: tier),
            builder.userPrompt(from: prompt)
        )
    }
}
