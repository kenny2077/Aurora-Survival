import Foundation

public enum ExpertContextProfile: String, CaseIterable, Codable, Sendable {
    case full
    case balanced
    case constrained

    public var contextTokens: Int {
        switch self {
        case .full: return 8_192
        case .balanced: return 6_144
        case .constrained: return 4_096
        }
    }

    public var historyMessageLimit: Int {
        switch self {
        case .full: return 6
        case .balanced: return 4
        case .constrained: return 2
        }
    }

    public var historyTokenLimit: Int {
        switch self {
        case .full: return 1_600
        case .balanced: return 1_000
        case .constrained: return 500
        }
    }

    public var maximumImageDimension: Int {
        switch self {
        case .full: return 1_024
        case .balanced: return 768
        case .constrained: return 512
        }
    }
}

public struct ExpertRuntimeMemoryProfile: Equatable, Sendable {
    public static let requiredHeadroomBytes: UInt64 = 768 * 1_024 * 1_024

    public let measuredPeakBytes: [ExpertContextProfile: UInt64]

    public init(measuredPeakBytes: [ExpertContextProfile: UInt64]) {
        self.measuredPeakBytes = measuredPeakBytes
    }

    public func supports(
        _ profile: ExpertContextProfile,
        availableMemoryBytes: UInt64?
    ) -> Bool {
        guard let availableMemoryBytes,
              let measuredPeak = measuredPeakBytes[profile],
              measuredPeak <= UInt64.max - Self.requiredHeadroomBytes
        else { return false }
        return availableMemoryBytes >= measuredPeak + Self.requiredHeadroomBytes
    }
}

public struct ExpertContextAssembly: Equatable, Sendable {
    public let profile: ExpertContextProfile
    public let conversationHistory: [ConversationTurn]
    public let maximumImageDimension: Int
    public let inputTokenBudget: Int

    public init(
        profile: ExpertContextProfile,
        conversationHistory: [ConversationTurn],
        maximumImageDimension: Int,
        inputTokenBudget: Int
    ) {
        self.profile = profile
        self.conversationHistory = conversationHistory
        self.maximumImageDimension = maximumImageDimension
        self.inputTokenBudget = inputTokenBudget
    }
}

public enum ExpertTurnIntent: String, Codable, Equatable, Sendable {
    case generalQuestion = "general_question"
    case survivalQuestion = "survival_question"
}

public struct ExpertResolvedTurnContext: Equatable, Sendable {
    public let relevantHistory: [ConversationTurn]
    public let priorEvidenceIDs: [String]

    public init(
        relevantHistory: [ConversationTurn],
        priorEvidenceIDs: [String]
    ) {
        self.relevantHistory = relevantHistory
        self.priorEvidenceIDs = priorEvidenceIDs
    }
}

public struct ExpertTurnResolver: Sendable {
    public init() {}

    public func resolve(_ request: ChatRequest) -> ExpertResolvedTurnContext {
        if request.hasImage {
            return ExpertResolvedTurnContext(
                relevantHistory: [],
                priorEvidenceIDs: []
            )
        }
        let normalized = RetrievalEngine.tokens(in: request.question)
            .joined(separator: " ")
        if Self.isStandaloneConversation(normalized) {
            return ExpertResolvedTurnContext(
                relevantHistory: [],
                priorEvidenceIDs: []
            )
        }
        let history = request.conversationHistory
        if Self.isAnswerFocusedFollowUp(normalized),
           let assistantIndex = history.lastIndex(where: { $0.role == .assistant }) {
            let assistant = history[assistantIndex]
            let priorUser = history[..<assistantIndex].last { $0.role == .user }
            return ExpertResolvedTurnContext(
                relevantHistory: [priorUser, assistant].compactMap { $0 },
                priorEvidenceIDs: assistant.evidenceIDs
            )
        }
        if ExpertRetrievalEngine.isEllipticalFollowUp(request.question),
           let priorUser = history.last(where: { $0.role == .user }) {
            return ExpertResolvedTurnContext(
                relevantHistory: [priorUser],
                priorEvidenceIDs: history.last(where: {
                    $0.role == .assistant
                })?.evidenceIDs ?? []
            )
        }
        return ExpertResolvedTurnContext(
            relevantHistory: [],
            priorEvidenceIDs: []
        )
    }

