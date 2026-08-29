import Foundation

public struct OnboardingState: Codable, Equatable, Sendable {
    public let legalSchemaVersion: Int?
    public let acceptedAt: String?
    public let onboardingCompletedAt: String?

    public init(
        legalSchemaVersion: Int? = nil,
        acceptedAt: String? = nil,
        onboardingCompletedAt: String? = nil
    ) {
        self.legalSchemaVersion = legalSchemaVersion
        self.acceptedAt = acceptedAt
        self.onboardingCompletedAt = onboardingCompletedAt
    }

    public func accepts(schemaVersion: Int) -> Bool {
        legalSchemaVersion == schemaVersion && acceptedAt != nil
    }

    public var isComplete: Bool { onboardingCompletedAt != nil }
}

public struct OnboardingStateStore {
    private let defaults: UserDefaults
    private let key: String
    private let now: @Sendable () -> Date

    public init(
        defaults: UserDefaults = .standard,
        key: String = "Aurora.onboardingState",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    public func load() -> OnboardingState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(OnboardingState.self, from: data)
        else { return OnboardingState() }
        return state
    }

    @discardableResult
    public func accept(schemaVersion: Int) -> OnboardingState {
        let previous = load()
        let state = OnboardingState(
            legalSchemaVersion: schemaVersion,
            acceptedAt: timestamp,
            onboardingCompletedAt: previous.onboardingCompletedAt
        )
        save(state)
        return state
    }

    @discardableResult
    public func complete(schemaVersion: Int) -> OnboardingState {
        let previous = load()
        let state = OnboardingState(
            legalSchemaVersion: previous.accepts(schemaVersion: schemaVersion)
                ? previous.legalSchemaVersion
                : schemaVersion,
            acceptedAt: previous.accepts(schemaVersion: schemaVersion)
                ? previous.acceptedAt
                : timestamp,
            onboardingCompletedAt: timestamp
        )
        save(state)
        return state
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private var timestamp: String {
        ISO8601DateFormatter().string(from: now())
    }

    private func save(_ state: OnboardingState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
