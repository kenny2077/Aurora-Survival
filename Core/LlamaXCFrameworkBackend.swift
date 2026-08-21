#if canImport(AuroraLlamaRuntime)
import Foundation
import ImageIO
import AuroraLlamaRuntime

public enum LlamaXCFrameworkBackendError: Error, Equatable {
    case imageInputNotImplemented
    case corruptImage
}

public actor LlamaXCFrameworkBackend: LlamaRuntimeBackend {
    private var session: LlamaSession?
    private var maximumImageDimension: Int?

    public init() {}

    public nonisolated static var supportsVision: Bool {
        LlamaSession.supportsVision
    }

    public nonisolated static func validateExpertRuntime(
        configuration: LlamaRuntimeConfiguration
    ) async throws {
        guard Self.supportsVision else {
            throw LlamaXCFrameworkBackendError.imageInputNotImplemented
        }
        let probe = try LlamaSession(
            modelURL: configuration.modelURL,
            projectorURL: configuration.visionProjectorURL,
            contextTokens: ExpertContextProfile.constrained.contextTokens,
            threadCount: configuration.threadCount
        )
        await probe.unload()
    }

    public func load(configuration: LlamaRuntimeConfiguration) async throws {
        guard session == nil else { return }
        session = try LlamaSession(
            modelURL: configuration.modelURL,
            projectorURL: configuration.visionProjectorURL,
            contextTokens: configuration.contextTokens,
            threadCount: configuration.threadCount
        )
        maximumImageDimension = configuration.maximumImageDimension
    }

    public func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode
    ) async throws -> LlamaCompletionResult {
        try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imageData: imageData,
            maximumOutputTokens: maximumOutputTokens,
            evidenceCount: evidenceCount,
            grammarMode: grammarMode,
            tokenSink: nil
        )
    }

    public func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode,
        tokenSink: (@Sendable (String) -> Void)?
    ) async throws -> LlamaCompletionResult {
        guard let session else {
            throw LlamaSessionError.invalidConfiguration
        }
        let boundedImage = try imageData.map {
            try Self.boundedImageData(
                $0,
                maximumDimension: maximumImageDimension
            )
        }
        let sessionGrammar: LlamaSessionGrammar
        switch grammarMode {
        case .expertIntent: sessionGrammar = .expertIntent
        case .expertClarification: sessionGrammar = .expertClarification
        case .responseEnvelope: sessionGrammar = .responseEnvelope
        }
        let completion = try await session.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            imageData: boundedImage,
            maximumOutputTokens: maximumOutputTokens,
            evidenceCount: evidenceCount,
            grammarMode: sessionGrammar,
            tokenSink: tokenSink
        )
        return LlamaCompletionResult(
            text: completion.text,
            metrics: LlamaCompletionMetrics(
                firstTokenMilliseconds: Int(
                    completion.firstTokenMicroseconds / 1_000
                ),
                totalMilliseconds: Int(
                    completion.totalMicroseconds / 1_000
                ),
                generatedTokenCount: completion.generatedTokenCount,
                coldStart: false
            )
        )
    }

    public func unload() async {
        guard let session else { return }
        await session.unload()
        self.session = nil
        maximumImageDimension = nil
    }

    private nonisolated static func boundedImageData(
        _ data: Data,
        maximumDimension: Int?
    ) throws -> Data {
        guard let maximumDimension else { return data }
        guard maximumDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                ] as CFDictionary
              )
        else { throw LlamaXCFrameworkBackendError.corruptImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { throw LlamaXCFrameworkBackendError.corruptImage }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw LlamaXCFrameworkBackendError.corruptImage
        }
        return output as Data
    }
}

public actor LlamaBGEEmbeddingProvider: ExpertQueryEmbeddingProvider {
    public static let queryPrefix =
        "Represent this sentence for searching relevant passages: "

    private let modelURL: URL
    private let threadCount: Int
    private var session: LlamaEmbeddingSession?
    private var passageCache: [String: [Float]] = [:]

    public init(modelURL: URL, threadCount: Int = 4) {
        self.modelURL = modelURL
        self.threadCount = threadCount
    }

    public func embedding(for query: String) async throws -> [Float] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LlamaSessionError.invalidConfiguration }
        let active: LlamaEmbeddingSession
        if let session {
            active = session
        } else {
            let created = try LlamaEmbeddingSession(
                modelURL: modelURL,
                contextTokens: ActiveModelRuntimeResolver
                    .acceptedExpertEmbeddingContextTokens,
                threadCount: threadCount,
                dimensions: ActiveModelRuntimeResolver
                    .acceptedExpertEmbeddingDimensions
            )
            session = created
            active = created
        }
        return try await active.embedding(for: Self.queryPrefix + clean)
    }

    public func passageEmbedding(for text: String) async throws -> [Float] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw LlamaSessionError.invalidConfiguration }
        if let cached = passageCache[clean] { return cached }
        let active = try activeSession()
        let value = try await active.embedding(for: clean)
        if passageCache.count >= 512 {
            passageCache.removeAll(keepingCapacity: true)
        }
        passageCache[clean] = value
        return value
    }

    private func activeSession() throws -> LlamaEmbeddingSession {
        if let session { return session }
        let created = try LlamaEmbeddingSession(
            modelURL: modelURL,
            contextTokens: ActiveModelRuntimeResolver
                .acceptedExpertEmbeddingContextTokens,
            threadCount: threadCount,
            dimensions: ActiveModelRuntimeResolver
                .acceptedExpertEmbeddingDimensions
        )
        session = created
        return created
    }

    public func unload() async {
        await session?.unload()
        session = nil
        passageCache.removeAll()
    }
}
#endif