    private static func isStandaloneConversation(_ normalized: String) -> Bool {
        let phrases: Set<String> = [
            "good afternoon", "good evening", "good morning", "hello", "hey",
            "hi", "how are you", "sup", "thank you", "thanks", "wassup",
            "what is up", "whats up",
        ]
        if phrases.contains(normalized) { return true }
        let terms = Set(normalized.split(separator: " ").map(String.init))
        let conversational: Set<String> = [
            "are", "doing", "good", "hello", "hey", "hi", "how", "ok",
            "okay", "sup", "thank", "thanks", "up", "wassup", "what", "you",
        ]
        let clearlyNonIncident: Set<String> = [
            "compliment", "computer", "fiction", "laptop", "movie", "poem",
            "software", "story",
        ]
        return (!terms.isEmpty && terms.isSubset(of: conversational))
            || !terms.isDisjoint(with: clearlyNonIncident)
    }

    private static func isAnswerFocusedFollowUp(_ normalized: String) -> Bool {
        let phrases = [
            "explain that", "what did you mean", "what do you mean",
            "why did you say", "why is that", "why",
        ]
        return phrases.contains(normalized)
    }
}

public struct ExpertContextAssembler: Sendable {
    public static let outputTokenReserve = 384
    public static let templateHeadroomTokens = 512

    private let memoryProfile: ExpertRuntimeMemoryProfile

    public init(memoryProfile: ExpertRuntimeMemoryProfile) {
        self.memoryProfile = memoryProfile
    }

    public func assemble(
        question: String,
        conversationHistory: [ConversationTurn],
        availableMemoryBytes: UInt64?
    ) -> ExpertContextAssembly? {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let profile = ExpertContextProfile.allCases.first(where: {
                  memoryProfile.supports(
                      $0,
                      availableMemoryBytes: availableMemoryBytes
                  )
              })
        else { return nil }

        var selected: [ConversationTurn] = []
        var usedTokens = 0
        for turn in conversationHistory
            .suffix(profile.historyMessageLimit)
            .reversed() {
            let tokens = Self.estimatedTokenCount(turn.text) + 4
            guard usedTokens + tokens <= profile.historyTokenLimit else { continue }
            selected.append(turn)
            usedTokens += tokens
        }

        return ExpertContextAssembly(
            profile: profile,
            conversationHistory: selected.reversed(),
            maximumImageDimension: profile.maximumImageDimension,
            inputTokenBudget: profile.contextTokens
                - Self.outputTokenReserve
                - Self.templateHeadroomTokens
        )
    }

    /// Conservative deterministic estimate used before the native tokenizer is
    /// loaded. The runtime still enforces the actual context limit.
    public static func estimatedTokenCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let scalars = text.unicodeScalars.count
        let words = text.split(whereSeparator: \.isWhitespace).count
        return max(words, (scalars + 2) / 3)
    }
}

public struct ExpertRetrievalEngine: Sendable {
    private struct WeightedQuery: Sendable {
        let text: String
        let weight: Double
    }

    private let retrieval: any EvidenceRetrieving

    public init(retrieval: any EvidenceRetrieving) {
        self.retrieval = retrieval
    }

    public func search(request: ChatRequest, limit: Int = 2) -> [RetrievedPassage] {
        let queries = Self.queries(for: request)
        var fused: [String: RetrievedPassage] = [:]

        for query in queries {
            for (rank, passage) in retrieval.search(
                query: query.text,
                domain: request.domain,
                limit: 8
            ).enumerated() {
                let contribution = query.weight / Double(60 + rank + 1)
                if let existing = fused[passage.article.id] {
                    fused[passage.article.id] = RetrievedPassage(
                        article: existing.article,
                        score: existing.score + contribution
                    )
                } else {
                    fused[passage.article.id] = RetrievedPassage(
                        article: passage.article,
                        score: contribution
                    )
                }
            }
        }

        var seenLessons: Set<String> = []
        return fused.values.map { passage in
            RetrievedPassage(
                article: passage.article,
                score: passage.score + Self.rerankBonus(
                    passage.article,
                    request: request
                )
            )
        }.sorted {
            if $0.score == $1.score { return $0.article.id < $1.article.id }
            return $0.score > $1.score
        }.filter { passage in
            let lessonID = passage.article.manualReference?.lessonID
            let identity = lessonID.flatMap { $0.isEmpty ? nil : $0 }
                ?? passage.article.id
            return seenLessons.insert(identity).inserted
        }.prefix(max(1, min(4, limit))).map { $0 }
    }

