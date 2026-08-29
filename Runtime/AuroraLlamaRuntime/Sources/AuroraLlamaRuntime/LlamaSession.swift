import Foundation
import AuroraLlamaC

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

public enum LlamaSessionGrammar: Int32, Equatable, Sendable {
    case responseEnvelope = 0
    case expertIntent = 2
    case expertClarification = 3
}

public actor LlamaSession {
    private var handle: TGLlamaSessionRef?

    public init(
        modelURL: URL,
        projectorURL: URL? = nil,
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
            if let projectorURL {
                return projectorURL.path.withCString { projectorPath in
                    tg_llama_session_create(
                        modelPath,
                        projectorPath,
                        Int32(contextTokens),
                        Int32(threadCount),
                        &errorPointer
                    )
                }
            }
            return tg_llama_session_create(
                modelPath,
                nil,
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
        imageData: Data? = nil,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaSessionGrammar = .responseEnvelope,
        tokenSink: (@Sendable (String) -> Void)? = nil
    ) throws -> LlamaSessionCompletion {
        guard let handle,
              maximumOutputTokens > 0,
              maximumOutputTokens <= Int(Int32.max),
              (0...30).contains(evidenceCount)
        else {
            throw LlamaSessionError.invalidConfiguration
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        var firstTokenMicroseconds: Int64 = 0
        var totalMicroseconds: Int64 = 0
        var generatedTokenCount: Int32 = 0
        let tokenBox = tokenSink.map(TokenCallbackBox.init)
        let tokenContext = tokenBox.map {
            Unmanaged.passUnretained($0).toOpaque()
        }
        let invoke: (UnsafePointer<UInt8>?, Int64) -> UnsafeMutablePointer<CChar>? = {
            imageBytes, imageByteCount in
            systemPrompt.withCString { system in
                userPrompt.withCString { user in
                    tg_llama_session_complete(
                        handle,
                        system,
                        user,
                        imageBytes,
                        imageByteCount,
                        Int32(maximumOutputTokens),
                        Int32(evidenceCount),
                        grammarMode.rawValue,
                        tokenBox == nil ? nil : llamaTokenCallback,
                        tokenContext,
                        &firstTokenMicroseconds,
                        &totalMicroseconds,
                        &generatedTokenCount,
                        &errorPointer
                    )
                }
            }
        }
        let outputPointer = imageData?.withUnsafeBytes { bytes in
            invoke(
                bytes.bindMemory(to: UInt8.self).baseAddress,
                Int64(bytes.count)
            )
        } ?? invoke(nil, 0)
        guard let outputPointer else {
            throw LlamaSessionError.completionFailed(
                Self.consumeError(errorPointer)
            )
        }
        tokenBox?.flush()
        defer { tg_llama_string_free(outputPointer) }
        return LlamaSessionCompletion(
            text: String(cString: outputPointer),
            firstTokenMicroseconds: firstTokenMicroseconds,
            totalMicroseconds: totalMicroseconds,
            generatedTokenCount: Int(generatedTokenCount)
        )
    }

    public nonisolated static var supportsVision: Bool {
        tg_llama_runtime_supports_vision() == 1
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

private final class TokenCallbackBox: @unchecked Sendable {
    private let sink: @Sendable (String) -> Void
    private var pending = Data()

    init(_ sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    func receive(_ bytes: UnsafePointer<UInt8>, count: Int) {
        pending.append(bytes, count: count)
        let maximumTail = min(3, pending.count)
        for tailCount in 0...maximumTail {
            let prefixCount = pending.count - tailCount
            guard prefixCount > 0,
                  let value = String(
                    data: pending.prefix(prefixCount),
                    encoding: .utf8
                  ) else { continue }
            sink(value)
            pending.removeFirst(prefixCount)
            return
        }
    }

    func flush() {
        guard !pending.isEmpty else { return }
        sink(String(decoding: pending, as: UTF8.self))
        pending.removeAll(keepingCapacity: false)
    }
}

private let llamaTokenCallback: @convention(c) (
    UnsafePointer<UInt8>?,
    Int32,
    UnsafeMutableRawPointer?
) -> Void = { bytes, count, context in
    guard let bytes, count > 0, let context else { return }
    Unmanaged<TokenCallbackBox>.fromOpaque(context)
        .takeUnretainedValue()
        .receive(bytes, count: Int(count))
}

public actor LlamaEmbeddingSession {
    private var handle: TGEmbeddingSessionRef?
    public nonisolated let dimensions: Int

    public init(
        modelURL: URL,
        contextTokens: Int = 512,
        threadCount: Int,
        dimensions: Int = 384
    ) throws {
        guard contextTokens > 0,
              threadCount > 0,
              dimensions > 0,
              contextTokens <= Int(Int32.max),
              threadCount <= Int(Int32.max),
              dimensions <= Int(Int32.max)
        else { throw LlamaSessionError.invalidConfiguration }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let session = modelURL.path.withCString { path in
            tg_embedding_session_create(
                path,
                Int32(contextTokens),
                Int32(threadCount),
                Int32(dimensions),
                &errorPointer
            )
        }
        guard let session else {
            throw LlamaSessionError.loadFailed(Self.consumeEmbeddingError(errorPointer))
        }
        self.dimensions = dimensions
        handle = session
    }

    deinit {
        if let handle { tg_embedding_session_destroy(handle) }
    }

    public func embedding(for text: String) throws -> [Float] {
        guard let handle,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LlamaSessionError.invalidConfiguration }
        var output = [Float](repeating: 0, count: dimensions)
        var errorPointer: UnsafeMutablePointer<CChar>?
        let succeeded = text.withCString { value in
            output.withUnsafeMutableBufferPointer { buffer in
                tg_embedding_session_embed(
                    handle,
                    value,
                    buffer.baseAddress,
                    Int32(dimensions),
                    &errorPointer
                )
            }
        }
        guard succeeded == 1 else {
            throw LlamaSessionError.completionFailed(
                Self.consumeEmbeddingError(errorPointer)
            )
        }
        return output
    }

    public func unload() {
        guard let handle else { return }
        tg_embedding_session_destroy(handle)
        self.handle = nil
    }

    private nonisolated static func consumeEmbeddingError(
        _ pointer: UnsafeMutablePointer<CChar>?
    ) -> String {
        guard let pointer else { return "Unknown embedding runtime error." }
        defer { tg_llama_string_free(pointer) }
        return String(cString: pointer)
    }
}
