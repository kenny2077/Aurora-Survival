import SwiftUI

struct SystemStatusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Incident operation") {
                Toggle(
                    "Incident mode",
                    isOn: $model.incidentModeEnabled
                )
                Text(
                    model.incidentModeEnabled
                        ? "Catalog, download, purchase, entitlement refresh, and telemetry traffic is denied."
                        : "Use this state only while preparing downloads before a trip."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Offline core") {
                Label(
                    model.emergencyCoreStatus,
                    systemImage: "checkmark.shield.fill"
                )
                LabeledContent(
                    "Reviewed fixture articles",
                    value: "\(model.articles.count)"
                )
                LabeledContent(
                    "Model tiers",
                    value: model.installedTierSummary
                )
            }

            Section("Integrated controls") {
                StatusRow(
                    title: "Structured model output",
                    detail: "Evidence, procedure, step, and warning validation"
                )
                StatusRow(
                    title: "Package delivery",
                    detail: "Range resume, signatures, hashes, rollback, and recall"
                )
                StatusRow(
                    title: "Offline entitlements",
                    detail: "StoreKit bridge plus verified ledger with restore, refund, and revocation handling"
                )
                StatusRow(
                    title: "Map runtime boundary",
                    detail: "Local file, coverage, freshness, detail, and routing checks"
                )
                StatusRow(
                    title: "Read-only OBD records",
                    detail: "Vehicle, adapter, raw response, codes, and sources"
                )
            }

            Section("External release evidence") {
                Label("Licensed model and map artifacts required", systemImage: "lock.fill")
                Label("Expert knowledge attestations required", systemImage: "person.badge.shield.checkmark")
                Label("Physical iPhone and OBD tests required", systemImage: "iphone.gen3")
                Label("App Store and legal approval required", systemImage: "checkmark.seal")
            }
            .font(.callout)
        }
        .navigationTitle("System Status")
    }
}

private struct StatusRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