    private static func queries(for request: ChatRequest) -> [WeightedQuery] {
        let current = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorUserTurns = request.conversationHistory
            .filter { $0.role == .user }
            .suffix(2)
            .map { String($0.text.prefix(240)) }
        let resolvesHistory = isEllipticalFollowUp(current)
            && !priorUserTurns.isEmpty
        let observationDriven = current.lowercased().contains(
            "visible observation"
        ) && !request.imageObservations.isEmpty
        var result: [WeightedQuery] = []
        if resolvesHistory {
            result.append(
                WeightedQuery(
                    text: (priorUserTurns + [current]).joined(separator: " "),
                    weight: 1.0
                )
            )
        } else if !observationDriven {
            result.append(WeightedQuery(text: current, weight: 1.0))
        }
        let qualityMarkers: Set<String> = [
            "blurred", "low contrast", "uncertain edge",
        ]
        let observations = request.imageObservations.prefix(4)
            .map { String($0.prefix(160)) }
            .filter { !qualityMarkers.contains($0.lowercased()) }
        if !observations.isEmpty {
            result.append(
                WeightedQuery(
                    text: ((observationDriven ? [] : [current]) + observations)
                        .joined(separator: " "),
                    weight: 0.5
                )
            )
        }
        return result
    }

    static func isEllipticalFollowUp(_ text: String) -> Bool {
        let terms = RetrievalEngine.tokens(in: text)
        let genericTerms: Set<String> = [
            "about", "again", "also", "and", "another", "do", "for", "i",
            "it", "me", "my", "now", "please", "should", "that", "then",
            "this", "those", "to", "what", "with",
        ]
        let pronouns: Set<String> = ["it", "that", "this", "those"]
        return terms.subtracting(genericTerms).isEmpty
            && !terms.isDisjoint(with: pronouns)
    }

    private static func rerankBonus(
        _ article: KnowledgeArticle,
        request: ChatRequest
    ) -> Double {
        let genericIntentTerms: Set<String> = [
            "about", "action", "another", "do", "identify", "mean", "now",
            "observation", "safe", "safety", "should", "that", "this", "those",
            "use", "visible", "what",
        ]
        let rawCurrentTerms = RetrievalEngine.tokens(in: request.question)
        let currentTerms = rawCurrentTerms.subtracting(genericIntentTerms)
        let titleTerms = RetrievalEngine.tokens(in: article.title)
        let keywordTerms = Set(article.keywords.flatMap(RetrievalEngine.tokens))
        let warningTerms = Set(article.warnings.flatMap(RetrievalEngine.tokens))
        let observationTerms = RetrievalEngine.tokens(
            in: request.imageObservations.prefix(4).joined(separator: " ")
        )
        let reviewedTerms = RetrievalEngine.tokens(in: article.searchableText)
        let resolvesHistory = Self.isEllipticalFollowUp(request.question)
        let observationDriven = request.question.lowercased().contains(
            "visible observation"
        ) && !request.imageObservations.isEmpty
        let resolvedText = if resolvesHistory {
            request.conversationHistory
                .filter { $0.role == .user }
                .suffix(2)
                .map(\.text)
                .joined(separator: " ")
        } else if observationDriven {
            request.imageObservations.prefix(4).joined(separator: " ")
        } else {
            request.question
        }
        let resolvedPhrase = normalizedPhrase(resolvedText)
        let observationPhrases = request.imageObservations.prefix(4)
            .map(normalizedPhrase)
        let titlePhrase = normalizedPhrase(article.title)
        let summaryPhrase = normalizedPhrase(article.summary)
        var bonus = 0.0
        if resolvedPhrase == titlePhrase || observationPhrases.contains(titlePhrase) {
            bonus += 8.0
        } else if resolvedPhrase == summaryPhrase
            || observationPhrases.contains(summaryPhrase) {
            bonus += 8.0
        } else if resolvedPhrase.contains(titlePhrase) {
            bonus += 8.0
        }
        if article.steps.contains(where: {
            let phrase = normalizedPhrase($0)
            return phrase == resolvedPhrase || observationPhrases.contains(phrase)
        }) || article.warnings.contains(where: {
            let phrase = normalizedPhrase($0)
            return phrase == resolvedPhrase || observationPhrases.contains(phrase)
        }) {
            bonus += 8.0
        }
        for keyword in article.keywords {
            let phrase = normalizedPhrase(keyword)
            guard !phrase.isEmpty else { continue }
            if resolvedPhrase == phrase || observationPhrases.contains(phrase) {
                bonus += 6.0
                break
            }
            if resolvedPhrase.contains(phrase), phrase.split(separator: " ").count > 1 {
                bonus += 2.5
                break
            }
        }
        if resolvedPhrase == "assessment",
           article.manualReference?.lessonID == "basics-danger-injury" {
            // With no patient-specific sign, scene danger and life threats
            // precede a detailed medical assessment.
            bonus += 1.0
        }
        if !currentTerms.isEmpty {
            bonus += 0.25 * Double(currentTerms.intersection(titleTerms).count)
            bonus += 0.20 * Double(currentTerms.intersection(keywordTerms).count)
            bonus += 0.10 * Double(currentTerms.intersection(warningTerms).count)
            bonus += min(
                1.2,
                0.12 * Double(currentTerms.intersection(reviewedTerms).count)
            )
        }
        if request.domain == article.domain { bonus += 0.15 }
        bonus += min(
            1.0,
            0.12 * Double(observationTerms.intersection(reviewedTerms).count)
        )
        if resolvesHistory {
            let historyTerms = RetrievalEngine.tokens(in: request.conversationHistory
                .filter { $0.role == .user }
                .suffix(2)
                .map(\.text)
                .joined(separator: " "))
            bonus += min(
                1.0,
                0.12 * Double(historyTerms.intersection(reviewedTerms).count)
            )
        }
        return bonus
    }

