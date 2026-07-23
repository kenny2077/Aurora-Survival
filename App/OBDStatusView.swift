import SwiftUI

struct OBDStatusView: View {
    private let allowed = [
        "Stored, pending, and permanent trouble codes",
        "Freeze-frame data",
        "Coolant and intake temperature",
        "Engine RPM, vehicle speed, and throttle position"
    ]

    var body: some View {
        List {
            Section {
                Label("No OBD adapter connected", systemImage: "cable.connector")
                    .font(.headline)
                Text("The read-only protocol, parser, command whitelist, and vehicle-bound observation store are implemented. BLE hardware transport remains a physical-device milestone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permitted reads") {
                ForEach(allowed, id: \.self) {
                    Label($0, systemImage: "checkmark.shield.fill")
                }
            }

            Section("Blocked by design") {
                Label("Clear trouble codes", systemImage: "xmark.octagon.fill")
                Label("Actuator tests or ECU coding", systemImage: "xmark.octagon.fill")
                Label("Airbag, immobilizer, or emissions bypass", systemImage: "xmark.octagon.fill")
            }
            .foregroundStyle(.red)
        }
        .navigationTitle("Read-only OBD")
    }
}
