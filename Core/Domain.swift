import Foundation

public enum KnowledgeDomain: String, Codable, CaseIterable, Sendable {
    case vehicle
    case wilderness
    case firstAid = "first_aid"
    case navigation

    public var displayName: String {
        switch self {
        case .vehicle: return "Vehicle"
        case .wilderness: return "Wilderness"
        case .firstAid: return "First Aid"
        case .navigation: return "Navigation"
        }
    }
}

public enum IncidentSeverity: Int, Codable, Comparable, Sendable {
    case informational = 0
    case caution = 1
    case urgent = 2
    case critical = 3

    public static func < (lhs: IncidentSeverity, rhs: IncidentSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SourceReference: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let organization: String
    public let revision: String
    public let url: String?

    public init(
        id: String,
        title: String,
        organization: String,
        revision: String,
        url: String? = nil
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.revision = revision
        self.url = url
    }
}

public struct KnowledgeArticle: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let domain: KnowledgeDomain
    public let title: String
    public let summary: String
    public let steps: [String]
    public let warnings: [String]
    public let keywords: [String]
    public let source: SourceReference
    public let reviewed: Bool
    public let manualReference: ManualReference?

    public init(
        id: String,
        domain: KnowledgeDomain,
        title: String,
        summary: String,
        steps: [String],
        warnings: [String],
        keywords: [String],
        source: SourceReference,
        reviewed: Bool,
        manualReference: ManualReference? = nil
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.summary = summary
        self.steps = steps
        self.warnings = warnings
        self.keywords = keywords
        self.source = source
        self.reviewed = reviewed
        self.manualReference = manualReference
    }

    public var searchableText: String {
        ([title, summary] + steps + warnings + keywords).joined(separator: " ")
    }
}

public struct RetrievedPassage: Hashable, Sendable {
    public let article: KnowledgeArticle
    public let score: Double

    public init(article: KnowledgeArticle, score: Double) {
        self.article = article
        self.score = score
    }
}

public struct ManualReference: Codable, Hashable, Sendable, Identifiable {
    public let passageID: String
    public let lessonID: String
    public let chapterID: String
    public let chapterNumber: Int
    public let chapterTitle: String
    public let sectionTitle: String
    public let sourceLabel: String

    public var id: String { passageID }
    public var chunkID: String { passageID }
    public var pageStart: Int { 0 }
    public var pageEnd: Int { 0 }

    public init(
        passageID: String,
        lessonID: String,
        chapterID: String,
        chapterNumber: Int,
        chapterTitle: String,
        sectionTitle: String,
        sourceLabel: String
    ) {
        self.passageID = passageID
        self.lessonID = lessonID
        self.chapterID = chapterID
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.sectionTitle = sectionTitle
        self.sourceLabel = sourceLabel
    }

    /// Compatibility initializer for pre-overhaul corpus anchors.
    public init(
        chunkID: String,
        chapterNumber: Int,
        chapterTitle: String,
        sectionTitle: String,
        pageStart: Int,
        pageEnd: Int
    ) {
        passageID = chunkID
        lessonID = ""
        chapterID = ""
        self.chapterNumber = chapterNumber
        self.chapterTitle = chapterTitle
        self.sectionTitle = sectionTitle
        sourceLabel = pageStart == pageEnd
            ? "Legacy page \(pageStart)"
            : "Legacy pages \(pageStart)–\(pageEnd)"
    }

    public var pageLabel: String { sourceLabel }

    private enum CodingKeys: String, CodingKey {
        case passageID
        case chunkID
        case lessonID
        case chapterID
        case chapterNumber
        case chapterTitle
        case sectionTitle
        case sourceLabel
        case pageStart
        case pageEnd
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        passageID = try values.decodeIfPresent(String.self, forKey: .passageID)
            ?? values.decode(String.self, forKey: .chunkID)
        lessonID = try values.decodeIfPresent(String.self, forKey: .lessonID) ?? ""
        chapterID = try values.decodeIfPresent(String.self, forKey: .chapterID) ?? ""
        chapterNumber = try values.decode(Int.self, forKey: .chapterNumber)
        chapterTitle = try values.decode(String.self, forKey: .chapterTitle)
        sectionTitle = try values.decode(String.self, forKey: .sectionTitle)
        if let label = try values.decodeIfPresent(String.self, forKey: .sourceLabel) {
            sourceLabel = label
        } else {
            let start = try values.decodeIfPresent(Int.self, forKey: .pageStart) ?? 0
            let end = try values.decodeIfPresent(Int.self, forKey: .pageEnd) ?? start
            sourceLabel = start == end ? "Legacy page \(start)" : "Legacy pages \(start)–\(end)"
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(passageID, forKey: .passageID)
        try values.encode(passageID, forKey: .chunkID)
        try values.encode(lessonID, forKey: .lessonID)
        try values.encode(chapterID, forKey: .chapterID)
        try values.encode(chapterNumber, forKey: .chapterNumber)
        try values.encode(chapterTitle, forKey: .chapterTitle)
        try values.encode(sectionTitle, forKey: .sectionTitle)
        try values.encode(sourceLabel, forKey: .sourceLabel)
    }
}

public enum ModelTier: String, Codable, CaseIterable, Sendable {
    case lite
    case expert = "vision_expert"