    static func normalizedPhrase(_ value: String) -> String {
        let aliases = [
            "firre": "fire",
            "sheltr": "shelter",
            "watre": "water",
        ]
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "can", "do", "for",
            "from", "how", "i", "in", "is", "it", "my", "of", "on", "or",
            "the", "to", "what", "when", "where", "with",
        ]
        let normalized = value
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: .current
            )
            .lowercased()
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
            .map { aliases[$0] ?? $0 }
            .joined(separator: " ")
    }
}

struct RetrievalFacet: Equatable, Sendable {
    let text: String
    let normalizedQuery: String
    let subjectConcepts: Set<String>
    let operationConcepts: Set<String>
    let hazardConcepts: Set<String>
}

struct EvidenceCoverageDecision: Sendable {
    let facets: [RetrievalFacet]
    let selectedEvidence: [RetrievedEvidenceScenario]
    let coversCompleteRequest: Bool
    let reason: String
}

public struct ExpertScenarioRetrievalEngine: Sendable {
    public static let strongDenseSimilarityThreshold = 0.68
    public static let moderateDenseSimilarityThreshold = 0.58

    private struct WeightedQuery {
        let text: String
        let weight: Double
    }

    public enum RankingMode: Equatable, Sendable {
        case standard
        case liteOperationAware
    }

    struct RetrievalProfile: Equatable, Sendable {
        let subjectConcepts: Set<String>
        let requestedOperations: Set<String>
        let hazardConcepts: Set<String>

        var queryConcepts: Set<String> {
            subjectConcepts.union(requestedOperations).union(hazardConcepts)
        }
    }

    private let retrieval: any ExpertEvidenceRetrieving
    private let includesShadowCorpus: Bool

    public init(
        retrieval: any ExpertEvidenceRetrieving,
        includesShadowCorpus: Bool = true
    ) {
        self.retrieval = retrieval
        self.includesShadowCorpus = includesShadowCorpus
    }

