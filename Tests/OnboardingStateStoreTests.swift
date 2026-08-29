import XCTest

#if SWIFT_PACKAGE
@testable import AuroraCore
#else
@testable import Aurora
#endif

final class OnboardingStateStoreTests: XCTestCase {
    func testAcceptanceAndCompletionAreVersionedAndPersisted() {
        let suite = "OnboardingStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = OnboardingStateStore(
            defaults: defaults,
            now: { date }
        )

        XCTAssertFalse(store.load().accepts(schemaVersion: 1))
        XCTAssertFalse(store.load().isComplete)

        let accepted = store.accept(schemaVersion: 1)
        XCTAssertTrue(accepted.accepts(schemaVersion: 1))
        XCTAssertFalse(accepted.isComplete)

        let completed = store.complete(schemaVersion: 1)
        XCTAssertTrue(completed.accepts(schemaVersion: 1))
        XCTAssertTrue(completed.isComplete)
        XCTAssertEqual(store.load(), completed)
    }

    func testNewLegalVersionRequiresAcceptanceWithoutForgettingCompletion() {
        let suite = "OnboardingStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStateStore(defaults: defaults)

        _ = store.complete(schemaVersion: 1)
        XCTAssertFalse(store.load().accepts(schemaVersion: 2))
        XCTAssertTrue(store.load().isComplete)

        let updated = store.accept(schemaVersion: 2)
        XCTAssertTrue(updated.accepts(schemaVersion: 2))
        XCTAssertTrue(updated.isComplete)
    }
}
