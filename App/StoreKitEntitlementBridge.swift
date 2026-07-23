import Foundation
import StoreKit
import SwiftUI

enum StoreKitEntitlementBridgeError: Error {
    case verificationFailed
}

@MainActor
final class StoreKitEntitlementBridge: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var lastError: String?

    func loadProducts(productIDs: Set<String>) async {
        do {
            products = try await Product.products(for: productIDs)
                .sorted { $0.displayName < $1.displayName }
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    @discardableResult
    func purchase(
        _ product: Product,
        ledger: EntitlementLedger
    ) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verified(verification)
            try await apply(
                transaction: transaction,
                kind: transaction.revocationDate == nil
                    ? .purchased
                    : .revoked,
                ledger: ledger
            )
            await transaction.finish()
            return transaction.revocationDate == nil
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restore(ledger: EntitlementLedger) async throws {
        try await AppStore.sync()
        try await refreshCurrentEntitlements(ledger: ledger)
    }

    func refreshCurrentEntitlements(
        ledger: EntitlementLedger
    ) async throws {
        for await verification in StoreKit.Transaction.currentEntitlements {
            let transaction = try verified(verification)
            try await apply(
                transaction: transaction,
                kind: transaction.revocationDate == nil
                    ? .restored
                    : .revoked,
                ledger: ledger
            )
        }
    }

    private func verified<T>(
        _ result: VerificationResult<T>
    ) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreKitEntitlementBridgeError.verificationFailed
        }
    }

    private func apply(
        transaction: StoreKit.Transaction,
        kind: EntitlementEventKind,
        ledger: EntitlementLedger
    ) async throws {
        try await ledger.apply(
            VerifiedEntitlementEvent(
                eventID: String(transaction.id),
                productID: transaction.productID,
                kind: kind,
                verifiedAt: ISO8601DateFormatter().string(
                    from: transaction.purchaseDate
                ),
                verificationSucceeded: true
            )
        )
    }
}
