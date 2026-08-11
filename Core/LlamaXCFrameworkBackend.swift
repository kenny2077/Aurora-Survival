#if canImport(TrailGuardLlamaRuntime)
import Foundation
import TrailGuardLlamaRuntime

public enum LlamaXCFrameworkBackendError: Error, Equatable {
    case imageInputNotImplemented
}

public actor LlamaXCFrameworkBackend: LlamaRuntimeBackend {
    private var session: LlamaSession?

    public init() {}

    public func load(configuration: LlamaRuntimeConfiguration) async throws {
        guard session == nil else { return }
        session = try LlamaSession(
            modelURL: configuration.modelURL,
            contextTokens: configuration.contextTokens,
            threadCount: configuration.threadCount
        )
    }

    public func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int
    ) async throws -> LlamaCompletionResult {
        guard imageData == nil else {
            throw LlamaXCFrameworkBackendError.imageInputNotImplemented
        }
        guard let session else {
            throw LlamaSessionError.invalidConfiguration
        }
        let completion = try await session.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maximumOutputTokens: maximumOutputTokens,
            evidenceCount: evidenceCount
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
    }
}
#endif
