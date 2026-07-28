import Foundation

public struct ModelRouter: Sendable {
    public static let minimumVisionMemory: UInt64 = 7_500_000_000
    public static let minimumVisionStorage: Int64 = 3_500_000_000
    public static let minimumFieldMemory: UInt64 = 5_000_000_000
    public static let minimumLiteMemory: UInt64 = 3_500_000_000

    public init() {}

    public func route(
        requested: ModelTier,
        installed: Set<ModelTier>,
        device: DeviceSnapshot
    ) -> ModelRoutingDecision {
        let fallback = bestAvailableTextTier(
            installed: installed,
            device: device
        )

        guard installed.contains(requested) else {
            return ModelRoutingDecision(
                requested: requested,
                selected: fallback,
                canAnalyzeImage: false,
                explanation: "\(requested.displayName) is not installed; using the best available text tier."
            )
        }

        let reasons = ineligibilityReasons(
            for: requested,
            device: device
        )
        guard reasons.isEmpty else {
            let prefix = requested == .visionExpert
                ? "Vision"
                : requested.displayName
            return ModelRoutingDecision(
                requested: requested,
                selected: fallback,
                canAnalyzeImage: false,
                explanation: "\(prefix) paused because of \(reasons.joined(separator: ", ")); using \(fallback.displayName)."
            )
        }

        return ModelRoutingDecision(
            requested: requested,
            selected: requested,
            canAnalyzeImage: requested.supportsVision,
            explanation: "\(requested.displayName) is available for this incident."
        )
    }

    private func bestAvailableTextTier(
        installed: Set<ModelTier>,
        device: DeviceSnapshot
    ) -> ModelTier {
        for tier in [ModelTier.field, .lite] {
            if installed.contains(tier),
               ineligibilityReasons(for: tier, device: device).isEmpty {
                return tier
            }
        }
        return .essential
    }

    private func ineligibilityReasons(
        for tier: ModelTier,
        device: DeviceSnapshot
    ) -> [String] {
        guard tier != .essential else { return [] }

        var reasons: [String] = []
        let minimumMemory: UInt64
        switch tier {
        case .essential:
            minimumMemory = 0
        case .lite:
            minimumMemory = Self.minimumLiteMemory
        case .field:
            minimumMemory = Self.minimumFieldMemory
        case .visionExpert:
            minimumMemory = Self.minimumVisionMemory
        }
        if device.physicalMemoryBytes < minimumMemory {
            reasons.append("memory")
        }
        if tier == .visionExpert,
           device.freeStorageBytes < Self.minimumVisionStorage {
            reasons.append("free storage")
        }
        if device.thermalCondition != .nominal
            && device.thermalCondition != .fair {
            reasons.append("thermal state")
        }
        if device.isLowPowerMode {
            reasons.append("Low Power Mode")
        }
        return reasons
    }
}
