import Foundation

public actor IncidentAssistant {
    private let safety: SafetyEngine
    private let retrieval: any EvidenceRetrieving
    private let router: ModelRouter
    private let citationPolicy: CitationPolicy
    private let groundedCodec: GroundedResponseCodec
    private let modelProvider: @Sendable (ModelTier) -> any LocalLanguageModel
    private let installedTiers: Set<ModelTier>

    public init(
        articles: [KnowledgeArticle],
        installedTiers: Set<ModelTier> = [.essential],
        safety: SafetyEngine = SafetyEngine(),
        retrieval: (any EvidenceRetrieving)? = nil,
        router: ModelRouter = ModelRouter(),
        citationPolicy: CitationPolicy = CitationPolicy(),
        groundedCodec: GroundedResponseCodec = GroundedResponseCodec(),
        modelProvider: @escaping @Sendable (ModelTier) -> any LocalLanguageModel = {
            ExtractiveLanguageModel(tier: $0)
        }
    ) {
        self.safety = safety
        self.retrieval = retrieval ?? RetrievalEngine(articles: articles)
        self.router = router
        self.citationPolicy = citationPolicy
        self.groundedCodec = groundedCodec
        self.modelProvider = modelProvider
        self.installedTiers = installedTiers
    }

    public func answer(
        request: ChatRequest,
        device: DeviceSnapshot
    ) async -> AssistantAnswer {
        let recentUserContext = request.conversationHistory
            .filter { $0.role == .user }
            .suffix(2)
            .map(\.text)
        let safetyText = (
            recentUserContext + [request.question] + request.imageObservations
        ).joined(separator: " ")
        if let directive = safety.evaluate(safetyText) {
            return Self.safetyAnswer(
                directive,
                visionWasUsed: false
            )
        }

        let evidence = retrieval.search(
            query: Self.retrievalQuery(for: request),
            domain: request.domain,
            vehicle: request.vehicleProfile,
            limit: 2
        )
        let decision = router.route(
            requested: request.preferredTier,
            installed: installedTiers,
            device: device
        )
        let model = modelProvider(decision.selected)
        let prompt = ModelPrompt(
            question: request.question,
            evidence: evidence,
            imageData: decision.canAnalyzeImage ? request.imageData : nil,
            imageObservations: request.imageObservations,
            tier: decision.selected,
            permitsVisionReasoning: request.hasImage && decision.canAnalyzeImage,
            conversationHistory: Array(
                request.conversationHistory.suffix(3)
            )
        )

        var notices = [decision.explanation]
        if request.hasImage && !decision.canAnalyzeImage {
            notices.append(
                request.imageObservations.isEmpty
                    ? "The selected tier cannot inspect the photo. Describe what you see."
                    : "The selected tier used on-device OCR text only, not visual diagnosis."
            )
        }

        do {
            let generated = try await model.generate(prompt: prompt)
            let finalText: String
            var answerSources = evidence.map(\.article.source)
            switch model.outputMode {
            case .groundedJSON:
                do {
                    let decoded = try groundedCodec
                        .decodeConversationalAndValidate(
                        generated,
                        evidence: evidence
                    )
                    let response = Self.refineConversation(
                        decoded,
                        question: request.question,
                        evidence: evidence
                    )
                    if let directive = safety.evaluate(response.answer) {
                        return Self.safetyAnswer(
                            directive,
                            visionWasUsed: prompt.permitsVisionReasoning,
                            additionalNotice: "The model reply triggered a deterministic safety policy."
                        )
                    }
                    finalText = groundedCodec.renderConversational(
                        response,
                        evidence: evidence
                    )
                    let citedIDs = Set(
                        response.evidenceIDs + [response.procedureID]
                            .compactMap { $0 }
                    )
                    answerSources = evidence
                        .filter { citedIDs.contains($0.article.id) }
                        .map(\.article.source)
                } catch {
                    do {
                        let legacy = try groundedCodec.decodeAndValidate(
                            generated,
                            evidence: evidence
                        )
                        let observationText = legacy.observations
                            .map(\.fact)
                            .joined(separator: " ")
                        if let directive = safety.evaluate(observationText) {
                            return Self.safetyAnswer(
                                directive,
                                visionWasUsed: prompt.permitsVisionReasoning,
                                additionalNotice: "A model observation triggered a deterministic safety policy."
                            )
                        }
                        finalText = try groundedCodec.renderValidated(
                            legacy,
                            evidence: evidence
                        )
                        let citedIDs = Set(
                            legacy.immediateAction.evidenceIDs
                                + legacy.steps.flatMap(\.evidenceIDs)
                        )
                        answerSources = evidence
                            .filter { citedIDs.contains($0.article.id) }
                            .map(\.article.source)
                    } catch {
                        notices.append(
                            "Structured model output failed evidence validation; reviewed extractive guidance was used."
                        )
#if DEBUG
                        notices.append(
                            "Debug model decision: \(generated.prefix(512)) · \(String(describing: error))"
                        )
#endif
                        finalText = try await ExtractiveLanguageModel(
                            tier: decision.selected
                        ).generate(prompt: prompt)
                        answerSources = evidence.prefix(1).map(\.article.source)
                    }
                }
            case .citationText:
                if let validated = citationPolicy.validatedText(
                    generated,
                    evidenceCount: evidence.count
                ) {
                    finalText = validated
                } else {
                    notices.append(
                        "Generated text failed citation validation; reviewed extractive guidance was used."
                    )
                    finalText = try await ExtractiveLanguageModel(
                        tier: decision.selected
                    ).generate(prompt: prompt)
                }
            }
            return AssistantAnswer(
                text: finalText,
                severity: evidence.isEmpty ? .caution : .informational,
                sources: answerSources,
                modelTier: decision.selected,
                usedDeterministicOverride: false,
                visionWasUsed: prompt.permitsVisionReasoning,
                notices: notices
            )
        } catch {
            let fallback = (try? await ExtractiveLanguageModel(tier: .essential).generate(prompt: prompt))
                ?? "No reviewed offline procedure matched."
            notices.append("The local model was unavailable; reviewed extractive guidance was used.")
            return AssistantAnswer(
                text: fallback,
                severity: .caution,
                sources: evidence.prefix(1).map(\.article.source),
                modelTier: .essential,
                usedDeterministicOverride: false,
                visionWasUsed: false,
                notices: notices
            )
        }
    }

    public func search(
        _ query: String,
        domain: KnowledgeDomain? = nil,
        vehicle: VehicleProfile? = nil
    ) -> [KnowledgeArticle] {
        retrieval.search(
            query: query,
            domain: domain,
            vehicle: vehicle,
            limit: 20
        ).map(\.article)
    }

    private static func retrievalQuery(for request: ChatRequest) -> String {
        let context = request.conversationHistory.suffix(3).map { turn in
            String(
                turn.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(180)
            )
        }
        return (context + [request.question]).joined(separator: " ")
    }

    private static func refineConversation(
        _ response: ConversationalGroundedResponse,
        question: String,
        evidence: [RetrievedPassage]
    ) -> ConversationalGroundedResponse {
        let citedEvidence = response.evidenceIDs.prefix(2)
        let primary = citedEvidence.first.flatMap { evidenceID in
            evidence.map(\.article).first(where: { $0.id == evidenceID })
        }
        let selectedAnswer = normalized(response.answer) == normalized(question)
            ? primary?.summary ?? response.answer
            : response.answer
        let answer = completeSentences(in: selectedAnswer)
            ?? primary?.summary
            ?? selectedAnswer
        let procedureID = response.procedureID
            ?? (isProcedural(question) ? primary?.id : nil)
        let followUp = response.followUp.flatMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasSuffix("?")
                && !isQuestionEcho(value, question: question)
                && !isQuizLikeFollowUp(value)
                ? value
                : nil
        }

        return ConversationalGroundedResponse(
            answer: answer,
            evidenceIDs: Array(citedEvidence),
            procedureID: procedureID,
            followUp: followUp
        )
    }

    private static func isProcedural(_ question: String) -> Bool {
        let value = question.lowercased()
        return value.hasPrefix("how ")
            || value.contains("what should i")
            || value.contains("what do i")
            || value.contains("what if")
            || value.contains("steps")
            || value.contains("without")
            || value.contains("do not have")
            || value.contains("don't have")
    }

    private static func isQuestionEcho(
        _ candidate: String,
        question: String
    ) -> Bool {
        if normalized(candidate) == normalized(question) {
            return true
        }
        let candidateWords = contentWords(candidate)
        let questionWords = contentWords(question)
        guard !candidateWords.isEmpty, !questionWords.isEmpty else {
            return false
        }
        let shared = candidateWords.intersection(questionWords).count
        return Double(shared) / Double(min(candidateWords.count, questionWords.count)) >= 0.75
    }

    private static func isQuizLikeFollowUp(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("what is the first step")
            || normalized.hasPrefix("what steps")
            || normalized.hasPrefix("what specific steps")
            || normalized.hasPrefix("how would you")
    }

    private static func completeSentences(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return nil }
        let sentenceEndings = ".?!"
        if sentenceEndings.contains(last) {
            return trimmed
        }
        guard let end = trimmed.lastIndex(where: {
            sentenceEndings.contains($0)
        }) else {
            return nil
        }
        return String(trimmed[...end])
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func contentWords(_ value: String) -> Set<String> {
        let ignored: Set<String> = [
            "a", "an", "do", "for", "how", "i", "me", "my", "the",
            "to", "what", "would", "you", "your",
        ]
        return Set(
            value.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !ignored.contains($0) }
        )
    }

    private static func safetyAnswer(
        _ directive: SafetyDirective,
        visionWasUsed: Bool,
        additionalNotice: String? = nil
    ) -> AssistantAnswer {
        let actions = directive.immediateActions
            .map { "• \($0)" }
            .joined(separator: "\n")
        let prohibited = directive.prohibitedActions
            .map { "• \($0)" }
            .joined(separator: "\n")
        let text = """
        \(directive.title)

        Do this now:
        \(actions)

        Do not:
        \(prohibited)
        """
        var notices = [
            directive.rationale,
            "Policy: \(directive.policyID)",
        ]
        if let additionalNotice {
            notices.append(additionalNotice)
        }
        return AssistantAnswer(
            text: text,
            severity: directive.severity,
            sources: [directive.source],
            modelTier: nil,
            usedDeterministicOverride: true,
            visionWasUsed: visionWasUsed,
            notices: notices
        )
    }
}
