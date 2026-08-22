import Foundation

public enum ExpertRiskClass: String, Codable, CaseIterable, Sendable {
    case low
    case high
    case critical
}

public enum ExpertSourceAuthorityTier: String, Codable, CaseIterable, Sendable {
    case authority
    case corroboration
    case discovery
}

public enum ExpertRedistributionClass: String, Codable, CaseIterable, Sendable {
    case publicDomainFullText = "public_domain_full_text"
    case publicDomainSelectedSections = "public_domain_selected_sections"
    case linkedMetadataOnly = "linked_metadata_only"
    case developmentOnly = "development_only"
    case ownedFullText = "owned_full_text"
}

public enum ExpertClaimPromotionStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case criticReviewed = "critic_reviewed"
    case humanApproved = "human_approved"
    case rejected
}

public struct ExpertSourceDocument: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let organization: String
    public let url: String
    public let authorityTier: ExpertSourceAuthorityTier
    public let redistributionClass: ExpertRedistributionClass
    public let jurisdiction: String
    public let publishedAt: String
    public let updatedAt: String
    public let reviewedAt: String
    public let licenseEvidence: String
    public let contentHash: String
    public let supersededByDocumentID: String?

    public init(
        id: String, title: String, organization: String, url: String,
        authorityTier: ExpertSourceAuthorityTier,
        redistributionClass: ExpertRedistributionClass,
        jurisdiction: String, publishedAt: String, updatedAt: String,
        reviewedAt: String, licenseEvidence: String, contentHash: String,
        supersededByDocumentID: String? = nil
    ) {
        self.id = id; self.title = title; self.organization = organization
        self.url = url; self.authorityTier = authorityTier
        self.redistributionClass = redistributionClass
        self.jurisdiction = jurisdiction; self.publishedAt = publishedAt
        self.updatedAt = updatedAt; self.reviewedAt = reviewedAt
        self.licenseEvidence = licenseEvidence; self.contentHash = contentHash
        self.supersededByDocumentID = supersededByDocumentID
    }
}

public struct ExpertSourceChunk: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let documentID: String
    public let locator: String
    public let sectionPath: String
    public let text: String
    public let scenarioIDs: [String]

    public init(
        id: String, documentID: String, locator: String,
        sectionPath: String, text: String, scenarioIDs: [String]
    ) {
        self.id = id; self.documentID = documentID; self.locator = locator
        self.sectionPath = sectionPath; self.text = text
        self.scenarioIDs = scenarioIDs
    }
}

public struct ExpertCorroborationEdge: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let leftDocumentID: String
    public let rightDocumentID: String
    public let topic: String
    public let locator: String

    public init(
        id: String, leftDocumentID: String, rightDocumentID: String,
        topic: String, locator: String
    ) {
        self.id = id; self.leftDocumentID = leftDocumentID
        self.rightDocumentID = rightDocumentID; self.topic = topic
        self.locator = locator
    }
}

public struct ExpertConflictRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let documentIDs: [String]
    public let topic: String
    public let resolution: String
    public let jurisdiction: String

    public init(
        id: String, documentIDs: [String], topic: String,
        resolution: String, jurisdiction: String
    ) {
        self.id = id; self.documentIDs = documentIDs; self.topic = topic
        self.resolution = resolution; self.jurisdiction = jurisdiction
    }
}

public struct ExpertClaimPromotionRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let scenarioID: String
    public let kind: ReviewedClaimKind
    public let text: String
    public let sourceDocumentIDs: [String]
    public let sourceLocators: [String]
    public let benchmarkGapIDs: [String]
    public let status: ExpertClaimPromotionStatus
    public let extractorReviewID: String
    public let criticReviewID: String
    public let humanReviewerID: String?

    public init(
        id: String, scenarioID: String, kind: ReviewedClaimKind, text: String,
        sourceDocumentIDs: [String], sourceLocators: [String],
        benchmarkGapIDs: [String], status: ExpertClaimPromotionStatus,
        extractorReviewID: String, criticReviewID: String,
        humanReviewerID: String? = nil
    ) {
        self.id = id; self.scenarioID = scenarioID; self.kind = kind
        self.text = text; self.sourceDocumentIDs = sourceDocumentIDs
        self.sourceLocators = sourceLocators; self.benchmarkGapIDs = benchmarkGapIDs
        self.status = status; self.extractorReviewID = extractorReviewID
        self.criticReviewID = criticReviewID; self.humanReviewerID = humanReviewerID
    }
}

public struct ExpertCorpusCandidate: Codable, Hashable, Sendable {
    public let scenario: EvidenceScenarioRecord
    public let chunkIDs: [String]
    public let score: Double
    public let authorityTier: ExpertSourceAuthorityTier