    public func search(
        request: ChatRequest,
        denseResults: [ExpertVectorSearchResult] = [],
        limit: Int = 8,
        rankingMode: RankingMode = .standard
    ) -> [RetrievedEvidenceScenario] {
        let current = request.question.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let priorUser = request.conversationHistory
            .filter { $0.role == .user }
            .suffix(2)
            .map { String($0.text.prefix(240)) }
        let observations = request.imageObservations.prefix(4)
            .filter { observation in
                !["blurred", "low contrast", "uncertain edge"]
                    .contains(observation.lowercased())
            }
        let base = ExpertRetrievalEngine.isEllipticalFollowUp(current)
            && !priorUser.isEmpty
            ? priorUser + [current]
            : [current]
        let semanticQuery = (base + observations)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let requestsLiveInformation = Self.requestsLiveInformation(semanticQuery)
        let retrievalProfile = Self.retrievalProfile(in: semanticQuery)
        let lexicalTerms = rankingMode == .liteOperationAware
            ? retrievalProfile.queryConcepts
            : Self.meaningfulSurvivalTerms(in: semanticQuery)
        let boundedQuery = lexicalTerms.sorted().joined(separator: " ")
        var queries = boundedQuery.isEmpty
            ? []
            : [WeightedQuery(text: String(boundedQuery.prefix(720)), weight: 1)]
        let topicGroups: [Set<String>] = [
            ["bearing", "compass", "disoriented", "lost", "navigation"],
            ["cold", "hypothermia", "shivering", "soaked", "wet"],
            ["bleeding", "cut", "hemorrhage", "wound"],
        ]
        let activeTopics = topicGroups.filter {
            !$0.isDisjoint(with: lexicalTerms)
        }
        if activeTopics.count > 1 {
            queries.append(contentsOf: activeTopics.map {
                WeightedQuery(text: $0.sorted().joined(separator: " "), weight: 1)
            })
        }

        var lexical: [String: (EvidenceScenarioRecord, Int, Double)] = [:]
        var corpusBoosts: [String: Double] = [:]
        var corpusChunkIDs: [String: Set<String>] = [:]
        var corpusAuthorities: [String: ExpertSourceAuthorityTier] = [:]
        for query in queries {
            let results = retrieval.searchExpertEvidence(
                query: query.text,
                domain: request.domain,
                limit: 128
            )
            for (rank, result) in results.enumerated() {
                let contribution = query.weight / Double(60 + rank + 1)
                let scenarioID = result.scenario.id
                if lexical[scenarioID].map({ rank < $0.1 }) ?? true {
                    lexical[scenarioID] = (result.scenario, rank, contribution)
                }
            }
            let corpusResults = includesShadowCorpus
                ? retrieval.searchExpertCorpus(
                    query: query.text,
                    domain: request.domain,
                    limit: 128
                  )
                : []
            for (rank, result) in corpusResults.enumerated() {
                let scenarioID = result.scenarioID
                let corpusContribution = min(
                    0.6,
                    0.15 + query.weight * 0.45 / Double(rank + 1)
                )
                corpusBoosts[scenarioID] = max(
                    corpusBoosts[scenarioID] ?? 0,
                    corpusContribution
                )
                corpusChunkIDs[scenarioID, default: []]
                    .formUnion(result.chunkIDs)
                corpusAuthorities[scenarioID] = Self.higherAuthority(
                    corpusAuthorities[scenarioID],
                    result.authorityTier
                )
            }
        }
        var denseByScenario: [String: (
            EvidenceScenarioRecord, Int, Double, Double
        )] = [:]
        var denseDiscoveryBoosts: [String: Double] = [:]
        for (rank, result) in denseResults.prefix(128).enumerated() {
            let contribution = 1.0 / Double(60 + rank + 1)
            for scenarioID in result.record.scenarioIDs {
                switch result.record.authority {
                case .promoted:
                    guard let scenario = lexical[scenarioID]?.0
                            ?? retrieval.expertScenario(id: scenarioID)
                    else { continue }
                    if denseByScenario[scenarioID].map({ rank < $0.1 }) ?? true {
                        denseByScenario[scenarioID] = (
                            scenario, rank, contribution, result.score
                        )
                    }
                case .discovery:
                    denseDiscoveryBoosts[scenarioID] = max(
                        denseDiscoveryBoosts[scenarioID] ?? 0,
                        contribution
                    )
                }
            }
        }
        let scenarioIDs = Set(lexical.keys).union(denseByScenario.keys)
        let fused = scenarioIDs.compactMap { scenarioID -> RetrievedEvidenceScenario? in
            guard let scenario = lexical[scenarioID]?.0
                    ?? denseByScenario[scenarioID]?.0 else {
                return nil
            }
            let lexicalRank = lexical[scenarioID]?.1
            let denseRank = denseByScenario[scenarioID]?.1
            let denseSimilarity = denseByScenario[scenarioID]?.3
            let rrf = (lexical[scenarioID]?.2 ?? 0)
                + (denseByScenario[scenarioID]?.2 ?? 0)
            let relevance = Self.oneTimeRelevanceBonus(
                scenario,
                request: request
            )
            let discovery = min(
                0.006,
                (corpusBoosts[scenarioID] ?? 0) * 0.01
                    + (denseDiscoveryBoosts[scenarioID] ?? 0) * 0.1
            )
            let overlapCount = Self.meaningfulOverlapCount(
                queryTerms: lexicalTerms,
                scenario: scenario
            )
            let scenarioProfile = Self.retrievalProfile(
                in: scenario.searchableText
            )
            let relatedOperations = Set(scenario.relatedScenarioIDs.flatMap {
                retrieval.expertScenario(id: $0).map {
                    Self.retrievalProfile(in: $0.searchableText)
                        .requestedOperations
                } ?? []
            })
            let operationAlignment = retrievalProfile.requestedOperations
                .intersection(
                    scenarioProfile.requestedOperations.union(relatedOperations)
                ).count
            let subjectAlignment = retrievalProfile.subjectConcepts
                .intersection(scenarioProfile.subjectConcepts).count
            let coveredConcepts = retrievalProfile.queryConcepts
                .intersection(
                    scenarioProfile.queryConcepts.union(relatedOperations)
                ).count
            let subjectAligned = retrievalProfile.subjectConcepts.isEmpty
                || subjectAlignment > 0
            let operationAligned = retrievalProfile.requestedOperations.isEmpty
                || operationAlignment > 0
            let hazardAligned = retrievalProfile.hazardConcepts.isEmpty
                || !retrievalProfile.hazardConcepts.isDisjoint(
                    with: scenarioProfile.hazardConcepts
                )
            let eligibility: (Bool, String)
            if requestsLiveInformation {
                eligibility = (false, "live_information_not_offline_evidence")
            } else if relevance.exact {
                eligibility = (true, "exact_multiword_match")
            } else if let denseSimilarity,
                      denseSimilarity >= Self.strongDenseSimilarityThreshold,
                      subjectAligned,
                      operationAligned,
                      hazardAligned {
                eligibility = (true, "strong_dense_alignment")
            } else {
                eligibility = (false, "insufficient_absolute_relevance")
            }
            var boosts = relevance.labels
            if eligibility.0, discovery > 0 { boosts.append("linked_discovery") }
            let score = rrf + relevance.score + (eligibility.0 ? discovery : 0)
            return RetrievedEvidenceScenario(
                scenario: scenario,
                score: score,
                preBoostScore: rrf,
                shadowCorpusBoost: discovery,
                linkedChunkIDs: Array(corpusChunkIDs[scenarioID] ?? []).sorted(),
                highestAuthorityTier: corpusAuthorities[scenarioID],
                promotionStatus: .humanApproved,
                lexicalRank: lexicalRank,
                denseRank: denseRank,
                denseSimilarity: denseSimilarity,
                fusedScore: score,
                meaningfulOverlapCount: overlapCount,
                appliedBoosts: boosts,
                isEligible: eligibility.0,
                eligibilityReason: eligibility.1,
                exclusionReasons: eligibility.0
                    ? [] : ["insufficient_absolute_relevance"],
                subjectConcepts: retrievalProfile.subjectConcepts.sorted(),
                operationConcepts: retrievalProfile.requestedOperations.sorted(),
                hazardConcepts: retrievalProfile.hazardConcepts.sorted(),
                subjectAlignment: subjectAlignment,
                operationAlignment: operationAlignment,
                coveredQueryConcepts: coveredConcepts
            )
        }
        var ranked = fused.sorted {
            if rankingMode == .liteOperationAware {
                if $0.isEligible != $1.isEligible { return $0.isEligible }
                if $0.operationAlignment != $1.operationAlignment {
                    return $0.operationAlignment > $1.operationAlignment
                }
                if $0.subjectAlignment != $1.subjectAlignment {
                    return $0.subjectAlignment > $1.subjectAlignment
                }
                if $0.coveredQueryConcepts != $1.coveredQueryConcepts {
                    return $0.coveredQueryConcepts > $1.coveredQueryConcepts
                }
            }
            if $0.score == $1.score { return $0.scenario.id < $1.scenario.id }
            return $0.score > $1.score
        }
        if rankingMode == .liteOperationAware,
           let first = ranked.first,
           first.isEligible,
           let relatedIndex = ranked.dropFirst().firstIndex(where: {
               $0.isEligible
                   && first.scenario.relatedScenarioIDs.contains($0.scenario.id)
           }) {
            let related = ranked.remove(at: relatedIndex)
            ranked.insert(related, at: 1)
        }
        ranked = Array(ranked.prefix(max(1, min(limit, 16))))
        if rankingMode == .liteOperationAware {
            for index in ranked.indices {
                ranked[index].candidatePoolPosition = index + 1
            }
        }
        return ranked
    }

