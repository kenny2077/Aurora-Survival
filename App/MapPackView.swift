import SwiftUI

struct MapPackView: View {
    var body: some View {
        List {
            Section {
                Label("No signed map pack installed", systemImage: "map.fill")
                    .font(.headline)
                Text("The package verifier and readiness checks are implemented. A production PMTiles catalog and MapLibre renderer require licensed map artifacts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Detail tiers") {
                MapTierRow(
                    tier: .scout,
                    detail: "Roads, settlements, water, and basic landmarks."
                )
                MapTierRow(
                    tier: .field,
                    detail: "Adds trails, contours, land cover, and offline routing graph."
                )
                MapTierRow(
                    tier: .expedition,
                    detail: "Maximum regional detail and larger storage footprint."
                )
            }

            Section("Readiness contract") {
                Label("Signed and hash verified", systemImage: "signature")
                Label("Trip coordinate inside coverage", systemImage: "location.fill")
                Label("Pack detail meets trip requirement", systemImage: "square.3.layers.3d")
                Label("Map age shown before departure", systemImage: "calendar.badge.clock")
                Label("Airplane Mode route preview", systemImage: "airplane")
            }
        }
        .navigationTitle("Offline Maps")
    }
}

private struct MapTierRow: View {
    let tier: MapDetailTier
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tier.displayName).font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
