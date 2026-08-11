import Foundation

public struct ModelPreferenceStore {
    private let defaults: UserDefaults
    private let legacyFileURL: URL?
    private let key = "TrailGuard.modelSelectionPreference"

    public init(
        defaults: UserDefaults = .standard,
        legacyFileURL: URL? = nil
    ) {
        self.defaults = defaults
        self.legacyFileURL = legacyFileURL
    }

    public func load() -> ModelSelectionPreference {
        if let raw = defaults.string(forKey: key),
           let preference = ModelSelectionPreference(rawValue: raw) {
            return preference
        }
        guard let legacyFileURL,
              let data = try? Data(contentsOf: legacyFileURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rawTier = dictionary["preferredTier"] as? String
                    ?? dictionary["preferred_tier"] as? String
        else { return .automatic }
        let migrated: ModelSelectionPreference = rawTier == ModelTier.expert.rawValue
            ? .expert
            : .lite
        save(migrated)
        return migrated
    }

    public func save(_ preference: ModelSelectionPreference) {
        defaults.set(preference.rawValue, forKey: key)
    }
}
