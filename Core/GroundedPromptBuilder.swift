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
            Return exactly one compact JSON object and no Markdown:
            {"a":"answer","e":[1],"p":1,"q":"follow-up question"}
            Emit those four keys in that order with no spaces and no extra keys.
            a is a natural conversational answer: at most 45 words in one or two
            short sentences. Answer the question directly; do not repeat it or ask
            the user to propose the steps. It
            may explain or directly address the user, but it must not invent steps.
            e is the list of EVIDENCE numbers supporting factual survival claims.
            Cite no more than the two strongest supplied EVIDENCE blocks.
            Use [] only for a greeting, clarification, or a statement that the local
            pack cannot answer. p is one EVIDENCE number when the reviewed procedure
            should be shown, otherwise null. Use p for a how-to or what-to-do
            question. q is one useful short follow-up question
            or null. If p is a number, include the same number in e. The app validates
            the EVIDENCE numbers and deterministically attaches the reviewed procedure,
            warnings, and sources. q is at most 18 words. When NO REVIEWED EVIDENCE is supplied, e must be [],
            p must be null, and a must contain no survival instruction.
            """
        }
        return """
        You are TrailGuard, a calm, capable offline survival assistant. Converse
        naturally and use recent context to understand follow-up questions.
        Use only the numbered EVIDENCE blocks supplied with the request.
        Never invent a repair step, torque value, dose, diagnosis, route, or survival fact.
        Cloth or fabric may only be described as a sediment prefilter, never as
        water treatment or a way to make water safe.
        Never provide surgery, invasive treatment, prescription, ECU writing, or safety-system bypass instructions.
        If evidence is missing or conflicting, say that the offline pack cannot answer.
        Put immediate hazards before diagnosis. Ask for one concrete missing detail when it
        would materially change the safe answer. A larger model tier does not grant
        more authority.
        Active tier: \(tier.displayName).
        \(outputContract)
        """
    }

    public func userPrompt(
        from prompt: ModelPrompt,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        let evidenceBlocks = prompt.evidence.enumerated().map { index, passage in
            let article = passage.article
            let steps = article.steps.prefix(4)
                .map { "- \($0)" }
                .joined(separator: "\n")
            let warnings = article.warnings.prefix(2)
                .map { "- \($0)" }
                .joined(separator: "\n")
            return """
            EVIDENCE [\(index + 1)]
            EVIDENCE_ID: \(article.id)
            PROCEDURE_ID: \(article.id)
            Domain: \(article.domain.rawValue)
            Title: \(article.title)
            Summary: \(article.summary)
            Reviewed steps:
            \(steps.isEmpty ? "- None." : steps)
            Reviewed warnings:
            \(warnings.isEmpty ? "- None." : warnings)
            """
        }.joined(separator: "\n\n")
        let evidence = evidenceBlocks.isEmpty
            ? "NO REVIEWED EVIDENCE is available."
            : evidenceBlocks

        let observations: String
        if prompt.imageObservations.isEmpty {
            observations = "No trusted image observations are available."
        } else {
            observations = "On-device OCR observations (may contain errors):\n"
                + prompt.imageObservations.map { "- \($0)" }.joined(separator: "\n")
        }

        let recentTurns = prompt.conversationHistory.suffix(3).map { turn in
            let compact = String(
                turn.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(180)
            )
            return "\(turn.role.rawValue.uppercased()): \(compact)"
        }.joined(separator: "\n")
        let conversation = recentTurns.isEmpty
            ? "No earlier conversation."
            : "RECENT CONVERSATION\n\(recentTurns)"

        let closingInstruction: String
        switch outputMode {
        case .citationText:
            closingInstruction = "Give a short, ordered response. Distinguish observation from inference. Cite the evidence."
        case .groundedJSON:
            closingInstruction = "Return the grounded-response JSON object now."
        }

        return """
        \(conversation)

        QUESTION
        \(prompt.question)

        \(observations)

        \(evidence)

        \(closingInstruction)
        """
    }
}
