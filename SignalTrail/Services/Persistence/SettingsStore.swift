import Foundation

final class SettingsStore {
    private struct StoredSettings: Codable {
        let schemaVersion: Int
        let settings: AppSettings
    }

    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private static let currentSchemaVersion = 1
    private let defaults: UserDefaults
    private let key = "SignalTrail.AppSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: key) else {
                return .default
            }

            let decoder = JSONDecoder()
            if let header = try? decoder.decode(SchemaHeader.self, from: data) {
                guard header.schemaVersion <= Self.currentSchemaVersion,
                      let stored = try? decoder.decode(StoredSettings.self, from: data) else {
                    return .default
                }
                return stored.settings
            }

            // Version 0 stored AppSettings directly. Rewrite it only after a
            // successful decode so corrupt or newer data is not destroyed.
            guard let legacySettings = try? decoder.decode(AppSettings.self, from: data) else {
                return .default
            }
            persist(legacySettings)
            return legacySettings
        }
        set {
            persist(newValue)
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func persist(_ settings: AppSettings) {
        let stored = StoredSettings(schemaVersion: Self.currentSchemaVersion, settings: settings)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }
}
