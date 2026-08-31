import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class LlamaRuntimeAdapterTests: XCTestCase {
    func testDecodeRateExcludesFirstTokenLatency() {
        let metrics = LlamaCompletionMetrics(
            firstTokenMilliseconds: 100,
            totalMilliseconds: 1_100,
            generatedTokenCount: 11,
            coldStart: true
        )

        XCTAssertEqual(metrics.tokensPerSecond, 10, accuracy: 0.001)
    }

    func testLiteConfigurationUsesConservativeLimits() throws {
        let fixture = try makeFiles(includeProjector: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let configuration = LlamaRuntimeConfiguration.lite(
            modelURL: fixture.model,
            threadCount: 2
        )

        XCTAssertEqual(configuration.contextTokens, 2_048)
        XCTAssertEqual(configuration.maximumOutputTokens, 256)
        XCTAssertNil(configuration.visionProjectorURL)
    }

    func testTextTierNeverForwardsImage() async throws {
        let fixture = try makeFiles(includeProjector: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .lite,
            configuration: LlamaRuntimeConfiguration(
                modelURL: fixture.model,
                threadCount: 4
            ),
            backend: backend
        )
        let prompt = ModelPrompt(
            question: "question",
            evidence: [],
            imageData: Data("image".utf8),
            imageObservations: ["OCR"],
            tier: .lite,
            permitsVisionReasoning: false
        )

        _ = try await model.generate(prompt: prompt)
        let imageWasForwarded = await backend.imageWasForwarded
        XCTAssertFalse(imageWasForwarded)
    }

    func testVisionTierRequiresProjector() throws {
        let fixture = try makeFiles(includeProjector: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertThrowsError(
            try LlamaLanguageModel(
                tier: .expert,
                configuration: LlamaRuntimeConfiguration(
                    modelURL: fixture.model,
                    threadCount: 4
                ),
                backend: RecordingLlamaBackend()
            )
        ) { error in
            XCTAssertEqual(
                error as? LlamaAdapterError,
                .projectorRequiredForVisionTier
            )
        }
    }

    func testVisionTierForwardsImageAfterCapabilityApproval() async throws {
        let fixture = try makeFiles(includeProjector: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .expert,
            configuration: LlamaRuntimeConfiguration(
                modelURL: fixture.model,
                visionProjectorURL: fixture.projector,
                threadCount: 4
            ),
            backend: backend
        )
        let prompt = ModelPrompt(
            question: "What is visible?",
            evidence: [],
            imageData: Data("image".utf8),
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: true
        )

        _ = try await model.generate(prompt: prompt)
        let imageWasForwarded = await backend.imageWasForwarded
        let loadCount = await backend.loadCount
        XCTAssertTrue(imageWasForwarded)
        XCTAssertEqual(loadCount, 1)
    }

    func testExpertContextProfileChangeReloadsNativeContext() async throws {
        let fixture = try makeFiles(includeProjector: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .expert,
            configuration: .expert(
                modelURL: fixture.model,
                visionProjectorURL: try XCTUnwrap(fixture.projector),
                profile: .full,
                threadCount: 4
            ),
            backend: backend
        )

        for profile in [ExpertContextProfile.full, .balanced, .constrained] {
            _ = try await model.generate(prompt: ModelPrompt(
                question: "Give safe text-only guidance.",
                evidence: [],
                imageObservations: [],
                tier: .expert,
                permitsVisionReasoning: false,
                expertContextProfile: profile
            ))
        }

        let loadedContexts = await backend.loadedContexts
        let unloadCount = await backend.unloadCount
        XCTAssertEqual(loadedContexts, [8_192, 6_144, 4_096])
        XCTAssertEqual(unloadCount, 2)
    }

    func testExpertRuntimeFailureUnloadsBeforeReturningFailure() async throws {
        let fixture = try makeFiles(includeProjector: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        await backend.setShouldFail(true)
        let model = try LlamaLanguageModel(
            tier: .expert,
            configuration: .expert(
                modelURL: fixture.model,
                visionProjectorURL: try XCTUnwrap(fixture.projector),
                profile: .constrained,
                threadCount: 4
            ),
            backend: backend
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await model.generate(prompt: ModelPrompt(
                question: "What now?",
                evidence: [],
                imageObservations: [],
                tier: .expert,
                permitsVisionReasoning: false,
                expertContextProfile: .constrained
            ))
        }
        let unloadCount = await backend.unloadCount
        XCTAssertEqual(unloadCount, 1)
    }

    func testBackendLoadsOnlyOnceUntilUnload() async throws {
        let fixture = try makeFiles(includeProjector: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .lite,
            configuration: LlamaRuntimeConfiguration(
                modelURL: fixture.model,
                threadCount: 4
            ),
            backend: backend
        )
        let prompt = ModelPrompt(
            question: "question",
            evidence: [],
            imageObservations: [],
            tier: .lite,
            permitsVisionReasoning: false
        )

        _ = try await model.generate(prompt: prompt)
        _ = try await model.generate(prompt: prompt)
        var loadCount = await backend.loadCount
        XCTAssertEqual(loadCount, 1)

        await model.unload()
        _ = try await model.generate(prompt: prompt)
        loadCount = await backend.loadCount
        XCTAssertEqual(loadCount, 2)
    }

    func testGrammarEvidenceModeFollowsPromptPurpose() async throws {
        let fixture = try makeFiles(includeProjector: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .lite,
            configuration: .lite(modelURL: fixture.model, threadCount: 2),
            backend: backend
        )

        _ = try await model.generate(prompt: ModelPrompt(
            question: "incident",
            evidence: [],
            imageObservations: [],
            tier: .lite,
            permitsVisionReasoning: false,
            purpose: .incidentFallback
        ))
        let fallbackEvidenceCount = await backend.lastEvidenceCount
        XCTAssertEqual(fallbackEvidenceCount, 0)

        _ = try await model.generate(prompt: ModelPrompt(
            question: "grounded",
            evidence: [RetrievedPassage(article: makeArticle(), score: 1)],
            imageObservations: [],
            tier: .lite,
            permitsVisionReasoning: false,
            purpose: .grounded
        ))
        let groundedEvidenceCount = await backend.lastEvidenceCount
        XCTAssertEqual(groundedEvidenceCount, 1)
    }

    func testExpertIntentUsesDedicatedGrammarMode() async throws {
        let fixture = try makeFiles(includeProjector: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = RecordingLlamaBackend()
        let model = try LlamaLanguageModel(
            tier: .expert,
            configuration: .expert(
                modelURL: fixture.model,
                visionProjectorURL: try XCTUnwrap(fixture.projector),
                profile: .constrained,
                threadCount: 2
            ),
            backend: backend
        )

        _ = try await model.generate(prompt: ModelPrompt(
            question: "What should I do?",
            evidence: [],
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: false,
            purpose: .expertIntent
        ))
        let grammarMode = await backend.lastGrammarMode
        XCTAssertEqual(grammarMode, .expertIntent)

        _ = try await model.generate(prompt: ModelPrompt(
            question: "What condition is visible?",
            evidence: [],
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: false,
            purpose: .clarification
        ))
        let clarificationGrammar = await backend.lastGrammarMode
        XCTAssertEqual(clarificationGrammar, .expertClarification)

        _ = try await model.generate(prompt: ModelPrompt(
            question: "What is in this photo?",
            evidence: [],
            imageData: Data("image".utf8),
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: true,
            purpose: .nativeVisionAnswer
        ))
        let visionGrammar = await backend.lastGrammarMode
        let imageWasForwarded = await backend.imageWasForwarded
        XCTAssertEqual(visionGrammar, .responseEnvelope)
        XCTAssertTrue(imageWasForwarded)
    }

    private struct Files {
        let root: URL
        let model: URL
        let projector: URL?
    }

    private func makeArticle() -> KnowledgeArticle {
        KnowledgeArticle(
            id: "water-locate",
            domain: .wilderness,
            title: "Locate Water",
            summary: "Find likely water without wasting energy.",
            steps: ["Check terrain and drainage."],
            warnings: ["Avoid unstable banks."],
            keywords: ["water"],
            source: SourceReference(
                id: "test-source",
                title: "Test Source",
                organization: "Aurora",
                revision: "1"
            ),
            reviewed: true
        )
    }

    private func makeFiles(includeProjector: Bool) throws -> Files {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AuroraLlamaTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = root.appendingPathComponent("model.gguf")
        try Data("model".utf8).write(to: model)
        let projector: URL?
        if includeProjector {
            let url = root.appendingPathComponent("mmproj.gguf")
            try Data("projector".utf8).write(to: url)
            projector = url
        } else {
            projector = nil
        }
        return Files(root: root, model: model, projector: projector)
    }
}

private actor RecordingLlamaBackend: LlamaRuntimeBackend {
    private(set) var loadCount = 0
    private(set) var unloadCount = 0
    private(set) var loadedContexts: [Int] = []
    private(set) var imageWasForwarded = false
    private(set) var lastEvidenceCount = 0
    private(set) var lastGrammarMode: LlamaGrammarMode = .responseEnvelope
    private var shouldFail = false

    func load(configuration: LlamaRuntimeConfiguration) async throws {
        loadCount += 1
        loadedContexts.append(configuration.contextTokens)
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int,
        grammarMode: LlamaGrammarMode
    ) async throws -> LlamaCompletionResult {
        if shouldFail { throw ModelFailure.unavailable }
        imageWasForwarded = imageData != nil
        lastEvidenceCount = evidenceCount
        lastGrammarMode = grammarMode
        return LlamaCompletionResult(
            text: "No evidence available.",
            metrics: LlamaCompletionMetrics(
                firstTokenMilliseconds: 10,
                totalMilliseconds: 20,
                generatedTokenCount: 2,
                coldStart: false
            )
        )
    }

    func unload() async { unloadCount += 1 }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {}
}
