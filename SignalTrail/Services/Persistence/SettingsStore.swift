import Foundation

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "SignalTrail.AppSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: key),
                  let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
