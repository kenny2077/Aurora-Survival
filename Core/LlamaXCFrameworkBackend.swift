#if canImport(AuroraLlamaRuntime)
import Foundation
import AuroraLlamaRuntime

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
        maximumOutputTokens: Int
    ) async throws -> String {
        guard imageData == nil else {
            throw LlamaXCFrameworkBackendError.imageInputNotImplemented
        }
        guard let session else {
            throw LlamaSessionError.invalidConfiguration
        }
        return try await session.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maximumOutputTokens: maximumOutputTokens
        )
    }

    public func unload() async {
        guard let session else { return }
        await session.unload()
        self.session = nil
    }
}
#endif
