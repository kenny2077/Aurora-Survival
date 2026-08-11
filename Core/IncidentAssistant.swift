import Foundation

public actor IncidentAssistant {
    private let retrieval: any EvidenceRetrieving
    private let router: ModelRouter
    private let citationPolicy: CitationPolicy
    private let responseCodec: GroundedResponseCodec
    private let modelProvider: @Sendable (ModelTier) -> any LocalLanguageModel
    private let installedTiers: Set<ModelTier>

    public init(
        articles: [KnowledgeArticle],
        installedTiers: Set<ModelTier> = [],
        retrieval: (any EvidenceRetrieving)? = nil,
        router: ModelRouter = ModelRouter(),
        citationPolicy: CitationPolicy = CitationPolicy(),
        groundedCodec: GroundedResponseCodec = GroundedResponseCodec(),
        modelProvider: @escaping @Sendable (ModelTier) -> any LocalLanguageModel = {
            UnavailableLanguageModel(tier: $0)
        }
    ) {
        self.retrieval = retrieval ?? RetrievalEngine(articles: articles)
        self.router = router
        self.citationPolicy = citationPolicy
        self.responseCodec = groundedCodec
        self.modelProvider = modelProvider
        self.installedTiers = installedTiers
    }

    public func answer(
        request: ChatRequest,
        device: DeviceSnapshot
    ) async -> AssistantAnswer? {
        let decision = router.route(
            requested: request.preferredTier,
            installed: installedTiers,
            device: device
        )
        guard let selectedTier = decision.selected else { return nil }
        let retrievalQuery = Self.retrievalQuery(
            for: request,
            tier: selectedTier
        )
        let candidates: [RetrievedPassage]
        let purpose: ModelPromptPurpose
        if selectedTier == .lite {
            let retrieved = retrieval.search(
                query: retrievalQuery,
                domain: request.domain,
                limit: 2
            )
            let matched = retrieved.filter {
                Self.matchesReviewedIntent(
                    query: retrievalQuery,
                    article: $0.article
                )
            }
            purpose = if !matched.isEmpty {
                .grounded
            } else if Self.isIncidentIntakeQuery(retrievalQuery) {
                .incidentIntake
            } else {
                .incidentFallback
            }
            // Gemma 3 1B is more reliable when one complete reviewed lesson is
            // supplied than when two neighboring lessons compete for attention.
            // Retrieval may inspect two candidates, but a specific Lite request
            // is grounded in the strongest accepted match only.
            candidates = Array(matched.prefix(1))
        } else {
            let requiresReviewedEvidence = Self.shouldRetrieve(
                for: request,
                query: retrievalQuery
            )
            candidates = requiresReviewedEvidence
                ? retrieval.search(
                    query: retrievalQuery,
                    domain: request.domain,
                    limit: 2
                )
                : []
            let needsClarification = requiresReviewedEvidence
                && Self.needsClarification(
                query: retrievalQuery,
                evidence: candidates
            )
            purpose = if !requiresReviewedEvidence {
                .ordinary
            } else if needsClarification {
                .clarification
            } else {
                .grounded
            }
        }
        var notices: [String] = []
        if decision.requested != decision.selected {
            notices.append(decision.explanation)
        }
        let model = modelProvider(selectedTier)
        let prompt = ModelPrompt(
            question: request.question,
            evidence: purpose == .grounded ? candidates : [],
            imageData: decision.canAnalyzeImage ? request.imageData : nil,
            imageObservations: request.imageObservations,
            tier: selectedTier,
            permitsVisionReasoning: request.hasImage && decision.canAnalyzeImage,
            conversationHistory: selectedTier == .lite
                ? []
                : Array(request.conversationHistory.suffix(4)),
            purpose: purpose
        )

        if request.hasImage && !decision.canAnalyzeImage {
            notices.append(
                request.imageObservations.isEmpty
                    ? "The selected tier cannot inspect the photo. Describe what you see."
                    : "The selected tier used on-device OCR text only."
            )
        }

        let generated: String
        do {
            generated = try await model.generate(prompt: prompt)
        } catch {
            return Self.runtimeFailure(tier: selectedTier, notices: notices)
        }

        if let result = try? Self.decode(
            generated,
            outputMode: model.outputMode,
            purpose: prompt.purpose,
            question: prompt.question,
            evidence: prompt.evidence,
            codec: responseCodec,
            citationPolicy: citationPolicy
        ) {
            return Self.answer(
                from: result,
                tier: selectedTier,
                usedVision: prompt.permitsVisionReasoning,
                notices: notices
            )
        }

        let repaired: String
        do {
            repaired = try await model.generate(prompt: prompt.repairing())
        } catch {
            return Self.runtimeFailure(tier: selectedTier, notices: notices)
        }
        guard let result = try? Self.decode(
            repaired,
            outputMode: model.outputMode,
            purpose: prompt.purpose,
            question: prompt.question,
            evidence: prompt.evidence,
            codec: responseCodec,
            citationPolicy: citationPolicy
        ) else {
            return AssistantAnswer(
                text: "\(selectedTier.displayName) couldn’t form a complete answer. Try rephrasing your question.",
                severity: .caution,
                sources: [],
                manualReferences: [],
                modelTier: selectedTier,
                visionWasUsed: false,
                notices: notices
            )
        }
        return Self.answer(
            from: result,
            tier: selectedTier,
            usedVision: prompt.permitsVisionReasoning,
            notices: notices
        )
    }

    public func search(
        _ query: String,
        domain: KnowledgeDomain? = nil
    ) -> [KnowledgeArticle] {
        retrieval.search(
            query: query,
            domain: domain,
            limit: 20
        ).map(\.article)
    }

    private static func retrievalQuery(
        for request: ChatRequest,
        tier: ModelTier
    ) -> String {
        let context = tier == .lite
            ? []
            : request.conversationHistory
                .filter { $0.role == .user }
                .suffix(2)
                .map { turn in
                    String(
                        turn.text
                            .replacingOccurrences(of: "\n", with: " ")
                            .prefix(180)
                    )
                }
        return (
            context
                + [request.question]
                + request.imageObservations.prefix(4)
        ).joined(separator: " ")
    }

    private static func shouldRetrieve(
        for request: ChatRequest,
        query: String
    ) -> Bool {
        if request.domain != nil {
            return true
        }
        let survivalTerms: Set<String> = [
            "aid", "airbag", "altitude", "animal", "avalanche", "bear", "bite", "bleeding",
            "boil", "burn", "camp", "camping", "car", "cold", "compass",
            "dehydration", "drink", "edible", "emergency", "filter", "fire",
            "dose", "ecu", "fish", "flood", "food", "forage", "fracture", "fuel", "heat", "ice",
            "hiking", "hurt", "hypothermia", "injured", "injury", "leak", "lightning", "lost",
            "map", "medical", "navigate", "navigation", "outdoors", "pack",
            "prescription", "purify", "rescue", "river", "shelter", "signal", "snake", "snow",
            "sting", "stream", "survive",
            "storm", "stranded", "surgery", "survival", "tarp", "tent", "trail", "travel",
            "vehicle", "warmth", "water", "weather", "wilderness", "wound",
        ]
        return !RetrievalEngine.tokens(in: query)
            .isDisjoint(with: survivalTerms)
    }

    private static func matchesReviewedIntent(
        query: String,
        article: KnowledgeArticle
    ) -> Bool {
        let queryTerms = normalizedIntentTerms(query)
        guard !queryTerms.isEmpty else { return false }
        if article.id.hasPrefix("navigation-"),
           !queryTerms.isDisjoint(with: ["key", "keys", "phone", "wallet"]) {
            return false
        }
        if article.id == "weather-wildlife-wildfire",
           !queryTerms.isDisjoint(with: ["building", "house", "indoor", "inside", "room"]),
           queryTerms.isDisjoint(with: ["ash", "forest", "wildfire"]) {
            return false
        }
        if article.id == "car-fuse",
           !queryTerms.isDisjoint(with: ["building", "house", "indoor", "inside", "room", "wire"]),
           queryTerms.isDisjoint(with: ["car", "vehicle"]) {
            return false
        }
        let genericTerms: Set<String> = [
            "car", "chest", "cleaner", "emergency", "feel", "fix", "have",
            "help", "household", "incident", "issue", "nearby", "pain",
            "phone", "problem", "severe", "swallowed", "survival", "survive",
            "thing", "vehicle",
        ]

        for phrase in article.keywords {
            let phraseTerms = normalizedIntentTerms(phrase)
            guard !phraseTerms.isEmpty else { continue }
            if phraseTerms.isSubset(of: queryTerms),
               phraseTerms.count > 1
                || phraseTerms.contains(where: { !genericTerms.contains($0) }) {
                return true
            }
        }

        let reviewedText = ([article.summary] + article.steps + article.warnings)
            .joined(separator: " ")
        let reviewedTerms = normalizedIntentTerms(reviewedText)
            .subtracting(genericTerms)
        let overlap = queryTerms.subtracting(genericTerms)
            .intersection(reviewedTerms)
        return overlap.count >= 2
    }

    private static func normalizedIntentTerms(_ text: String) -> Set<String> {
        let aliases: [String: String] = [
            "bled": "bleeding", "bleed": "bleeding",
            "bleeds": "bleeding", "bleading": "bleeding",
            "punctured": "puncture",
            "tires": "tire", "tyre": "tire", "tyres": "tire",
            "wounded": "wound", "wounds": "wound",
        ]
        return Set(RetrievalEngine.tokens(in: text).map { aliases[$0] ?? $0 })
    }

    private static func isIncidentIntakeQuery(_ query: String) -> Bool {
        let normalized = RetrievalEngine.tokens(in: query).joined(separator: " ")
        let phrases: Set<String> = [
            "can you help", "good afternoon", "good evening", "good morning",
            "how are you", "thank you", "thanks", "what can you do",
            "what is up", "whats up",
        ]
        if phrases.contains(normalized) { return true }

        let conversationalTerms: Set<String> = [
            "afternoon", "are", "can", "do", "doing", "evening", "good",
            "hello", "help", "hey", "hi", "how", "me", "morning", "oh",
            "ok", "okay", "please", "sup", "thank", "thanks", "up", "what",
            "you", "your",
        ]
        let terms = Set(RetrievalEngine.tokens(in: query))
        return !terms.isEmpty && terms.isSubset(of: conversationalTerms)
    }

    private static func suggestedChapter(for query: String) -> String {
        let terms = RetrievalEngine.tokens(in: query)
        if !terms.isDisjoint(with: ["water", "drink", "filter", "boil", "dehydration"]) {
            return "Find and Treat Water"
        }
        if !terms.isDisjoint(with: ["bleeding", "dose", "injured", "injury", "medical", "prescription", "surgery", "wound", "fracture"]) {
            return "Wilderness First Aid"
        }
        if !terms.isDisjoint(with: ["airbag", "car", "ecu", "vehicle", "battery", "tire", "overheat"]) {
            return "Car Breakdown"
        }
        if !terms.isDisjoint(with: ["lost", "map", "compass", "navigate"]) {
            return "Navigate When Lost"
        }
        if !terms.isDisjoint(with: ["fire", "flame", "tinder"]) {
            return "Start a Fire"
        }
        if !terms.isDisjoint(with: ["shelter", "tent", "tarp", "cold"]) {
            return "Build a Shelter"
        }
        return "Survival Basics"
    }

    private static func needsClarification(
        query: String,
        evidence: [RetrievedPassage]
    ) -> Bool {
        let terms = RetrievalEngine.tokens(in: query)
        let directIntentTerms: Set<String> = [
            "avalanche", "bear", "bite", "bleeding", "boil", "burn",
            "compass", "dehydration", "filter", "fire", "flood", "fracture",
            "hypothermia", "injured", "injury", "leak", "lightning", "lost",
            "overheating", "purify", "rescue", "shelter", "snake", "snow",
            "start", "storm", "stranded", "tire", "water", "wound",
        ]
        if !terms.isDisjoint(with: directIntentTerms) {
            return false
        }

        let genericTerms: Set<String> = [
            "a", "an", "and", "are", "car", "can", "do", "fix", "for",
            "help", "how", "i", "is", "it", "me", "my", "of", "please",
            "problem", "should", "survival", "survive", "the", "this", "to",
            "vehicle", "what", "with",
        ]
        for keyword in evidence.flatMap(\.article.keywords) {
            let keywordTerms = RetrievalEngine.tokens(in: keyword)
            guard !keywordTerms.isEmpty else { continue }
            if keywordTerms.isSubset(of: terms),
               keywordTerms.count > 1
                || keywordTerms.contains(where: { !genericTerms.contains($0) }) {
                return false
            }
        }

        return terms.subtracting(genericTerms).count < 2
    }

    private static func decode(
        _ generated: String,
        outputMode: ModelOutputMode,
        purpose: ModelPromptPurpose,
        question: String,
        evidence: [RetrievedPassage],
        codec: GroundedResponseCodec,
        citationPolicy: CitationPolicy
    ) throws -> (text: String, passages: [RetrievedPassage]) {
        switch outputMode {
        case .groundedJSON:
            let response = try codec.decodeConversationalAndValidate(
                generated,
                evidence: evidence,
                purpose: purpose,
                question: question
            )
            let selected = response.evidenceIDs.compactMap { evidenceID in
                evidence.first { $0.article.id == evidenceID }
            }
            return (response.answer, selected)
        case .citationText:
            let clean = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw ModelFailure.invalidOutput }
            guard !evidence.isEmpty else { return (clean, []) }
            if let validated = citationPolicy.validatedText(
                clean,
                evidenceCount: evidence.count
            ) {
                let selected = evidence.enumerated().compactMap { index, passage in
                    validated.contains("[\(index + 1)]") ? passage : nil
                }
                return (Self.removingEvidenceMarkers(validated), selected)
            }
            return (clean, [])
        }
    }

    private static func manualReferences(
        _ passages: [RetrievedPassage]
    ) -> [ManualReference] {
        var seen: Set<String> = []
        return passages.compactMap { passage in
            guard let reference = passage.article.manualReference else {
                return nil
            }
            let sectionID = "\(reference.chapterNumber)|\(reference.sectionTitle)"
            return seen.insert(sectionID).inserted ? reference : nil
        }.prefix(2).map { $0 }
    }

    private static func removingEvidenceMarkers(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s*\[[0-9]+\]"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func answer(
        from result: (text: String, passages: [RetrievedPassage]),
        tier: ModelTier,
        usedVision: Bool,
        notices: [String]
    ) -> AssistantAnswer {
        AssistantAnswer(
            text: result.text,
            severity: .informational,
            sources: result.passages.map(\.article.source),
            manualReferences: manualReferences(result.passages),
            modelTier: tier,
            visionWasUsed: usedVision,
            notices: notices
        )
    }

    private static func runtimeFailure(
        tier: ModelTier,
        notices: [String]
    ) -> AssistantAnswer {
        AssistantAnswer(
            text: "\(tier.displayName) couldn’t run right now. Try again in a moment.",
            severity: .caution,
            sources: [],
            manualReferences: [],
            modelTier: tier,
            visionWasUsed: false,
            notices: notices
        )
    }

}
