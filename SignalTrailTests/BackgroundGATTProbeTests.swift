import CoreBluetooth
import XCTest

@testable import SignalTrail

final class BackgroundGATTProbeTests: XCTestCase {
    // MARK: - Settings Persistence & Backward Compatibility

    func testAppSettingsDefaultHasAutomaticGATTEnrichmentEnabled() {
        let defaultSettings = AppSettings.default
        XCTAssertTrue(defaultSettings.isAutomaticGATTEnrichmentEnabled)

        let newSettings = AppSettings()
        XCTAssertTrue(newSettings.isAutomaticGATTEnrichmentEnabled)
    }

    func testHunterSettingsDefaultsAndBackwardCompatibility() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: "{\"activeScanDuration\":90}".data(using: .utf8)!
        )
        XCTAssertTrue(decoded.isHunterSoundEnabled)
        XCTAssertEqual(decoded.hunterAlertTone, .sonar)
        XCTAssertEqual(decoded.hunterHapticStyle, .medium)
    }

    func testFoxhunterRSSIPulseIntervals() {
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -95), 3.0, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -85), 1.0, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -75), 0.5, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -65), 0.2, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -55), 0.1, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -45), 0.05, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -35), 0.025, accuracy: 0.001)
        XCTAssertEqual(HunterProximity.pulseInterval(forRSSI: -25), 0.010, accuracy: 0.001)
    }

    func testAppSettingsCodableRoundTrip() throws {
        var settings = AppSettings()
        settings.isAutomaticGATTEnrichmentEnabled = false
        settings.activeScanDuration = 60
        settings.minimumRSSI = -75
        settings.isHunterSoundEnabled = false
        settings.hunterAlertTone = .deepPing
        settings.hunterHapticStyle = .heavy

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertFalse(decoded.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(decoded.activeScanDuration, 60)
        XCTAssertEqual(decoded.minimumRSSI, -75)
        XCTAssertFalse(decoded.isHunterSoundEnabled)
        XCTAssertEqual(decoded.hunterAlertTone, .deepPing)
        XCTAssertEqual(decoded.hunterHapticStyle, .heavy)
    }

    func testAppSettingsBackwardCompatibilityFallback() throws {
        // Simulating JSON payload from an older version of the app without `isAutomaticGATTEnrichmentEnabled`
        let legacyJSON = """
        {
            "activeScanDuration": 90,
            "recordingBurstDuration": 2,
            "recordingPauseDuration": 8,
            "minimumRSSI": -80,
            "keepScreenAwakeDuringRecording": true,
            "requestNotificationPermissionOnRuleCreation": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppSettings.self, from: legacyJSON)

        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(decoded.activeScanDuration, 90)
        XCTAssertEqual(decoded.recordingBurstDuration, 2)
        XCTAssertEqual(decoded.recordingPauseDuration, 8)
        XCTAssertEqual(decoded.minimumRSSI, -80)
        XCTAssertTrue(decoded.keepScreenAwakeDuringRecording)
        XCTAssertFalse(decoded.requestNotificationPermissionOnRuleCreation)
    }

    func testSettingsStorePersistence() {
        let userDefaultsSuite = "SignalTrailTests.SettingsStore.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: userDefaultsSuite) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { userDefaults.removePersistentDomain(forName: userDefaultsSuite) }

        let store = SettingsStore(defaults: userDefaults)
        XCTAssertTrue(store.settings.isAutomaticGATTEnrichmentEnabled)

        var mutated = store.settings
        mutated.isAutomaticGATTEnrichmentEnabled = false
        store.settings = mutated

        XCTAssertFalse(store.settings.isAutomaticGATTEnrichmentEnabled)

        store.reset()
        XCTAssertTrue(store.settings.isAutomaticGATTEnrichmentEnabled)
    }

    func testAppSettingsDecodesEmptyJSONWithAllDefaults() throws {
        let emptyJSON = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: emptyJSON)
        XCTAssertEqual(decoded, AppSettings.default)
        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(decoded.activeScanDuration, 120)
        XCTAssertEqual(decoded.recordingBurstDuration, 1)
        XCTAssertEqual(decoded.recordingPauseDuration, 5)
        XCTAssertEqual(decoded.minimumRSSI, -100)
        XCTAssertTrue(decoded.keepScreenAwakeDuringRecording)
        XCTAssertTrue(decoded.requestNotificationPermissionOnRuleCreation)
    }

    func testAppSettingsDecodesWithNullEnrichmentFlag() throws {
        let nullJSON = """
        {
            "isAutomaticGATTEnrichmentEnabled": null,
            "activeScanDuration": 180
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: nullJSON)
        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(decoded.activeScanDuration, 180)
    }

    func testAppSettingsDecodesWithFutureUnknownKeys() throws {
        let futureJSON = """
        {
            "isAutomaticGATTEnrichmentEnabled": false,
            "activeScanDuration": 45,
            "futureBluetoothSIGFeatureFlag": "enabled",
            "futureNumericLimit": 999
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: futureJSON)
        XCTAssertFalse(decoded.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(decoded.activeScanDuration, 45)
    }

    func testAppSettingsThrowsOnTypeMismatch() {
        let boolTypeMismatch = """
        {
            "isAutomaticGATTEnrichmentEnabled": "not_a_bool"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: boolTypeMismatch))

        let intTypeMismatch = """
        {
            "minimumRSSI": true
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AppSettings.self, from: intTypeMismatch))
    }

    func testSettingsStoreHandlesCorruptedDataGracefully() {
        let userDefaultsSuite = "SignalTrailTests.SettingsStore.Corruption.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: userDefaultsSuite) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { userDefaults.removePersistentDomain(forName: userDefaultsSuite) }

        let store = SettingsStore(defaults: userDefaults)

        // Corrupt binary
        userDefaults.set(Data([0xFF, 0xFE, 0xDE, 0xAD, 0xBE, 0xEF]), forKey: "SignalTrail.AppSettings")
        XCTAssertEqual(store.settings, AppSettings.default)
        XCTAssertTrue(store.settings.isAutomaticGATTEnrichmentEnabled)

        // Truncated JSON
        userDefaults.set("{\"isAutomaticGATTEnrichmentEnabled\": ".data(using: .utf8)!, forKey: "SignalTrail.AppSettings")
        XCTAssertEqual(store.settings, AppSettings.default)

        // Empty Data
        userDefaults.set(Data(), forKey: "SignalTrail.AppSettings")
        XCTAssertEqual(store.settings, AppSettings.default)

        // Non-data object in key
        userDefaults.set("plain string instead of data", forKey: "SignalTrail.AppSettings")
        XCTAssertEqual(store.settings, AppSettings.default)
    }

    func testSettingsStoreResetAndSubsequentMutation() {
        let userDefaultsSuite = "SignalTrailTests.SettingsStore.ResetMutate.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: userDefaultsSuite) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { userDefaults.removePersistentDomain(forName: userDefaultsSuite) }

        let store = SettingsStore(defaults: userDefaults)
        var mutated = store.settings
        mutated.isAutomaticGATTEnrichmentEnabled = false
        store.settings = mutated
        XCTAssertFalse(store.settings.isAutomaticGATTEnrichmentEnabled)

        store.reset()
        XCTAssertTrue(store.settings.isAutomaticGATTEnrichmentEnabled)
        XCTAssertNil(userDefaults.object(forKey: "SignalTrail.AppSettings"))

        var updated = store.settings
        updated.activeScanDuration = 300
        store.settings = updated
        XCTAssertEqual(store.settings.activeScanDuration, 300)
        XCTAssertNotNil(userDefaults.data(forKey: "SignalTrail.AppSettings"))
    }

    // MARK: - Target Characteristic Whitelist & Read-Only Safety

    func testTargetCharacteristicWhitelistContainsIdentificationUUIDs() {
        let expected16BitUUIDs: [UInt16] = [
            0x2A00, // Device Name
            0x2A01, // Appearance
            0x2A19, // Battery Level
            0x2A23, // System ID
            0x2A24, // Model Number String
            0x2A25, // Serial Number String
            0x2A26, // Firmware Revision String
            0x2A27, // Hardware Revision String
            0x2A28, // Software Revision String
            0x2A29, // Manufacturer Name String
            0x2A50  // PnP ID
        ]

        XCTAssertEqual(BackgroundGATTProbe.targetCharacteristicUUIDs.count, expected16BitUUIDs.count)

        for uuid in expected16BitUUIDs {
            XCTAssertTrue(
                BackgroundGATTProbe.targetCharacteristicUUIDs.contains(uuid),
                "Missing target characteristic 0x\(String(format: "%04X", uuid))"
            )
            let shortHex = String(format: "%04X", uuid)
            XCTAssertTrue(
                BackgroundGATTProbe.isTargetCharacteristic(uuidString: shortHex),
                "Failed to match short UUID \(shortHex)"
            )
            let longUUID = "0000\(shortHex)-0000-1000-8000-00805F9B34FB"
            XCTAssertTrue(
                BackgroundGATTProbe.isTargetCharacteristic(uuidString: longUUID),
                "Failed to match 128-bit base UUID \(longUUID)"
            )
        }
    }

    func testTargetCharacteristicWhitelistExcludesNonIdentificationCharacteristics() {
        let nonTargetUUIDs = [
            "2A37", // Heart Rate Measurement
            "2A6D", // Pressure
            "2A6E", // Temperature
            "2A06", // Alert Level (write-only)
            "FFF0", // Custom vendor service/characteristic
            "00001800-0000-1000-8000-00805F9B34FB", // Service UUID, not characteristic
            "INVALID-UUID"
        ]

        for uuid in nonTargetUUIDs {
            XCTAssertFalse(
                BackgroundGATTProbe.isTargetCharacteristic(uuidString: uuid),
                "Expected \(uuid) to not be a target characteristic"
            )
        }
    }

    // MARK: - Error Handling & Formatting

    func testBackgroundGATTProbeErrorDescriptions() {
        let timedOut = BackgroundGATTProbeError.timedOut
        XCTAssertEqual(timedOut.errorDescription, "GATT probe timed out.")

        let cancelled = BackgroundGATTProbeError.cancelled
        XCTAssertEqual(cancelled.errorDescription, "GATT probe was cancelled.")

        let failed = BackgroundGATTProbeError.connectionFailed("Link lost")
        XCTAssertEqual(failed.errorDescription, "Peripheral connection failed: Link lost")

        let disconnected = BackgroundGATTProbeError.disconnected
        XCTAssertEqual(disconnected.errorDescription, "Peripheral disconnected before GATT probe completed.")

        let discoveryFailed = BackgroundGATTProbeError.serviceDiscoveryFailed("Unknown error")
        XCTAssertEqual(discoveryFailed.errorDescription, "Service discovery failed: Unknown error")
    }

    func testDefaultTimeoutConstant() {
        XCTAssertEqual(BackgroundGATTProbe.defaultTimeout, 5.0)
    }

    // MARK: - Evidence Merging & Decoding

    func testEvidenceMergingFromIdentificationCharacteristics() {
        var evidence = GATTDeviceEvidence()

        // 0x2A00: Device Name
        let nameData = "Signal Beacon".data(using: .utf8)!
        let nameDecoded = GATTValueDecoder.decode(characteristicUUID: "2A00", data: nameData)
        evidence.merge(characteristicUUID: "2A00", decodedValue: nameDecoded)
        XCTAssertEqual(evidence.identity.deviceName, "Signal Beacon")

        // 0x2A01: GAP Appearance (0x00C2 -> Smartwatch)
        var appearanceRaw = UInt16(0x00C2).littleEndian
        let appearanceData = Data(bytes: &appearanceRaw, count: 2)
        let appearanceDecoded = GATTValueDecoder.decode(characteristicUUID: "2A01", data: appearanceData)
        evidence.merge(characteristicUUID: "2A01", decodedValue: appearanceDecoded)
        XCTAssertEqual(evidence.identity.appearance?.rawValue, 0x00C2)
        XCTAssertEqual(evidence.identity.appearance?.categoryName, "Watch")

        // 0x2A24: Model Number
        let modelData = "AppleTV14,1".data(using: .utf8)!
        let modelDecoded = GATTValueDecoder.decode(characteristicUUID: "2A24", data: modelData)
        evidence.merge(characteristicUUID: "2A24", decodedValue: modelDecoded)
        XCTAssertEqual(evidence.identity.modelNumber, "AppleTV14,1")

        // 0x2A25: Serial Number
        let serialData = "C02G12345678".data(using: .utf8)!
        let serialDecoded = GATTValueDecoder.decode(characteristicUUID: "2A25", data: serialData)
        evidence.merge(characteristicUUID: "2A25", decodedValue: serialDecoded)
        XCTAssertEqual(evidence.identity.serialNumber, "C02G12345678")

        // 0x2A26: Firmware Revision
        let fwData = "1.2.3".data(using: .utf8)!
        let fwDecoded = GATTValueDecoder.decode(characteristicUUID: "2A26", data: fwData)
        evidence.merge(characteristicUUID: "2A26", decodedValue: fwDecoded)
        XCTAssertEqual(evidence.identity.firmwareRevision, "1.2.3")

        // 0x2A27: Hardware Revision
        let hwData = "Rev B".data(using: .utf8)!
        let hwDecoded = GATTValueDecoder.decode(characteristicUUID: "2A27", data: hwData)
        evidence.merge(characteristicUUID: "2A27", decodedValue: hwDecoded)
        XCTAssertEqual(evidence.identity.hardwareRevision, "Rev B")

        // 0x2A28: Software Revision
        let swData = "Build 99".data(using: .utf8)!
        let swDecoded = GATTValueDecoder.decode(characteristicUUID: "2A28", data: swData)
        evidence.merge(characteristicUUID: "2A28", decodedValue: swDecoded)
        XCTAssertEqual(evidence.identity.softwareRevision, "Build 99")

        // 0x2A29: Manufacturer Name
        let mfgData = "Apple Inc.".data(using: .utf8)!
        let mfgDecoded = GATTValueDecoder.decode(characteristicUUID: "2A29", data: mfgData)
        evidence.merge(characteristicUUID: "2A29", decodedValue: mfgDecoded)
        XCTAssertEqual(evidence.identity.manufacturerName, "Apple Inc.")

        // 0x2A23: System ID (8 bytes)
        let systemIDBytes: [UInt8] = [0x11, 0x22, 0x33, 0xFE, 0xFF, 0x44, 0x55, 0x66]
        let systemIDData = Data(systemIDBytes)
        let systemIDDecoded = GATTValueDecoder.decode(characteristicUUID: "2A23", data: systemIDData)
        evidence.merge(characteristicUUID: "2A23", decodedValue: systemIDDecoded)
        XCTAssertEqual(evidence.identity.systemID, "66:55:44:FF:FE:33:22:11")

        // 0x2A50: PnP ID (7 bytes: vendorSource(1), vendorID(2), productID(2), productVersion(2))
        let pnpBytes: [UInt8] = [0x01, 0x4C, 0x00, 0x01, 0x02, 0x03, 0x04]
        let pnpData = Data(pnpBytes)
        let pnpDecoded = GATTValueDecoder.decode(characteristicUUID: "2A50", data: pnpData)
        evidence.merge(characteristicUUID: "2A50", decodedValue: pnpDecoded)
        XCTAssertNotNil(evidence.identity.pnpIdentifier)
        XCTAssertEqual(evidence.identity.pnpIdentifier?.vendorID, 0x004C)
        XCTAssertEqual(evidence.identity.pnpIdentifier?.productID, 0x0201)
        XCTAssertEqual(evidence.identity.pnpIdentifier?.productVersion, 0x0403)

        XCTAssertTrue(evidence.hasValues)
    }

    func testBatteryLevelDecoding() {
        let batteryData = Data([85])
        let batteryDecoded = GATTValueDecoder.decode(characteristicUUID: "2A19", data: batteryData)
        XCTAssertNotNil(batteryDecoded)
        XCTAssertEqual(batteryDecoded?.displayText, "85%")
    }
}
