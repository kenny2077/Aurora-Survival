import SwiftUI

struct ModelSettingsView: View {
    @EnvironmentObject private var model: AppModel

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

            Section("Important") {
                Label(
                    "A larger model is not a safer source. Every tier uses the same signed knowledge and deterministic safety gates.",
                    systemImage: "shield.lefthalf.filled"
                )
            }
        }
        .navigationTitle("Model Tiers")
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
