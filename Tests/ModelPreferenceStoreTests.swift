import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class ModelPreferenceStoreTests: XCTestCase {
    func testRoundTripsTwoTierPreference() throws {
        let suite = "Aurora.ModelPreference.\(UUID().uuidString)"
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
            let suite = "Aurora.ModelPreference.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }

            XCTAssertEqual(
                ModelPreferenceStore(defaults: defaults, legacyFileURL: legacy).load(),
                .lite
            )
        }
    }

    func testMissingOrCorruptLegacyStateDefaultsToLite() throws {
        let suite = "Aurora.ModelPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not-json".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(
            ModelPreferenceStore(defaults: defaults, legacyFileURL: file).load(),
            .lite
        )
    }

    func testStoredAutoMigratesToLite() throws {
        let suite = "Aurora.ModelPreference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("automatic", forKey: "Aurora.modelSelectionPreference")

        XCTAssertEqual(ModelPreferenceStore(defaults: defaults).load(), .lite)
    }
}
