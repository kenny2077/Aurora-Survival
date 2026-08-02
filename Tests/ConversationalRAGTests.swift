import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class ConversationalRAGTests: XCTestCase {
    func testCodecRendersNaturalAnswerAndOnlyReviewedProcedure() throws {
        let article = makeWaterArticle()
        let evidence = [RetrievedPassage(article: article, score: 1)]
        let generated = """
        {"a":"Yes. A filter is helpful, but it is not the only treatment option.","e":[1],"p":1,"q":"Do you have a pot and a way to make heat?"}
        """

        let codec = GroundedResponseCodec()
        let response = try codec.decodeConversationalAndValidate(
            generated,
            evidence: evidence
        )
        let rendered = codec.renderConversational(
            response,
            evidence: evidence
        )

        XCTAssertTrue(rendered.contains("filter is helpful"))
        XCTAssertTrue(rendered.contains(article.steps[0]))
        XCTAssertTrue(rendered.contains("Do you have a pot"))
        XCTAssertEqual(response.evidenceIDs, [article.id])
        XCTAssertEqual(response.procedureID, article.id)
    }

    func testCodecRejectsUnknownConversationalEvidenceIndex() {
        let evidence = [RetrievedPassage(article: makeWaterArticle(), score: 1)]

        XCTAssertThrowsError(
            try GroundedResponseCodec().decodeConversationalAndValidate(
                "{\"a\":\"Treat the water.\",\"e\":[2],\"p\":null,\"q\":null}",
                evidence: evidence
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .unknownEvidenceIndex(2)
            )
        }
    }

    func testCodecRejectsConversationalTextThatExceedsLiteGrammarBounds() {
        let evidence = [RetrievedPassage(article: makeWaterArticle(), score: 1)]
        let longAnswer = String(repeating: "a", count: 221)
        let longFollowUp = String(repeating: "q", count: 97)
        let codec = GroundedResponseCodec()

        XCTAssertThrowsError(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"\(longAnswer)\",\"e\":[1],\"p\":null,\"q\":null}",
                evidence: evidence
            )
        ) { error in
            XCTAssertEqual(
                error as? GroundedResponseError,
                .invalidConversationalAnswer
            )
        }
        XCTAssertThrowsError(
            try codec.decodeConversationalAndValidate(
                "{\"a\":\"Treat the water.\",\"e\":[1],\"p\":null,\"q\":\"\(longFollowUp)\"}",
                evidence: evidence
            )
        ) { error in
            XCTAssertEqual(error as? GroundedResponseError, .invalidFollowUp)
        }
    }

    func testAssistantSuppliesRecentConversationToModel() async {
        let recorder = PromptRecorder()
        let article = makeWaterArticle()
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .lite],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, userPrompt in
                    await recorder.record(userPrompt)
                    return "{\"a\":\"You can use another reviewed treatment method.\",\"e\":[1],\"p\":1,\"q\":null}"
                }
            }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What if I do not have one?",
                preferredTier: .lite,
                conversationHistory: [
                    ConversationTurn(
                        role: .user,
                        text: "How do I make stream water safer?"
                    ),
                    ConversationTurn(
                        role: .assistant,
                        text: "A portable filter can be one part of treatment."
                    ),
                ]
            ),
            device: capableDevice()
        )

        let prompt = await recorder.value
        XCTAssertTrue(prompt.contains("How do I make stream water safer?"))
        XCTAssertTrue(prompt.contains("What if I do not have one?"))
        XCTAssertTrue(answer.text.contains("another reviewed treatment method"))
        XCTAssertEqual(answer.sources.map(\.id), [article.source.id])
    }

    func testAssistantRepairsQuestionEchoWithReviewedProcedure() async {
        let article = makeWaterArticle()
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .lite],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, _ in
                    "{\"a\":\"How do I make stream water safer?\",\"e\":[1],\"p\":null,\"q\":\"What steps would you take to make stream water safer?\"}"
                }
            }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "How do I make stream water safer?",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertTrue(answer.text.contains(article.summary))
        XCTAssertTrue(answer.text.contains(article.steps[0]))
        XCTAssertFalse(answer.text.contains("What steps would you take"))
        XCTAssertFalse(
            answer.notices.contains(where: {
                $0.contains("failed evidence validation")
            })
        )
        XCTAssertEqual(answer.sources.map(\.id), [article.source.id])
    }

    func testAssistantDropsIncompleteGeneratedFollowUp() async {
        let article = makeWaterArticle()
        let assistant = IncidentAssistant(
            articles: [article],
            installedTiers: [.essential, .lite],
            modelProvider: { tier in
                ClosureBackedLanguageModel(
                    tier: tier,
                    outputMode: .groundedJSON
                ) { _, _ in
                    "{\"a\":\"Boiling is an available reviewed option. This fragment is unfinished,\",\"e\":[1],\"p\":null,\"q\":\"What is the first step to ensure water safety?\"}"
                }
            }
        )

        let answer = await assistant.answer(
            request: ChatRequest(
                question: "What if I do not have a filter?",
                preferredTier: .lite
            ),
            device: capableDevice()
        )

        XCTAssertTrue(answer.text.contains("Boiling is an available reviewed option."))
        XCTAssertFalse(answer.text.contains("This fragment is unfinished"))
        XCTAssertFalse(answer.text.contains("What is the first step"))
        XCTAssertTrue(answer.text.contains(article.steps[0]))
    }

    private func makeWaterArticle() -> KnowledgeArticle {
        KnowledgeArticle(
            id: "water.reviewed",
            domain: .wilderness,
            title: "Make water safer",
            summary: "Natural water may contain organisms even when it looks clear.",
            steps: [
                "Bring water to a rolling boil when boiling is the selected reviewed method.",
                "Store treated water in a clean, covered container.",
            ],
            warnings: [
                "Boiling does not remove fuel, salt, heavy metals, or toxic chemicals."
            ],
            keywords: ["water", "filter", "boil", "stream"],
            source: SourceReference(
                id: "source.water",
                title: "Reviewed water guidance",
                organization: "Fixture",
                revision: "1"
            ),
            reviewed: true
        )
    }

    private func capableDevice() -> DeviceSnapshot {
        DeviceSnapshot(
            physicalMemoryBytes: 8_000_000_000,
            freeStorageBytes: 20_000_000_000,
            thermalCondition: .nominal,
            isLowPowerMode: false
        )
    }
}

private actor PromptRecorder {
    private(set) var value = ""

    func record(_ prompt: String) {
        value = prompt
    }
}
