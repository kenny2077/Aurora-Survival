import SwiftUI

struct TripSheetView: View {
    @State private var travelerNames = ""
    @State private var vehicleDescription = ""
    @State private var route = ""
    @State private var destination = ""
    @State private var departure = ""
    @State private var expectedReturn = ""
    @State private var emergencyContact = ""
    @State private var equipmentNotes = ""
    @State private var medicalNotes = ""

    private var plan: TripPlan {
        TripPlan(
            travelerNames: travelerNames,
            vehicleDescription: vehicleDescription,
            route: route,
            destination: destination,
            departure: departure,
            expectedReturn: expectedReturn,
            emergencyContact: emergencyContact,
            equipmentNotes: equipmentNotes,
            medicalNotes: medicalNotes
        )
    }

    var body: some View {
        Form {
            Section("Party and vehicle") {
                TextField("Travelers", text: $travelerNames)
                TextField("Vehicle description", text: $vehicleDescription)
            }
            Section("Route and time") {
                TextField("Planned route", text: $route, axis: .vertical)
                TextField("Destination", text: $destination)
                TextField("Departure", text: $departure)
                TextField("Expected return", text: $expectedReturn)
            }
            Section("Emergency contact") {
                TextField("Name and phone", text: $emergencyContact)
                    .textContentType(.telephoneNumber)
            }
            Section("Preparation notes") {
                TextField(
                    "Equipment, water, food, power, and shelter",
                    text: $equipmentNotes,
                    axis: .vertical
                )
                TextField(
                    "Medical or accessibility information you choose to share",
                    text: $medicalNotes,
                    axis: .vertical
                )
            }
            Section {
                ShareLink(
                    item: plan.exportText,
                    subject: Text("TrailGuard trip sheet"),
                    message: Text(
                        "Save, print, or send this before leaving coverage."
                    )
                ) {
                    Label("Share or print trip sheet", systemImage: "square.and.arrow.up")
                }
                .disabled(!plan.isReadyToShare)
            } footer: {
                Text("No app works after the battery is depleted. Give this sheet to a trusted contact and carry a printed copy.")
            }
        }
        .navigationTitle("Trip Sheet")
    }
}
