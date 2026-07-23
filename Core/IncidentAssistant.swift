import Foundation

public actor IncidentAssistant {
    private let safety: SafetyEngine
    private let retrieval: RetrievalEngine
    private let router: ModelRouter
    private let citationPolicy: CitationPolicy
    private let modelProvider: @Sendable (ModelTier) -> any LocalLanguageModel
    private let installedTiers: Set<ModelTier>

    public init(
        articles: [KnowledgeArticle],
        installedTiers: Set<ModelTier> = [.essential],
        safety: SafetyEngine = SafetyEngine(),
        router: ModelRouter = ModelRouter(),
        citationPolicy: CitationPolicy = CitationPolicy(),
        modelProvider: @escaping @Sendable (ModelTier) -> any LocalLanguageModel = {
            ExtractiveLanguageModel(tier: $0)
        }
    ) {
        self.safety = safety
        self.retrieval = RetrievalEngine(articles: articles)
        self.router = router
        self.citationPolicy = citationPolicy
        self.modelProvider = modelProvider
        self.installedTiers = installedTiers
    }

    public func answer(
        request: ChatRequest,
        device: DeviceSnapshot
    ) async -> AssistantAnswer {
        let safetyText = ([request.question] + request.imageObservations).joined(separator: " ")
        if let directive = safety.evaluate(safetyText) {
            let actions = directive.immediateActions.map { "• \($0)" }.joined(separator: "\n")
            let prohibited = directive.prohibitedActions.map { "• \($0)" }.joined(separator: "\n")
            let text = "\(directive.title)\n\nDo this now:\n\(actions)\n\nDo not:\n\(prohibited)"
            return AssistantAnswer(
                text: text,
                severity: directive.severity,
                sources: [],
                modelTier: nil,
                usedDeterministicOverride: true,
                visionWasUsed: false,
                notices: [directive.rationale]
            )
        }

        let evidence = retrieval.search(
            query: request.question,
            domain: request.domain,
            vehicle: request.vehicleProfile
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
            permitsVisionReasoning: request.hasImage && decision.canAnalyzeImage
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
            if let validated = citationPolicy.validatedText(generated, evidenceCount: evidence.count) {
                finalText = validated
            } else {
                notices.append("Generated text failed citation validation; reviewed extractive guidance was used.")
                finalText = try await ExtractiveLanguageModel(tier: decision.selected).generate(prompt: prompt)
            }
            return AssistantAnswer(
                text: finalText,
                severity: evidence.isEmpty ? .caution : .informational,
                sources: evidence.map(\.article.source),
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
                sources: evidence.map(\.article.source),
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
}
