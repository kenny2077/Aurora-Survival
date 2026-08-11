import Foundation

public struct GroundedPromptBuilder: Sendable {
    public init() {}

    public func systemPrompt(
        for prompt: ModelPrompt,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        systemPrompt(
            for: prompt.tier,
            purpose: prompt.purpose,
            attempt: prompt.attempt,
            outputMode: outputMode
        )
    }

    public func systemPrompt(
        for tier: ModelTier,
        purpose: ModelPromptPurpose = .ordinary,
        attempt: ModelPromptAttempt = .initial,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        guard outputMode == .groundedJSON else {
            return "You are TrailGuard. Answer the current message directly in short, natural prose. Active tier: \(tier.displayName)."
        }

        switch (purpose, attempt) {
        case (.ordinary, .initial):
            return """
            You are TrailGuard, a friendly offline assistant. This is a new conversation.
            Answer only the current message in one complete natural sentence of 4–28 words.
            Return exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.ordinary, .repair):
            return """
            Answer the current message with one complete natural sentence.
            Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
            """
        case (.grounded, .initial):
            return """
            You are TrailGuard, an offline survival assistant. Use only the numbered
            REVIEWED EXCERPTS below. Answer the exact question in one compact
            35–55 word paragraph under 360 characters. Write exactly three sentences:
            paraphrase reviewed action 1, then action 2, then the warning. Begin the
            warning sentence with Avoid, Stop, or Do not. Begin directly with the first
            action, not the lesson title. Use plain prose; do not
            reverse or weaken any warning or prohibition in the reviewed excerpt. Do not
            output excerpt titles, headings, labels, or lists. Return exactly
            {"a":"answer","e":[1]} with no Markdown or extra keys. e must contain
            one or two unique excerpt numbers actually used. Put no source labels,
            page numbers, or evidence markers inside a. If only excerpt [1] is
            provided, e must be exactly [1].
            """
        case (.grounded, .repair):
            return """
            Start over using only the reviewed excerpts. Write exactly three short
            plain-prose sentences totaling 30–50 words: paraphrase reviewed action 1,
            then action 2, then the warning beginning Avoid, Stop, or Do not. Follow
            prohibitions literally; never suggest the warned-against
            action even "with caution." Begin with the first action, never the lesson
            title, and do not stop before the warning sentence. Never use a heading,
            label, list, or newline.
            Return valid JSON as {"a":"answer","e":[1]} and nothing else. Cite one
            or two used excerpts. If only excerpt [1] is provided, e must be [1].
            """
        case (.clarification, .initial):
            return """
            You are TrailGuard. The current survival request is too broad for a safe
            procedure. In 18–45 words, give one general scene-safety precaution, ask
            for observable symptoms or conditions, and tell the user to restate the
            complete situation. Do not name a repair procedure. Return exactly
            {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.clarification, .repair):
            return """
            Ask for concrete observations and a complete restatement in 18–45 words.
            Give only a general scene-safety precaution, name no procedure, and return
            valid JSON exactly as {"a":"answer","e":[]}.
            """
        case (.incidentFallback, .initial):
            return """
            You are TrailGuard, an offline survival and incident assistant. Answer the
            user's current situation directly using your best relevant knowledge. In
            30–60 words, give two useful actions and one warning, stop condition, or
            escalation. Speak to the user; never claim their condition as your own.
            Never claim water slows alcohol absorption; never advise inducing vomiting,
            driving while impaired, touching live wiring, or remaining in smoke.
            For intoxication, include sober supervision and emergency signs. For a
            swallowed chemical, call poison control or emergency help and keep its
            label. For severe chest pain, call emergency services and rest.
            Return exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.incidentFallback, .repair):
            return """
            Start over and answer the user's incident in exactly three short sentences
            totaling 30–60 words: first action, second action, then a warning or
            escalation. Do not ask for details or speak as if you have the condition.
            Never claim water slows alcohol absorption; never advise inducing vomiting,
            driving while impaired, touching live wiring, or remaining in smoke.
            For intoxication, chemical ingestion, or severe chest pain, include the
            applicable emergency escalation stated in the initial instructions.
            Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
            """
        case (.incidentIntake, .initial):
            return """
            You are TrailGuard, an offline survival and incident assistant. No actual
            incident was described. Briefly acknowledge the user and ask them to state
            the complete current situation, location, observable hazards or injuries,
            and available resources. Do not invent danger or give a procedure. Return
            exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.incidentIntake, .repair):
            return """
            No incident was described. In one or two sentences, ask the user for the
            complete current situation and observable conditions. Do not invent danger
            or give actions. Return valid JSON exactly as {"a":"answer","e":[]}.
            """
        }
    }

    public func userPrompt(
        from prompt: ModelPrompt,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        var sections: [String] = []

        if prompt.tier == .expert, !prompt.conversationHistory.isEmpty {
            let recentTurns = prompt.conversationHistory.suffix(4).map { turn in
                let compact = String(
                    turn.text
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(180)
                )
                return "\(turn.role.rawValue.uppercased()): \(compact)"
            }.joined(separator: "\n")
            sections.append("RECENT CONVERSATION\n\(recentTurns)")
        }

        sections.append("QUESTION\n\(prompt.question)")

        if !prompt.imageObservations.isEmpty {
            sections.append(
                "ON-DEVICE OCR\n" + prompt.imageObservations.prefix(4)
                    .map { "- \($0)" }
                    .joined(separator: "\n")
            )
        }

        if prompt.purpose == .grounded {
            let excerpts = prompt.evidence.prefix(2).enumerated().map { index, passage in
                let article = passage.article
                var lines = [
                    "REVIEWED EXCERPT [\(index + 1)]",
                    article.title,
                    "GOAL: \(String(article.summary.prefix(420)))",
                ]
                if !article.steps.isEmpty {
                    lines.append("ACTIONS:")
                    lines.append(contentsOf: article.steps.prefix(3).enumerated().map {
                        "\($0.offset + 1). \(String($0.element.prefix(280)))"
                    })
                }
                if let warning = article.warnings.first {
                    lines.append("WARNING: \(String(warning.prefix(280)))")
                }
                return lines.joined(separator: "\n")
            }
            sections.append(excerpts.joined(separator: "\n\n"))
        }

        switch prompt.purpose {
        case .grounded:
            let indexes = Array(1...max(1, min(2, prompt.evidence.count)))
                .map(String.init)
                .joined(separator: ",")
            sections.append(
                "RESPONSE CHECK: Write all three sentences and 30–50 words: "
                + "first action, second action, warning. Use only evidence "
                + "indexes [\(indexes)]. Begin with the first action and do not "
                + "repeat the lesson title or field labels. A shorter or one-action "
                + "answer is invalid."
            )
        case .incidentFallback:
            sections.append(
                "RESPONSE CHECK: Write all three sentences and 30–60 words: "
                + "first action, second action, warning or escalation. Address "
                + "the user with imperative directions and return e=[]."
            )
        case .incidentIntake:
            sections.append(
                "RESPONSE CHECK: Ask directly for the complete incident, location, "
                + "observable conditions, and available resources. Give no procedure "
                + "and return e=[]."
            )
        case .ordinary, .clarification:
            break
        }

        sections.append(outputMode == .groundedJSON ? "JSON:" : "Answer:")
        return sections.joined(separator: "\n\n")
    }
}
