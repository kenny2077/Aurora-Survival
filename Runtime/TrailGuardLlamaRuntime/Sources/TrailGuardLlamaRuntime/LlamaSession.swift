import Foundation
import AuroraLlamaC

public enum LlamaSessionError: Error, Equatable, Sendable {
    case invalidConfiguration
    case loadFailed(String)
    case completionFailed(String)
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
    ) throws -> String {
        guard let handle,
              maximumOutputTokens > 0,
              maximumOutputTokens <= Int(Int32.max)
        else {
            throw LlamaSessionError.invalidConfiguration
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let outputPointer = systemPrompt.withCString { system in
            userPrompt.withCString { user in
                tg_llama_session_complete(
                    handle,
                    system,
                    user,
                    Int32(maximumOutputTokens),
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
        return String(cString: outputPointer)
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
