import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class LlamaRuntimeAdapterTests: XCTestCase {
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
            tier: .field,
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
            tier: .field,
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
                tier: .visionExpert,
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
            tier: .visionExpert,
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
            tier: .visionExpert,
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
            tier: .field,
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
            tier: .field,
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

    private struct Files {
        let root: URL
        let model: URL
        let projector: URL?
    }

    private func makeFiles(includeProjector: Bool) throws -> Files {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardLlamaTests-\(UUID().uuidString)",
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

    func load(configuration: LlamaRuntimeConfiguration) async throws {
        loadCount += 1
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        imageData: Data?,
        maximumOutputTokens: Int
    ) async throws -> String {
        imageWasForwarded = imageData != nil
        return "No evidence available."
    }

    func unload() async {}
}