    public var scenarioID: String { scenario.id }

    public init(
        scenario: EvidenceScenarioRecord, chunkIDs: [String], score: Double,
        authorityTier: ExpertSourceAuthorityTier
    ) {
        self.scenario = scenario; self.chunkIDs = chunkIDs; self.score = score
        self.authorityTier = authorityTier
    }
}

public struct ExpertCorpusBoost: Codable, Hashable, Sendable {
    public let preBoostScore: Double
    public let shadowCorpusBoost: Double
    public let linkedChunkIDs: [String]
    public let highestAuthorityTier: ExpertSourceAuthorityTier?

    public static let none = ExpertCorpusBoost(
        preBoostScore: 0,
        shadowCorpusBoost: 0,
        linkedChunkIDs: [],
        highestAuthorityTier: nil
    )

    public init(
        preBoostScore: Double, shadowCorpusBoost: Double,
        linkedChunkIDs: [String],
        highestAuthorityTier: ExpertSourceAuthorityTier?
    ) {
        self.preBoostScore = preBoostScore
        self.shadowCorpusBoost = shadowCorpusBoost
        self.linkedChunkIDs = linkedChunkIDs
        self.highestAuthorityTier = highestAuthorityTier
    }
}

public enum ExpertFailureCategory: String, Codable, CaseIterable, Sendable {
    case missingEvidence = "missing_evidence"
    case retrievalMiss = "retrieval_miss"
    case evidenceSelectionError = "evidence_selection_error"
    case insufficientCoverage = "insufficient_coverage"
    case unsupportedGeneration = "unsupported_generation"
    case validatorFalseNegative = "validator_false_negative"
    case malformedOutput = "malformed_output"
    case inappropriateClarification = "inappropriate_clarification"
}

public enum ReviewedClaimKind: String, Codable, CaseIterable, Sendable {
    case applicability
    case action
    case rationale
    case contraindication
    case escalation
    case stopCondition = "stop_condition"
    case allowedNumber = "allowed_number"
}

public enum ReviewedClaimRequirementClass: String, Codable, CaseIterable, Sendable {
    case context
    case immediateAction = "immediate_action"
    case conditionalAction = "conditional_action"
    case contraindication
    case escalation
    case stopCondition = "stop_condition"
    case rationale
    case allowedNumber = "allowed_number"
}

public struct AllowedNumericFact: Codable, Hashable, Sendable {
    public let token: String
    public let sourceClaimID: String

    public init(token: String, sourceClaimID: String) {
        self.token = token
        self.sourceClaimID = sourceClaimID
    }
}

public struct ReviewedClaim: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: ReviewedClaimKind
    public let text: String
    public let applicability: String
    public let requirementClass: ReviewedClaimRequirementClass
    public let sourceIDs: [String]
    public let sourceLocators: [String]
    public let allowedNumericFacts: [AllowedNumericFact]

    public init(
        id: String,
        kind: ReviewedClaimKind,
        text: String,
        applicability: String = "",
        requirementClass: ReviewedClaimRequirementClass? = nil,
        sourceIDs: [String],
        sourceLocators: [String],
        allowedNumericFacts: [AllowedNumericFact] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.applicability = applicability
        let defaultRequirement: ReviewedClaimRequirementClass = switch kind {
        case .applicability: .context
        case .action: .immediateAction
        case .rationale: .rationale
        case .contraindication: .contraindication
        case .escalation: .escalation
        case .stopCondition: .stopCondition
        case .allowedNumber: .allowedNumber
        }
        self.requirementClass = requirementClass ?? defaultRequirement
        self.sourceIDs = sourceIDs
        self.sourceLocators = sourceLocators
        self.allowedNumericFacts = allowedNumericFacts
    }
}

public struct ExpertEvidenceLocator: Codable, Hashable, Sendable {
    public let documentID: String
    public let chunkID: String
    public let sectionPath: String
    public let locator: String

    public init(
        documentID: String, chunkID: String, sectionPath: String, locator: String
    ) {
        self.documentID = documentID
        self.chunkID = chunkID
        self.sectionPath = sectionPath
        self.locator = locator
    }
}

