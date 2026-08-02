import Foundation
import TrailGuardLlamaC

public enum LlamaSessionError: Error, Equatable, Sendable {
    case invalidConfiguration
    case loadFailed(String)
    case completionFailed(String)
}

public struct LlamaSessionCompletion: Equatable, Sendable {
    public let text: String
    public let firstTokenMicroseconds: Int64
    public let totalMicroseconds: Int64
    public let generatedTokenCount: Int
}

public actor LlamaSession {
    private var handle: TGLlamaSessionRef?

    public init(
        modelURL: URL,
        contextTokens: Int,
        threadCount: Int
    ) throws {
        guard contextTokens > 0,
              threadCount > 0,
              contextTokens <= Int(Int32.max),
              threadCount <= Int(Int32.max)
        else {
            throw LlamaSessionError.invalidConfiguration
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let session = modelURL.path.withCString { modelPath in
            tg_llama_session_create(
                modelPath,
                Int32(contextTokens),
                Int32(threadCount),
                &errorPointer
            )
        }
        guard let session else {
            throw LlamaSessionError.loadFailed(
                Self.consumeError(errorPointer)
            )
        }
        handle = session
    }

    deinit {
        if let handle {
            tg_llama_session_destroy(handle)
        }
    }

    public func complete(
        systemPrompt: String,
        userPrompt: String,
        maximumOutputTokens: Int
    ) throws -> LlamaSessionCompletion {
        guard let handle,
              maximumOutputTokens > 0,
              maximumOutputTokens <= Int(Int32.max)
        else {
            throw LlamaSessionError.invalidConfiguration
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        var firstTokenMicroseconds: Int64 = 0
        var totalMicroseconds: Int64 = 0
        var generatedTokenCount: Int32 = 0
        let outputPointer = systemPrompt.withCString { system in
            userPrompt.withCString { user in
                tg_llama_session_complete(
                    handle,
                    system,
                    user,
                    Int32(maximumOutputTokens),
                    &firstTokenMicroseconds,
                    &totalMicroseconds,
                    &generatedTokenCount,
                    &errorPointer
                )
            }
        }
        guard let outputPointer else {
            throw LlamaSessionError.completionFailed(
                Self.consumeError(errorPointer)
            )
        }
        defer { tg_llama_string_free(outputPointer) }
        return LlamaSessionCompletion(
            text: String(cString: outputPointer),
            firstTokenMicroseconds: firstTokenMicroseconds,
            totalMicroseconds: totalMicroseconds,
            generatedTokenCount: Int(generatedTokenCount)
        )
    }

    public func unload() {
        guard let handle else { return }
        tg_llama_session_destroy(handle)
        self.handle = nil
    }

    private nonisolated static func consumeError(
        _ pointer: UnsafeMutablePointer<CChar>?
    ) -> String {
        guard let pointer else { return "Unknown llama runtime error." }
        defer { tg_llama_string_free(pointer) }
        return String(cString: pointer)
    }
}
