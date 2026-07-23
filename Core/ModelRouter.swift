import Foundation

public struct ModelRouter: Sendable {
    public static let minimumVisionMemory: UInt64 = 7_500_000_000
    public static let minimumVisionStorage: Int64 = 3_500_000_000
    public static let minimumFieldMemory: UInt64 = 5_000_000_000

    public init() {}

    public func route(
        requested: ModelTier,
        installed: Set<ModelTier>,
        device: DeviceSnapshot
    ) -> ModelRoutingDecision {
        let fallback = installed.contains(.field) && device.physicalMemoryBytes >= Self.minimumFieldMemory
            ? ModelTier.field
            : .essential

        guard installed.contains(requested) else {
            return ModelRoutingDecision(
                requested: requested,
                selected: installed.contains(fallback) ? fallback : .essential,
                canAnalyzeImage: false,
                explanation: "\(requested.displayName) is not installed; using the best available text tier."
            )
        }

        if requested == .visionExpert {
            let thermalOK = device.thermalCondition == .nominal || device.thermalCondition == .fair
            let eligible = device.physicalMemoryBytes >= Self.minimumVisionMemory
                && device.freeStorageBytes >= Self.minimumVisionStorage
                && thermalOK
                && !device.isLowPowerMode

            guard eligible else {
                let reasons = [
                    device.physicalMemoryBytes < Self.minimumVisionMemory ? "memory" : nil,
                    device.freeStorageBytes < Self.minimumVisionStorage ? "free storage" : nil,
                    !thermalOK ? "thermal state" : nil,
                    device.isLowPowerMode ? "Low Power Mode" : nil
                ].compactMap { $0 }
                return ModelRoutingDecision(
                    requested: requested,
                    selected: installed.contains(fallback) ? fallback : .essential,
                    canAnalyzeImage: false,
                    explanation: "Vision paused because of \(reasons.joined(separator: ", ")); using text plus OCR."
                )
            }
        }

        return ModelRoutingDecision(
            requested: requested,
            selected: requested,
            canAnalyzeImage: requested.supportsVision,
            explanation: "\(requested.displayName) is available for this incident."
        )
    }
}