public struct EvidenceScenarioRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let lessonID: String
    public let chapterID: String
    public let title: String
    public let applicability: String
    public let observableCues: [String]
    public let prerequisites: [String]
    public let riskClass: ExpertRiskClass
    public let jurisdiction: String
    public let units: String
    public let relatedScenarioIDs: [String]
    public let claims: [ReviewedClaim]
    public let manualReference: ManualReference?
    public let evidenceLocator: ExpertEvidenceLocator?

    public init(
        id: String,
        lessonID: String,
        chapterID: String,
        title: String,
        applicability: String,
        observableCues: [String],
        prerequisites: [String],
        riskClass: ExpertRiskClass,
        jurisdiction: String,
        units: String,
        relatedScenarioIDs: [String],
        claims: [ReviewedClaim],
        manualReference: ManualReference? = nil,
        evidenceLocator: ExpertEvidenceLocator? = nil
    ) {
        self.id = id
        self.lessonID = lessonID
        self.chapterID = chapterID
        self.title = title
        self.applicability = applicability
        self.observableCues = observableCues
        self.prerequisites = prerequisites
        self.riskClass = riskClass
        self.jurisdiction = jurisdiction
        self.units = units
        self.relatedScenarioIDs = relatedScenarioIDs
        self.claims = claims
        self.manualReference = manualReference
        self.evidenceLocator = evidenceLocator
    }

    public var searchableText: String {
        ([title, applicability]
            + observableCues
            + prerequisites
            + claims.map(\.text))
            .joined(separator: " ")
    }

    public var actionClaims: [ReviewedClaim] {
        claims.filter { $0.kind == .action }
    }

    public var safetyClaims: [ReviewedClaim] {
        claims.filter {
            $0.kind == .contraindication || $0.kind == .escalation
                || $0.kind == .stopCondition
        }
    }
}

public struct RetrievedEvidenceScenario: Hashable, Sendable {
    public let scenario: EvidenceScenarioRecord
    public let preBoostScore: Double
    public let shadowCorpusBoost: Double
    public let linkedChunkIDs: [String]
    public let highestAuthorityTier: ExpertSourceAuthorityTier?
    public let promotionStatus: ExpertClaimPromotionStatus
    public let score: Double
    public let lexicalRank: Int?
    public let denseRank: Int?
    public let denseSimilarity: Double?
    public let fusedScore: Double
    public let meaningfulOverlapCount: Int
    public let appliedBoosts: [String]
    public let isEligible: Bool
    public let eligibilityReason: String
    public let exclusionReasons: [String]
    public var subjectConcepts: [String]
    public var operationConcepts: [String]
    public var hazardConcepts: [String]
    public var subjectAlignment: Int
    public var operationAlignment: Int
    public var coveredQueryConcepts: Int
    public var candidatePoolPosition: Int?
    public var promptTokenContribution: Int
    public var claimQualityStatus: String
    public var finalSelectionReason: String?

    public init(
        scenario: EvidenceScenarioRecord,
        score: Double,
        preBoostScore: Double? = nil,
        shadowCorpusBoost: Double = 0,
        linkedChunkIDs: [String] = [],
        highestAuthorityTier: ExpertSourceAuthorityTier? = nil,
        promotionStatus: ExpertClaimPromotionStatus = .humanApproved,
        lexicalRank: Int? = nil,
        denseRank: Int? = nil,
        denseSimilarity: Double? = nil,
        fusedScore: Double? = nil,
        meaningfulOverlapCount: Int = 0,
        appliedBoosts: [String] = [],
        isEligible: Bool = true,
        eligibilityReason: String = "legacy_eligible",
        exclusionReasons: [String] = [],
        subjectConcepts: [String] = [],
        operationConcepts: [String] = [],
        hazardConcepts: [String] = [],
        subjectAlignment: Int = 0,
        operationAlignment: Int = 0,
        coveredQueryConcepts: Int = 0,
        candidatePoolPosition: Int? = nil,
        promptTokenContribution: Int = 0,
        claimQualityStatus: String = "not_evaluated",
        finalSelectionReason: String? = nil
    ) {
        self.scenario = scenario
        self.preBoostScore = preBoostScore ?? score
        self.shadowCorpusBoost = shadowCorpusBoost
        self.linkedChunkIDs = linkedChunkIDs
        self.highestAuthorityTier = highestAuthorityTier
        self.promotionStatus = promotionStatus
        self.score = score
        self.lexicalRank = lexicalRank
        self.denseRank = denseRank
        self.denseSimilarity = denseSimilarity
        self.fusedScore = fusedScore ?? score
        self.meaningfulOverlapCount = meaningfulOverlapCount
        self.appliedBoosts = appliedBoosts
        self.isEligible = isEligible
        self.eligibilityReason = eligibilityReason
        self.exclusionReasons = exclusionReasons
        self.subjectConcepts = subjectConcepts
        self.operationConcepts = operationConcepts
        self.hazardConcepts = hazardConcepts
        self.subjectAlignment = subjectAlignment
        self.operationAlignment = operationAlignment
        self.coveredQueryConcepts = coveredQueryConcepts
        self.candidatePoolPosition = candidatePoolPosition
        self.promptTokenContribution = promptTokenContribution
        self.claimQualityStatus = claimQualityStatus
        self.finalSelectionReason = finalSelectionReason
    }
}