    private static func higherAuthority(
        _ left: ExpertSourceAuthorityTier?,
        _ right: ExpertSourceAuthorityTier
    ) -> ExpertSourceAuthorityTier {
        let rank: [ExpertSourceAuthorityTier: Int] = [
            .discovery: 0, .corroboration: 1, .authority: 2,
        ]
        guard let left else { return right }
        return rank[left, default: 0] >= rank[right, default: 0] ? left : right
    }

    private static func oneTimeRelevanceBonus(
        _ scenario: EvidenceScenarioRecord,
        request: ChatRequest
    ) -> (score: Double, labels: [String], exact: Bool) {
        let resolvedText: String
        if ExpertRetrievalEngine.isEllipticalFollowUp(request.question) {
            resolvedText = request.conversationHistory
                .filter { $0.role == .user }
                .suffix(2)
                .map(\.text)
                .joined(separator: " ")
        } else {
            resolvedText = ([request.question]
                + request.imageObservations.prefix(4))
                .joined(separator: " ")
        }
        let queryTerms = RetrievalEngine.tokens(in: resolvedText)
        let titleTerms = RetrievalEngine.tokens(in: scenario.title)
        let cueTerms = Set(scenario.observableCues.flatMap(RetrievalEngine.tokens))
        let reviewedTerms = RetrievalEngine.tokens(in: scenario.searchableText)
        let phrase = ExpertRetrievalEngine.normalizedPhrase(resolvedText)
        let titlePhrase = ExpertRetrievalEngine.normalizedPhrase(scenario.title)
        var labels: [String] = []
        let titleMeaningful = meaningfulSurvivalTerms(in: scenario.title)
        var exact = titleMeaningful.count >= 2
            && (phrase == titlePhrase || phrase.contains(titlePhrase))
        if exact { labels.append("exact_title") }
        if scenario.observableCues.contains(where: { cue in
            let cuePhrase = ExpertRetrievalEngine.normalizedPhrase(cue)
            let cueTerms = meaningfulSurvivalTerms(in: cue)
            return cueTerms.count >= 2 && (cuePhrase == phrase || (
                cuePhrase.split(separator: " ").count >= 2
                    && phrase.contains(cuePhrase)
            ))
        }) {
            exact = true
            labels.append("exact_current_cue")
        }
        let overlap = 0.002 * Double(queryTerms.intersection(titleTerms).count)
            + 0.0015 * Double(queryTerms.intersection(cueTerms).count)
            + min(0.01, 0.001 * Double(
                queryTerms.intersection(reviewedTerms).count
            ))
        if overlap > 0 { labels.append("term_overlap") }
        return (min(0.08, exact ? 0.08 : overlap), labels, exact)
    }

