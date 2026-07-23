import Foundation

public struct LlamaRuntimeConfiguration: Equatable, Sendable {
    public let modelURL: URL
    public let visionProjectorURL: URL?
    public let contextTokens: Int
    public let maximumOutputTokens: Int
    public let threadCount: Int

    public init(
        modelURL: URL,
        visionProjectorURL: URL? = nil,
        contextTokens: Int = 4_096,
        maximumOutputTokens: Int = 512,
        threadCount: Int
    ) {
        self.modelURL = modelURL
        self.visionProjectorURL = visionProjectorURL
        self.contextTokens = contextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.threadCount = threadCount
    }
}

public protocol LlamaRuntimeBackend: Sendable {
    func load(configuration: LlamaRuntimeConfiguration) async throws
    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int
    ) async throws -> String
    func unload() async
}

public enum LlamaAdapterError: Error, Equatable {
    case modelFileMissing
    case projectorFileMissing
    case projectorNotAllowedForTextTier
    case projectorRequiredForVisionTier
    case imageRequiredForVisionRequest
}

/// Owns policy around a future pinned llama.cpp XCFramework. The C/Objective-C++
/// bridge implements `LlamaRuntimeBackend`; this actor keeps that bridge behind
/// the same evidence and citation contract used by every other model.
public actor LlamaLanguageModel: LocalLanguageModel {
    public nonisolated let tier: ModelTier
    public nonisolated let outputMode: ModelOutputMode = .groundedJSON

    private let backend: any LlamaRuntimeBackend
    private let configuration: LlamaRuntimeConfiguration
    private var loaded = false

    public init(
        tier: ModelTier,
        configuration: LlamaRuntimeConfiguration,
        backend: any LlamaRuntimeBackend
    ) throws {
        guard FileManager.default.fileExists(atPath: configuration.modelURL.path) else {
            throw LlamaAdapterError.modelFileMissing
        }
        if tier == .visionExpert {
            guard let projector = configuration.visionProjectorURL else {
                throw LlamaAdapterError.projectorRequiredForVisionTier
            }
            guard FileManager.default.fileExists(atPath: projector.path) else {
                throw LlamaAdapterError.projectorFileMissing
            }
        } else if configuration.visionProjectorURL != nil {
            throw LlamaAdapterError.projectorNotAllowedForTextTier
        }
        self.tier = tier
        self.configuration = configuration
        self.backend = backend
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        if prompt.permitsVisionReasoning && prompt.imageData == nil {
            throw LlamaAdapterError.imageRequiredForVisionRequest
        }
        if !loaded {
            try await backend.load(configuration: configuration)
            loaded = true
        }
        let builder = GroundedPromptBuilder()
        return try await backend.complete(
            systemPrompt: builder.systemPrompt(
                for: tier,
                outputMode: outputMode
            ),
            userPrompt: builder.userPrompt(
                from: prompt,
                outputMode: outputMode
            ),
            imageData: prompt.permitsVisionReasoning ? prompt.imageData : nil,
            maximumOutputTokens: configuration.maximumOutputTokens
        )
    }

    public func unload() async {
        guard loaded else { return }
        await backend.unload()
        loaded = false
    }
}
