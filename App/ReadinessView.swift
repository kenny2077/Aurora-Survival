import SwiftUI

struct ReadinessView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Int(model.readinessProgress * 100))% ready")
                        .font(.title.bold())
                    ProgressView(value: model.readinessProgress)
                    Text("Finish this check before leaving coverage.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Pre-trip checks") {
                ForEach(model.readinessChecks) { check in
                    Button {
                        model.toggleReadiness(check.id)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: check.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(check.isComplete ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.title).foregroundStyle(.primary)
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Vehicle identity") {
                NavigationLink {
                    VehicleProfileView()
                } label: {
                    if let vehicle = model.vehicleProfile {
                        LabeledContent("Active vehicle", value: vehicle.displayName)
                    } else {
                        Label("Add exact vehicle profile", systemImage: "car.fill")
                    }
                }
                Text("Vehicle-specific procedures remain hidden until make, model, year, market, and powertrain match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Trip systems") {
                NavigationLink {
                    MapPackView()
                } label: {
                    Label("Offline map packs", systemImage: "map.fill")
                }
                NavigationLink {
                    OBDStatusView()
                } label: {
                    Label("Read-only OBD", systemImage: "cable.connector")
                }
            }

            Section("Zero-power reality") {
                Text("No app works after the battery is drained. Carry a power bank and a paper trip plan with emergency contacts, route, return time, and essential first-aid steps.")
            }
        }
        .navigationTitle("Offline Readiness")
    }
}