    static func meaningfulSurvivalTerms(in value: String) -> Set<String> {
        let generic: Set<String> = [
            "a", "about", "action", "an", "and", "another", "answer", "are",
            "as", "at", "be", "can", "could", "do", "find", "for", "from",
            "get", "give", "go", "have", "help", "how", "i", "identify", "in",
            "is", "it", "make", "my", "need", "now", "of", "on", "or",
            "device", "model", "repair", "survival", "unfamiliar",
            "please", "problem", "safe", "safety", "should", "take", "tell",
            "that", "the", "this", "to", "use", "want", "way", "what",
            "when", "where", "with",
        ]
        let raw = RetrievalEngine.tokens(in: value)
        var terms = raw.subtracting(generic)
        let expansions: [String: Set<String>] = [
            "darkness": ["darkness", "night", "daylight"],
            "lost": ["lost", "navigation", "disoriented"],
            "shivering": ["shivering", "cold", "hypothermia"],
            "soaked": ["soaked", "wet", "cold"],
        ]
        for token in raw {
            terms.formUnion(expansions[token] ?? [])
        }
        return terms
    }

    static func retrievalProfile(in value: String) -> RetrievalProfile {
        let raw = RetrievalEngine.tokens(in: value)
        let operationAliases: [String: String] = [
            "find": "locate", "finding": "locate", "search": "locate", "seek": "locate",
            "where": "locate", "locate": "locate",
            "start": "ignite", "starting": "ignite", "ignite": "ignite",
            "light": "ignite", "lighting": "ignite",
            "hunt": "hunt", "hunting": "hunt", "trap": "hunt",
            "trapping": "hunt", "catch": "hunt", "capture": "hunt",
            "eat": "eat", "eating": "eat", "edible": "eat",
            "consume": "eat", "consuming": "eat",
            "cook": "cook", "cooking": "cook", "roast": "cook",
            "roasting": "cook", "prepare": "cook", "preparing": "cook",
            "collect": "collect", "collection": "collect", "gather": "collect",
            "treat": "treat", "treatment": "treat", "purify": "treat",
            "filter": "filter", "boil": "boil", "boiling": "boil",
            "build": "build", "building": "build", "construct": "build",
            "constructing": "build", "erect": "build",
            "extinguish": "extinguish",
            "navigate": "navigate", "repair": "repair",
        ]
        let hazards: Set<String> = [
            "bleeding", "chemical", "cold", "contaminated", "contamination",
            "darkness", "dehydration", "fire", "frostbite", "heat",
            "hypothermia", "injury", "lost", "poison", "shivering",
            "soaked", "storm", "unsafe",
        ]
        var operations: Set<String> = []
        for token in raw {
            if let canonical = operationAliases[token] { operations.insert(canonical) }
        }
        let meaningful = meaningfulSurvivalTerms(in: value)
        let hazardConcepts = raw.intersection(hazards)
        let subjects = meaningful
            .subtracting(Set(operationAliases.keys))
            .subtracting(Set(operationAliases.values))
            .subtracting(hazards)
        return RetrievalProfile(
            subjectConcepts: subjects,
            requestedOperations: operations,
            hazardConcepts: hazardConcepts
        )
    }