public struct EvidenceBundle: Hashable, Sendable {
    public let scenarios: [RetrievedEvidenceScenario]

    public init(scenarios: [RetrievedEvidenceScenario]) {
        self.scenarios = Array(scenarios.prefix(3))
    }

    public var claims: [ReviewedClaim] {
        scenarios.flatMap(\.scenario.claims)
    }

    public func scenario(forClaimIndex index: Int) -> RetrievedEvidenceScenario? {
        guard index > 0 else { return nil }
        var offset = 0
        for scenario in scenarios {
            let next = offset + scenario.scenario.claims.count
            if index <= next { return scenario }
            offset = next
        }
        return nil
    }

    public var allowedNumericFacts: [AllowedNumericFact] {
        claims.flatMap(\.allowedNumericFacts)
    }
}

public protocol ExpertEvidenceRetrieving: Sendable {
    func searchExpertEvidence(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedEvidenceScenario]

    func searchExpertCorpus(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [ExpertCorpusCandidate]

    func expertScenario(id: String) -> EvidenceScenarioRecord?

    func expertSources(ids: [String]) -> [SurvivalSource]
}

public protocol ExpertCorpusReading: Sendable {
    func expertSourceDocuments() -> [ExpertSourceDocument]
    func expertClaimPromotions() -> [ExpertClaimPromotionRecord]
}

public extension ExpertEvidenceRetrieving {
    func searchExpertCorpus(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [ExpertCorpusCandidate] { [] }

    func expertScenario(id: String) -> EvidenceScenarioRecord? { nil }

    func expertSources(ids: [String]) -> [SurvivalSource] { [] }
}

public struct ArticleBackedExpertEvidenceRetriever: ExpertEvidenceRetrieving {
    private let retrieval: any EvidenceRetrieving

    public init(retrieval: any EvidenceRetrieving) {
        self.retrieval = retrieval
    }

    public func searchExpertEvidence(
        query: String,
        domain: KnowledgeDomain?,
        limit: Int
    ) -> [RetrievedEvidenceScenario] {
        retrieval.search(query: query, domain: domain, limit: limit).map {
            passage in
            let article = passage.article
            let sourceIDs = [article.source.id]
            let sourceLocators = [article.source.title]
            var claims = [ReviewedClaim(
                id: "\(article.id)-applicability",
                kind: .applicability,
                text: article.summary,
                sourceIDs: sourceIDs,
                sourceLocators: sourceLocators
            )]
            claims += article.steps.enumerated().map { index, text in
                ReviewedClaim(
                    id: "\(article.id)-action-\(index + 1)",
                    kind: .action,
                    text: text,
                    sourceIDs: sourceIDs,
                    sourceLocators: sourceLocators,
                    allowedNumericFacts: Self.numericFacts(
                        in: text,
                        claimID: "\(article.id)-action-\(index + 1)"
                    )
                )
            }
            claims += article.warnings.enumerated().map { index, text in
                ReviewedClaim(
                    id: "\(article.id)-warning-\(index + 1)",
                    kind: .contraindication,
                    text: text,
                    sourceIDs: sourceIDs,
                    sourceLocators: sourceLocators,
                    allowedNumericFacts: Self.numericFacts(
                        in: text,
                        claimID: "\(article.id)-warning-\(index + 1)"
                    )
                )
            }
            let reference = article.manualReference ?? ManualReference(
                passageID: article.id,
                lessonID: article.id,
                chapterID: article.domain.rawValue,
                chapterNumber: 0,
                chapterTitle: article.domain.displayName,
                sectionTitle: article.title,
                sourceLabel: article.source.title
            )
            return RetrievedEvidenceScenario(
                scenario: EvidenceScenarioRecord(
                    id: "\(reference.lessonID)-scenario",
                    lessonID: reference.lessonID,
                    chapterID: reference.chapterID,
                    title: article.title,
                    applicability: article.summary,
                    observableCues: article.keywords,
                    prerequisites: [],
                    riskClass: .high,
                    jurisdiction: "global",
                    units: "dual",
                    relatedScenarioIDs: [],
                    claims: claims,
                    manualReference: reference
                ),
                score: passage.score
            )
        }
    }

    private static func numericFacts(
        in text: String,
        claimID: String
    ) -> [AllowedNumericFact] {
        let pattern = #"\b\d+(?:[,.]\d+)*(?:%|°|[a-zA-Z]+)?\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }
            return AllowedNumericFact(
                token: String(text[matchRange]).lowercased(),
                sourceClaimID: claimID
            )
        }
    }
}