    public var displayName: String {
        switch self {
        case .lite: return "Lite"
        case .expert: return "Expert"
        }
    }

    public var supportsVision: Bool { self == .expert }
}

public enum ModelSelectionPreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case lite
    case expert

    public var displayName: String {
        switch self {
        case .automatic: return "Auto"
        case .lite: return "Lite"
        case .expert: return "Expert"
        }
    }

    public var requestedTier: ModelTier? {
        switch self {
        case .automatic: return nil
        case .lite: return .lite
        case .expert: return .expert
        }
    }
}

public enum ModelAvailability: String, Codable, Sendable {
    case ready
    case missing
    case temporarilyIneligible = "temporarily_ineligible"
    case validationLocked = "validation_locked"
}

public enum ThermalCondition: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct DeviceSnapshot: Equatable, Sendable {
    public let physicalMemoryBytes: UInt64
    public let availableMemoryBytes: UInt64?
    public let freeStorageBytes: Int64
    public let thermalCondition: ThermalCondition
    public let isLowPowerMode: Bool

    public init(
        physicalMemoryBytes: UInt64,
        availableMemoryBytes: UInt64? = nil,
        freeStorageBytes: Int64,
        thermalCondition: ThermalCondition,
        isLowPowerMode: Bool
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.availableMemoryBytes = availableMemoryBytes
        self.freeStorageBytes = freeStorageBytes
        self.thermalCondition = thermalCondition
        self.isLowPowerMode = isLowPowerMode
    }
}

public struct ModelRoutingDecision: Equatable, Sendable {
    public let requested: ModelTier?
    public let selected: ModelTier?
    public let canAnalyzeImage: Bool
    public let availability: ModelAvailability
    public let explanation: String

    public init(
        requested: ModelTier?,
        selected: ModelTier?,
        canAnalyzeImage: Bool,
        availability: ModelAvailability,
        explanation: String
    ) {
        self.requested = requested
        self.selected = selected
        self.canAnalyzeImage = canAnalyzeImage
        self.availability = availability
        self.explanation = explanation
    }
}

public struct ChatRequest: Equatable, Sendable {
    public let question: String
    public let domain: KnowledgeDomain?
    public let preferredTier: ModelTier
    public let hasImage: Bool
    public let imageData: Data?
    public let imageObservations: [String]
    public let conversationHistory: [ConversationTurn]

    public init(
        question: String,
        domain: KnowledgeDomain? = nil,
        preferredTier: ModelTier = .lite,
        hasImage: Bool = false,
        imageData: Data? = nil,
        imageObservations: [String] = [],
        conversationHistory: [ConversationTurn] = []
    ) {
        self.question = question
        self.domain = domain
        self.preferredTier = preferredTier
        self.hasImage = hasImage
        self.imageData = imageData
        self.imageObservations = imageObservations
        self.conversationHistory = conversationHistory
    }
}

public struct ConversationTurn: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let text: String
    public let evidenceIDs: [String]

    public init(
        role: Role,
        text: String,
        evidenceIDs: [String] = []
    ) {
        self.role = role
        self.text = text
        self.evidenceIDs = evidenceIDs
    }
}

public enum AnswerSupportStatus: String, Codable, Equatable, Sendable {
    case supported
    case partiallySupported = "partially_supported"
    case unsupported
}

public enum AnswerCoverageStatus: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case insufficient
}

