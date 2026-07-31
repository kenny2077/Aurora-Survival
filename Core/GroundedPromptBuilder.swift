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
            Return exactly one JSON object and no Markdown. Use this exact shape and
            key casing; angle-bracket text describes allowed values and must not be
            copied literally:
            {
              "domain": "<vehicle|wilderness|first_aid|navigation>",
              "risk_level": "<critical|high|moderate|low>",
              "immediate_action": {
                "kind": "<stop|move|sos|assess|continue>",
                "evidence_ids": ["<supplied EVIDENCE_ID>"]
              },
              "questions": [],
              "observations": [],
              "procedure_id": "<supplied PROCEDURE_ID or null>",
              "steps": [],
              "do_not_do": [],
              "driveability": "<do_not_drive|unknown|conditional|not_applicable>",
              "escalation": {"reason": "<reason>", "action": "<safe action>"},
              "answer_confidence": "<insufficient|limited|supported>"
            }
            Emit every key as compact JSON with no indentation and no extra keys.
            Always emit empty questions and observations. Keep escalation reason and
            action short. risk_level must always be exactly "critical", "high",
            "moderate", or "low"; "insufficient" is only an answer_confidence value.
            Use only supplied EVIDENCE_ID and PROCEDURE_ID values.
            answer_confidence describes whether a reviewed procedure applies, not
            whether this summary contains every instruction. If any EVIDENCE block is
            supplied, use answer_confidence "limited", select its PROCEDURE_ID, cite
            its EVIDENCE_ID, and copy its Domain exactly; the app supplies the complete
            approved procedure. Always emit empty steps and do_not_do arrays; the app
            attaches every approved step and warning for the selected procedure
            deterministically. If NO REVIEWED EVIDENCE is supplied, use null
            procedure_id, empty steps and do_not_do, and answer_confidence
            "insufficient". For an unsupported prohibited request, use "assess" or
            "stop", do not echo the requested act, and keep questions empty. ECU,
            airbag, and vehicle requests use domain "vehicle"; surgery, medication,
            and dose requests use domain "first_aid".
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
        let evidenceBlocks = prompt.evidence.enumerated().map { index, passage in
            let article = passage.article
            return """
            EVIDENCE [\(index + 1)]
            EVIDENCE_ID: \(article.id)
            PROCEDURE_ID: \(article.id)
            Domain: \(article.domain.rawValue)
            Title: \(article.title)
            Summary: \(article.summary)
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
