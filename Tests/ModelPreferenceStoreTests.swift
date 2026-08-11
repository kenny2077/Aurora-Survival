import XCTest

#if SWIFT_PACKAGE
@testable import TrailGuardCore
#else
@testable import TrailGuard
#endif

final class ModelPreferenceStoreTests: XCTestCase {
    func testRoundTripsTwoTierPreference() throws {
        let suite = "TrailGuard.ModelPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelPreferenceStore(defaults: defaults)

        store.save(.expert)

        XCTAssertEqual(store.load(), .expert)
    }

    func testLegacyEssentialAndFieldPreferencesMigrateToLite() throws {
        for legacyTier in ["essential", "field"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let legacy = root.appendingPathComponent("preparation-state.json")
            try Data("{\"preferredTier\":\"\(legacyTier)\"}".utf8).write(to: legacy)
            let suite = "TrailGuard.ModelPreference.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            XCTAssertEqual(
                ModelPreferenceStore(defaults: defaults, legacyFileURL: legacy).load(),
                .lite
            )
        }
    }

    func testMissingOrCorruptLegacyStateDefaultsToAuto() throws {
        let suite = "TrailGuard.ModelPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not-json".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(
            ModelPreferenceStore(defaults: defaults, legacyFileURL: file).load(),
            .automatic
        )
    }
}