public struct AnswerSentenceCitation: Codable, Equatable, Hashable, Sendable,
    Identifiable {
    public let sentence: Int
    public let sourceIDs: [String]

    public var id: String { "\(sentence):\(sourceIDs.joined(separator: ","))" }

    public init(sentence: Int, sourceIDs: [String]) {
        self.sentence = sentence
        self.sourceIDs = sourceIDs
    }
}

public struct AnswerSourceCard: Codable, Equatable, Hashable, Sendable,
    Identifiable {
    public let id: String
    public let title: String
    public let organization: String?
    public let url: String?
    public let locator: String
    public let publishedAt: String
    public let updatedAt: String
    public let reviewedAt: String
    public let jurisdiction: String
    public let reviewStatus: String

    public init(
        id: String,
        title: String,
        organization: String? = nil,
        url: String?,
        locator: String,
        publishedAt: String,
        updatedAt: String,
        reviewedAt: String,
        jurisdiction: String,
        reviewStatus: String
    ) {
        self.id = id
        self.title = title
        self.organization = organization
        self.url = url
        self.locator = locator
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.reviewedAt = reviewedAt
        self.jurisdiction = jurisdiction
        self.reviewStatus = reviewStatus
    }
}

public struct AssistantAnswer: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let severity: IncidentSeverity
    public let sources: [SourceReference]
    public let manualReferences: [ManualReference]
    public let modelTier: ModelTier?
    public let visionWasUsed: Bool
    public let notices: [String]
    public let verificationStatus: AnswerVerificationStatus?
    public let verificationIssues: [AnswerVerificationIssue]
    public let retrievalWasDegraded: Bool
    public let corroboratingSourceCount: Int
    public let supportStatus: AnswerSupportStatus?
    public let coverageStatus: AnswerCoverageStatus?
    public let sentenceCitations: [AnswerSentenceCitation]
    public let sourceCards: [AnswerSourceCard]
    public let evidenceIDs: [String]
    public let expertIntent: ExpertTurnIntent?
    public let expertRetrievalStatus: ExpertRetrievalStatus?

    public init(
        id: UUID = UUID(),
        text: String,
        severity: IncidentSeverity,
        sources: [SourceReference],
        manualReferences: [ManualReference] = [],
        modelTier: ModelTier?,
        visionWasUsed: Bool,
        notices: [String],
        verificationStatus: AnswerVerificationStatus? = nil,
        verificationIssues: [AnswerVerificationIssue] = [],
        retrievalWasDegraded: Bool = false,
        corroboratingSourceCount: Int = 0,
        supportStatus: AnswerSupportStatus? = nil,
        coverageStatus: AnswerCoverageStatus? = nil,
        sentenceCitations: [AnswerSentenceCitation] = [],
        sourceCards: [AnswerSourceCard] = [],
        evidenceIDs: [String] = [],
        expertIntent: ExpertTurnIntent? = nil,
        expertRetrievalStatus: ExpertRetrievalStatus? = nil
    ) {
        self.id = id
        self.text = text
        self.severity = severity
        self.sources = sources
        self.manualReferences = manualReferences
        self.modelTier = modelTier
        self.visionWasUsed = visionWasUsed
        self.notices = notices
        self.verificationStatus = verificationStatus
        self.verificationIssues = verificationIssues
        self.retrievalWasDegraded = retrievalWasDegraded
        self.corroboratingSourceCount = corroboratingSourceCount
        self.supportStatus = supportStatus
        self.coverageStatus = coverageStatus
        self.sentenceCitations = sentenceCitations
        self.sourceCards = sourceCards
        self.evidenceIDs = evidenceIDs
        self.expertIntent = expertIntent
        self.expertRetrievalStatus = expertRetrievalStatus
    }
}

public enum ExpertRetrievalStatus: String, Codable, Equatable, Sendable {
    case acceptedEvidence = "accepted_evidence"
    case noRelevantEvidence = "no_relevant_evidence"
}

public enum AnswerVerificationStatus: String, Codable, Equatable, Sendable {
    case verified
    case partiallyVerified = "partially_verified"
    case unverified

    public var displayName: String {
        switch self {
        case .verified: return "Verified against reviewed guidance"
        case .partiallyVerified: return "Partially verified"
        case .unverified: return "Unverified model draft"
        }
    }
}

public struct AnswerVerificationIssue: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let sentence: Int?
    public let code: String
    public let message: String

    public var id: String { "\(sentence ?? 0):\(code):\(message)" }

    public init(sentence: Int? = nil, code: String, message: String) {
        self.sentence = sentence
        self.code = code
        self.message = message
    }
}