    static func requestFacets(in question: String) -> [RetrievalFacet]? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let boundaryPattern = #"(?i)(?:[.!?;]+|\b(?:and then|also|additionally|plus)\b)"#
        guard let expression = try? NSRegularExpression(pattern: boundaryPattern) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var pieces: [String] = []
        var cursor = trimmed.startIndex
        for match in expression.matches(in: trimmed, range: range) {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            let piece = trimmed[cursor..<matchRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            cursor = matchRange.upperBound
        }
        let tail = trimmed[cursor...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }

        var expanded: [String] = []
        for piece in pieces {
            let connector = " and "
            guard let split = piece.range(
                of: connector,
                options: [.caseInsensitive]
            ) else {
                expanded.append(piece)
                continue
            }
            let left = piece[..<split.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let right = piece[split.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let leftProfile = retrievalProfile(in: left)
            let rightProfile = retrievalProfile(in: right)
            if !leftProfile.requestedOperations.isEmpty,
               !rightProfile.requestedOperations.isEmpty {
                expanded.append(contentsOf: [left, right])
            } else {
                expanded.append(piece)
            }
        }
        guard !expanded.isEmpty, expanded.count <= 3 else { return nil }

        var seen: Set<String> = []
        var facets: [RetrievalFacet] = []
        for text in expanded {
            let profile = retrievalProfile(in: text)
            guard !profile.queryConcepts.isEmpty else { return nil }
            let normalized = profile.queryConcepts.sorted().joined(separator: " ")
            guard seen.insert(normalized).inserted else { continue }
            facets.append(RetrievalFacet(
                text: text,
                normalizedQuery: normalized,
                subjectConcepts: profile.subjectConcepts,
                operationConcepts: profile.requestedOperations,
                hazardConcepts: profile.hazardConcepts
            ))
        }
        return facets.isEmpty ? nil : facets
    }

    private static func meaningfulOverlapCount(
        queryTerms: Set<String>,
        scenario: EvidenceScenarioRecord
    ) -> Int {
        queryTerms.intersection(
            meaningfulSurvivalTerms(in: scenario.searchableText)
        ).count
    }

    private static func requestsLiveInformation(_ value: String) -> Bool {
        let lower = value.lowercased()
        let markers = [
            " today", "current ", "currently", "latest ", "near me",
            "right now", "running on time", "playing tonight", "open tonight",
            "won last night", "next flight",
        ]
        return markers.contains(where: lower.contains)
    }
}
