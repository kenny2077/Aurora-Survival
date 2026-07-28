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
        let safetyText = ([request.question] + request.imageObservations).joined(separator: " ")
        if let directive = safety.evaluate(safetyText) {
            return Self.safetyAnswer(
                directive,
                visionWasUsed: false
            )
        }

        let evidence = retrieval.search(
            query: request.question,
            domain: request.domain,
            vehicle: request.vehicleProfile,
            limit: 4
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
            switch model.outputMode {
            case .groundedJSON:
                do {
                    let response = try groundedCodec.decodeAndValidate(
                        generated,
                        evidence: evidence
                    )
                    let observationText = response.observations
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
                        response,
                        evidence: evidence
                    )
                } catch {
                    notices.append(
                        "Structured model output failed evidence validation; reviewed extractive guidance was used."
                    )
                    finalText = try await ExtractiveLanguageModel(
                        tier: decision.selected
                    ).generate(prompt: prompt)
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
