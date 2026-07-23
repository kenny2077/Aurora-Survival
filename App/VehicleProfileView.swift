import SwiftUI

struct VehicleProfileView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var make = ""
    @State private var vehicleModel = ""
    @State private var year = String(Calendar.current.component(.year, from: Date()))
    @State private var market = Locale.current.region?.identifier ?? "US"
    @State private var powertrain: VehiclePowertrain = .gasoline
    @State private var documentID = ""
    @State private var vinLastSix = ""
    @State private var showInvalid = false

    var body: some View {
        Form {
            Section("Exact vehicle") {
                TextField("Make", text: $make)
                    .textInputAutocapitalization(.words)
                TextField("Model", text: $vehicleModel)
                    .textInputAutocapitalization(.words)
                TextField("Model year", text: $year)
                    .keyboardType(.numberPad)
                TextField("Market or country code", text: $market)
                    .textInputAutocapitalization(.characters)
                Picker("Powertrain", selection: $powertrain) {
                    ForEach(VehiclePowertrain.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            }

            Section("Document binding") {
                TextField("Owner-manual document ID (optional)", text: $documentID)
                TextField("VIN last six (optional)", text: $vinLastSix)
                    .textInputAutocapitalization(.characters)
                Text("The full VIN is not required or stored by this MVP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save vehicle") {
                    guard let modelYear = Int(year) else {
                        showInvalid = true
                        return
                    }
                    let profile = VehicleProfile(
                        make: make,
                        model: vehicleModel,
                        modelYear: modelYear,
                        market: market,
                        powertrain: powertrain,
                        documentID: documentID.isEmpty ? nil : documentID,
                        vinLastSix: vinLastSix.isEmpty ? nil : vinLastSix
                    )
                    guard profile.isPlausible else {
                        showInvalid = true
                        return
                    }
                    appModel.saveVehicle(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                if appModel.vehicleProfile != nil {
                    Button("Remove active vehicle", role: .destructive) {
                        appModel.removeVehicle()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Vehicle Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: populate)
        .alert("Check vehicle details", isPresented: $showInvalid) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Make, model, market, and a plausible model year are required.")
        }
    }

    private func populate() {
        guard let profile = appModel.vehicleProfile else { return }
        make = profile.make
        vehicleModel = profile.model
        year = String(profile.modelYear)
        market = profile.market
        powertrain = profile.powertrain
        documentID = profile.documentID ?? ""
        vinLastSix = profile.vinLastSix ?? ""
    }
}
