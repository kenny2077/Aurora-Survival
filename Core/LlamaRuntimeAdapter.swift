import Foundation

public struct LlamaRuntimeConfiguration: Equatable, Sendable {
    public static let liteContextTokens = 2_048
    public static let liteMaximumOutputTokens = 160
    public static let expertMaximumOutputTokens = 256

    public let modelURL: URL
    public let visionProjectorURL: URL?
    public let contextTokens: Int
    public let maximumOutputTokens: Int
    public let maximumImageDimension: Int?
    public let threadCount: Int

    public init(
        modelURL: URL,
        visionProjectorURL: URL? = nil,
        contextTokens: Int = 4_096,
        maximumOutputTokens: Int = 512,
        maximumImageDimension: Int? = nil,
        threadCount: Int
    ) {
        self.modelURL = modelURL
        self.visionProjectorURL = visionProjectorURL
        self.contextTokens = contextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.maximumImageDimension = maximumImageDimension
        self.threadCount = threadCount
    }

    public static func expert(
        modelURL: URL,
        visionProjectorURL: URL,
        profile: ExpertContextProfile,
        threadCount: Int
    ) -> LlamaRuntimeConfiguration {
        LlamaRuntimeConfiguration(
            modelURL: modelURL,
            visionProjectorURL: visionProjectorURL,
            contextTokens: profile.contextTokens,
            maximumOutputTokens: expertMaximumOutputTokens,
            maximumImageDimension: profile.maximumImageDimension,
            threadCount: threadCount
        )
    }

    public func applying(_ profile: ExpertContextProfile) -> LlamaRuntimeConfiguration {
        LlamaRuntimeConfiguration(
            modelURL: modelURL,
            visionProjectorURL: visionProjectorURL,
            contextTokens: profile.contextTokens,
            maximumOutputTokens: maximumOutputTokens,
            maximumImageDimension: profile.maximumImageDimension,
            threadCount: threadCount
        )
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
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode
    ) async throws -> LlamaCompletionResult
    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> LlamaCompletionResult
    func unload() async
}

public extension LlamaRuntimeBackend {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> LlamaCompletionResult {
        let completion = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imageData: imageData,
            maximumOutputTokens: maximumOutputTokens,
            evidenceCount: evidenceCount,
            grammarMode: grammarMode
        )
        tokenSink?(completion.text)
        return completion
    }
}

public enum LlamaGrammarMode: Int32, Equatable, Sendable {
    case responseEnvelope = 0
    case expertIntent = 2
    case expertClarification = 3
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
    private let completionSink: (@Sendable (String) async -> Void)?
    private var loaded = false
    private var loadedContextTokens: Int?

    public init(
        tier: ModelTier,
        configuration: LlamaRuntimeConfiguration,
        backend: any LlamaRuntimeBackend,
        metricsSink: (@Sendable (LlamaCompletionMetrics) async -> Void)? = nil,
        completionSink: (@Sendable (String) async -> Void)? = nil
    ) throws {
        guard FileManager.default.fileExists(atPath: configuration.modelURL.path) else {
            throw LlamaAdapterError.modelFileMissing
        }
        if tier == .expert {
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
        self.completionSink = completionSink
    }

    public func generate(prompt: ModelPrompt) async throws -> String {
        try await generate(prompt: prompt, tokenSink: nil)
    }

    public func generate(
        prompt: ModelPrompt,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> String {
        if prompt.permitsVisionReasoning && prompt.imageData == nil {
            throw LlamaAdapterError.imageRequiredForVisionRequest
        }
        let activeConfiguration = prompt.tier == .expert
            ? configuration.applying(prompt.expertContextProfile ?? .constrained)
            : configuration
        if loaded, loadedContextTokens != activeConfiguration.contextTokens {
            await backend.unload()
            loaded = false
            loadedContextTokens = nil
        }
        let wasColdStart = !loaded
        var loadMilliseconds = 0
        if wasColdStart {
            let loadStarted = Date()
            try await backend.load(configuration: activeConfiguration)
            loadMilliseconds = Int(
                Date().timeIntervalSince(loadStarted) * 1_000
            )
            loaded = true
            loadedContextTokens = activeConfiguration.contextTokens
        }
        let builder = GroundedPromptBuilder()
        let completion: LlamaCompletionResult
        let grammarMode: LlamaGrammarMode
        switch prompt.purpose {
        case .expertIntent: grammarMode = .expertIntent
        case .clarification where prompt.tier == .expert:
            grammarMode = .expertClarification
        default: grammarMode = .responseEnvelope
        }
        do {
            try Task.checkCancellation()
            completion = try await backend.complete(
                systemPrompt: builder.systemPrompt(
                    for: prompt,
                    outputMode: outputMode
                ),
                userPrompt: builder.userPrompt(
                    from: prompt,
                    outputMode: outputMode
                ),
                imageData: prompt.permitsVisionReasoning ? prompt.imageData : nil,
                maximumOutputTokens: activeConfiguration.maximumOutputTokens,
                evidenceCount: prompt.purpose == .grounded
                    ? prompt.tier == .expert
                        ? prompt.expertEvidence.flatMap { $0.scenario.claims }.count
                        : prompt.evidence.count
                    : 0,
                grammarMode: grammarMode,
                tokenSink: tokenSink
            )
        } catch {
            if tier == .expert {
                await backend.unload()
                loaded = false
                loadedContextTokens = nil
            }
            throw error
        }
        await completionSink?(completion.text)
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
        loadedContextTokens = nil
    }
}
