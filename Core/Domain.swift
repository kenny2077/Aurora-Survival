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
    public let vehicleApplicability: VehicleApplicability?

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
        vehicleApplicability: VehicleApplicability? = nil
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
        self.vehicleApplicability = vehicleApplicability
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

public enum ModelTier: String, Codable, CaseIterable, Sendable {
    case essential
    case field
    case visionExpert = "vision_expert"

    public var displayName: String {
        switch self {
        case .essential: return "Essential"
        case .field: return "Field"
        case .visionExpert: return "Vision Expert"
        }
    }

    public var supportsVision: Bool { self == .visionExpert }
}

public enum ThermalCondition: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public struct DeviceSnapshot: Equatable, Sendable {
    public let physicalMemoryBytes: UInt64
    public let freeStorageBytes: Int64
    public let thermalCondition: ThermalCondition
    public let isLowPowerMode: Bool

    public init(
        physicalMemoryBytes: UInt64,
        freeStorageBytes: Int64,
        thermalCondition: ThermalCondition,
        isLowPowerMode: Bool
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.freeStorageBytes = freeStorageBytes
        self.thermalCondition = thermalCondition
        self.isLowPowerMode = isLowPowerMode
    }
}

public struct ModelRoutingDecision: Equatable, Sendable {
    public let requested: ModelTier
    public let selected: ModelTier
    public let canAnalyzeImage: Bool
    public let explanation: String

    public init(
        requested: ModelTier,
        selected: ModelTier,
        canAnalyzeImage: Bool,
        explanation: String
    ) {
        self.requested = requested
        self.selected = selected
        self.canAnalyzeImage = canAnalyzeImage
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
    public let vehicleProfile: VehicleProfile?

    public init(
        question: String,
        domain: KnowledgeDomain? = nil,
        preferredTier: ModelTier = .field,
        hasImage: Bool = false,
        imageData: Data? = nil,
        imageObservations: [String] = [],
        vehicleProfile: VehicleProfile? = nil
    ) {
        self.question = question
        self.domain = domain
        self.preferredTier = preferredTier
        self.hasImage = hasImage
        self.imageData = imageData
        self.imageObservations = imageObservations
        self.vehicleProfile = vehicleProfile
    }
}

public struct SafetyDirective: Equatable, Sendable {
    public let severity: IncidentSeverity
    public let title: String
    public let immediateActions: [String]
    public let prohibitedActions: [String]
    public let rationale: String

    public init(
        severity: IncidentSeverity,
        title: String,
        immediateActions: [String],
        prohibitedActions: [String],
        rationale: String
    ) {
        self.severity = severity
        self.title = title
        self.immediateActions = immediateActions
        self.prohibitedActions = prohibitedActions
        self.rationale = rationale
    }
}

public struct AssistantAnswer: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let severity: IncidentSeverity
    public let sources: [SourceReference]
    public let modelTier: ModelTier?
    public let usedDeterministicOverride: Bool
    public let visionWasUsed: Bool
    public let notices: [String]

    public init(
        id: UUID = UUID(),
        text: String,
        severity: IncidentSeverity,
        sources: [SourceReference],
        modelTier: ModelTier?,
        usedDeterministicOverride: Bool,
        visionWasUsed: Bool,
        notices: [String]
    ) {
        self.id = id
        self.text = text
        self.severity = severity
        self.sources = sources
        self.modelTier = modelTier
        self.usedDeterministicOverride = usedDeterministicOverride
        self.visionWasUsed = visionWasUsed
        self.notices = notices
    }
}
