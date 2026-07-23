import Foundation

public struct GroundedPromptBuilder: Sendable {
    public init() {}

    public func systemPrompt(for tier: ModelTier) -> String {
        """
        You are the explanation layer in an offline incident assistant.
        Use only the numbered EVIDENCE blocks supplied with the request.
        Cite every factual instruction with its evidence number, such as [1].
        Never invent a repair step, torque value, dose, diagnosis, route, or survival fact.
        Never provide surgery, invasive treatment, prescription, ECU writing, or safety-system bypass instructions.
        If evidence is missing or conflicting, say that the offline pack cannot answer.
        Put immediate hazards before diagnosis. A larger model tier does not grant more authority.
        Active tier: \(tier.displayName).
        """
    }

    public func userPrompt(from prompt: ModelPrompt) -> String {
        let evidence = prompt.evidence.enumerated().map { index, passage in
            let article = passage.article
            let steps = article.steps.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            let warnings = article.warnings.map { "WARNING: \($0)" }.joined(separator: "\n")
            return """
            EVIDENCE [\(index + 1)]
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

        return """
        QUESTION
        \(prompt.question)

        \(observations)

        \(evidence)

        Give a short, ordered response. Distinguish observation from inference. Cite the evidence.
        """
    }
}
