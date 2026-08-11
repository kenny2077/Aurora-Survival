import Foundation

public struct ModelBenchmarkMetrics: Codable, Equatable, Sendable {
    public let firstTokenMilliseconds: Int
    public let tokensPerSecond: Double
    public let peakMemoryBytes: UInt64
    public let endingThermalCondition: ThermalCondition
    public let batteryPercentConsumed: Double

    public init(
        firstTokenMilliseconds: Int,
        tokensPerSecond: Double,
        peakMemoryBytes: UInt64,
        endingThermalCondition: ThermalCondition,
        batteryPercentConsumed: Double
    ) {
        self.firstTokenMilliseconds = firstTokenMilliseconds
        self.tokensPerSecond = tokensPerSecond
        self.peakMemoryBytes = peakMemoryBytes
        self.endingThermalCondition = endingThermalCondition
        self.batteryPercentConsumed = batteryPercentConsumed
    }
}

public struct ModelAcceptanceThresholds: Codable, Equatable, Sendable {
    public let maximumFirstTokenMilliseconds: Int
    public let minimumTokensPerSecond: Double
    public let maximumPeakMemoryBytes: UInt64
    public let maximumBatteryPercentConsumed: Double

    public init(
        maximumFirstTokenMilliseconds: Int,
        minimumTokensPerSecond: Double,
        maximumPeakMemoryBytes: UInt64,
        maximumBatteryPercentConsumed: Double
    ) {
        self.maximumFirstTokenMilliseconds = maximumFirstTokenMilliseconds
        self.minimumTokensPerSecond = minimumTokensPerSecond
        self.maximumPeakMemoryBytes = maximumPeakMemoryBytes
        self.maximumBatteryPercentConsumed = maximumBatteryPercentConsumed
    }
}

public enum ModelAcceptanceIssue: String, Codable, Hashable, Sendable {
    case firstTokenTooSlow
    case generationTooSlow
    case memoryTooHigh
    case thermalLimitExceeded
    case batteryUseTooHigh
}

public struct ModelAcceptanceEvaluator: Sendable {
    public init() {}

    public func evaluate(
        metrics: ModelBenchmarkMetrics,
        thresholds: ModelAcceptanceThresholds
    ) -> [ModelAcceptanceIssue] {
        var issues: [ModelAcceptanceIssue] = []
        if metrics.firstTokenMilliseconds > thresholds.maximumFirstTokenMilliseconds {
            issues.append(.firstTokenTooSlow)
        }
        if metrics.tokensPerSecond < thresholds.minimumTokensPerSecond {
            issues.append(.generationTooSlow)
        }
        if metrics.peakMemoryBytes > thresholds.maximumPeakMemoryBytes {
            issues.append(.memoryTooHigh)
        }
        if [.serious, .critical].contains(metrics.endingThermalCondition) {
            issues.append(.thermalLimitExceeded)
        }
        if metrics.batteryPercentConsumed > thresholds.maximumBatteryPercentConsumed {
            issues.append(.batteryUseTooHigh)
        }
        return issues
    }
}

public struct AccessibilityAuditSnapshot: Codable, Equatable, Sendable {
    public let emergencyControlsHaveLabels: Bool
    public let supportsLargestDynamicType: Bool
    public let logicalVoiceOverOrder: Bool
    public let meaningDoesNotDependOnColor: Bool
    public let motionCanBeReduced: Bool

    public init(
        emergencyControlsHaveLabels: Bool,
        supportsLargestDynamicType: Bool,
        logicalVoiceOverOrder: Bool,
        meaningDoesNotDependOnColor: Bool,
        motionCanBeReduced: Bool
    ) {
        self.emergencyControlsHaveLabels = emergencyControlsHaveLabels
        self.supportsLargestDynamicType = supportsLargestDynamicType
        self.logicalVoiceOverOrder = logicalVoiceOverOrder
        self.meaningDoesNotDependOnColor = meaningDoesNotDependOnColor
        self.motionCanBeReduced = motionCanBeReduced
    }

    public var passesAutomatedContract: Bool {
        emergencyControlsHaveLabels
            && supportsLargestDynamicType
            && logicalVoiceOverOrder
            && meaningDoesNotDependOnColor
            && motionCanBeReduced
    }
}

public struct VirtualReleaseScenario: Codable, Equatable, Sendable {
    public let survivalCorpusIsReady: Bool
    public let bundledCoreRecovers: Bool
    public let installedMapIsReady: Bool
    public let installedEntitlementsWorkOffline: Bool
    public let accessibility: AccessibilityAuditSnapshot
    public let incidentModeNetworkIsContained: Bool

    public init(
        survivalCorpusIsReady: Bool,
        bundledCoreRecovers: Bool,
        installedMapIsReady: Bool,
        installedEntitlementsWorkOffline: Bool,
        accessibility: AccessibilityAuditSnapshot,
        incidentModeNetworkIsContained: Bool
    ) {
        self.survivalCorpusIsReady = survivalCorpusIsReady
        self.bundledCoreRecovers = bundledCoreRecovers
        self.installedMapIsReady = installedMapIsReady
        self.installedEntitlementsWorkOffline = installedEntitlementsWorkOffline
        self.accessibility = accessibility
        self.incidentModeNetworkIsContained = incidentModeNetworkIsContained
    }
}

public enum VirtualReleaseIssue: String, Codable, Hashable, Sendable {
    case survivalCorpusUnavailable
    case emergencyCoreUnavailable
    case mapUnavailable
    case offlineEntitlementFailure
    case accessibilityContractFailure
    case incidentNetworkLeak
}

public struct VirtualReleaseEvaluator: Sendable {
    public init() {}

    public func evaluate(_ scenario: VirtualReleaseScenario) -> [VirtualReleaseIssue] {
        var issues: [VirtualReleaseIssue] = []
        if !scenario.survivalCorpusIsReady {
            issues.append(.survivalCorpusUnavailable)
        }
        if !scenario.bundledCoreRecovers { issues.append(.emergencyCoreUnavailable) }
        if !scenario.installedMapIsReady { issues.append(.mapUnavailable) }
        if !scenario.installedEntitlementsWorkOffline {
            issues.append(.offlineEntitlementFailure)
        }
        if !scenario.accessibility.passesAutomatedContract {
            issues.append(.accessibilityContractFailure)
        }
        if !scenario.incidentModeNetworkIsContained {
            issues.append(.incidentNetworkLeak)
        }
        return issues
    }
}
