import Foundation

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
