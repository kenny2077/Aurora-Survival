import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class TripPlanTests: XCTestCase {
    func testTripPlanRequiresContactRouteAndReturn() {
        let incomplete = TripPlan(
            travelerNames: "A",
            vehicleDescription: "Vehicle",
            route: "",
            destination: "Camp",
            departure: "Morning",
            expectedReturn: "",
            emergencyContact: "",
            equipmentNotes: "",
            medicalNotes: ""
        )
        XCTAssertFalse(incomplete.isReadyToShare)
    }

    func testTripPlanExportContainsRescueEssentials() {
        let plan = TripPlan(
            travelerNames: "A and B",
            vehicleDescription: "Blue test vehicle",
            route: "North trail",
            destination: "Test camp",
            departure: "08:00",
            expectedReturn: "18:00",
            emergencyContact: "Trusted contact",
            equipmentNotes: "Water and power bank",
            medicalNotes: "User-chosen information"
        )
        XCTAssertTrue(plan.isReadyToShare)
        XCTAssertTrue(plan.exportText.contains("North trail"))
        XCTAssertTrue(plan.exportText.contains("18:00"))
        XCTAssertTrue(plan.exportText.contains("Blue test vehicle"))
        XCTAssertTrue(plan.exportText.contains("Trusted contact"))
    }
}
