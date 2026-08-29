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
            outputMode: outputMode,
            usesReviewedClaims: !prompt.expertEvidence.isEmpty,
            responseLanguage: prompt.responseLanguage
        )
    }

    public func systemPrompt(
        for tier: ModelTier,
        purpose: ModelPromptPurpose = .ordinary,
        attempt: ModelPromptAttempt = .initial,
        outputMode: ModelOutputMode = .citationText,
        usesReviewedClaims: Bool = false,
        responseLanguage: ResponseLanguage = .english
    ) -> String {
        guard outputMode == .groundedJSON else {
            return "You are Aurora Survival Agent. \(responseLanguage.instruction) Answer the current message directly in short, natural prose. Active tier: \(tier.displayName)."
        }

        if usesReviewedClaims, purpose == .grounded {
            return """
            You are Aurora Survival Agent \(tier.displayName), a fully offline survival assistant.
            \(responseLanguage.instruction) Answer the CURRENT USER MESSAGE directly
            using only the numbered REVIEWED SCENARIOS as factual and procedural support.
            Lead with the most useful actions. Include safety limits only when they are
            relevant to the request and supported by the reviewed text. Use natural prose;
            do not discuss the database, scenario labels, or internal instructions. The e
            array must contain only the unique scenario numbers actually used. Do not
            invent measurements or exact numbers. Return exactly one JSON object shaped
            {"a":"best-effort answer","e":[1]} with no Markdown or extra keys.
            """
        }

        if purpose == .expertIntent, tier == .lite {
            return """
            Classify only the current message. Return t=survival for an
            explicit wilderness, outdoor survival, emergency, first-aid, rescue,
            navigation, exposure, unsafe water/food, or vehicle-incident question.
            Return t=general for chat, relationships, software, live/current
            information, ordinary knowledge, recipes, baking, and home or kitchen
            cooking. A direct request to start a fire, find or purify outdoor water,
            obtain wilderness food, or build an overnight shelter is survival. Ordinary
            indoor cooking and household uses of fire or water are general.
            "How do I get a girlfriend?" is general.
            For survival, set q to a short English retrieval query that preserves the
            user's requested subject, operation, and hazard. Translate any non-English
            message into English. For general, q must be empty. When uncertain, choose general.
            Output exactly {"t":"general","q":""} or
            {"t":"survival","q":"English retrieval query"} with no explanation or
            extra keys.
            """
        }

        if purpose == .expertIntent {
            return """
            Classify only the CURRENT USER MESSAGE as either general or survival.
            Most messages are general. Choose survival only when the current message
            explicitly asks about an emergency, outdoor survival need, or preventing
            physical harm in a survival setting.
            Survival means practical wilderness, emergency, first-aid, navigation,
            exposure, food or water safety, vehicle incident, rescue, or outdoor hazard
            guidance. General includes conversation, relationships, software, ordinary
            knowledge, creative requests, and requests for current weather, news, prices,
            schedules, location, or other live information. Use bounded history only to
            resolve an explicit short follow-up; a new topic overrides history. When
            deciding whether unknown wild food, mushrooms, water, plants, or animals are
            safe, choose survival. A survival question must explicitly concern staying
            alive, preventing physical harm, or handling an outdoor/emergency incident.
            "How do I get a girlfriend?" is general. "How's the weather today?" is
            general. "How do I stay warm overnight if stranded in snow?" is survival.
            "How do I find water sources?", "How do I treat collected water?", and
            "How do I cook raw meat outdoors?" are survival. A direct request to start
            a fire or build an overnight shelter is survival. Ordinary recipes and
            indoor cooking questions without a survival or outdoor context are general.
            The words cook, bake, fire, cold, fish, car, or water alone do not make a
            question survival. "How do I bake a cake at home?" and "How do I cook
            dinner in my kitchen?" are general.
            For survival, set q to a short English retrieval query preserving the
            requested subject, operation, and hazard; translate any non-English message.
            For general, q must be empty. When uncertain, choose general. Return exactly
            {"t":"general","q":""} or {"t":"survival","q":"English retrieval query"}
            with no explanation or extra keys.
            """
        }

        if tier == .expert, purpose == .nativeVisionAnswer {
            return """
            You are Aurora Survival Agent Expert using native visual understanding.
            \(responseLanguage.instruction) Answer the
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

        if purpose == .ordinary {
            if tier == .lite {
                return """
                You are Aurora Survival Agent Lite, a fully offline assistant.
                \(responseLanguage.instruction) Answer only the
                current message in 1–3 complete, natural sentences totaling no more than
                75 words. Use best-effort general knowledge. For a greeting, greet the
                user directly and offer help without introducing weather or limitations.
                Mention that live data is unavailable only when the current message asks
                for current weather, news, prices, schedules, location, or similar live
                information; otherwise do not mention it. Do not guess live facts or invent an
                emergency or citation. Return exactly {"a":"answer","e":[]} with no
                Markdown or extra keys.
                """
            }
            return attempt == .initial
                ? """
                You are Aurora Survival Agent \(tier.displayName), a fully offline assistant.
                \(responseLanguage.instruction) Answer the current
                message directly and naturally using your best general knowledge and the
                bounded relevant context. If the request is substantive, give useful
                actions and state important uncertainty without pretending an offline
                source was found. For a greeting, greet the user directly and offer help.
                Mention live-data limits only when the current message asks for current
                weather, news, prices, schedules, location, or similar live information,
                and do not guess the value. Otherwise do not mention those limits. Do not invent an
                emergency or citation. Return exactly
                {"a":"answer","e":[]} with no Markdown or extra keys.
                """
                : """
                Answer the current non-procedural message directly in natural prose.
                Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
                """
        }

        if purpose == .incidentFallback {
            return """
            You are Aurora Survival Agent \(tier.displayName), a fully offline assistant.
            \(responseLanguage.instruction) No reviewed offline
            evidence matched this survival request. Give a conservative best-effort
            response and clearly state the important uncertainty. Do not invent an exact
            model-specific repair, material, chemical, measurement, diagnosis, or
            identity. Prefer broad immediate risk reduction and direct the user to the
            applicable manufacturer instructions, qualified help, or emergency services
            when the unknown detail could make action dangerous. Use concise, complete
            prose and return exactly {"a":"answer","e":[]} with no Markdown or
            extra keys. The value of a must contain prose only; never print e=[] inside
            the answer string.
            """
        }

        if tier == .expert, purpose == .clarification {
            return attempt == .initial
                ? """
                You are Aurora Survival Agent Expert. \(responseLanguage.instruction)
                The current survival request lacks enough
                reviewed grounding for a specific procedure. Give only a
                broad immediate avoidance precaution and ask one focused question for the
                observable condition that would change the safe action. Do not invent a
                procedure, diagnosis, identity, number, or Manual citation. Return exactly
                {"a":"answer","e":[]} with no Markdown or extra keys.
                """
                : """
                Ask one focused question for concrete observations. Give
                only a broad avoidance precaution, name no procedure or diagnosis, and return
                valid JSON exactly as {"a":"answer","e":[]}.
                """
        }

        switch (purpose, attempt) {
        case (.ordinary, .initial):
            return """
            You are Aurora Survival Agent, a friendly offline assistant.
            \(responseLanguage.instruction) This is a new conversation.
            Answer only the current message in concise, complete natural prose.
            Return exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.ordinary, .repair):
            return """
            Answer the current message with concise, complete natural prose.
            Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
            """
        case (.grounded, .initial):
            return """
            You are Aurora Survival Agent, an offline survival assistant.
            \(responseLanguage.instruction) Use only the numbered
            REVIEWED EXCERPTS below. Answer the exact question with useful actions first.
            Add safety guidance only when it is relevant and supported. Use plain prose; do not
            reverse or weaken any warning or prohibition in the reviewed excerpt. Do not
            output excerpt titles, headings, labels, or lists. Return exactly
            {"a":"answer","e":[1]} with no Markdown or extra keys. e must contain
            only unique excerpt numbers actually used. Put no source labels,
            page numbers, or evidence markers inside a.
            """
        case (.grounded, .repair):
            return """
            Start over using only the reviewed excerpts. Give a direct, useful answer in
            complete natural prose. Follow prohibitions literally and never suggest a
            warned-against action. Return valid JSON as {"a":"answer","e":[1]} and
            nothing else. Cite only excerpt numbers actually used.
            """
        case (.clarification, .initial):
            return """
            You are Aurora Survival Agent. \(responseLanguage.instruction)
            The current survival request is too broad for a safe
            procedure. Give a general scene-safety precaution only when relevant, ask
            for observable symptoms or conditions, and tell the user to restate the
            complete situation. Do not name a repair procedure. Return exactly
            {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.clarification, .repair):
            return """
            Ask for concrete observations and a complete restatement.
            Give only a general scene-safety precaution, name no procedure, and return
            valid JSON exactly as {"a":"answer","e":[]}.
            """
        case (.incidentFallback, .initial):
            return """
            You are Aurora Survival Agent, an offline survival and incident assistant.
            \(responseLanguage.instruction) Answer the
            user's current situation directly using your best relevant knowledge. Lead
            with useful actions and add a warning, stop condition, or escalation only
            when relevant. Speak to the user; never claim their condition as your own.
            Never claim water slows alcohol absorption; never advise inducing vomiting,
            driving while impaired, touching live wiring, or remaining in smoke.
            For intoxication, include sober supervision and emergency signs. For a
            swallowed chemical, call poison control or emergency help and keep its
            label. For severe chest pain, call emergency services and rest.
            Return exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.incidentFallback, .repair):
            return """
            Start over and answer the user's incident directly in complete natural prose.
            Do not ask for details or speak as if you have the condition.
            Never claim water slows alcohol absorption; never advise inducing vomiting,
            driving while impaired, touching live wiring, or remaining in smoke.
            For intoxication, chemical ingestion, or severe chest pain, include the
            applicable emergency escalation stated in the initial instructions.
            Return valid JSON exactly as {"a":"answer","e":[]} and nothing else.
            """
        case (.incidentIntake, .initial):
            return """
            You are Aurora Survival Agent, an offline survival and incident assistant.
            \(responseLanguage.instruction) No actual
            incident was described. Briefly acknowledge the user and ask them to state
            the complete current situation, location, observable hazards or injuries,
            and available resources. Do not invent danger or give a procedure. Return
            exactly {"a":"answer","e":[]} with no Markdown or extra keys.
            """
        case (.incidentIntake, .repair):
            return """
            No incident was described. Ask the user for the
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

        if !prompt.imageObservations.isEmpty {
            sections.append(
                "ON-DEVICE OCR\n" + prompt.imageObservations.prefix(4)
                    .map { "- \($0)" }
                    .joined(separator: "\n")
            )
        }

        if prompt.purpose == .grounded {
            if !prompt.expertEvidence.isEmpty {
                let scenarioLimit = prompt.tier == .lite ? 2 : 3
                let records = prompt.expertEvidence.prefix(scenarioLimit).enumerated().map { scenarioOffset, result in
                    let scenario = result.scenario
                    var lines = [
                        "REVIEWED SCENARIO [\(scenarioOffset + 1)]",
                        "APPLIES WHEN: \(scenario.applicability)",
                    ]
                    if !scenario.prerequisites.isEmpty {
                        lines.append(
                            "PREREQUISITES: "
                                + scenario.prerequisites.joined(separator: " ")
                        )
                    }
                    lines.append("REVIEWED GUIDANCE:")
                    lines.append(contentsOf: scenario.claims.map { claim in
                        let applies = claim.applicability.isEmpty
                            ? "" : " applies when: \(claim.applicability)"
                        return "- "
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
            if !prompt.expertEvidence.isEmpty {
                let available = Array(1...min(
                    prompt.tier == .lite ? 2 : 3,
                    prompt.expertEvidence.count
                )).map(String.init).joined(separator: ",")
                sections.append(
                    "RESPONSE CHECK: Give the best direct answer in complete natural prose. "
                    + "Cite only the reviewed scenario numbers actually used from [\(available)]. "
                    + "Use more than one only when each contributes. Put citations only in e, "
                    + "not inside a. Do not repeat REVIEWED SCENARIO or internal labels."
                )
            } else {
                sections.append(
                    "RESPONSE CHECK: Give the best direct answer in complete natural prose. "
                    + "Use only evidence indexes [\(indexes)] actually used, and do not "
                    + "repeat the lesson title or field labels."
                )
            }
        case .incidentFallback:
            sections.append(
                "RESPONSE CHECK: Give the useful answer first, adding safety guidance "
                + "only when relevant. Address the user directly and return e=[]."
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
                "ROUTING CHECK: Classify the current message only. "
                    + "For survival, return a short translated English retrieval query in q; "
                    + "otherwise return t=general and q as an empty string."
            )
        }

        sections.append("CURRENT USER MESSAGE\n\(prompt.question)")

        sections.append(
            prompt.purpose == .expertIntent
                    ? "ROUTING JSON:"
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
