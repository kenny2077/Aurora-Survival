import Foundation

public struct LlamaRuntimeConfiguration: Equatable, Sendable {
    public static let liteContextTokens = 2_048
    public static let liteMaximumOutputTokens = 128

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

    public static func lite(
        modelURL: URL,
        threadCount: Int
    ) -> LlamaRuntimeConfiguration {
        LlamaRuntimeConfiguration(
            modelURL: modelURL,
            contextTokens: liteContextTokens,
            maximumOutputTokens: liteMaximumOutputTokens,
            threadCount: threadCount
        )
    }
}

public protocol LlamaRuntimeBackend: Sendable {
    func load(configuration: LlamaRuntimeConfiguration) async throws
    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int
    ) async throws -> LlamaCompletionResult
    func unload() async
}

public struct LlamaCompletionMetrics: Equatable, Sendable {
    public let firstTokenMilliseconds: Int
    public let totalMilliseconds: Int
    public let generatedTokenCount: Int
    public let coldStart: Bool

    public var tokensPerSecond: Double {
        let decodeMilliseconds = totalMilliseconds - firstTokenMilliseconds
        if generatedTokenCount > 1, decodeMilliseconds > 0 {
            return Double(generatedTokenCount - 1) * 1_000
                / Double(decodeMilliseconds)
        }
        guard totalMilliseconds > 0 else { return 0 }
        return Double(generatedTokenCount) * 1_000
            / Double(totalMilliseconds)
    }
}

public struct LlamaCompletionResult: Equatable, Sendable {
    public let text: String
    public let metrics: LlamaCompletionMetrics

    public init(text: String, metrics: LlamaCompletionMetrics) {
        self.text = text
        self.metrics = metrics
    }
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
    private let metricsSink: (@Sendable (LlamaCompletionMetrics) async -> Void)?
    private var loaded = false

    public init(
        tier: ModelTier,
        configuration: LlamaRuntimeConfiguration,
        backend: any LlamaRuntimeBackend,
        metricsSink: (@Sendable (LlamaCompletionMetrics) async -> Void)? = nil
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
        self.metricsSink = metricsSink
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        if prompt.permitsVisionReasoning && prompt.imageData == nil {
            throw LlamaAdapterError.imageRequiredForVisionRequest
        }
        let wasColdStart = !loaded
        var loadMilliseconds = 0
        if wasColdStart {
            let loadStarted = Date()
            try await backend.load(configuration: configuration)
            loadMilliseconds = Int(
                Date().timeIntervalSince(loadStarted) * 1_000
            )
            loaded = true
        }
        let builder = GroundedPromptBuilder()
        let completion = try await backend.complete(
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
        let metrics = LlamaCompletionMetrics(
            firstTokenMilliseconds: completion.metrics.firstTokenMilliseconds
                + loadMilliseconds,
            totalMilliseconds: completion.metrics.totalMilliseconds
                + loadMilliseconds,
            generatedTokenCount: completion.metrics.generatedTokenCount,
            coldStart: wasColdStart
        )
        await metricsSink?(metrics)
        return completion.text
    }

    public func unload() async {
        guard loaded else { return }
        await backend.unload()
        loaded = false
    }
}
