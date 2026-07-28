import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var store = StoreKitEntitlementBridge()
    @State private var purchaseStatus: String?

    private let optionalProductIDs: Set<String> = [
        "com.example.TrailGuard.model.lite",
        "com.example.TrailGuard.model.field",
        "com.example.TrailGuard.model.vision",
    ]

    var body: some View {
        List {
            Section("Preferred intelligence tier") {
                Picker("Model", selection: $model.preferredTier) {
                    ForEach(ModelTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("Installed") {
                TierRow(
                    tier: .essential,
                    status: "Included",
                    detail: "Reviewed extractive answers and OCR. Works without model weights."
                )
                TierRow(
                    tier: .lite,
                    status: "Not installed",
                    detail: "Small text-only local model for iPhone 13-class memory. Same evidence, citations, and safety authority."
                )
                TierRow(
                    tier: .field,
                    status: "Not installed",
                    detail: "Text-only local LLM candidate. Better conversation; same facts and safety rules."
                )
                TierRow(
                    tier: .visionExpert,
                    status: "Not installed",
                    detail: "Qwen3-VL-2B candidate. Requires capability, thermal, and storage checks."
                )
            }

            Section("Optional App Store downloads") {
                if store.products.isEmpty {
                    Text("No optional products are configured for this build. Essential remains fully available offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task {
                                do {
                                    let completed = try await store.purchase(
                                        product,
                                        ledger: model.entitlementLedger
                                    )
                                    purchaseStatus = completed
                                        ? "\(product.displayName) entitlement verified."
                                        : "Purchase was cancelled or remains pending."
                                    if completed {
                                        await model.refreshActivePacks()
                                    }
                                } catch {
                                    purchaseStatus = "Purchase verification failed."
                                }
                            }
                        } label: {
                            LabeledContent(
                                product.displayName,
                                value: product.displayPrice
                            )
                        }
                    }
                }
                Button("Restore purchases") {
                    Task {
                        do {
                            try await store.restore(
                                ledger: model.entitlementLedger
                            )
                            await model.refreshActivePacks()
                            purchaseStatus = "Verified purchases restored."
                        } catch {
                            purchaseStatus = "Restore or verification failed."
                        }
                    }
                }
                if let purchaseStatus {
                    Text(purchaseStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Important") {
                Label(
                    "A larger model is not a safer source. Every tier uses the same signed knowledge and deterministic safety gates.",
                    systemImage: "shield.lefthalf.filled"
                )
            }
        }
        .navigationTitle("Model Tiers")
        .task {
            await store.loadProducts(productIDs: optionalProductIDs)
        }
    }
}

private struct TierRow: View {
    let tier: ModelTier
    let status: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(tier.displayName, systemImage: tier.supportsVision ? "eye.fill" : "text.bubble.fill")
                Spacer()
                Text(status)
                    .font(.caption.bold())
                    .foregroundStyle(status == "Included" ? .green : .secondary)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
