import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class SafetyEvaluationTests: XCTestCase {
    func testLockedSafetyCasesAlwaysBypassModel() async throws {
        let cases: [SafetyEvaluationCase] = try fixture(named: "safety_cases")

        for testCase in cases {
            let counter = GenerationCounter()
            let assistant = IncidentAssistant(
                articles: [],
                installedTiers: [.essential],
                modelProvider: { tier in
                    CountingLanguageModel(tier: tier, counter: counter)
                }
            )
            let result = await assistant.answer(
                request: ChatRequest(question: testCase.input),
                device: DeviceSnapshot(
                    physicalMemoryBytes: 8_000_000_000,
                    freeStorageBytes: 10_000_000_000,
                    thermalCondition: .nominal,
                    isLowPowerMode: false
                )
            )

            XCTAssertTrue(
                result.usedDeterministicOverride,
                "Case \(testCase.id) reached the model"
            )
            XCTAssertTrue(
                result.text.hasPrefix(testCase.expectedTitle),
                "Case \(testCase.id) returned the wrong safety card"
            )
            let calls = await counter.calls
            XCTAssertEqual(calls, 0, "Case \(testCase.id) invoked generation")
        }
    }

    func testLockedOBDCommandsAreRejected() throws {
        let commands: [String] = try fixture(named: "obd_rejected_commands")
        let policy = OBDCommandPolicy()
        for command in commands {
            XCTAssertThrowsError(
                try policy.validate(command),
                "Command should be blocked: \(command)"
            )
        }
    }

    private func fixture<T: Decodable>(named name: String) throws -> T {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: SafetyEvaluationTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

private struct SafetyEvaluationCase: Decodable {
    let id: String
    let input: String
    let expectedTitle: String

    enum CodingKeys: String, CodingKey {
        case id
        case input
        case expectedTitle = "expected_title"
    }
}

private actor GenerationCounter {
    private(set) var calls = 0
    func record() { calls += 1 }
}

private struct CountingLanguageModel: LocalLanguageModel {
    let tier: ModelTier
    let counter: GenerationCounter

    func generate(prompt: ModelPrompt) async throws -> String {
        await counter.record()
        return "This must never be reached."
    }
}
