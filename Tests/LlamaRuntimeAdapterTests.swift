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
        XCTAssertEqual(configuration.maximumOutputTokens, 160)
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
    private(set) var imageWasForwarded = false
    private(set) var lastEvidenceCount = 0

    func load(configuration: LlamaRuntimeConfiguration) async throws {
        loadCount += 1
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int,
        evidenceCount: Int
    ) async throws -> LlamaCompletionResult {
        imageWasForwarded = imageData != nil
        lastEvidenceCount = evidenceCount
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

    func unload() async {}
}
