import XCTest

#if !SWIFT_PACKAGE
@testable import Aurora

@MainActor
final class SurvivalToolsPersistenceTests: XCTestCase {
    func testEmergencyProfileRoundTripsSeparatelyFromChecklist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EmergencyProfileStore(rootDirectory: root)
        store.profile.bloodType = "O+"
        store.profile.contacts = [EmergencyContact(
            name: "Alex",
            relationship: "Partner",
            phone: "+1 555 0100"
        )]
        store.save()

        let reloaded = EmergencyProfileStore(rootDirectory: root)
        XCTAssertEqual(reloaded.profile.bloodType, "O+")
        XCTAssertEqual(reloaded.profile.contacts.first?.name, "Alex")
        XCTAssertNil(reloaded.errorMessage)
    }

    func testChecklistRecoversDefaultsAndResetRemovesCustomProgress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TripChecklistStore(rootDirectory: root)
        let defaultCount = store.items.count
        store.toggle(try XCTUnwrap(store.items.first))
        store.add(title: "Custom beacon", category: "Safety")
        XCTAssertEqual(store.completedCount, 1)
        XCTAssertEqual(store.items.count, defaultCount + 1)

        store.reset()
        XCTAssertEqual(store.completedCount, 0)
        XCTAssertEqual(store.items.count, defaultCount)
        XCTAssertFalse(store.items.contains(where: \.isCustom))

        try Data("corrupt".utf8).write(
            to: root.appendingPathComponent("trip-checklist.json"),
            options: .atomic
        )
        XCTAssertEqual(TripChecklistStore(rootDirectory: root).items.count, defaultCount)
    }
}
#endif
