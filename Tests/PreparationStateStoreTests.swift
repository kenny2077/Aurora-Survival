import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class PreparationStateStoreTests: XCTestCase {
    func testPreparationStateRoundTrips() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PreparationStateStore(
            fileURL: root.appendingPathComponent("preparation.json")
        )
        let state = PreparationState(
            vehicleProfile: VehicleProfile(
                make: "Test",
                model: "Vehicle",
                modelYear: 2025,
                market: "US",
                powertrain: .gasoline
            ),
            completedReadinessIDs: ["power", "vehicle"],
            preferredTier: .field
        )

        try store.save(state)

        XCTAssertEqual(try store.load(), state)
    }

    func testCorruptPreparationStateFailsClosed() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appendingPathComponent("preparation.json")
        try Data("not-json".utf8).write(to: file)

        XCTAssertThrowsError(
            try PreparationStateStore(fileURL: file).load()
        ) { error in
            XCTAssertEqual(
                error as? PreparationStateStoreError,
                .invalidData
            )
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TrailGuardPreparation-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
