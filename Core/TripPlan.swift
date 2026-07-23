import Foundation

public struct TripPlan: Codable, Equatable, Sendable {
    public let travelerNames: String
    public let vehicleDescription: String
    public let route: String
    public let destination: String
    public let departure: String
    public let expectedReturn: String
    public let emergencyContact: String
    public let equipmentNotes: String
    public let medicalNotes: String

    public init(
        travelerNames: String,
        vehicleDescription: String,
        route: String,
        destination: String,
        departure: String,
        expectedReturn: String,
        emergencyContact: String,
        equipmentNotes: String,
        medicalNotes: String
    ) {
        self.travelerNames = travelerNames
        self.vehicleDescription = vehicleDescription
        self.route = route
        self.destination = destination
        self.departure = departure
        self.expectedReturn = expectedReturn
        self.emergencyContact = emergencyContact
        self.equipmentNotes = equipmentNotes
        self.medicalNotes = medicalNotes
    }

    public var exportText: String {
        """
        TRAILGUARD TRIP SHEET

        Travelers: \(travelerNames)
        Vehicle: \(vehicleDescription)
        Route: \(route)
        Destination: \(destination)
        Departure: \(departure)
        Expected return: \(expectedReturn)
        Emergency contact: \(emergencyContact)

        Equipment and supplies:
        \(equipmentNotes)

        Medical/accessibility information shared for this trip:
        \(medicalNotes)

        If overdue, contact local emergency services and provide this route,
        destination, vehicle description, party information, and expected return.

        This sheet is preparation information, not medical or rescue advice.
        """
    }

    public var isReadyToShare: Bool {
        !travelerNames.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            && !route.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !expectedReturn.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
            && !emergencyContact.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }
}
