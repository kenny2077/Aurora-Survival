import Foundation

public struct ModelRouter: Sendable {
    public static let minimumExpertMemory: UInt64 = 7_500_000_000
    public static let minimumExpertStorage: Int64 = 3_500_000_000
    public static let minimumLiteMemory: UInt64 = 3_500_000_000

    public init() {}

    public func route(
        preference: ModelSelectionPreference,
        installed: Set<ModelTier>,
        expertValidated: Bool = false,
        device: DeviceSnapshot
    ) -> ModelRoutingDecision {
        let requested = preference.requestedTier
        let liteIsEligible = installed.contains(.lite)
            && ineligibilityReasons(for: .lite, device: device).isEmpty
        let expertReasons = ineligibilityReasons(for: .expert, device: device)
        let expertIsEligible = expertValidated
            && installed.contains(.expert)
            && expertReasons.isEmpty

        if requested == .expert && !expertValidated {
            return ModelRoutingDecision(
                requested: .expert,
                selected: liteIsEligible ? .lite : nil,
                canAnalyzeImage: false,
                availability: .validationLocked,
                explanation: liteIsEligible
                    ? "Expert validation is pending; using Lite."
                    : "Expert validation is pending. Install Lite to use Ask."
            )
        }

        let selected: ModelTier?
        switch preference {
        case .automatic:
            selected = expertIsEligible ? .expert : (liteIsEligible ? .lite : nil)
        case .lite:
            selected = liteIsEligible ? .lite : nil
        case .expert:
            selected = expertIsEligible ? .expert : (liteIsEligible ? .lite : nil)
        }

        if let selected {
            return ModelRoutingDecision(
                requested: requested,
                selected: selected,
                canAnalyzeImage: selected.supportsVision,
                availability: .ready,
                explanation: explanation(
                    preference: preference,
                    selected: selected
                )
            )
        }

        let requestedReasons = requested.map {
            ineligibilityReasons(for: $0, device: device)
        } ?? []
        return ModelRoutingDecision(
            requested: requested,
            selected: nil,
            canAnalyzeImage: false,
            availability: requestedReasons.isEmpty ? .missing : .temporarilyIneligible,
            explanation: requestedReasons.isEmpty
                ? "Install Lite in Tools to use Ask."
                : "The selected model is paused because of \(requestedReasons.joined(separator: ", "))."
        )
    }

    public func route(
        requested: ModelTier,
        installed: Set<ModelTier>,
        expertValidated: Bool = false,
        device: DeviceSnapshot
    ) -> ModelRoutingDecision {
        route(
            preference: requested == .lite ? .lite : .expert,
            installed: installed,
            expertValidated: expertValidated,
            device: device
        )
    }

    private func explanation(
        preference: ModelSelectionPreference,
        selected: ModelTier
    ) -> String {
        if preference == .automatic {
            return "Auto selected \(selected.displayName) for this device."
        }
        if preference.requestedTier != selected {
            return "The preferred tier is unavailable; using \(selected.displayName)."
        }
        return "\(selected.displayName) is ready offline."
    }

    private func ineligibilityReasons(
        for tier: ModelTier,
        device: DeviceSnapshot
    ) -> [String] {
        var reasons: [String] = []
        let minimumMemory: UInt64
        switch tier {
        case .lite:
            minimumMemory = Self.minimumLiteMemory
        case .expert:
            minimumMemory = Self.minimumExpertMemory
        }
        if device.physicalMemoryBytes < minimumMemory {
            reasons.append("memory")
        }
        if tier == .expert,
           device.freeStorageBytes < Self.minimumExpertStorage {
            reasons.append("free storage")
        }
        if tier == .expert {
            if device.thermalCondition != .nominal
                && device.thermalCondition != .fair {
                reasons.append("thermal state")
            }
            if device.isLowPowerMode {
                reasons.append("Low Power Mode")
            }
        }
        return reasons
    }
}
