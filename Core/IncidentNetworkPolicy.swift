import Foundation

public enum NetworkOperation: String, Codable, Sendable {
    case emergencyContact
    case packageCatalog
    case packageDownload
    case purchase
    case entitlementRefresh
    case telemetry
    case modelInference
    case knowledgeRetrieval
    case mapUse
}

public struct IncidentNetworkPolicy: Sendable {
    public let incidentModeEnabled: Bool

    public init(incidentModeEnabled: Bool) {
        self.incidentModeEnabled = incidentModeEnabled
    }

    public func permits(_ operation: NetworkOperation) -> Bool {
        guard incidentModeEnabled else { return true }
        switch operation {
        case .emergencyContact:
            return true
        case .modelInference, .knowledgeRetrieval, .mapUse:
            return true
        case .packageCatalog, .packageDownload, .purchase,
             .entitlementRefresh, .telemetry:
            return false
        }
    }
}

public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public let productID: String
    public let verified: Bool
    public let verifiedAt: String
}

public struct OfflineEntitlementResolver: Sendable {
    public init() {}

    /// An installed package remains launchable offline only when a previously
    /// verified entitlement is cached. No new entitlement is inferred.
    public func canLaunch(
        productID: String?,
        packageIsInstalled: Bool,
        cachedEntitlements: [EntitlementSnapshot]
    ) -> Bool {
        guard packageIsInstalled else { return false }
        guard let productID else { return true }
        return cachedEntitlements.contains {
            $0.productID == productID && $0.verified
        }
    }
}
