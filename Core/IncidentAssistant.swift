import Foundation

private struct ExpertRenderedResult {
    let text: String
    let passages: [RetrievedPassage]
    let sentenceCitations: [AnswerSentenceCitation]
    let sourceCards: [AnswerSourceCard]
    let evidenceIDs: [String]
}

public actor IncidentAssistant {
    enum LiteEvidencePolicy: Sendable {
        case legacyTopOne
        case operationAwareTopTwo
    }

    private let retrieval: any EvidenceRetrieving
    private let expertEvidenceRetrieval: any ExpertEvidenceRetrieving
    private let router: ModelRouter
    private let citationPolicy: CitationPolicy
    private let responseCodec: GroundedResponseCodec
    private let modelProvider: @Sendable (ModelTier) -> any LocalLanguageModel
    private let installedTiers: Set<ModelTier>
    private let expertValidated: Bool
    private let expertContextAssembler: ExpertContextAssembler?
    private let expertEmbeddingProvider: (any ExpertQueryEmbeddingProvider)?
    private let expertVectorIndex: ShardedExpertVectorIndex?
    private var expertSuspended = false
    private var lastExpertRetrievalCandidates: [RetrievedEvidenceScenario] = []
    private var liteEvidencePolicy: LiteEvidencePolicy = .operationAwareTopTwo

    public init(
        articles: [KnowledgeArticle],
        installedTiers: Set<ModelTier> = [],
        retrieval: (any EvidenceRetrieving)? = nil,
        expertEvidenceRetrieval: (any ExpertEvidenceRetrieving)? = nil,
        router: ModelRouter = ModelRouter(),
        citationPolicy: CitationPolicy = CitationPolicy(),
        groundedCodec: GroundedResponseCodec = GroundedResponseCodec(),
        expertValidated: Bool = false,
        expertContextAssembler: ExpertContextAssembler? = nil,
        expertEmbeddingProvider: (any ExpertQueryEmbeddingProvider)? = nil,
        expertVectorIndex: ShardedExpertVectorIndex? = nil,
        modelProvider: @escaping @Sendable (ModelTier) -> any LocalLanguageModel = {
            UnavailableLanguageModel(tier: $0)
        }
    ) {
        let resolvedRetrieval = retrieval ?? RetrievalEngine(articles: articles)
        self.retrieval = resolvedRetrieval
        self.expertEvidenceRetrieval = expertEvidenceRetrieval
            ?? ArticleBackedExpertEvidenceRetriever(retrieval: resolvedRetrieval)
        self.router = router
        self.citationPolicy = citationPolicy
        self.responseCodec = groundedCodec
        self.modelProvider = modelProvider
        self.installedTiers = installedTiers
        self.expertValidated = expertValidated
        self.expertContextAssembler = expertContextAssembler
        self.expertEmbeddingProvider = expertEmbeddingProvider
        self.expertVectorIndex = expertVectorIndex
    }

#if DEBUG
    func setDebugLiteEvidencePolicy(_ policy: LiteEvidencePolicy) {
        liteEvidencePolicy = policy
    }
#endif

    public func answer(
        request: ChatRequest,
        device: DeviceSnapshot,
        tokenSink: (@Sendable (String) -> Void)? = nil
    ) async -> AssistantAnswer? {
        lastExpertRetrievalCandidates = []
        let decision = router.route(
            requested: request.preferredTier,
            installed: installedTiers,
            expertValidated: expertValidated && !expertSuspended,
            device: device
        )
        guard var selectedTier = decision.selected else { return nil }
        var usedMemoryFallback = false
        let expertAssembly: ExpertContextAssembly?
        var expertRequest = request
        var expertTurnContext: ExpertResolvedTurnContext?
        if selectedTier == .expert {
            let resolved = ExpertTurnResolver().resolve(request)
            expertTurnContext = resolved
            expertRequest = ChatRequest(
                question: request.question,
                domain: request.domain,
                preferredTier: request.preferredTier,
                hasImage: request.hasImage,
                imageData: request.imageData,
                imageObservations: request.imageObservations,
                conversationHistory: resolved.relevantHistory
            )
            if let assembly = expertContextAssembler?.assemble(
                question: expertRequest.question,
                conversationHistory: expertRequest.conversationHistory,
                availableMemoryBytes: device.availableMemoryBytes
            ) {
                expertAssembly = assembly
            } else if installedTiers.contains(.lite),
                      router.route(
                        requested: .lite,
                        installed: installedTiers,
                        device: device
                      ).selected == .lite {
                selectedTier = .lite
                usedMemoryFallback = true
                expertAssembly = nil
            } else {
                return Self.runtimeFailure(tier: .expert, notices: [])
            }
        } else {
            expertAssembly = nil
        }
        var notices: [String] = []
        if usedMemoryFallback {
            notices.append("Expert paused for memory headroom; using Lite.")
        }
        if decision.requested != decision.selected {
            notices.append(decision.explanation)
        }

        if selectedTier == .expert,
           let expertAssembly,
           expertTurnContext != nil {
            return await answerExpert(
                request: expertRequest,
                assembly: expertAssembly,
                notices: notices,
                tokenSink: tokenSink
            )
        }
        if request.hasImage {
            notices.append("Lite is text-only; the attached image was not sent to the model.")
        }
        let liteRequest = ChatRequest(
            question: request.question,
            domain: request.domain,
            preferredTier: .lite,
            hasImage: false,
            imageData: nil,
            imageObservations: [],
            conversationHistory: []
        )
        return await answerSharedText(
            request: liteRequest,
            tier: .lite,
            conversationHistory: [],
            contextProfile: nil,
            maximumImageDimension: nil,
            notices: notices,
            tokenSink: tokenSink
        )
    }

    private func answerExpert(
        request: ChatRequest,
        assembly: ExpertContextAssembly,
        notices initialNotices: [String],
        tokenSink: (@Sendable (String) -> Void)?
    ) async -> AssistantAnswer {
        let model = modelProvider(.expert)
        var notices = initialNotices
        if request.hasImage {
            guard let imageData = request.imageData else {
                return Self.visionFailure(
                    notices: notices,
                    message: "Expert couldn’t read the attached photo. Attach it again and retry."
                )
            }
            return await answerNativeVision(
                question: request.question,
                imageData: imageData,
                conversationHistory: assembly.conversationHistory,
                assembly: assembly,
                model: model,
                notices: notices,
                tokenSink: tokenSink
            )
        }
        return await answerSharedText(
            request: request,
            tier: .expert,
            conversationHistory: assembly.conversationHistory,
            contextProfile: assembly.profile,
            maximumImageDimension: assembly.maximumImageDimension,
            notices: notices,
            tokenSink: tokenSink
        )
    }

    private func answerSharedText(
        request: ChatRequest,
        tier: ModelTier,
        conversationHistory: [ConversationTurn],
        contextProfile: ExpertContextProfile?,
        maximumImageDimension: Int?,
        notices initialNotices: [String],
        tokenSink: (@Sendable (String) -> Void)?
    ) async -> AssistantAnswer {
        let model = modelProvider(tier)
        var notices = initialNotices
        let imageObservations: [String] = []
        let responseLanguage = ResponseLanguage.detect(in: request.question)
        let languageCompatibleHistory = Self.languageCompatibleHistory(
            conversationHistory,
            responseLanguage: responseLanguage
        )
        let intentPrompt = ModelPrompt(
            question: request.question,
            evidence: [],
            imageObservations: imageObservations,
            tier: tier,
            permitsVisionReasoning: false,
            conversationHistory: languageCompatibleHistory,
            expertContextProfile: contextProfile,
            maximumImageDimension: maximumImageDimension,
            purpose: .expertIntent
        )
        let routingDecision: TurnRoutingDecision
        do {
            let rawIntent = try await model.generate(prompt: intentPrompt)
            routingDecision = try TurnRoutingDecisionCodec().decodeAndValidate(rawIntent)
        } catch {
            routingDecision = TurnRoutingDecision(
                intent: .generalQuestion,
                retrievalQuery: ""
            )
        }
        let intent = routingDecision.intent
        let shouldSearch = intent == .survivalQuestion
        let routedQuery = shouldSearch ? routingDecision.retrievalQuery : ""
        let semanticQuery = shouldSearch ? routedQuery : ""
        let retrievalRequest = ChatRequest(
            question: semanticQuery,
            domain: request.domain,
            preferredTier: tier,
            hasImage: false,
            imageData: nil,
            imageObservations: imageObservations,
            conversationHistory: languageCompatibleHistory
        )
        var denseResults: [ExpertVectorSearchResult] = []
        var sharedRAGAvailable = expertEmbeddingProvider != nil
            && expertVectorIndex != nil
            && expertVectorIndex?.issues.isEmpty == true
        if shouldSearch, sharedRAGAvailable,
           let expertEmbeddingProvider, let expertVectorIndex {
            do {
                var denseByID: [String: ExpertVectorSearchResult] = [:]
                for query in Self.semanticRetrievalQueries(
                    base: semanticQuery,
                    question: request.question
                ) {
                    let vector = try await expertEmbeddingProvider.embedding(for: query)
                    for result in expertVectorIndex.search(
                        queryVector: vector,
                        domain: request.domain,
                        globalLimit: 128
                    ) where result.score > (denseByID[result.record.id]?.score ?? -.infinity) {
                        denseByID[result.record.id] = result
                    }
                }
                denseResults = denseByID.values.sorted {
                    if $0.score == $1.score { return $0.record.id < $1.record.id }
                    return $0.score > $1.score
                }
            } catch {
                sharedRAGAvailable = false
            }
        }
        if shouldSearch, !sharedRAGAvailable {
            notices.append(
                "Shared semantic retrieval is unavailable; this answer uses no offline grounding."
            )
        }
        let candidates = shouldSearch && sharedRAGAvailable
            ? ExpertScenarioRetrievalEngine(
                retrieval: expertEvidenceRetrieval
              ).search(
                request: retrievalRequest,
                denseResults: denseResults,
                limit: tier == .lite && liteEvidencePolicy == .operationAwareTopTwo
                    ? 10 : 16,
                rankingMode: tier == .lite
                    && liteEvidencePolicy == .operationAwareTopTwo
                    ? .liteOperationAware : .standard
              )
            : []
        let selectedExpertEvidence = Self.selectEligibleEvidence(
            candidates,
            tier: tier,
            question: request.question,
            litePolicy: liteEvidencePolicy
        )
        let selectedByID = Dictionary(uniqueKeysWithValues:
            selectedExpertEvidence.map { ($0.scenario.id, $0) }
        )
        lastExpertRetrievalCandidates = candidates.map { candidate in
            guard let selected = selectedByID[candidate.scenario.id] else {
                var rejected = candidate
                if candidate.isEligible {
                    rejected.finalSelectionReason = "eligible_below_selection_cutoff"
                }
                return rejected
            }
            return selected
        }
        let selectedEvidence = selectedExpertEvidence.map(Self.passage(for:))
        let finalPurpose: ModelPromptPurpose = if !selectedExpertEvidence.isEmpty {
            .grounded
        } else if intent == .survivalQuestion {
            .incidentFallback
        } else {
            .ordinary
        }
        if selectedExpertEvidence.isEmpty,
           intent == .survivalQuestion {
            notices.append(
                "No matching offline source was found; this is the model's best-effort answer."
            )
        }

        let finalPrompt = ModelPrompt(
            question: request.question,
            evidence: selectedEvidence,
            imageObservations: imageObservations,
            tier: tier,
            permitsVisionReasoning: false,
            conversationHistory: languageCompatibleHistory,
            expertContextProfile: contextProfile,
            maximumImageDimension: maximumImageDimension,
            expertEvidence: selectedExpertEvidence,
            responseLanguage: responseLanguage,
            purpose: finalPurpose
        )
        let streamDecoder = ExpertEnvelopeStreamDecoder()
        let streamedTokenSink: @Sendable (String) -> Void = { piece in
            for delta in streamDecoder.append(piece) {
                tokenSink?(delta)
            }
        }
        let generated: String
        do {
            generated = try await model.generate(
                prompt: finalPrompt,
                tokenSink: streamedTokenSink
            )
        } catch {
            #if DEBUG
            print("Aurora \(tier.displayName) answer generation failed: \(error)")
            #endif
            if tier == .expert { expertSuspended = true }
            return Self.runtimeFailure(tier: tier, notices: notices)
        }
        for delta in streamDecoder.finish() {
            tokenSink?(delta)
        }
        let chosen: ExpertRenderedResult
        if let result = try? oneShotExpertResult(generated, prompt: finalPrompt) {
            chosen = result
        } else {
            let streamedText = streamDecoder.text
            guard finalPurpose == .ordinary,
                  !streamedText.isEmpty,
                  streamedText.last.map({ ".!?…。！？".contains($0) }) == true,
                  !GroundedResponseCodec.containsControlLeakage(streamedText),
                  responseLanguage.accepts(streamedText)
            else {
                return Self.modelFormatFailure(
                    tier: tier,
                    language: responseLanguage,
                    notices: notices
                )
            }
            chosen = ExpertRenderedResult(
                text: streamedText,
                passages: [],
                sentenceCitations: [],
                sourceCards: [],
                evidenceIDs: []
            )
        }
        return Self.answer(
            from: chosen,
            tier: tier,
            usedVision: false,
            notices: notices,
            intent: intent,
            retrievalStatus: intent == .survivalQuestion
                ? (selectedExpertEvidence.isEmpty
                    ? .noRelevantEvidence : .acceptedEvidence)
                : nil
        )
    }

    private func answerNativeVision(
        question: String,
        imageData: Data,
        conversationHistory: [ConversationTurn],
        assembly: ExpertContextAssembly,
        model: any LocalLanguageModel,
        notices initialNotices: [String],
        tokenSink: (@Sendable (String) -> Void)?
    ) async -> AssistantAnswer {
        var notices = initialNotices
        let prompt = ModelPrompt(
            question: question,
            evidence: [],
            imageData: imageData,
            imageObservations: [],
            tier: .expert,
            permitsVisionReasoning: true,
            conversationHistory: conversationHistory,
            expertContextProfile: assembly.profile,
            maximumImageDimension: assembly.maximumImageDimension,
            responseLanguage: ResponseLanguage.detect(in: question),
            purpose: .nativeVisionAnswer
        )
        let streamDecoder = ExpertEnvelopeStreamDecoder()
        let streamedTokenSink: @Sendable (String) -> Void = { piece in
            for delta in streamDecoder.append(piece) {
                tokenSink?(delta)
            }
        }
        let generated: String
        do {
            generated = try await model.generate(
                prompt: prompt,
                tokenSink: streamedTokenSink
            )
        } catch {
            #if DEBUG
            print("Aurora Expert native vision generation failed: \(error)")
            #endif
            expertSuspended = true
            return Self.visionFailure(notices: notices)
        }
        for delta in streamDecoder.finish() {
            tokenSink?(delta)
        }
        let text: String
        if let result = try? oneShotExpertResult(generated, prompt: prompt) {
            text = result.text
        } else {
            let streamedText = streamDecoder.text
            guard !streamedText.isEmpty,
                  streamedText.last.map({ ".!?…。！？".contains($0) }) == true,
                  !GroundedResponseCodec.containsControlLeakage(streamedText)
            else {
                return Self.visionFailure(
                    notices: notices,
                    message: "Expert returned an unreadable vision answer. Retry with the photo attached."
                )
            }
            notices.append(
                "The vision response format was incomplete; clean model prose is shown."
            )
            text = streamedText
        }
        return AssistantAnswer(
            text: text,
            severity: .informational,
            sources: [],
            manualReferences: [],
            modelTier: .expert,
            visionWasUsed: true,
            notices: notices
        )
    }

    static func languageCompatibleHistory(
        _ history: [ConversationTurn],
        responseLanguage: ResponseLanguage
    ) -> [ConversationTurn] {
        history.filter { turn in
            turn.role == .user || responseLanguage.accepts(turn.text)
        }
    }

    static func prioritizeScenarioCoverage(
        _ candidates: [RetrievedEvidenceScenario],
        for question: String
    ) -> [RetrievedEvidenceScenario] {
        let terms = Set(RetrievalEngine.tokens(in: question))
        var desiredChapters: [String] = []
        let medical: Set<String> = [
            "bleeding", "clumsy", "frostbite", "hypothermia", "shivering", "soaked",
        ]
        let navigation: Set<String> = [
            "bearing", "compass", "disoriented", "lost", "navigation", "trail",
        ]
        if !terms.isDisjoint(with: medical) { desiredChapters.append("first-aid") }
        if !terms.isDisjoint(with: navigation) { desiredChapters.append("navigation") }
        guard desiredChapters.count > 1 else { return candidates }

        var prioritized: [RetrievedEvidenceScenario] = []
        var selectedIDs: Set<String> = []
        for chapter in desiredChapters {
            if let candidate = candidates.first(where: {
                $0.isEligible && $0.scenario.chapterID == chapter
            }) {
                prioritized.append(candidate)
                selectedIDs.insert(candidate.scenario.id)
            }
        }
        if prioritized.count == desiredChapters.count {
            return prioritized
        }
        prioritized.append(contentsOf: candidates.filter {
            !selectedIDs.contains($0.scenario.id)
        })
        return prioritized
    }

    static func selectEligibleEvidence(
        _ candidates: [RetrievedEvidenceScenario],
        tier: ModelTier,
        question: String,
        litePolicy: LiteEvidencePolicy = .operationAwareTopTwo
    ) -> [RetrievedEvidenceScenario] {
        var selected: [RetrievedEvidenceScenario] = []
        var selectedClaimCount = 0
        let scenarioLimit = tier == .lite
            ? (litePolicy == .legacyTopOne ? 1 : 2)
            : 3
        let ordered = tier == .lite
            ? candidates
            : prioritizeScenarioCoverage(candidates, for: question)
        for candidate in ordered
        where candidate.isEligible {
            guard selected.count < scenarioLimit else { break }
            let claimLimit = tier == .lite
                ? litePolicy == .legacyTopOne
                    ? 4 : (selected.isEmpty ? 6 : 4)
                : 8
            let prioritized = prioritizeClaims(
                in: candidate,
                for: question,
                maximumClaims: claimLimit
            )
            let proposedClaimCount = selectedClaimCount
                + prioritized.scenario.claims.count
            guard proposedClaimCount <= 30 else { continue }
            var diagnosed = prioritized
            diagnosed.finalSelectionReason = "eligible_rank_\(selected.count + 1)"
            diagnosed.promptTokenContribution = max(
                1,
                diagnosed.scenario.claims.reduce(0) { $0 + $1.text.count } / 4
            )
            selected.append(diagnosed)
            selectedClaimCount = proposedClaimCount
        }
        return selected
    }

    static func semanticRetrievalQueries(
        base: String,
        question: String
    ) -> [String] {
        let terms = Set(RetrievalEngine.tokens(in: question))
        let medical: Set<String> = [
            "bleeding", "clumsy", "frostbite", "hypothermia", "shivering", "soaked",
        ]
        let navigation: Set<String> = [
            "bearing", "compass", "disoriented", "lost", "navigation", "trail",
        ]
        guard !terms.isDisjoint(with: medical),
              !terms.isDisjoint(with: navigation)
        else { return [base] }
        return [
            base,
            "soaked shivering cold hypothermia exposure",
            "lost navigation disoriented stop mark last known point",
        ]
    }

    static func prioritizeClaims(
        in candidate: RetrievedEvidenceScenario,
        for question: String,
        maximumClaims: Int = 8
    ) -> RetrievedEvidenceScenario {
        func normalizedTerms(_ value: String) -> Set<String> {
            Set(RetrievalEngine.tokens(in: value).map {
                $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0
            })
        }
        let queryTerms = normalizedTerms(question)
        func score(_ claim: ReviewedClaim) -> Int {
            let searchable = ([claim.text] + claim.sourceLocators)
                .joined(separator: " ")
            let overlap = queryTerms.intersection(normalizedTerms(searchable)).count
            let safety = switch claim.kind {
            case .contraindication, .escalation, .stopCondition: 1
            default: 0
            }
            return overlap * 10 + safety
        }
        let standalone = candidate.scenario.claims.enumerated().filter {
            Self.isStandaloneClaim($0.element)
        }
        let pool = standalone.isEmpty
            ? Array(candidate.scenario.claims.enumerated())
            : standalone
        func priority(_ claim: ReviewedClaim) -> Int {
            let directlyRelevant = score(claim) >= 10
            return switch claim.kind {
            case .action where directlyRelevant: 0
            case .contraindication, .stopCondition, .escalation: 1
            case .allowedNumber where directlyRelevant: 2
            case .applicability: 3
            case .action: 4
            case .allowedNumber: 5
            case .rationale: 6
            }
        }
        let ranked = pool.sorted { left, right in
            let leftPriority = priority(left.element)
            let rightPriority = priority(right.element)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            let leftScore = score(left.element)
            let rightScore = score(right.element)
            return leftScore == rightScore
                ? left.offset < right.offset
                : leftScore > rightScore
        }
        var selectedOffsets: Set<Int> = []
        if let applicableAction = ranked.first(where: {
            $0.element.kind == .action || $0.element.kind == .applicability
        }) {
            selectedOffsets.insert(applicableAction.offset)
        }
        if let warning = ranked.first(where: {
            [.contraindication, .stopCondition, .escalation]
                .contains($0.element.kind)
        }) {
            selectedOffsets.insert(warning.offset)
        }
        for item in ranked where selectedOffsets.count < maximumClaims {
            selectedOffsets.insert(item.offset)
        }
        let claims = ranked.filter { selectedOffsets.contains($0.offset) }
            .prefix(maximumClaims)
            .map(\.element)
        let scenario = candidate.scenario
        let reordered = EvidenceScenarioRecord(
            id: scenario.id,
            lessonID: scenario.lessonID,
            chapterID: scenario.chapterID,
            title: scenario.title,
            applicability: scenario.applicability,
            observableCues: scenario.observableCues,
            prerequisites: scenario.prerequisites,
            riskClass: scenario.riskClass,
            jurisdiction: scenario.jurisdiction,
            units: scenario.units,
            relatedScenarioIDs: scenario.relatedScenarioIDs,
            claims: claims,
            manualReference: scenario.manualReference,
            evidenceLocator: scenario.evidenceLocator
        )
        return RetrievedEvidenceScenario(
            scenario: reordered,
            score: candidate.score,
            preBoostScore: candidate.preBoostScore,
            shadowCorpusBoost: candidate.shadowCorpusBoost,
            linkedChunkIDs: candidate.linkedChunkIDs,
            highestAuthorityTier: candidate.highestAuthorityTier,
            promotionStatus: candidate.promotionStatus,
            lexicalRank: candidate.lexicalRank,
            denseRank: candidate.denseRank,
            denseSimilarity: candidate.denseSimilarity,
            fusedScore: candidate.fusedScore,
            meaningfulOverlapCount: candidate.meaningfulOverlapCount,
            appliedBoosts: candidate.appliedBoosts,
            isEligible: candidate.isEligible,
            eligibilityReason: candidate.eligibilityReason,
            exclusionReasons: candidate.exclusionReasons,
            subjectConcepts: candidate.subjectConcepts,
            operationConcepts: candidate.operationConcepts,
            hazardConcepts: candidate.hazardConcepts,
            subjectAlignment: candidate.subjectAlignment,
            operationAlignment: candidate.operationAlignment,
            coveredQueryConcepts: candidate.coveredQueryConcepts,
            candidatePoolPosition: candidate.candidatePoolPosition,
            promptTokenContribution: candidate.promptTokenContribution,
            claimQualityStatus: claims.allSatisfy(Self.isStandaloneClaim)
                ? "standalone" : "contains_fragment",
            finalSelectionReason: candidate.finalSelectionReason
        )
    }

    static func isStandaloneClaim(_ claim: ReviewedClaim) -> Bool {
        let text = claim.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12,
              !text.hasSuffix(":"),
              !text.hasSuffix(";"),
              !text.hasPrefix("- ") else { return false }
        let orphanLabels: Set<String> = [
            "best for", "contains", "keep", "look for", "materials",
            "methods", "possible indicators", "priority", "procedure",
            "provides", "search", "separate", "use",
        ]
        return !orphanLabels.contains(text.lowercased())
    }

    public func expertRetrievalDiagnostics() -> [RetrievedEvidenceScenario] {
        lastExpertRetrievalCandidates
    }

    private static func hasExplicitMultiTopicMarker(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(" also ")
            || lower.contains("also,")
            || lower.contains("additionally")
            || lower.contains("at the same time")
    }

    private func oneShotExpertResult(
        _ generated: String,
        prompt: ModelPrompt
    ) throws -> ExpertRenderedResult {
        if prompt.purpose == .grounded {
            let result = try Self.decode(
                generated,
                outputMode: .groundedJSON,
                purpose: prompt.purpose,
                question: prompt.question,
                tier: prompt.tier,
                responseLanguage: prompt.responseLanguage,
                evidence: prompt.evidence,
                codec: responseCodec,
                citationPolicy: citationPolicy
            )
            let citedPassageIDs = Set(result.passages.map { $0.article.id })
            let usedScenarios = zip(prompt.evidence, prompt.expertEvidence)
                .compactMap { passage, scenario in
                    citedPassageIDs.contains(passage.article.id) ? scenario : nil
                }
            guard !usedScenarios.isEmpty else { throw ModelFailure.invalidOutput }
            try ExpertAnswerSafetyValidator().validateEssential(
                answer: result.text,
                scenarios: usedScenarios
            )
            let sourceIDs = Array(Set(
                usedScenarios.flatMap { scenario in
                    scenario.scenario.claims.flatMap(\.sourceIDs)
                }
            )).sorted()
            var locatorBySourceID: [String: String] = [:]
            for claim in usedScenarios.flatMap({ $0.scenario.claims }) {
                for (offset, sourceID) in claim.sourceIDs.enumerated()
                where claim.sourceLocators.indices.contains(offset) {
                    locatorBySourceID[sourceID] = claim.sourceLocators[offset]
                }
            }
            let sourceCards = expertEvidenceRetrieval.expertSources(ids: sourceIDs)
                .map { source in
                    Self.sourceCard(
                        from: source,
                        locator: locatorBySourceID[source.id]
                    )
                }
            return ExpertRenderedResult(
                text: result.text,
                passages: result.passages,
                sentenceCitations: [AnswerSentenceCitation(
                    sentence: 1,
                    sourceIDs: sourceIDs
                )],
                sourceCards: sourceCards,
                evidenceIDs: usedScenarios.map { $0.scenario.id }.sorted()
            )
        }
        let result = try Self.decode(
            generated,
            outputMode: .groundedJSON,
            purpose: prompt.purpose,
            question: prompt.question,
            tier: prompt.tier,
            responseLanguage: prompt.responseLanguage,
            evidence: prompt.evidence,
            codec: responseCodec,
            citationPolicy: citationPolicy
        )
        return ExpertRenderedResult(
            text: result.text,
            passages: result.passages,
            sentenceCitations: [],
            sourceCards: [],
            evidenceIDs: []
        )
    }

    private static func sourceCard(
        from source: SurvivalSource,
        locator: String? = nil
    ) -> AnswerSourceCard {
        AnswerSourceCard(
            id: source.id,
            title: source.title,
            organization: source.organization.isEmpty ? nil : source.organization,
            url: source.url.isEmpty ? nil : source.url,
            locator: locator ?? source.locator,
            publishedAt: source.publishedAt,
            updatedAt: source.updatedAt,
            reviewedAt: source.reviewedAt,
            jurisdiction: source.jurisdiction,
            reviewStatus: source.reviewLevel
        )
    }

    private static func article(
        for scenario: EvidenceScenarioRecord
    ) -> KnowledgeArticle {
        let firstClaim = scenario.claims.first
        let reference = scenario.manualReference
        let locator = scenario.evidenceLocator
        return KnowledgeArticle(
            id: reference?.passageID ?? locator?.chunkID ?? scenario.id,
            domain: Self.domain(for: scenario.chapterID),
            title: scenario.title,
            summary: scenario.applicability,
            steps: scenario.actionClaims.map(\.text),
            warnings: scenario.safetyClaims.map(\.text),
            keywords: scenario.observableCues,
            source: SourceReference(
                id: firstClaim?.sourceIDs.first ?? scenario.id,
                title: firstClaim?.sourceLocators.first ?? scenario.title,
                organization: reference?.chapterTitle ?? "Survival Manual 2026",
                revision: reference?.sourceLabel ?? locator?.sectionPath ?? "Reviewed evidence"
            ),
            reviewed: firstClaim?.sourceIDs.isEmpty == false,
            manualReference: reference
        )
    }

    private static func passage(
        for result: RetrievedEvidenceScenario
    ) -> RetrievedPassage {
        RetrievedPassage(
            article: article(for: result.scenario),
            score: result.score
        )
    }

    private static func domain(for chapterID: String) -> KnowledgeDomain {
        switch chapterID {
        case "car": return .vehicle
        case "first-aid": return .firstAid
        case "navigation", "signal": return .navigation
        default: return .wilderness
        }
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
            || !ExpertRetrievalEngine.isEllipticalFollowUp(request.question)
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
        let naturalQuery = (
            context
                + [request.question]
                + request.imageObservations.prefix(4)
        ).joined(separator: " ")
        guard tier == .expert else { return naturalQuery }
        let additions = ExpertScenarioRetrievalEngine
            .meaningfulSurvivalTerms(in: naturalQuery)
            .subtracting(RetrievalEngine.tokens(in: naturalQuery))
            .sorted()
        guard !additions.isEmpty else { return naturalQuery }
        return naturalQuery + " Related survival concepts: "
            + additions.joined(separator: " ")
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
            "insect", "map", "medical", "mushroom", "navigate", "navigation", "outdoors", "pack", "plant",
            "prescription", "purify", "rescue", "river", "shelter", "signal", "snake", "snow",
            "sting", "stream", "survive",
            "storm", "stranded", "surgery", "survival", "tarp", "tent", "tick", "trail", "travel", "venomous",
            "vehicle", "warmth", "water", "weather", "wilderness", "wound",
        ]
        return !normalizedIntentTerms(query)
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

    static func matchesExactReviewedIntent(
        query: String,
        article: KnowledgeArticle
    ) -> Bool {
        reviewedIntentMatchPriority(query: query, article: article) > 0
    }

    private static func reviewedIntentMatchPriority(
        query: String,
        article: KnowledgeArticle
    ) -> Int {
        let queryTerms = normalizedIntentTerms(query)
        let titleTerms = normalizedIntentTerms(article.title)
        if titleTerms.count > 1, titleTerms.isSubset(of: queryTerms) {
            return 3
        }
        let summaryTerms = normalizedIntentTerms(article.summary)
        if summaryTerms.count > 3, summaryTerms.isSubset(of: queryTerms) {
            return 2
        }
        return article.keywords.contains { value in
            let terms = normalizedIntentTerms(value)
            return terms.count > 1 && terms.isSubset(of: queryTerms)
                || terms.count == 1
                    && terms == queryTerms
                    && !terms.isDisjoint(with: distinctiveSingleTermAliases)
        } ? 1 : 0
    }

    private static let distinctiveSingleTermAliases: Set<String> = [
        "assessment", "backtrack", "compass", "dehydration", "gear",
        "inventory", "lighter", "map", "prefilter", "priorities", "stop",
        "tarp", "tinder",
    ]

    private static func normalizedIntentTerms(_ text: String) -> Set<String> {
        let aliases: [String: String] = [
            "bled": "bleeding", "bleed": "bleeding",
            "bleeds": "bleeding", "bleading": "bleeding",
            "firre": "fire", "sheltr": "shelter", "watre": "water",
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
            "hypothermia", "injured", "injury", "insect", "leak", "lightning", "lost",
            "mushroom", "overheating", "plant", "purify", "rescue", "shelter", "snake", "snow", "tick", "venomous",
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
        tier: ModelTier,
        responseLanguage: ResponseLanguage,
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
                question: question,
                tier: tier,
                responseLanguage: responseLanguage
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

    private static func answer(
        from result: ExpertRenderedResult,
        tier: ModelTier,
        usedVision: Bool,
        notices: [String],
        intent: ExpertTurnIntent,
        retrievalStatus: ExpertRetrievalStatus?
    ) -> AssistantAnswer {
        AssistantAnswer(
            text: result.text,
            severity: .informational,
            sources: result.sourceCards.isEmpty
                ? result.passages.map(\.article.source)
                : result.sourceCards.map { card in
                    SourceReference(
                        id: card.id,
                        title: card.title,
                        organization: card.organization ?? card.title,
                        revision: card.updatedAt,
                        url: card.url
                    )
                },
            manualReferences: [],
            modelTier: tier,
            visionWasUsed: usedVision,
            notices: notices,
            retrievalWasDegraded: notices.contains { notice in
                notice.localizedCaseInsensitiveContains("degraded")
                    || notice.localizedCaseInsensitiveContains("unavailable")
                    || notice.localizedCaseInsensitiveContains("quarantined")
            },
            corroboratingSourceCount: Set(
                result.sourceCards.isEmpty
                    ? result.passages.map { $0.article.source.id }
                    : result.sourceCards.map(\.id)
            ).count,
            sentenceCitations: result.sentenceCitations,
            sourceCards: result.sourceCards,
            evidenceIDs: result.evidenceIDs,
            expertIntent: intent,
            expertRetrievalStatus: retrievalStatus
        )
    }

    private static func modelFormatFailure(
        tier: ModelTier,
        language: ResponseLanguage,
        notices: [String]
    ) -> AssistantAnswer {
        AssistantAnswer(
            text: language.retryMessage,
            severity: .caution,
            sources: [],
            modelTier: tier,
            visionWasUsed: false,
            notices: notices + [
                "Internal model-format text was withheld instead of being shown as guidance."
            ]
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

    private static func visionFailure(
        notices: [String],
        message: String = "Expert couldn’t inspect the photo. Attach it again and retry."
    ) -> AssistantAnswer {
        AssistantAnswer(
            text: message,
            severity: .caution,
            sources: [],
            manualReferences: [],
            modelTier: .expert,
            visionWasUsed: false,
            notices: notices
        )
    }

}
