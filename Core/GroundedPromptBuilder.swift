import Foundation

public struct GroundedPromptBuilder: Sendable {
    public init() {}

    public func systemPrompt(
        for tier: ModelTier,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        let outputContract: String
        switch outputMode {
        case .citationText:
            outputContract = """
            Return short ordered prose. Cite every factual instruction with its
            evidence number, such as [1].
            """
        case .groundedJSON:
            outputContract = """
            Return exactly one JSON object and no Markdown. Use the grounded-response
            keys: domain, risk_level, immediate_action, questions, observations,
            procedure_id, steps, do_not_do, driveability, escalation, and
            answer_confidence. Use only EVIDENCE_ID, PROCEDURE_ID, and STEP_ID values
            supplied below. Copy warnings exactly into do_not_do; never paraphrase
            them. If evidence is insufficient, return no steps and confidence
            "insufficient".
            """
        }
        return """
        You are the explanation layer in an offline incident assistant.
        Use only the numbered EVIDENCE blocks supplied with the request.
        Never invent a repair step, torque value, dose, diagnosis, route, or survival fact.
        Never provide surgery, invasive treatment, prescription, ECU writing, or safety-system bypass instructions.
        If evidence is missing or conflicting, say that the offline pack cannot answer.
        Put immediate hazards before diagnosis. A larger model tier does not grant more authority.
        Active tier: \(tier.displayName).
        \(outputContract)
        """
    }

    public func userPrompt(
        from prompt: ModelPrompt,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        let evidence = prompt.evidence.enumerated().map { index, passage in
            let article = passage.article
            let steps = article.steps.enumerated()
                .map {
                    let stepID = "\(article.id)#step-\($0.offset + 1)"
                    return "STEP_ID \(stepID): \($0.element)"
                }
                .joined(separator: "\n")
            let warnings = article.warnings.map { "WARNING: \($0)" }.joined(separator: "\n")
            return """
            EVIDENCE [\(index + 1)]
            EVIDENCE_ID: \(article.id)
            PROCEDURE_ID: \(article.id)
            Title: \(article.title)
            Summary: \(article.summary)
            \(steps)
            \(warnings)
            """
        }.joined(separator: "\n\n")

        let observations: String
        if prompt.imageObservations.isEmpty {
            observations = "No trusted image observations are available."
        } else {
            observations = "On-device OCR observations (may contain errors):\n"
                + prompt.imageObservations.map { "- \($0)" }.joined(separator: "\n")
        }

        let closingInstruction: String
        switch outputMode {
        case .citationText:
            closingInstruction = "Give a short, ordered response. Distinguish observation from inference. Cite the evidence."
        case .groundedJSON:
            closingInstruction = "Return the grounded-response JSON object now."
        }

        return """
        QUESTION
        \(prompt.question)

        \(observations)

        \(evidence)

        \(closingInstruction)
        """
    }
}
