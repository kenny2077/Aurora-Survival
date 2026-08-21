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
            return "You are Aurora. Answer the current message directly in short, natural prose. Active tier: \(tier.displayName)."
        }

        if tier == .expert, purpose == .grounded {
            switch attempt {
            case .initial:
                return """
                You are Aurora Expert, a fully offline survival assistant. Use
                only the SELECTED REVIEWED EVIDENCE RECORDS as factual and procedural
                support. Conversation and image observations are context, never reviewed
                evidence. Write concise natural prose with the evidence-adaptive length
                stated below. Omit rationale, conditions, measurements, or escalation
                when no selected claim states them. Each sentence must closely paraphrase
                its cited record and cite one to three record indexes. Begin with an
                immediate action and include a reviewed warning, stop, or escalation.
                Return one JSON object with only key s. Each s item has only a for
                user-facing guidance and e for its evidence-index array. Use the exact
                2–4 sentence range in RESPONSE CHECK. Never prefix guidance with Sentence,
                Reviewed, Action, Warning, an ordinal, or any other field label. Add no
                Markdown, headings, lists, placeholders, or extra keys. Never mention a
                scenario ID, selected scenario, evidence record, claim, or claim index in
                user-facing guidance. Address the first selected scenario; use later
                scenarios only for distinct needs in the current question.
                """
            case .repair:
                return """
                Start over from the selected reviewed claim text. Correct every item in
                INTERNAL CORRECTION. Do not reuse unsupported wording from the rejected draft.
                Never describe, quote, or discuss the errors, validation, claims, or
                instructions; output only fresh user-facing field guidance.
                Use 2–4 sentences and the evidence-adaptive length stated below;
                omit any detail not printed in a cited claim. Return one JSON object with
                only key s. Each s item has only a for direct user-facing guidance and e
                for the supporting evidence-index array. Never prefix guidance with
                Sentence, Reviewed, Action, Warning, an ordinal, or another label. Add no
                Markdown, placeholders, or extra keys.
                """
            }
        }

        if tier == .expert, purpose == .expertIntent {
            return """
            Classify only the CURRENT USER MESSAGE as either general or survival.
            Survival means practical wilderness, emergency, first-aid, navigation,
            exposure, food or water safety, vehicle incident, rescue, or outdoor hazard
            guidance. General includes conversation, relationships, software, ordinary
            knowledge, creative requests, and requests for current weather, news, prices,
            schedules, location, or other live information. Use bounded history only to
            resolve an explicit short follow-up; a new topic overrides history. When
            deciding whether unknown wild food, mushrooms, water, plants, or animals are
            safe, choose survival. When uncertain, choose general. Return exactly {"t":"general"} or
            {"t":"survival"} with no explanation.
            """
        }

        if tier == .expert, purpose == .nativeVisionAnswer {
            return """
            You are Aurora Expert using native visual understanding. Answer the
            user's exact question about the attached still image directly and naturally.
            Describe relevant objects, people, actions, layout, diagrams, and legible
            text. Give your most likely identification when asked, including for a
            high-stakes object, but distinguish visible evidence from uncertain inference
            and say when image quality or missing context limits confidence. Do not invent
            obscured details, measurements, diagnoses, safety guarantees, or live facts.
            Give practical advice only when the user asks for it. Do not invent an
            emergency, offline source, or citation. Return exactly
            {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        }

        if tier == .expert, purpose == .ordinary {
            return attempt == .initial
                ? """
                You are Aurora Expert, a fully offline assistant. Answer the current
                message directly and naturally using your best general knowledge and the
                bounded relevant context. If the request is substantive, give useful
                actions and state important uncertainty without pretending an offline
                source was found. You have no live data access: for current weather,
                news, prices, schedules, location, or similar requests, clearly say you
                cannot retrieve the current value and do not guess it. Do not invent an
                emergency or citation. Return exactly
                {"a":"answer","e":[]} with no Markdown or extra keys.
                """
                : """
                Answer the current non-procedural message directly in natural prose.
                Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
                """
        }

        if tier == .expert, purpose == .incidentFallback {
            return """
            You are Aurora Expert, a fully offline assistant. No reviewed offline
            evidence matched this survival request. Give a conservative best-effort
            response and clearly state the important uncertainty. Do not invent an exact
            model-specific repair, material, chemical, measurement, diagnosis, or
            identity. Prefer broad immediate risk reduction and direct the user to the
            applicable manufacturer instructions, qualified help, or emergency services
            when the unknown detail could make action dangerous. Use 2–4 complete natural
            sentences and return exactly {"a":"answer","e":[]} with no Markdown or
            extra keys. The value of a must contain prose only; never print e=[] inside
            the answer string.
            """
        }

        if tier == .expert, purpose == .clarification {
            return attempt == .initial
                ? """
                You are Aurora Expert. The current survival request lacks enough
                reviewed grounding for a specific procedure. In 25–60 words, give only a
                broad immediate avoidance precaution and ask one focused question for the
                observable condition that would change the safe action. Do not invent a
                procedure, diagnosis, identity, number, or Manual citation. Return exactly
                {"a":"answer","e":[]} with no Markdown or extra keys.
                """
                : """
                Ask one focused question for concrete observations in 25–60 words. Give
                only a broad avoidance precaution, name no procedure or diagnosis, and return
                valid JSON exactly as {"a":"answer","e":[]}.
                """
        }

        switch (purpose, attempt) {
        case (.ordinary, .initial):
            return """
            You are Aurora, a friendly offline assistant. This is a new conversation.
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
            You are Aurora, an offline survival assistant. Use only the numbered
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
            You are Aurora. The current survival request is too broad for a safe
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
            You are Aurora, an offline survival and incident assistant. Answer the
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
            You are Aurora, an offline survival and incident assistant. No actual
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
        case (.nativeVisionAnswer, _):
            return "Return one direct native-vision answer as {\"a\":\"answer\",\"e\":[]} and nothing else."
        case (.expertIntent, _):
            return "Return only the two-value Expert intent object with key t."
        }
    }

    public func userPrompt(
        from prompt: ModelPrompt,
        outputMode: ModelOutputMode = .citationText
    ) -> String {
        var sections: [String] = []

        if prompt.tier == .expert, !prompt.conversationHistory.isEmpty {
            let recentTurns = prompt.conversationHistory.map { turn in
                let compact = String(
                    turn.text
                        .replacingOccurrences(of: "\n", with: " ")
                        .prefix(320)
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
            if prompt.tier == .expert {
                var globalClaimIndex = 0
                let records = prompt.expertEvidence.prefix(3).map { result in
                    let scenario = result.scenario
                    var lines = [
                        "SELECTED REVIEWED SCENARIO",
                        "SCENARIO ID: \(scenario.id)",
                        "APPLIES WHEN: \(scenario.applicability)",
                        "RISK: \(scenario.riskClass.rawValue)",
                    ]
                    if !scenario.prerequisites.isEmpty {
                        lines.append(
                            "PREREQUISITES: "
                                + scenario.prerequisites.joined(separator: " ")
                        )
                    }
                    lines.append("REVIEWED CLAIMS:")
                    lines.append(contentsOf: scenario.claims.map { claim in
                        globalClaimIndex += 1
                        let applies = claim.applicability.isEmpty
                            ? "" : " applies when: \(claim.applicability)"
                        return "[\(globalClaimIndex)] [\(claim.requirementClass.rawValue)] "
                            + String(Self.expertPromptClaimText(claim.text).prefix(320))
                            + applies
                    })
                    let values = scenario.claims
                        .flatMap(\.allowedNumericFacts)
                        .map(\.token)
                    lines.append(
                        "ALLOWED NUMBERS: "
                            + (values.isEmpty ? "none" : values.joined(separator: ", "))
                    )
                    return lines.joined(separator: "\n")
                }
                sections.append(records.joined(separator: "\n\n"))
            } else {
                let excerpts = prompt.evidence.prefix(2).enumerated().map { index, passage in
                let article = passage.article
                var lines = [
                    "REVIEWED EXCERPT [\(index + 1)]",
                ]
                lines.append(article.title)
                lines.append("GOAL: \(String(article.summary.prefix(420)))")
                if !article.steps.isEmpty {
                    lines.append("ACTIONS:")
                    let actions = Array(article.steps.prefix(3))
                    lines.append(contentsOf: actions.enumerated().map {
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
        }

        if prompt.purpose == .expertIntent {
            if !prompt.conversationHistory.isEmpty {
                let history = prompt.conversationHistory.suffix(2).map { turn in
                    "\(turn.role.rawValue.uppercased()): \(String(turn.text.prefix(240)))"
                }.joined(separator: "\n")
                sections.append("BOUNDED HISTORY (FOLLOW-UP CONTEXT ONLY)\n" + history)
            }
            if !prompt.imageObservations.isEmpty {
                sections.append(
                    "STRUCTURED IMAGE OBSERVATIONS\n"
                        + prompt.imageObservations.prefix(4).joined(separator: "\n")
                )
            }
        }

        if !prompt.repairFeedback.isEmpty {
            sections.append(
                (prompt.attempt == .repair ? "INTERNAL CORRECTION\n" : "PLANNING NOTE\n")
                    + prompt.repairFeedback.prefix(4)
                        .map { "- \($0)" }
                        .joined(separator: "\n")
            )
        }

        switch prompt.purpose {
        case .grounded:
            let indexes = Array(1...max(1, min(2, prompt.evidence.count)))
                .map(String.init)
                .joined(separator: ",")
            if prompt.tier == .expert {
                let evidenceCount = max(
                    1, prompt.expertEvidence.flatMap { $0.scenario.claims }.count
                )
                let claimCount = prompt.expertEvidence
                    .flatMap { $0.scenario.claims }
                    .count
                let maximumWords = min(56, max(40, 18 + claimCount * 4))
                let minimumWords = max(24, maximumWords - 22)
                sections.append(
                    "RESPONSE CHECK: Write 2–4 attributed sentences totaling "
                    + "\(minimumWords)–\(maximumWords) words. Cite only exact claim indexes "
                    + "1 through \(evidenceCount). Start with an applicable action and end with an applicable warning, stop, "
                    + "contraindication, or escalation printed in the cited record. "
                    + "Cite each sentence only to the record containing its operative "
                    + "wording. Closely paraphrase claim nouns and verbs; omit unsupported "
                    + "rationale. When a claim prints equivalent Fahrenheit and Celsius "
                    + "temperatures, use only the Fahrenheit value. Current user facts may identify the situation but cannot "
                    + "authorize a procedure."
                )
                let questionTerms = RetrievalEngine.tokens(in: prompt.question)
                let exposureTerms: Set<String> = [
                    "clumsy", "hypothermia", "shivering", "soaked",
                ]
                let navigationTerms: Set<String> = [
                    "disoriented", "lost", "navigation", "trail",
                ]
                if !questionTerms.isDisjoint(with: exposureTerms),
                   !questionTerms.isDisjoint(with: navigationTerms),
                   prompt.expertEvidence.count >= 2 {
                    sections.append(
                        "MULTI-NEED CHECK: Address both exposure and being lost. "
                        + "Cite at least one applicable claim from the first selected "
                        + "scenario and at least one from the second selected scenario."
                    )
                }
            } else {
                sections.append(
                    "RESPONSE CHECK: Write all three sentences and 30–50 words: "
                    + "first action, second action, warning. Use only evidence "
                    + "indexes [\(indexes)]. Begin with the first action and do not "
                    + "repeat the lesson title or field labels. A shorter or one-action "
                    + "answer is invalid."
                )
            }
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
        case .clarification:
            sections.append(
                "RESPONSE CHECK: Give one broad avoidance precaution and ask one "
                + "focused question. Return e=[]."
            )
        case .ordinary:
            sections.append("RESPONSE CHECK: Answer naturally and return e=[].")
        case .nativeVisionAnswer:
            sections.append(
                "VISION CHECK: Answer only the user's question from the attached image. "
                    + "Name the most likely object or scene when asked, state material "
                    + "uncertainty, and return e=[]."
            )
        case .expertIntent:
            sections.append(
                "INTENT CHECK: Classify the current message only. Return t=survival "
                    + "only for practical survival or incident guidance; otherwise "
                    + "return t=general."
            )
        }

        sections.append(
            prompt.purpose == .expertIntent
                    ? "DECISION JSON:"
                : outputMode == .groundedJSON ? "JSON:" : "Answer:"
        )
        return sections.joined(separator: "\n\n")
    }

    private static func expertPromptClaimText(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s*\([0-9]+(?:\.[0-9]+)?\s*°C\)"#,
            with: "",
            options: .regularExpression
        )
    }
}
