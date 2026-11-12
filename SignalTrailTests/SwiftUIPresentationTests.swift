import XCTest
@testable import SignalTrail

final class SwiftUIPresentationTests: XCTestCase {
    func testHunterReadingExpiresAtFiveSeconds() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(HunterReading(rssi: -52, lastSeen: now.addingTimeInterval(-4.9), now: now).rssi, -52)
        XCTAssertNil(HunterReading(rssi: -52, lastSeen: now.addingTimeInterval(-5), now: now).rssi)
        XCTAssertNil(HunterReading(rssi: -52, lastSeen: nil, now: now).rssi)
    }

    func testHunterReadingClampsSignalAndDescribesProximity() {
        let now = Date()
        XCTAssertEqual(HunterReading(rssi: -20, lastSeen: now, now: now).level, 1)
        XCTAssertEqual(HunterReading(rssi: -110, lastSeen: now, now: now).level, 0)
        XCTAssertEqual(HunterReading(rssi: -60, lastSeen: now, now: now).proximity, "Close")
        XCTAssertEqual(HunterReading(rssi: -75, lastSeen: now, now: now).proximity, "Nearby")
    }

    func testSettingsEditsPreserveChangesFromOtherScreens() {
        let name = "SwiftUIPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        let model = TrailSettingsModel(store: store)
        var external = store.settings
        external.minimumRSSI = -65
        store.settings = external
        model.set(\.activeScanDuration, to: 300)
        XCTAssertEqual(store.settings.minimumRSSI, -65)
        XCTAssertEqual(store.settings.activeScanDuration, 300)
        XCTAssertEqual(model.settings, store.settings)
        model.reset()
        XCTAssertEqual(model.settings, .default)
    }
}
