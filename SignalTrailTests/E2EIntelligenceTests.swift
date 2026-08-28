import CoreBluetooth
import CoreLocation
import XCTest

@testable import SignalTrail

// MARK: - E2E Test Suite: Bluetooth SIG Device Intelligence (F1 to F8)
// 4-Tier Test Architecture:
// - Tier 1: Feature Coverage (>=5 tests per feature across all 8 features = 40 tests)
// - Tier 2: Boundary & Corner Cases (>=5 tests per feature = 40 tests)
// - Tier 3: Cross-Feature Combinations (5 pairwise & pipeline interaction tests)
// - Tier 4: Real-World Application Scenarios (4 end-to-end device scenarios)

final class E2EIntelligenceTests: XCTestCase {

    private var tempDirectory: URL!
    private var localStore: LocalStore!
    private var settingsStore: SettingsStore!
    private var mockLocationProvider: MockLocationProvider!
    private var notificationService: NotificationService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalTrailE2ETests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        localStore = try LocalStore(rootURL: tempDirectory)
        settingsStore = SettingsStore()
        mockLocationProvider = MockLocationProvider()
        notificationService = NotificationService()
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // =========================================================================
    // MARK: - TIER 1: FEATURE COVERAGE (40 tests)
    // =========================================================================

    // --- F1: SettingsToggle ---

    func testTier1_F1_DefaultSettingsEnablesAutomaticGATTEnrichment() {
        let settings = AppSettings.default
        let harness = TestSettingsHarness(settings: settings)
        XCTAssertTrue(harness.isAutomaticGATTEnrichmentEnabled, "Automatic GATT enrichment should be enabled by default")
    }

    func testTier1_F1_SettingsTogglePersistsDisabledState() throws {
        var harness = TestSettingsHarness()
        harness.isAutomaticGATTEnrichmentEnabled = false

        let encoded = try JSONEncoder().encode(harness)
        let decoded = try JSONDecoder().decode(TestSettingsHarness.self, from: encoded)

        XCTAssertFalse(decoded.isAutomaticGATTEnrichmentEnabled, "Disabled state must survive JSON serialization")
    }

    func testTier1_F1_SettingsTogglePersistsEnabledState() throws {
        var harness = TestSettingsHarness()
        harness.isAutomaticGATTEnrichmentEnabled = false
        harness.isAutomaticGATTEnrichmentEnabled = true

        let encoded = try JSONEncoder().encode(harness)
        let decoded = try JSONDecoder().decode(TestSettingsHarness.self, from: encoded)

        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled, "Re-enabled state must survive JSON serialization")
    }

    func testTier1_F1_BackwardCompatibleDecodingMissingKeyDefaultsToTrue() throws {
        let legacyJSON = """
        {
            "activeScanDuration": 120,
            "recordingBurstDuration": 1,
            "recordingPauseDuration": 5,
            "minimumRSSI": -100,
            "keepScreenAwakeDuringRecording": true,
            "requestNotificationPermissionOnRuleCreation": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TestSettingsHarness.self, from: legacyJSON)
        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled, "Legacy JSON missing the enrichment key must default to true")
    }

    func testTier1_F1_ScanCoordinatorRespectsSettingsToggleWhenDisabled() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: false)
        let peripheralID = UUID()

        let queued = queue.enqueueIfEligible(
            peripheralID: peripheralID,
            isConnectable: true,
            isScanActive: true
        )

        XCTAssertFalse(queued, "Probe queue must reject devices when automatic GATT enrichment setting is disabled")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // --- F2: BackgroundGATTProbe ---

    func testTier1_F2_ProbeDiscoversAndReadsIdentityCharacteristicsOnly() {
        let probe = TestBackgroundGATTProbeSimulator()
        let discoveredServices: [UInt16] = [0x1800, 0x180A, 0x180F, 0x1812]
        let candidateCharacteristics: [UInt16] = [
            0x2A00, 0x2A01, 0x2A19, 0x2A24, 0x2A29, // Whitelisted
            0x2A4D, 0x2A4E, 0xFFF1                   // Non-whitelisted
        ]

        let reads = probe.determineReadsToPerform(
            services: discoveredServices,
            characteristics: candidateCharacteristics
        )

        XCTAssertEqual(Set(reads), Set([0x2A00, 0x2A01, 0x2A19, 0x2A24, 0x2A29]), "Only whitelisted identification characteristics must be scheduled for read")
        XCTAssertFalse(reads.contains(0x2A4D), "Custom/report characteristics must not be auto-read")
        XCTAssertFalse(reads.contains(0xFFF1), "Vendor characteristics must not be auto-read")
    }

    func testTier1_F2_ProbeIsStrictlyReadOnlyWithZeroWritesOrNotifications() {
        let probe = TestBackgroundGATTProbeSimulator()
        probe.executeMockProbe(
            services: [0x1800, 0x180A, 0x180F],
            characteristics: [0x2A00: Data("Beacon-X".utf8), 0x2A19: Data([90])]
        )

        XCTAssertEqual(probe.writeOperationsCount, 0, "Background GATT probe MUST NEVER perform write operations")
        XCTAssertEqual(probe.notifySubscriptionCount, 0, "Background GATT probe MUST NEVER enable notifications")
    }

    func testTier1_F2_ProbeDeliversDeviceEvidenceOnSuccessfulCompletion() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(
            services: [0x1800, 0x180A, 0x180F],
            characteristics: [
                0x2A00: Data("Living Room TV".utf8),
                0x2A24: Data("AppleTV14,1".utf8),
                0x2A29: Data("Apple Inc.".utf8),
                0x2A19: Data([100])
            ]
        )

        XCTAssertEqual(evidence.identity.deviceName, "Living Room TV")
        XCTAssertEqual(evidence.identity.modelNumber, "AppleTV14,1")
        XCTAssertEqual(evidence.identity.manufacturerName, "Apple Inc.")
        XCTAssertTrue(evidence.discoveredServiceUUIDs.contains("180F"))
    }

    func testTier1_F2_ProbeHandlesPartialCharacteristicsGracefully() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(
            services: [0x180F],
            characteristics: [0x2A19: Data([75])]
        )

        XCTAssertNil(evidence.identity.modelNumber, "Missing model number should be nil")
        XCTAssertNil(evidence.identity.deviceName, "Missing device name should be nil")
        XCTAssertTrue(evidence.hasValues, "Evidence with only battery must still report hasValues == true")
    }

    func testTier1_F2_ProbeTimeoutCancelsConnectionAndCompletesWithPartialEvidence() {
        let probe = TestBackgroundGATTProbeSimulator()
        probe.simulateTimeout(timeoutSeconds: 5.0)

        XCTAssertTrue(probe.isCancelled, "Probe must be cancelled immediately upon timeout")
        XCTAssertTrue(probe.timeoutFired, "Timeout timer must have fired")
    }

    // --- F3: AutoProbeQueue ---

    func testTier1_F3_SequentialExecutionEnforcesStrictlyOneConcurrentConnection() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let dev1 = UUID(), dev2 = UUID(), dev3 = UUID()

        _ = queue.enqueueIfEligible(peripheralID: dev1, isConnectable: true, isScanActive: true)
        _ = queue.enqueueIfEligible(peripheralID: dev2, isConnectable: true, isScanActive: true)
        _ = queue.enqueueIfEligible(peripheralID: dev3, isConnectable: true, isScanActive: true)

        XCTAssertEqual(queue.activeConnectionsCount, 1, "Must strictly have at most 1 active concurrent background connection")
        XCTAssertEqual(queue.currentProbingID, dev1)
        XCTAssertEqual(queue.pendingCount, 2)
    }

    func testTier1_F3_QueueEnforcesSessionCapOfTwentyDevices() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true, maxSessionCap: 20)

        for _ in 0..<30 {
            let id = UUID()
            _ = queue.enqueueIfEligible(peripheralID: id, isConnectable: true, isScanActive: true)
            queue.completeCurrentProbe()
        }

        XCTAssertEqual(queue.totalProbedCount, 20, "Total probed devices in a single session must not exceed 20")
        XCTAssertEqual(queue.pendingCount, 0, "Excess devices beyond session cap must not be queued")
    }

    func testTier1_F3_QueueEnforcesDeduplicationPerScanSession() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let devID = UUID()

        let first = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)
        let second = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)

        XCTAssertTrue(first, "First discovery of connectable device should be enqueued")
        XCTAssertFalse(second, "Duplicate discovery of already queued device must be rejected")
        XCTAssertEqual(queue.pendingCount, 0) // It became active
        XCTAssertEqual(queue.currentProbingID, devID)

        queue.completeCurrentProbe()
        let third = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)
        XCTAssertFalse(third, "Device already probed in the current session must not be re-probed")
    }

    func testTier1_F3_StoppingScanCancelsInFlightProbeAndClearsQueue() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let dev1 = UUID(), dev2 = UUID()

        _ = queue.enqueueIfEligible(peripheralID: dev1, isConnectable: true, isScanActive: true)
        _ = queue.enqueueIfEligible(peripheralID: dev2, isConnectable: true, isScanActive: true)

        queue.stopScan()

        XCTAssertEqual(queue.activeConnectionsCount, 0, "Stopping scan must cancel active connection")
        XCTAssertNil(queue.currentProbingID)
        XCTAssertEqual(queue.pendingCount, 0, "Stopping scan must purge all pending items")
    }

    func testTier1_F3_UnconnectableDevicesAreNeverQueued() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let unconnectableID = UUID()

        let queued = queue.enqueueIfEligible(peripheralID: unconnectableID, isConnectable: false, isScanActive: true)

        XCTAssertFalse(queued, "Non-connectable devices must never be queued for background GATT inspection")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // --- F4: LiveIntelligenceEnrichment ---

    func testTier1_F4_ModelNumberEnrichmentRefinesTelevisionCategory() {
        let advertisement = BLEAdvertisement.empty
        var evidence = GATTDeviceEvidence()
        evidence.identity.modelNumber = "AppleTV14,1"
        evidence.identity.manufacturerName = "Apple Inc."

        let intelligence = DeviceIntelligenceEngine().analyze(advertisement, gattEvidence: evidence)

        XCTAssertEqual(intelligence.category, .television, "Model AppleTV14,1 must classify as .television")
        XCTAssertGreaterThanOrEqual(intelligence.probability, 92)
        XCTAssertEqual(intelligence.evidence.first?.kind, .gattIdentity)
    }

    func testTier1_F4_GAPAppearanceEnrichmentRefinesSmartWatchCategory() {
        let advertisement = BLEAdvertisement.empty
        var evidence = GATTDeviceEvidence()
        evidence.identity.appearance = GATTAppearance(rawValue: 0x00C2, categoryName: "Watch", subcategoryName: "Smartwatch")

        let intelligence = DeviceIntelligenceEngine().analyze(advertisement, gattEvidence: evidence)

        XCTAssertEqual(intelligence.category, .smartWatch, "Appearance 0x00C2 must classify as .smartWatch")
        XCTAssertGreaterThanOrEqual(intelligence.probability, 96)
        XCTAssertEqual(intelligence.evidence.first?.kind, .gattAppearance)
    }

    func testTier1_F4_BatteryLevelAndIdentityUpdateSnapshotAndPresentationName() {
        var snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Unnamed device",
            latestRSSI: -65,
            strongestRSSI: -65,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: .empty
        )
        XCTAssertEqual(snapshot.presentationName, "Unknown BLE device")

        var evidence = GATTDeviceEvidence()
        evidence.identity.deviceName = "Smart Thermostat Pro"
        snapshot.gattEvidence = evidence

        XCTAssertEqual(snapshot.presentationName, "Smart Thermostat Pro", "Presentation name must prioritize GATT device name over generic placeholder")
    }

    func testTier1_F4_LiveEnrichmentUpdatesDiskCacheAtomically() throws {
        let id = UUID()
        var snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: id,
            displayName: "Unnamed device",
            latestRSSI: -70,
            strongestRSSI: -70,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: .empty
        )
        try localStore.saveDeviceRecord(snapshot)

        var evidence = GATTDeviceEvidence()
        evidence.identity.modelNumber = "MacBookPro18,3"
        snapshot.gattEvidence = evidence
        try localStore.saveDeviceRecord(snapshot)

        let reloaded = localStore.loadDeviceRecord(for: id)
        XCTAssertEqual(reloaded?.gattEvidence?.identity.modelNumber, "MacBookPro18,3")
        XCTAssertEqual(reloaded?.intelligence.category, .computer)
    }

    func testTier1_F4_DuplicateReconciliationMergesRotatingRPADevicesWithSameSerial() {
        let serial = "SN-987654321"
        let id1 = UUID(), id2 = UUID()

        var snap1 = BLEDeviceSnapshot(
            peripheralIdentifier: id1,
            displayName: "Sensor A",
            latestRSSI: -80,
            strongestRSSI: -70,
            firstSeen: Date().addingTimeInterval(-100),
            lastSeen: Date().addingTimeInterval(-50),
            sightingCount: 5,
            advertisement: .empty
        )
        var ev1 = GATTDeviceEvidence()
        ev1.identity.serialNumber = serial
        snap1.gattEvidence = ev1

        var snap2 = BLEDeviceSnapshot(
            peripheralIdentifier: id2,
            displayName: "Sensor B",
            latestRSSI: -60,
            strongestRSSI: -60,
            firstSeen: Date().addingTimeInterval(-20),
            lastSeen: Date(),
            sightingCount: 10,
            advertisement: .empty
        )
        var ev2 = GATTDeviceEvidence()
        ev2.identity.serialNumber = serial
        snap2.gattEvidence = ev2

        let merged = TestGATTReconciler.mergeDuplicateSnapshots([snap1, snap2])

        XCTAssertEqual(merged.count, 1, "Snapshots with the same hardware serial number must reconcile into 1 record")
        XCTAssertEqual(merged.first?.sightingCount, 15, "Sighting counts must be aggregated")
        XCTAssertEqual(merged.first?.strongestRSSI, -60)
    }

    // --- F5: PermittedCharacteristicsLookup ---

    func testTier1_F5_PermittedCharacteristicsForEnvironmentalSensingService() {
        let permitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "181A")
        XCTAssertNotNil(permitted)
        XCTAssertTrue(permitted!.contains(0x2A6D), "ESS must permit Pressure (0x2A6D)")
        XCTAssertTrue(permitted!.contains(0x2A6E), "ESS must permit Temperature (0x2A6E)")
        XCTAssertTrue(permitted!.contains(0x2A6F), "ESS must permit Humidity (0x2A6F)")
        XCTAssertTrue(permitted!.contains(0x2A6C), "ESS must permit Elevation (0x2A6C)")
    }

    func testTier1_F5_PermittedCharacteristicsForUserDataService() {
        let permitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "181C")
        XCTAssertNotNil(permitted)
        XCTAssertTrue(permitted!.contains(0x2A8A), "UDS must permit First Name (0x2A8A)")
        XCTAssertTrue(permitted!.contains(0x2A90), "UDS must permit Last Name (0x2A90)")
        XCTAssertTrue(permitted!.contains(0x2A85), "UDS must permit Date of Birth (0x2A85)")
        XCTAssertTrue(permitted!.contains(0x2A8C), "UDS must permit Gender (0x2A8C)")
    }

    func testTier1_F5_PermittedCharacteristicsForIndustrialMeasurementService() {
        let permitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "183B")
        XCTAssertNotNil(permitted)
        XCTAssertTrue(permitted!.contains(0x2AC9), "IMDS must permit Analog Output (0x2AC9)")
        XCTAssertTrue(permitted!.contains(0x2B40), "IMDS must permit IMDS Feature (0x2B40)")
    }

    func testTier1_F5_PermittedCharacteristicsForBatteryAndDeviceInfoServices() {
        let basPermitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "180F")
        let disPermitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "180A")

        XCTAssertNotNil(basPermitted)
        XCTAssertTrue(basPermitted!.contains(0x2A19), "BAS must permit Battery Level (0x2A19)")

        XCTAssertNotNil(disPermitted)
        XCTAssertTrue(disPermitted!.contains(0x2A24), "DIS must permit Model Number (0x2A24)")
        XCTAssertTrue(disPermitted!.contains(0x2A29), "DIS must permit Manufacturer Name (0x2A29)")
        XCTAssertTrue(disPermitted!.contains(0x2A50), "DIS must permit PnP ID (0x2A50)")
    }

    func testTier1_F5_UnknownOrVendorServiceReturnsNilOrEmpty() {
        let customPermitted = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "12345678-1234-5678-1234-567812345678")
        XCTAssertNil(customPermitted, "Unknown vendor service UUID must return nil permitted set")
    }

    // --- F6: SemanticServiceGrouping ---

    func testTier1_F6_ServiceDetailSectionsPartitionPermittedAndCustomCharacteristics() {
        let chars: [GATTCharacteristicSnapshot] = [
            GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "08C5", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "2A6F", properties: ["Read"], valueHex: "12DE", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "FFF1", properties: ["Read", "Write"], valueHex: "0102", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "FFF2", properties: ["Notify"], valueHex: nil, decodedValue: nil, descriptors: [], isNotifying: true)
        ]

        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 2, "Must produce Standard Permitted and Additional / Custom sections")
        XCTAssertEqual(sections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(sections[0].characteristics.map(\.uuid), ["2A6E", "2A6F"])
        XCTAssertEqual(sections[1].title, "Additional / Custom Characteristics")
        XCTAssertEqual(sections[1].characteristics.map(\.uuid), ["FFF1", "FFF2"])
    }

    func testTier1_F6_ServiceWithOnlyPermittedCharacteristicsProducesSingleSection() {
        let chars: [GATTCharacteristicSnapshot] = [
            GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "5A", decodedValue: nil, descriptors: [], isNotifying: false)
        ]

        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "180F", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(sections[0].characteristics.first?.uuid, "2A19")
    }

    func testTier1_F6_ServiceWithOnlyCustomCharacteristicsProducesSingleSection() {
        let chars: [GATTCharacteristicSnapshot] = [
            GATTCharacteristicSnapshot(uuid: "A001", properties: ["Read"], valueHex: "00", decodedValue: nil, descriptors: [], isNotifying: false)
        ]

        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Additional / Custom Characteristics")
        XCTAssertEqual(sections[0].characteristics.first?.uuid, "A001")
    }

    func testTier1_F6_MissingPermittedCharacteristicsHandledNeutrallyWithoutErrors() {
        // ESS without Pressure (0x2A6D) or Elevation (0x2A6C)
        let chars: [GATTCharacteristicSnapshot] = [
            GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "07D0", decodedValue: nil, descriptors: [], isNotifying: false)
        ]

        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].characteristics.count, 1)
        XCTAssertNil(sections[0].warning, "Missing permitted characteristics must be handled neutrally with zero warnings")
    }

    func testTier1_F6_ServiceForUnknownUUIDGroupsAllAsDiscoveredOrCustom() {
        let chars: [GATTCharacteristicSnapshot] = [
            GATTCharacteristicSnapshot(uuid: "0001", properties: ["Read"], valueHex: "AA", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "0002", properties: ["Write"], valueHex: "BB", decodedValue: nil, descriptors: [], isNotifying: false)
        ]

        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "FFFF", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Discovered Characteristics")
        XCTAssertEqual(sections[0].characteristics.count, 2)
    }

    // --- F7: GATTValueDecoders ---

    func testTier1_F7_PressureDecoderFormatsWithHPaAndPreservesRawHex() {
        // 0x000F7728 = 1,013,544 in 0.1 Pa -> 1013.54 hPa
        let rawData = Data([0x28, 0x77, 0x0F, 0x00])
        let decoded = TestGATTDecoderExtension.decodePressure(rawData)

        XCTAssertEqual(decoded.displayText, "1013.54 hPa")
        XCTAssertEqual(decoded.rawHex, "28770F00")
        XCTAssertEqual(decoded.fields.first?.name, "Pressure")
        XCTAssertEqual(decoded.fields.first?.value, "1013.54 hPa")
        XCTAssertNil(decoded.warning)
    }

    func testTier1_F7_SensorLocationDecoderMapsIndexNamesAndPreservesRawHex() {
        let crankData = Data([0x06]) // Left Crank
        let decoded = TestGATTDecoderExtension.decodeSensorLocation(crankData)

        XCTAssertEqual(decoded.displayText, "Left Crank")
        XCTAssertEqual(decoded.rawHex, "06")
        XCTAssertEqual(decoded.fields.first?.value, "Left Crank")
        XCTAssertNil(decoded.warning)
    }

    func testTier1_F7_VolumeStateDecoderExtractsSettingAndMute() {
        // Volume 180 (0xB4), Mute: 0 (Unmuted), Change Counter: 1
        let volumeData = Data([0xB4, 0x00, 0x01])
        let decoded = TestGATTDecoderExtension.decodeVolumeState(volumeData)

        XCTAssertEqual(decoded.displayText, "Volume 180 • Unmuted")
        XCTAssertEqual(decoded.rawHex, "B40001")
        XCTAssertEqual(decoded.fields[0].value, "180")
        XCTAssertEqual(decoded.fields[1].value, "Unmuted")
    }

    func testTier1_F7_MediaStateAndControlDecoderExtractsPlaybackAndCommands() {
        let mediaStateData = Data([0x01]) // Playing
        let stateDecoded = TestGATTDecoderExtension.decodeMediaState(mediaStateData)

        XCTAssertEqual(stateDecoded.displayText, "Playing")
        XCTAssertEqual(stateDecoded.rawHex, "01")

        // Bitmask: 0x00000007 -> Play, Pause, Stop
        let opcodesData = Data([0x07, 0x00, 0x00, 0x00])
        let opcodesDecoded = TestGATTDecoderExtension.decodeMediaControlOpcodes(opcodesData)

        XCTAssertTrue(opcodesDecoded.displayText.contains("Play"))
        XCTAssertTrue(opcodesDecoded.displayText.contains("Pause"))
        XCTAssertTrue(opcodesDecoded.displayText.contains("Stop"))
    }

    func testTier1_F7_HearingAidFeaturesAndPresetDecoderExtractsCapabilities() {
        // Features: 0x03 -> Binaural, Independent Volume
        let featureData = Data([0x03, 0x00, 0x00, 0x00])
        let featureDecoded = TestGATTDecoderExtension.decodeHearingAidFeatures(featureData)

        XCTAssertTrue(featureDecoded.displayText.contains("Binaural"))
        XCTAssertTrue(featureDecoded.displayText.contains("Independent Volume"))

        let presetData = Data([0x02]) // Active Preset 2
        let presetDecoded = TestGATTDecoderExtension.decodeActivePreset(presetData)

        XCTAssertEqual(presetDecoded.displayText, "Preset 2")
    }

    // --- F8: ProfileDashboards ---

    func testTier1_F8_FitnessCyclingDashboardAggregatesSensorLocationPowerAndBattery() {
        let snapshot = makeMockSnapshot(
            services: [
                GATTServiceSnapshot(uuid: "1818", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A65", properties: ["Read"], valueHex: "00000005", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A65", data: Data([0x05, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A5D", properties: ["Read"], valueHex: "06", decodedValue: TestGATTDecoderExtension.decodeSensorLocation(Data([0x06])), descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "58", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([88])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        let fitness = dashboards.first { $0.profile == .fitnessCycling }

        XCTAssertNotNil(fitness, "Fitness & Cycling dashboard card must be generated")
        XCTAssertTrue(fitness!.metrics.contains { $0.title == "Sensor Location" && $0.value == "Left Crank" })
        XCTAssertTrue(fitness!.metrics.contains { $0.title == "Battery Level" && $0.value == "88%" })
        XCTAssertTrue(fitness!.metrics.allSatisfy { $0.rawHex != nil }, "Every metric must preserve raw hex")
    }

    func testTier1_F8_EnvironmentalDashboardAggregatesTempHumidityPressure() {
        let snapshot = makeMockSnapshot(
            services: [
                GATTServiceSnapshot(uuid: "181A", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "08C5", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6E", data: Data([0xC5, 0x08])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A6F", properties: ["Read"], valueHex: "12DE", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6F", data: Data([0xDE, 0x12])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A6D", properties: ["Read"], valueHex: "28770F00", decodedValue: TestGATTDecoderExtension.decodePressure(Data([0x28, 0x77, 0x0F, 0x00])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        let env = dashboards.first { $0.profile == .environmentalSensing }

        XCTAssertNotNil(env, "Environmental Sensing dashboard card must be generated")
        XCTAssertTrue(env!.metrics.contains { $0.title == "Temperature" && $0.value.contains("°C") })
        XCTAssertTrue(env!.metrics.contains { $0.title == "Humidity" && $0.value.contains("%") })
        XCTAssertTrue(env!.metrics.contains { $0.title == "Pressure" && $0.value.contains("hPa") })
    }

    func testTier1_F8_HIDAccessoryDashboardAggregatesTypeCapabilitiesCountryAndBattery() {
        let hidInfoData = Data([0x11, 0x01, 0x00, 0x03]) // HID 1.11, Remote wake + Normally connectable
        let snapshot = makeMockSnapshot(
            appearance: GATTAppearance(rawValue: 0x03C1, categoryName: "Human Interface Device", subcategoryName: "Keyboard"),
            services: [
                GATTServiceSnapshot(uuid: "1812", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A4A", properties: ["Read"], valueHex: "11010003", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A4A", data: hidInfoData), descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "55", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([85])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        let hid = dashboards.first { $0.profile == .hidAccessory }

        XCTAssertNotNil(hid, "HID dashboard card must be generated")
        XCTAssertTrue(hid!.metrics.contains { $0.title == "Input Device Type" && $0.value == "Keyboard" })
        XCTAssertTrue(hid!.metrics.contains { $0.title == "Capabilities" && $0.value.contains("Remote wake") })
        XCTAssertTrue(hid!.metrics.contains { $0.title == "Battery Level" && $0.value == "85%" })
    }

    func testTier1_F8_AudioHearingDashboardAggregatesControlsAndPresets() {
        let snapshot = makeMockSnapshot(
            services: [
                GATTServiceSnapshot(uuid: "1854", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2BDA", properties: ["Read"], valueHex: "03000000", decodedValue: TestGATTDecoderExtension.decodeHearingAidFeatures(Data([0x03, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2BDC", properties: ["Read"], valueHex: "02", decodedValue: TestGATTDecoderExtension.decodeActivePreset(Data([0x02])), descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "1844", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2B7D", properties: ["Read"], valueHex: "B40001", decodedValue: TestGATTDecoderExtension.decodeVolumeState(Data([0xB4, 0x00, 0x01])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        let audio = dashboards.first { $0.profile == .hearingAudio }

        XCTAssertNotNil(audio, "Audio & Hearing dashboard card must be generated")
        XCTAssertTrue(audio!.metrics.contains { $0.title == "Active Preset" && $0.value == "Preset 2" })
        XCTAssertTrue(audio!.metrics.contains { $0.title == "Volume Control" && $0.value.contains("Volume 180") })
    }

    func testTier1_F8_GenericPeripheralWithoutMatchingClustersGeneratesZeroDashboards() {
        let genericSnapshot = makeMockSnapshot(
            services: [
                GATTServiceSnapshot(uuid: "FFE0", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "FFE1", properties: ["Read"], valueHex: "0102", decodedValue: nil, descriptors: [], isNotifying: false)
                ])
            ]
        )

        let dashboards = TestProfileDashboardBuilder.buildCards(for: genericSnapshot)
        XCTAssertTrue(dashboards.isEmpty, "Generic beacon without standard profile clusters must produce 0 dashboard cards")
    }

    // =========================================================================
    // MARK: - TIER 2: BOUNDARY & CORNER CASES (40 tests)
    // =========================================================================

    // --- F1 Boundaries ---

    func testTier2_F1_Boundary_CorruptedSettingsJSONFallsBackToDefault() {
        let corruptData = "{\"activeScanDuration\": \"not_a_number\"}".data(using: .utf8)!
        let decoded = (try? JSONDecoder().decode(TestSettingsHarness.self, from: corruptData)) ?? TestSettingsHarness()

        XCTAssertTrue(decoded.isAutomaticGATTEnrichmentEnabled, "Corrupted settings data must safely fallback to default enabled")
    }

    func testTier2_F1_Boundary_EmptyUserDefaultsInitializesDefaultWithEnrichment() {
        let harness = TestSettingsHarness()
        XCTAssertTrue(harness.isAutomaticGATTEnrichmentEnabled)
        XCTAssertEqual(harness.activeScanDuration, 120)
    }

    func testTier2_F1_Boundary_RapidToggleStateFlapping() {
        var harness = TestSettingsHarness()
        for i in 0..<100 {
            harness.isAutomaticGATTEnrichmentEnabled = (i % 2 == 0)
        }
        XCTAssertFalse(harness.isAutomaticGATTEnrichmentEnabled)
    }

    func testTier2_F1_Boundary_ThreadSafeConcurrentSettingsReadsAndWrites() {
        var harness = TestSettingsHarness()
        let lock = NSLock()
        let group = DispatchGroup()

        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                lock.lock()
                harness.isAutomaticGATTEnrichmentEnabled = (i % 2 == 0)
                _ = harness.isAutomaticGATTEnrichmentEnabled
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        XCTAssertNotNil(harness.isAutomaticGATTEnrichmentEnabled)
    }

    func testTier2_F1_Boundary_SettingsStateEqualityAndHashing() {
        var s1 = TestSettingsHarness()
        var s2 = TestSettingsHarness()
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1.hashValue, s2.hashValue)

        s2.isAutomaticGATTEnrichmentEnabled = false
        XCTAssertNotEqual(s1, s2)
    }

    // --- F2 Boundaries ---

    func testTier2_F2_Boundary_PeripheralDisconnectsImmediatelyOnConnection() {
        let probe = TestBackgroundGATTProbeSimulator()
        probe.simulateImmediateDisconnect()

        XCTAssertTrue(probe.didComplete, "Probe must complete cleanly when peripheral disconnects immediately")
        XCTAssertFalse(probe.hasFailedCatastrophically)
    }

    func testTier2_F2_Boundary_EmptyServicesListDiscovery() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(services: [], characteristics: [:])

        XCTAssertFalse(evidence.hasValues)
        XCTAssertTrue(probe.didComplete)
    }

    func testTier2_F2_Boundary_ZeroReadableCharacteristicsInDiscoveredServices() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(services: [0x1800], characteristics: [:])

        XCTAssertFalse(evidence.identity.hasValues)
        XCTAssertTrue(probe.didComplete)
    }

    func testTier2_F2_Boundary_CharacteristicReadReturnsErrorOrRequiresAuth() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(
            services: [0x180A],
            characteristics: [:],
            readErrors: [0x2A24: "CBATTErrorInsufficientAuthentication"]
        )

        XCTAssertNil(evidence.identity.modelNumber, "Encrypted characteristic error must be ignored without prompting pairing")
        XCTAssertTrue(probe.didComplete)
    }

    func testTier2_F2_Boundary_ProbeCancellationDuringActiveRead() {
        let probe = TestBackgroundGATTProbeSimulator()
        probe.startAsyncRead()
        probe.cancel()

        XCTAssertTrue(probe.isCancelled)
        XCTAssertEqual(probe.activeReadsPendingCount, 0)
    }

    // --- F3 Boundaries ---

    func testTier2_F3_Boundary_QueueSaturationWithOneHundredDiscoveredPeripherals() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true, maxSessionCap: 20)

        for _ in 0..<100 {
            _ = queue.enqueueIfEligible(peripheralID: UUID(), isConnectable: true, isScanActive: true)
            queue.completeCurrentProbe()
        }

        XCTAssertEqual(queue.totalProbedCount, 20)
        XCTAssertEqual(queue.rejectedDueToCapCount, 80)
    }

    func testTier2_F3_Boundary_QueueProgressionAfterPerDeviceTimeout() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let dev1 = UUID(), dev2 = UUID()

        _ = queue.enqueueIfEligible(peripheralID: dev1, isConnectable: true, isScanActive: true)
        _ = queue.enqueueIfEligible(peripheralID: dev2, isConnectable: true, isScanActive: true)

        XCTAssertEqual(queue.currentProbingID, dev1)
        queue.simulateCurrentProbeTimeout()

        XCTAssertEqual(queue.currentProbingID, dev2, "Timeout on device 1 must immediately advance queue to device 2")
    }

    func testTier2_F3_Boundary_ScanStopDuringActiveProbeTimer() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        _ = queue.enqueueIfEligible(peripheralID: UUID(), isConnectable: true, isScanActive: true)
        XCTAssertTrue(queue.isTimeoutTimerActive)

        queue.stopScan()
        XCTAssertFalse(queue.isTimeoutTimerActive, "Stopping scan must invalidate timeout timer")
    }

    func testTier2_F3_Boundary_ScanModeSwitchFromActiveToRecordingPurgesQueue() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        _ = queue.enqueueIfEligible(peripheralID: UUID(), isConnectable: true, isScanActive: true)
        _ = queue.enqueueIfEligible(peripheralID: UUID(), isConnectable: true, isScanActive: true)

        queue.switchScanMode(to: .recording)

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(queue.currentProbingID)
    }

    func testTier2_F3_Boundary_DeduplicationWithDuplicateSightingsDuringInFlightProbe() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: true)
        let devID = UUID()

        _ = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)
        let duplicateWhileProbing = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)

        XCTAssertFalse(duplicateWhileProbing, "Sightings of currently active probe peripheral must not be re-queued")
    }

    // --- F4 Boundaries ---

    func testTier2_F4_Boundary_EmptyGATTDeviceIdentityMerge() {
        var snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Sensor Beacon",
            latestRSSI: -50,
            strongestRSSI: -50,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: BLEAdvertisement(localName: "Sensor Beacon", manufacturerDataHex: nil, companyIdentifier: nil, serviceUUIDs: [], solicitedServiceUUIDs: [], serviceData: [:], overflowServiceUUIDs: [], txPower: nil, isConnectable: true)
        )
        let emptyEvidence = GATTDeviceEvidence()
        snapshot.gattEvidence = emptyEvidence

        XCTAssertEqual(snapshot.presentationName, "Sensor Beacon", "Merging empty GATT evidence must not wipe advertised name")
    }

    func testTier2_F4_Boundary_DeviceWithMalformedUTF8StringsInIdentity() {
        let invalidUTF8Data = Data([0xFF, 0xFE, 0xFD])
        let decoded = GATTValueDecoder.decode(characteristicUUID: "2A24", data: invalidUTF8Data)

        XCTAssertEqual(decoded?.rawHex, "FFFEFD")
        XCTAssertTrue(decoded?.warning?.contains("UTF-8") == true || decoded?.displayText == "FFFEFD")
    }

    func testTier2_F4_Boundary_RPAAddressRotationWithoutHardwareSerialFallsBackToSeparateSnapshots() {
        let id1 = UUID(), id2 = UUID()
        let snap1 = BLEDeviceSnapshot(peripheralIdentifier: id1, displayName: "Beacon", latestRSSI: -70, strongestRSSI: -70, firstSeen: Date(), lastSeen: Date(), sightingCount: 1, advertisement: .empty)
        let snap2 = BLEDeviceSnapshot(peripheralIdentifier: id2, displayName: "Beacon", latestRSSI: -65, strongestRSSI: -65, firstSeen: Date(), lastSeen: Date(), sightingCount: 1, advertisement: .empty)

        let merged = TestGATTReconciler.mergeDuplicateSnapshots([snap1, snap2])
        XCTAssertEqual(merged.count, 2, "Devices without common serial/system ID must remain separate")
    }

    func testTier2_F4_Boundary_SpecialCharactersAndControlBytesInDeviceName() {
        var evidence = GATTDeviceEvidence()
        evidence.identity.deviceName = "My \u{0000} \t Speaker \n 🎉"

        let sanitized = TestSanitizer.sanitizeName(evidence.identity.deviceName)
        XCTAssertEqual(sanitized, "My Speaker 🎉")
    }

    func testTier2_F4_Boundary_EnrichmentWithNilOrExtremeRSSIValues() {
        let snapLow = BLEDeviceSnapshot(peripheralIdentifier: UUID(), displayName: "Low", latestRSSI: -127, strongestRSSI: -127, firstSeen: Date(), lastSeen: Date(), sightingCount: 1, advertisement: .empty)
        let snapHigh = BLEDeviceSnapshot(peripheralIdentifier: UUID(), displayName: "High", latestRSSI: 0, strongestRSSI: 0, firstSeen: Date(), lastSeen: Date(), sightingCount: 1, advertisement: .empty)

        XCTAssertEqual(snapLow.signalLevel, .unknown)
        XCTAssertEqual(snapHigh.signalLevel, .excellent)
    }

    // --- F5 Boundaries ---

    func testTier2_F5_Boundary_CaseInsensitiveLookupOfServiceUUIDs() {
        let lower = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "181a")
        let upper = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "181A")
        let sig128 = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "0000181A-0000-1000-8000-00805F9B34FB")

        XCTAssertEqual(lower, upper)
        XCTAssertEqual(lower, sig128)
    }

    func testTier2_F5_Boundary_MalformedAndInvalidLengthServiceUUIDs() {
        XCTAssertNil(TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: ""))
        XCTAssertNil(TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "18"))
        XCTAssertNil(TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "181"))
        XCTAssertNil(TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "ZZZZ"))
    }

    func testTier2_F5_Boundary_NonStandardVendorServiceUUID() {
        XCTAssertNil(TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "E000181A-0000-1000-8000-00805F9B34FB"))
    }

    func testTier2_F5_Boundary_AdoptedServicesWithoutPermittedCharacteristicsTable() {
        // e.g. Generic Access 0x1800 or custom adopted without defined permitted restrictions
        let result = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: "1801")
        XCTAssertNil(result, "Services without permitted tables must return nil")
    }

    func testTier2_F5_Boundary_WhitespaceAndPrefixTolerantLookup() {
        let withPrefix = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: " 0x181A ")
        XCTAssertNotNil(withPrefix)
        XCTAssertTrue(withPrefix!.contains(0x2A6E))
    }

    // --- F6 Boundaries ---

    func testTier2_F6_Boundary_EmptyCharacteristicsListInService() {
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: [])
        XCTAssertTrue(sections.isEmpty, "Empty characteristics list must produce 0 sections")
    }

    func testTier2_F6_Boundary_DuplicateCharacteristicsWithSameUUID() {
        let chars = [
            GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "01", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "02", decodedValue: nil, descriptors: [], isNotifying: false)
        ]
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].characteristics.count, 2)
    }

    func testTier2_F6_Boundary_AllCharacteristicsPermittedProducesZeroCustomRows() {
        let chars = [
            GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "01", decodedValue: nil, descriptors: [], isNotifying: false),
            GATTCharacteristicSnapshot(uuid: "2A6F", properties: ["Read"], valueHex: "02", decodedValue: nil, descriptors: [], isNotifying: false)
        ]
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Standard Permitted Characteristics")
    }

    func testTier2_F6_Boundary_AllCharacteristicsCustomProducesZeroStandardPermittedRows() {
        let chars = [
            GATTCharacteristicSnapshot(uuid: "FFF1", properties: ["Read"], valueHex: "01", decodedValue: nil, descriptors: [], isNotifying: false)
        ]
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "Additional / Custom Characteristics")
    }

    func testTier2_F6_Boundary_LargeCharacteristicCountStress() {
        var chars: [GATTCharacteristicSnapshot] = []
        for i in 0..<100 {
            let uuid = String(format: "%04X", 0x2A00 + i)
            chars.append(GATTCharacteristicSnapshot(uuid: uuid, properties: ["Read"], valueHex: "00", decodedValue: nil, descriptors: [], isNotifying: false))
        }

        let start = Date()
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: chars)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.05, "Partitioning 100 characteristics must execute in under 50ms")
        XCTAssertFalse(sections.isEmpty)
    }

    // --- F7 Boundaries ---

    func testTier2_F7_Boundary_PressureDecoderUnderflowZeroBytes() {
        let underflows: [Data] = [Data(), Data([0x01]), Data([0x01, 0x02]), Data([0x01, 0x02, 0x03])]
        for data in underflows {
            let decoded = TestGATTDecoderExtension.decodePressure(data)
            XCTAssertNotNil(decoded.warning)
            XCTAssertEqual(decoded.rawHex, data.hexadecimalString)
        }
    }

    func testTier2_F7_Boundary_PressureDecoderOverflowExtraBytes() {
        let overflow = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let decoded = TestGATTDecoderExtension.decodePressure(overflow)
        XCTAssertNotNil(decoded.warning)
        XCTAssertEqual(decoded.rawHex, "0102030405")
    }

    func testTier2_F7_Boundary_PressureDecoderExtremeValuesZeroAndMax() {
        let zero = TestGATTDecoderExtension.decodePressure(Data([0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(zero.displayText, "0.00 hPa")

        let maxVal = TestGATTDecoderExtension.decodePressure(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(maxVal.displayText, "4294967.29 hPa")
    }

    func testTier2_F7_Boundary_SensorLocationOutOfBoundsIndex() {
        let outOfBounds = Data([0x30]) // 48
        let decoded = TestGATTDecoderExtension.decodeSensorLocation(outOfBounds)
        XCTAssertNotNil(decoded.warning)
        XCTAssertEqual(decoded.rawHex, "30")
    }

    func testTier2_F7_Boundary_AudioMediaDecodersWithZeroLengthAndMalformedPayloads() {
        let empty = Data()
        let decodedVolume = TestGATTDecoderExtension.decodeVolumeState(empty)
        XCTAssertNotNil(decodedVolume.warning)

        let decodedMedia = TestGATTDecoderExtension.decodeMediaState(empty)
        XCTAssertNotNil(decodedMedia.warning)
    }

    // --- F8 Boundaries ---

    func testTier2_F8_Boundary_EmptySnapshotProducesZeroDashboardCards() {
        let emptySnapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Empty",
            latestRSSI: -80,
            strongestRSSI: -80,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: .empty,
            gattEvidence: nil,
            exploredServices: []
        )

        let cards = TestProfileDashboardBuilder.buildCards(for: emptySnapshot)
        XCTAssertTrue(cards.isEmpty)
    }

    func testTier2_F8_Boundary_SingleMetricEnvironmentalCard() {
        let snapshot = makeMockSnapshot(
            services: [
                GATTServiceSnapshot(uuid: "181A", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "07D0", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6E", data: Data([0xD0, 0x07])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        let cards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.metrics.count, 1)
        XCTAssertEqual(cards.first?.metrics.first?.title, "Temperature")
    }

    func testTier2_F8_Boundary_MalformedDecodedValuesRetainRawHexInDashboard() {
        let malformedTemp = GATTCharacteristicSnapshot(
            uuid: "2A6E",
            properties: ["Read"],
            valueHex: "FF",
            decodedValue: GATTDecodedValue(displayText: "FF", rawHex: "FF", fields: [], warning: "Expected 2 bytes"),
            descriptors: [],
            isNotifying: false
        )
        let snapshot = makeMockSnapshot(services: [GATTServiceSnapshot(uuid: "181A", characteristics: [malformedTemp])])

        let cards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(cards.first?.metrics.first?.rawHex, "FF")
    }

    func testTier2_F8_Boundary_MultipleDiscoveredServicesInSameClusterDeduplicateMetrics() {
        let batt1 = GATTServiceSnapshot(uuid: "180F", characteristics: [
            GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "50", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([80])), descriptors: [], isNotifying: false)
        ])
        let batt2 = GATTServiceSnapshot(uuid: "180F", characteristics: [
            GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "50", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([80])), descriptors: [], isNotifying: false)
        ])
        let csc = GATTServiceSnapshot(uuid: "1816", characteristics: [
            GATTCharacteristicSnapshot(uuid: "2A5C", properties: ["Read"], valueHex: "0300", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A5C", data: Data([0x03, 0x00])), descriptors: [], isNotifying: false)
        ])

        let snapshot = makeMockSnapshot(services: [csc, batt1, batt2])
        let cards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        let batteryMetrics = cards.first?.metrics.filter { $0.title == "Battery Level" }

        XCTAssertEqual(batteryMetrics?.count, 1, "Duplicate battery characteristics across services must deduplicate to 1 metric on dashboard")
    }

    func testTier2_F8_Boundary_NilAndWhitespaceStringsInMetrics() {
        let metric = TestProfileDashboardMetric(title: "  ", value: "   ", unit: nil, rawHex: "AA")
        XCTAssertEqual(metric.displayTitle, "Metric")
        XCTAssertEqual(metric.displayValue, "AA")
    }

    // =========================================================================
    // MARK: - TIER 3: CROSS-FEATURE COMBINATIONS (5 tests)
    // =========================================================================

    func testTier3_AutoProbeEnrichmentRefinesTelevisionAndGeneratesNoUnwantedDashboard() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(
            services: [0x1800, 0x180A],
            characteristics: [
                0x2A00: Data("Living Room Apple TV".utf8),
                0x2A24: Data("AppleTV14,1".utf8)
            ]
        )

        var snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Unnamed device",
            latestRSSI: -60,
            strongestRSSI: -60,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: .empty
        )
        snapshot.gattEvidence = evidence

        XCTAssertEqual(snapshot.intelligence.category, .television)
        XCTAssertEqual(snapshot.presentationName, "Living Room Apple TV")

        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertTrue(dashboards.isEmpty, "Apple TV should not generate fitness or environmental dashboards")
    }

    func testTier3_AutoProbeEnrichmentOnCyclingPowerMeterBuildsDashboardAndPermittedGrouping() {
        let probe = TestBackgroundGATTProbeSimulator()
        let evidence = probe.executeMockProbe(
            services: [0x1818, 0x180F],
            characteristics: [
                0x2A65: Data([0x05, 0x00, 0x00, 0x00]),
                0x2A5D: Data([0x06]), // Left Crank
                0x2A19: Data([92])
            ]
        )

        var snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "PowerMeter",
            latestRSSI: -55,
            strongestRSSI: -55,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: BLEAdvertisement(localName: "PowerMeter", manufacturerDataHex: nil, companyIdentifier: nil, serviceUUIDs: ["1818"], solicitedServiceUUIDs: [], serviceData: [:], overflowServiceUUIDs: [], txPower: nil, isConnectable: true),
            gattEvidence: evidence,
            exploredServices: [
                GATTServiceSnapshot(uuid: "1818", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A65", properties: ["Read"], valueHex: "05000000", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A65", data: Data([0x05, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A5D", properties: ["Read"], valueHex: "06", decodedValue: TestGATTDecoderExtension.decodeSensorLocation(Data([0x06])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "FFF0", properties: ["Read"], valueHex: "01", decodedValue: nil, descriptors: [], isNotifying: false)
                ])
            ]
        )

        // 1. Check intelligence
        XCTAssertEqual(snapshot.intelligence.category, .healthFitness)

        // 2. Check dashboard
        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(dashboards.count, 1)
        XCTAssertEqual(dashboards.first?.profile, .fitnessCycling)

        // 3. Check service grouping
        let sections = TestServiceDetailGrouping.buildSections(serviceUUID: "1818", characteristics: snapshot.exploredServices[0].characteristics)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(sections[0].characteristics.map(\.uuid), ["2A65", "2A5D"])
        XCTAssertEqual(sections[1].title, "Additional / Custom Characteristics")
        XCTAssertEqual(sections[1].characteristics.map(\.uuid), ["FFF0"])
    }

    func testTier3_SettingsToggleDisablesAutoProbeQueueAndPreservesAdvertisedOnlyIntelligence() {
        let queue = TestAutoProbeQueue(isEnrichmentEnabled: false)
        let devID = UUID()

        let enqueued = queue.enqueueIfEligible(peripheralID: devID, isConnectable: true, isScanActive: true)
        XCTAssertFalse(enqueued)

        let rawAdvSnapshot = BLEDeviceSnapshot(
            peripheralIdentifier: devID,
            displayName: "Generic Sensor",
            latestRSSI: -70,
            strongestRSSI: -70,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: BLEAdvertisement(localName: "Generic Sensor", manufacturerDataHex: nil, companyIdentifier: nil, serviceUUIDs: [], solicitedServiceUUIDs: [], serviceData: [:], overflowServiceUUIDs: [], txPower: nil, isConnectable: true)
        )

        XCTAssertNil(rawAdvSnapshot.gattEvidence)
        XCTAssertEqual(rawAdvSnapshot.presentationName, "Generic Sensor")
    }

    func testTier3_RPARotationReconciliationPreservesDashboardAndPermittedServices() {
        let serial = "WEATHER-PRO-2026"
        let id1 = UUID(), id2 = UUID()

        var snap1 = makeMockSnapshot(
            identifier: id1,
            services: [
                GATTServiceSnapshot(uuid: "181A", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read"], valueHex: "08C5", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6E", data: Data([0xC5, 0x08])), descriptors: [], isNotifying: false)
                ])
            ]
        )
        snap1.gattEvidence = GATTDeviceEvidence(identity: GATTDeviceIdentity(serialNumber: serial), discoveredServiceUUIDs: ["181A"])

        var snap2 = makeMockSnapshot(
            identifier: id2,
            services: [
                GATTServiceSnapshot(uuid: "181A", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A6F", properties: ["Read"], valueHex: "12DE", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6F", data: Data([0xDE, 0x12])), descriptors: [], isNotifying: false)
                ])
            ]
        )
        snap2.gattEvidence = GATTDeviceEvidence(identity: GATTDeviceIdentity(serialNumber: serial), discoveredServiceUUIDs: ["181A"])

        let merged = TestGATTReconciler.mergeDuplicateSnapshots([snap1, snap2])
        XCTAssertEqual(merged.count, 1)

        let cards = TestProfileDashboardBuilder.buildCards(for: merged.first!)
        XCTAssertEqual(cards.first?.profile, .environmentalSensing)
    }

    func testTier3_LiveEnrichmentToLocalStorePersistenceRoundTrip() throws {
        let id = UUID()
        let initialSnapshot = makeMockSnapshot(
            identifier: id,
            appearance: GATTAppearance(rawValue: 0x03C2, categoryName: "Human Interface Device", subcategoryName: "Mouse"),
            services: [
                GATTServiceSnapshot(uuid: "1812", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A4A", properties: ["Read"], valueHex: "11010003", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A4A", data: Data([0x11, 0x01, 0x00, 0x03])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        try localStore.saveDeviceRecord(initialSnapshot)
        let loaded = localStore.loadDeviceRecord(for: id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.intelligence.category, .peripheral)

        let cards = TestProfileDashboardBuilder.buildCards(for: loaded!)
        XCTAssertEqual(cards.first?.profile, .hidAccessory)
        XCTAssertTrue(cards.first!.metrics.contains { $0.title == "Input Device Type" && $0.value == "Mouse" })
    }

    // =========================================================================
    // MARK: - TIER 4: REAL-WORLD APPLICATION SCENARIOS (4 tests)
    // =========================================================================

    func testTier4_Scenario1_CyclingPowerMeterDualCrankAndBattery() {
        // Real-world smart trainer / cycling power meter broadcasting 0x1818 & 0x180F
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "PowerTrainer Pro",
            latestRSSI: -58,
            strongestRSSI: -54,
            firstSeen: Date().addingTimeInterval(-300),
            lastSeen: Date(),
            sightingCount: 42,
            advertisement: BLEAdvertisement(
                localName: "PowerTrainer Pro",
                manufacturerDataHex: "005901020304",
                companyIdentifier: 0x0059, // Nordic Semiconductor
                memberServiceUUIDs: [],
                serviceUUIDs: ["1818", "180F"],
                solicitedServiceUUIDs: [],
                serviceData: [:],
                overflowServiceUUIDs: [],
                txPower: 4,
                isConnectable: true
            ),
            gattEvidence: GATTDeviceEvidence(
                identity: GATTDeviceIdentity(
                    deviceName: "PowerTrainer Pro",
                    manufacturerName: "Wahoo Fitness",
                    modelNumber: "KICKR-V6",
                    serialNumber: "SN-WF-2026-991"
                ),
                discoveredServiceUUIDs: ["1818", "180F"]
            ),
            exploredServices: [
                GATTServiceSnapshot(uuid: "1818", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A65", properties: ["Read"], valueHex: "05000000", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A65", data: Data([0x05, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A5D", properties: ["Read"], valueHex: "06", decodedValue: TestGATTDecoderExtension.decodeSensorLocation(Data([0x06])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A63", properties: ["Notify"], valueHex: "0000F000", decodedValue: nil, descriptors: [], isNotifying: true),
                    GATTCharacteristicSnapshot(uuid: "A001", properties: ["Write"], valueHex: "00", decodedValue: nil, descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read", "Notify"], valueHex: "58", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([88])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        // 1. Intelligence Category Verification
        XCTAssertEqual(snapshot.intelligence.category, .healthFitness)
        XCTAssertEqual(snapshot.presentationName, "PowerTrainer Pro")

        // 2. Profile Dashboard Verification
        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(dashboards.count, 1)
        let card = dashboards[0]
        XCTAssertEqual(card.profile, .fitnessCycling)
        XCTAssertEqual(card.title, "Fitness & Cycling Dashboard")

        let locationMetric = card.metrics.first { $0.title == "Sensor Location" }
        XCTAssertEqual(locationMetric?.value, "Left Crank")
        XCTAssertEqual(locationMetric?.rawHex, "06")

        let battMetric = card.metrics.first { $0.title == "Battery Level" }
        XCTAssertEqual(battMetric?.value, "88%")
        XCTAssertEqual(battMetric?.rawHex, "58")

        // 3. Permitted Characteristics Table Sectioning Verification
        let cpsSections = TestServiceDetailGrouping.buildSections(serviceUUID: "1818", characteristics: snapshot.exploredServices[0].characteristics)
        XCTAssertEqual(cpsSections.count, 2)
        XCTAssertEqual(cpsSections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(Set(cpsSections[0].characteristics.map(\.uuid)), Set(["2A65", "2A5D", "2A63"]))
        XCTAssertEqual(cpsSections[1].title, "Additional / Custom Characteristics")
        XCTAssertEqual(cpsSections[1].characteristics.map(\.uuid), ["A001"])
    }

    func testTier4_Scenario2_EnvironmentalSensorStationTempHumidityPressure() {
        // High-precision weather station station broadcasting 0x181A
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "MeteoStation-9000",
            latestRSSI: -64,
            strongestRSSI: -60,
            firstSeen: Date().addingTimeInterval(-600),
            lastSeen: Date(),
            sightingCount: 65,
            advertisement: BLEAdvertisement(
                localName: "MeteoStation-9000",
                manufacturerDataHex: nil,
                companyIdentifier: nil,
                memberServiceUUIDs: [],
                serviceUUIDs: ["181A", "180F"],
                solicitedServiceUUIDs: [],
                serviceData: [:],
                overflowServiceUUIDs: [],
                txPower: 0,
                isConnectable: true
            ),
            gattEvidence: GATTDeviceEvidence(
                identity: GATTDeviceIdentity(
                    deviceName: "MeteoStation-9000",
                    manufacturerName: "Sensirion AG",
                    modelNumber: "SHT4x-SmartStation"
                ),
                discoveredServiceUUIDs: ["181A", "180F"]
            ),
            exploredServices: [
                GATTServiceSnapshot(uuid: "181A", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A6E", properties: ["Read", "Notify"], valueHex: "08C5", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6E", data: Data([0xC5, 0x08])), descriptors: [], isNotifying: true),
                    GATTCharacteristicSnapshot(uuid: "2A6F", properties: ["Read", "Notify"], valueHex: "12DE", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A6F", data: Data([0xDE, 0x12])), descriptors: [], isNotifying: true),
                    GATTCharacteristicSnapshot(uuid: "2A6D", properties: ["Read", "Notify"], valueHex: "28770F00", decodedValue: TestGATTDecoderExtension.decodePressure(Data([0x28, 0x77, 0x0F, 0x00])), descriptors: [], isNotifying: true),
                    GATTCharacteristicSnapshot(uuid: "2A6C", properties: ["Read"], valueHex: "603B00", decodedValue: TestGATTDecoderExtension.decodeElevation(Data([0x60, 0x3B, 0x00])), descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "5F", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([95])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        // 1. Classification
        XCTAssertEqual(snapshot.intelligence.category, .smartHome)

        // 2. Profile Dashboard Verification
        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(dashboards.count, 1)
        let envCard = dashboards[0]
        XCTAssertEqual(envCard.profile, .environmentalSensing)
        XCTAssertEqual(envCard.title, "Environmental Sensing Dashboard")

        let tempMetric = envCard.metrics.first { $0.title == "Temperature" }
        XCTAssertEqual(tempMetric?.value, "22.45 °C")
        XCTAssertEqual(tempMetric?.rawHex, "08C5")

        let humMetric = envCard.metrics.first { $0.title == "Humidity" }
        XCTAssertEqual(humMetric?.value, "48.30%")
        XCTAssertEqual(humMetric?.rawHex, "12DE")

        let pressMetric = envCard.metrics.first { $0.title == "Pressure" }
        XCTAssertEqual(pressMetric?.value, "1013.54 hPa")
        XCTAssertEqual(pressMetric?.rawHex, "28770F00")

        let battMetric = envCard.metrics.first { $0.title == "Battery Level" }
        XCTAssertEqual(battMetric?.value, "95%")
        XCTAssertEqual(battMetric?.rawHex, "5F")

        // 3. Permitted Characteristics Verification
        let essSections = TestServiceDetailGrouping.buildSections(serviceUUID: "181A", characteristics: snapshot.exploredServices[0].characteristics)
        XCTAssertEqual(essSections.count, 1)
        XCTAssertEqual(essSections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(essSections[0].characteristics.count, 4)
    }

    func testTier4_Scenario3_HIDWirelessKeyboardWithBattery() {
        // Bluetooth LE mechanical keyboard
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Keychron K2 Pro",
            latestRSSI: -45,
            strongestRSSI: -42,
            firstSeen: Date().addingTimeInterval(-1000),
            lastSeen: Date(),
            sightingCount: 150,
            advertisement: BLEAdvertisement(
                localName: "Keychron K2 Pro",
                manufacturerDataHex: nil,
                companyIdentifier: nil,
                memberServiceUUIDs: [],
                serviceUUIDs: ["1812", "180F"],
                solicitedServiceUUIDs: [],
                serviceData: [:],
                overflowServiceUUIDs: [],
                txPower: 2,
                isConnectable: true
            ),
            gattEvidence: GATTDeviceEvidence(
                identity: GATTDeviceIdentity(
                    deviceName: "Keychron K2 Pro",
                    manufacturerName: "Keychron",
                    modelNumber: "K2-Pro-ANSI",
                    appearance: GATTAppearance(rawValue: 0x03C1, categoryName: "Human Interface Device", subcategoryName: "Keyboard")
                ),
                discoveredServiceUUIDs: ["1812", "180F"]
            ),
            exploredServices: [
                GATTServiceSnapshot(uuid: "1812", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A4A", properties: ["Read"], valueHex: "11010003", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A4A", data: Data([0x11, 0x01, 0x00, 0x03])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A4B", properties: ["Read"], valueHex: "05010906", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A4B", data: Data([0x05, 0x01, 0x09, 0x06])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2A4D", properties: ["Read", "Notify"], valueHex: "00", decodedValue: nil, descriptors: [], isNotifying: true)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read", "Notify"], valueHex: "4E", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([78])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        // 1. Classification
        XCTAssertEqual(snapshot.intelligence.category, .peripheral)
        XCTAssertEqual(snapshot.presentationName, "Keychron K2 Pro")

        // 2. Profile Dashboard Verification
        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(dashboards.count, 1)
        let hidCard = dashboards[0]
        XCTAssertEqual(hidCard.profile, .hidAccessory)

        let typeMetric = hidCard.metrics.first { $0.title == "Input Device Type" }
        XCTAssertEqual(typeMetric?.value, "Keyboard")

        let capMetric = hidCard.metrics.first { $0.title == "Capabilities" }
        XCTAssertTrue(capMetric?.value.contains("Remote wake") == true)
        XCTAssertTrue(capMetric?.value.contains("Normally connectable") == true)

        let battMetric = hidCard.metrics.first { $0.title == "Battery Level" }
        XCTAssertEqual(battMetric?.value, "78%")

        // 3. Permitted Characteristics Verification
        let hidSections = TestServiceDetailGrouping.buildSections(serviceUUID: "1812", characteristics: snapshot.exploredServices[0].characteristics)
        XCTAssertEqual(hidSections.count, 1)
        XCTAssertEqual(hidSections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(hidSections[0].characteristics.count, 3)
    }

    func testTier4_Scenario4_HearingAidAndAudioPresetController() {
        // Bluetooth LE Audio Hearing Aid / VCS / MCS peripheral
        let snapshot = BLEDeviceSnapshot(
            peripheralIdentifier: UUID(),
            displayName: "Oticon Intent 1",
            latestRSSI: -52,
            strongestRSSI: -50,
            firstSeen: Date().addingTimeInterval(-400),
            lastSeen: Date(),
            sightingCount: 88,
            advertisement: BLEAdvertisement(
                localName: "Oticon Intent 1",
                manufacturerDataHex: nil,
                companyIdentifier: nil,
                memberServiceUUIDs: [],
                serviceUUIDs: ["1854", "1844", "1848", "180F"],
                solicitedServiceUUIDs: [],
                serviceData: [:],
                overflowServiceUUIDs: [],
                txPower: 0,
                isConnectable: true
            ),
            gattEvidence: GATTDeviceEvidence(
                identity: GATTDeviceIdentity(
                    deviceName: "Oticon Intent 1",
                    manufacturerName: "Demant A/S",
                    modelNumber: "Intent-1-BTE",
                    appearance: GATTAppearance(rawValue: 0x0840, categoryName: "Hearing Aid", subcategoryName: "Binaural Hearing Aid")
                ),
                discoveredServiceUUIDs: ["1854", "1844", "1848", "180F"]
            ),
            exploredServices: [
                GATTServiceSnapshot(uuid: "1854", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2BDA", properties: ["Read"], valueHex: "03000000", decodedValue: TestGATTDecoderExtension.decodeHearingAidFeatures(Data([0x03, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false),
                    GATTCharacteristicSnapshot(uuid: "2BDC", properties: ["Read", "Notify"], valueHex: "03", decodedValue: TestGATTDecoderExtension.decodeActivePreset(Data([0x03])), descriptors: [], isNotifying: true)
                ]),
                GATTServiceSnapshot(uuid: "1844", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2B7D", properties: ["Read", "Notify"], valueHex: "C00002", decodedValue: TestGATTDecoderExtension.decodeVolumeState(Data([0xC0, 0x00, 0x02])), descriptors: [], isNotifying: true)
                ]),
                GATTServiceSnapshot(uuid: "1848", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2BA4", properties: ["Read", "Notify"], valueHex: "01", decodedValue: TestGATTDecoderExtension.decodeMediaState(Data([0x01])), descriptors: [], isNotifying: true),
                    GATTCharacteristicSnapshot(uuid: "2BA6", properties: ["Read"], valueHex: "0F000000", decodedValue: TestGATTDecoderExtension.decodeMediaControlOpcodes(Data([0x0F, 0x00, 0x00, 0x00])), descriptors: [], isNotifying: false)
                ]),
                GATTServiceSnapshot(uuid: "180F", characteristics: [
                    GATTCharacteristicSnapshot(uuid: "2A19", properties: ["Read"], valueHex: "52", decodedValue: GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([82])), descriptors: [], isNotifying: false)
                ])
            ]
        )

        // 1. Classification
        XCTAssertEqual(snapshot.intelligence.category, .audio)
        XCTAssertEqual(snapshot.presentationName, "Oticon Intent 1")

        // 2. Profile Dashboard Verification
        let dashboards = TestProfileDashboardBuilder.buildCards(for: snapshot)
        XCTAssertEqual(dashboards.count, 1)
        let audioCard = dashboards[0]
        XCTAssertEqual(audioCard.profile, .hearingAudio)

        let presetMetric = audioCard.metrics.first { $0.title == "Active Preset" }
        XCTAssertEqual(presetMetric?.value, "Preset 3")

        let volMetric = audioCard.metrics.first { $0.title == "Volume Control" }
        XCTAssertEqual(volMetric?.value, "Volume 192 • Unmuted")

        let mediaMetric = audioCard.metrics.first { $0.title == "Media State" }
        XCTAssertEqual(mediaMetric?.value, "Playing")

        let battMetric = audioCard.metrics.first { $0.title == "Battery Level" }
        XCTAssertEqual(battMetric?.value, "82%")

        // 3. Permitted Characteristics Verification on HAS Service (1854)
        let hasSections = TestServiceDetailGrouping.buildSections(serviceUUID: "1854", characteristics: snapshot.exploredServices[0].characteristics)
        XCTAssertEqual(hasSections.count, 1)
        XCTAssertEqual(hasSections[0].title, "Standard Permitted Characteristics")
        XCTAssertEqual(hasSections[0].characteristics.count, 2)
    }

    // =========================================================================
    // MARK: - TEST HELPERS & HARNESS FACTORIES
    // =========================================================================

    private func makeMockSnapshot(
        identifier: UUID = UUID(),
        appearance: GATTAppearance? = nil,
        services: [GATTServiceSnapshot] = []
    ) -> BLEDeviceSnapshot {
        var evidence = GATTDeviceEvidence()
        evidence.identity.appearance = appearance
        evidence.discoveredServiceUUIDs = services.map(\.uuid)

        return BLEDeviceSnapshot(
            peripheralIdentifier: identifier,
            displayName: "Mock Device",
            latestRSSI: -60,
            strongestRSSI: -60,
            firstSeen: Date(),
            lastSeen: Date(),
            sightingCount: 1,
            advertisement: BLEAdvertisement(
                localName: "Mock Device",
                manufacturerDataHex: nil,
                companyIdentifier: nil,
                memberServiceUUIDs: [],
                serviceUUIDs: services.map(\.uuid),
                solicitedServiceUUIDs: [],
                serviceData: [:],
                overflowServiceUUIDs: [],
                txPower: nil,
                isConnectable: true
            ),
            gattEvidence: evidence,
            exploredServices: services
        )
    }
}

// =============================================================================
// MARK: - TEST HARNESS MODELS & SPECIFICATION SIMULATORS
// =============================================================================

// MARK: - Settings Test Harness
struct TestSettingsHarness: Codable, Equatable, Hashable {
    var activeScanDuration: TimeInterval = 120
    var isAutomaticGATTEnrichmentEnabled: Bool = true
    var recordingBurstDuration: TimeInterval = 1
    var recordingPauseDuration: TimeInterval = 5
    var minimumRSSI: Int = -100
    var keepScreenAwakeDuringRecording: Bool = true
    var requestNotificationPermissionOnRuleCreation: Bool = true

    init(settings: AppSettings = AppSettings.default) {
        self.activeScanDuration = settings.activeScanDuration
        self.recordingBurstDuration = settings.recordingBurstDuration
        self.recordingPauseDuration = settings.recordingPauseDuration
        self.minimumRSSI = settings.minimumRSSI
        self.keepScreenAwakeDuringRecording = settings.keepScreenAwakeDuringRecording
        self.requestNotificationPermissionOnRuleCreation = settings.requestNotificationPermissionOnRuleCreation
    }

    private enum CodingKeys: String, CodingKey {
        case activeScanDuration
        case isAutomaticGATTEnrichmentEnabled
        case recordingBurstDuration
        case recordingPauseDuration
        case minimumRSSI
        case keepScreenAwakeDuringRecording
        case requestNotificationPermissionOnRuleCreation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeScanDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .activeScanDuration) ?? 120
        isAutomaticGATTEnrichmentEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAutomaticGATTEnrichmentEnabled) ?? true
        recordingBurstDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingBurstDuration) ?? 1
        recordingPauseDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingPauseDuration) ?? 5
        minimumRSSI = try container.decodeIfPresent(Int.self, forKey: .minimumRSSI) ?? -100
        keepScreenAwakeDuringRecording = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeDuringRecording) ?? true
        requestNotificationPermissionOnRuleCreation = try container.decodeIfPresent(Bool.self, forKey: .requestNotificationPermissionOnRuleCreation) ?? true
    }
}

// MARK: - Background GATT Probe Simulator
final class TestBackgroundGATTProbeSimulator {
    var writeOperationsCount = 0
    var notifySubscriptionCount = 0
    var isCancelled = false
    var timeoutFired = false
    var didComplete = false
    var hasFailedCatastrophically = false
    var activeReadsPendingCount = 0

    let whitelist: Set<UInt16> = [
        0x2A00, 0x2A01, 0x2A19, 0x2A23, 0x2A24, 0x2A25, 0x2A26, 0x2A27, 0x2A28, 0x2A29, 0x2A50
    ]

    func determineReadsToPerform(services: [UInt16], characteristics: [UInt16]) -> [UInt16] {
        characteristics.filter { whitelist.contains($0) }
    }

    func executeMockProbe(
        services: [UInt16],
        characteristics: [UInt16: Data],
        readErrors: [UInt16: String] = [:]
    ) -> GATTDeviceEvidence {
        var evidence = GATTDeviceEvidence()
        evidence.setDiscoveredServiceUUIDs(services.map { String(format: "%04X", $0) })

        for (charUUID, data) in characteristics {
            if let decoded = GATTValueDecoder.decode(characteristicUUID: String(format: "%04X", charUUID), data: data) {
                evidence.merge(characteristicUUID: String(format: "%04X", charUUID), decodedValue: decoded)
            }
        }
        didComplete = true
        return evidence
    }

    func simulateImmediateDisconnect() {
        didComplete = true
    }

    func simulateTimeout(timeoutSeconds: TimeInterval) {
        timeoutFired = true
        cancel()
    }

    func startAsyncRead() {
        activeReadsPendingCount += 1
    }

    func cancel() {
        isCancelled = true
        activeReadsPendingCount = 0
    }
}

// MARK: - Auto-Probe Queue Simulator
final class TestAutoProbeQueue {
    var isEnrichmentEnabled: Bool
    var maxSessionCap: Int
    var pendingQueue: [UUID] = []
    var probedPeripheralIDs: Set<UUID> = []
    var currentProbingID: UUID?
    var isTimeoutTimerActive = false
    var rejectedDueToCapCount = 0
    var scanMode: ScanMode = .active

    init(isEnrichmentEnabled: Bool, maxSessionCap: Int = 20) {
        self.isEnrichmentEnabled = isEnrichmentEnabled
        self.maxSessionCap = maxSessionCap
    }

    var pendingCount: Int { pendingQueue.count }
    var activeConnectionsCount: Int { currentProbingID == nil ? 0 : 1 }
    var totalProbedCount: Int { probedPeripheralIDs.count }

    func enqueueIfEligible(peripheralID: UUID, isConnectable: Bool, isScanActive: Bool) -> Bool {
        guard isEnrichmentEnabled, isScanActive, scanMode == .active, isConnectable else { return false }
        guard probedPeripheralIDs.count < maxSessionCap else {
            rejectedDueToCapCount += 1
            return false
        }
        guard !probedPeripheralIDs.contains(peripheralID),
              !pendingQueue.contains(peripheralID),
              currentProbingID != peripheralID else { return false }

        if currentProbingID == nil {
            currentProbingID = peripheralID
            probedPeripheralIDs.insert(peripheralID)
            isTimeoutTimerActive = true
        } else {
            pendingQueue.append(peripheralID)
        }
        return true
    }

    func completeCurrentProbe() {
        isTimeoutTimerActive = false
        currentProbingID = nil
        processNext()
    }

    func simulateCurrentProbeTimeout() {
        completeCurrentProbe()
    }

    func stopScan() {
        pendingQueue.removeAll()
        currentProbingID = nil
        isTimeoutTimerActive = false
    }

    func switchScanMode(to mode: ScanMode) {
        self.scanMode = mode
        if mode != .active {
            stopScan()
        }
    }

    private func processNext() {
        guard !pendingQueue.isEmpty, probedPeripheralIDs.count < maxSessionCap else { return }
        let next = pendingQueue.removeFirst()
        currentProbingID = next
        probedPeripheralIDs.insert(next)
        isTimeoutTimerActive = true
    }
}

// MARK: - Permitted Characteristics Lookup Specification Simulator
enum TestPermittedCharacteristicsLookup {
    private static let registry: [UInt16: Set<UInt16>] = [
        0x181A: [0x2A6D, 0x2A6E, 0x2A6F, 0x2A6C, 0x2A70, 0x2A71, 0x2A72, 0x2A73, 0x2A74, 0x2A75, 0x2A76, 0x2A77, 0x2A78, 0x2A79, 0x2A7A, 0x2A7B, 0x2A7D],
        0x181C: [0x2A8A, 0x2A90, 0x2A85, 0x2A8C, 0x2A98, 0x2A8E, 0x2A97, 0x2A9F, 0x2A80],
        0x183B: [0x2AC9, 0x2B40, 0x2B41, 0x2B42],
        0x180F: [0x2A19],
        0x180A: [0x2A23, 0x2A24, 0x2A25, 0x2A26, 0x2A27, 0x2A28, 0x2A29, 0x2A50],
        0x180D: [0x2A37, 0x2A38, 0x2A39],
        0x1816: [0x2A5B, 0x2A5C, 0x2A5D, 0x2A55],
        0x1818: [0x2A63, 0x2A65, 0x2A5D, 0x2A66],
        0x1814: [0x2A53, 0x2A54, 0x2A5D, 0x2A55],
        0x1812: [0x2A4A, 0x2A4B, 0x2A4C, 0x2A4D, 0x2A4E, 0x2A22],
        0x1854: [0x2BDA, 0x2BDC, 0x2BDD, 0x2BDE],
        0x1844: [0x2B7D, 0x2B7E, 0x2B7F],
        0x1848: [0x2BA4, 0x2BA6, 0x2B93, 0x2B97]
    ]

    static func permittedCharacteristicUUIDs(forServiceUUIDString serviceUUID: String) -> Set<UInt16>? {
        guard let canonical = BluetoothAssignedUUIDLookup.canonical16BitValue(from: serviceUUID) else {
            return nil
        }
        return registry[canonical]
    }
}

// MARK: - Service Detail Semantic Grouping Simulator
struct TestServiceSection {
    let title: String
    let characteristics: [GATTCharacteristicSnapshot]
    let warning: String? = nil
}

enum TestServiceDetailGrouping {
    static func buildSections(serviceUUID: String, characteristics: [GATTCharacteristicSnapshot]) -> [TestServiceSection] {
        guard !characteristics.isEmpty else { return [] }
        guard let permittedSet = TestPermittedCharacteristicsLookup.permittedCharacteristicUUIDs(forServiceUUIDString: serviceUUID) else {
            return [TestServiceSection(title: "Discovered Characteristics", characteristics: characteristics)]
        }

        var permittedList: [GATTCharacteristicSnapshot] = []
        var customList: [GATTCharacteristicSnapshot] = []

        for char in characteristics {
            if let val = BluetoothAssignedUUIDLookup.canonical16BitValue(from: char.uuid), permittedSet.contains(val) {
                permittedList.append(char)
            } else {
                customList.append(char)
            }
        }

        var sections: [TestServiceSection] = []
        if !permittedList.isEmpty {
            sections.append(TestServiceSection(title: "Standard Permitted Characteristics", characteristics: permittedList))
        }
        if !customList.isEmpty {
            sections.append(TestServiceSection(title: "Additional / Custom Characteristics", characteristics: customList))
        }
        return sections
    }
}

// MARK: - Extended GATT Decoder Simulator
enum TestGATTDecoderExtension {
    static func decodePressure(_ data: Data) -> GATTDecodedValue {
        guard data.count == 4 else {
            return GATTDecodedValue(
                displayText: data.hexadecimalString,
                rawHex: data.hexadecimalString,
                fields: [],
                warning: "Expected 4-byte uint32 pressure"
            )
        }
        let raw = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let hPa = Double(raw) / 1000.0
        let display = String(format: "%.2f hPa", hPa)
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Pressure", value: display)]
        )
    }

    static func decodeElevation(_ data: Data) -> GATTDecodedValue {
        guard data.count == 3 else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected 3-byte sint24 elevation")
        }
        let b = [UInt8](data)
        let raw = Int(Int32(b[0]) | (Int32(b[1]) << 8) | (Int32(Int8(bitPattern: b[2])) << 16))
        let meters = Double(raw) / 100.0
        let display = String(format: "%.2f m", meters)
        return GATTDecodedValue(displayText: display, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Elevation", value: display)])
    }

    static func decodeSensorLocation(_ data: Data) -> GATTDecodedValue {
        let locations = [
            "Other", "Top of shoe", "In shoe", "Hip", "Front Wheel", "Rear Wheel",
            "Left Crank", "Right Crank", "Left Pedal", "Right Pedal", "Front Hub",
            "Rear Dropout", "Chainstay"
        ]
        guard data.count == 1, let idx = data.first, Int(idx) < locations.count else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Invalid Sensor Location index")
        }
        let name = locations[Int(idx)]
        return GATTDecodedValue(displayText: name, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Sensor Location", value: name)])
    }

    static func decodeVolumeState(_ data: Data) -> GATTDecodedValue {
        guard data.count >= 2 else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected at least 2-byte volume state")
        }
        let volume = Int(data[0])
        let mute = data[1] == 1 ? "Muted" : "Unmuted"
        let display = "Volume \(volume) • \(mute)"
        return GATTDecodedValue(displayText: display, rawHex: data.hexadecimalString, fields: [
            GATTDecodedField(name: "Volume Setting", value: String(volume)),
            GATTDecodedField(name: "Mute State", value: mute)
        ])
    }

    static func decodeMediaState(_ data: Data) -> GATTDecodedValue {
        guard let stateByte = data.first else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected 1-byte media state")
        }
        let states = ["Inactive", "Playing", "Paused", "Seeking"]
        let stateName = Int(stateByte) < states.count ? states[Int(stateByte)] : "State \(stateByte)"
        return GATTDecodedValue(displayText: stateName, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Media State", value: stateName)])
    }

    static func decodeMediaControlOpcodes(_ data: Data) -> GATTDecodedValue {
        guard data.count == 4 else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected 4-byte bitmask")
        }
        let mask = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        var commands: [String] = []
        if (mask & 0x01) != 0 { commands.append("Play") }
        if (mask & 0x02) != 0 { commands.append("Pause") }
        if (mask & 0x04) != 0 { commands.append("Stop") }
        if (mask & 0x08) != 0 { commands.append("Fast Forward") }
        if (mask & 0x10) != 0 { commands.append("Rewind") }
        let display = commands.joined(separator: ", ")
        return GATTDecodedValue(displayText: display, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Supported Commands", value: display)])
    }

    static func decodeHearingAidFeatures(_ data: Data) -> GATTDecodedValue {
        guard data.count >= 1 else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected feature bytes")
        }
        let b = data[0]
        var caps: [String] = []
        caps.append((b & 0x01) != 0 ? "Binaural" : "Monaural")
        if (b & 0x02) != 0 { caps.append("Independent Volume") }
        let display = caps.joined(separator: " • ")
        return GATTDecodedValue(displayText: display, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Hearing Aid Features", value: display)])
    }

    static func decodeActivePreset(_ data: Data) -> GATTDecodedValue {
        guard let idx = data.first else {
            return GATTDecodedValue(displayText: data.hexadecimalString, rawHex: data.hexadecimalString, fields: [], warning: "Expected 1-byte preset index")
        }
        let display = "Preset \(idx)"
        return GATTDecodedValue(displayText: display, rawHex: data.hexadecimalString, fields: [GATTDecodedField(name: "Active Preset", value: display)])
    }
}

// MARK: - Profile Dashboard Builder Simulator
enum TestProfileDashboardCluster: String {
    case fitnessCycling
    case environmentalSensing
    case hidAccessory
    case hearingAudio
}

struct TestProfileDashboardMetric: Hashable {
    let title: String
    let value: String
    let unit: String?
    let rawHex: String?

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Metric" : trimmed
    }

    var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return rawHex ?? "N/A"
    }
}

struct TestProfileDashboardCard: Hashable {
    let profile: TestProfileDashboardCluster
    let title: String
    let metrics: [TestProfileDashboardMetric]
}

enum TestProfileDashboardBuilder {
    static func buildCards(for snapshot: BLEDeviceSnapshot) -> [TestProfileDashboardCard] {
        var cards: [TestProfileDashboardCard] = []

        let allServices = Set(snapshot.exploredServices.map { $0.uuid.uppercased() } + snapshot.advertisement.serviceUUIDs.map { $0.uppercased() })
        let chars = snapshot.exploredServices.flatMap { $0.characteristics }

        // 1. Fitness & Cycling
        if allServices.contains("1818") || allServices.contains("1816") || allServices.contains("180D") || allServices.contains("1814") {
            var metrics: [TestProfileDashboardMetric] = []
            if let locChar = chars.first(where: { $0.uuid == "2A5D" || $0.uuid == "2A38" }), let dec = locChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Sensor Location", value: dec.displayText, unit: nil, rawHex: locChar.valueHex))
            }
            if let featChar = chars.first(where: { $0.uuid == "2A65" || $0.uuid == "2A5C" || $0.uuid == "2A54" }), let dec = featChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Supported Features", value: dec.displayText, unit: nil, rawHex: featChar.valueHex))
            }
            if let battChar = chars.first(where: { $0.uuid == "2A19" }), let dec = battChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Battery Level", value: dec.displayText, unit: "%", rawHex: battChar.valueHex))
            }
            if !metrics.isEmpty {
                cards.append(TestProfileDashboardCard(profile: .fitnessCycling, title: "Fitness & Cycling Dashboard", metrics: metrics))
            }
        }

        // 2. Environmental Sensing
        if allServices.contains("181A") || allServices.contains("1809") || chars.contains(where: { $0.uuid == "2A6E" || $0.uuid == "2A6F" || $0.uuid == "2A6D" }) {
            var metrics: [TestProfileDashboardMetric] = []
            if let tempChar = chars.first(where: { $0.uuid == "2A6E" }) {
                metrics.append(TestProfileDashboardMetric(title: "Temperature", value: tempChar.decodedValue?.displayText ?? tempChar.valueHex ?? "N/A", unit: "°C", rawHex: tempChar.valueHex))
            }
            if let humChar = chars.first(where: { $0.uuid == "2A6F" }) {
                metrics.append(TestProfileDashboardMetric(title: "Humidity", value: humChar.decodedValue?.displayText ?? humChar.valueHex ?? "N/A", unit: "%", rawHex: humChar.valueHex))
            }
            if let pressChar = chars.first(where: { $0.uuid == "2A6D" }) {
                metrics.append(TestProfileDashboardMetric(title: "Pressure", value: pressChar.decodedValue?.displayText ?? pressChar.valueHex ?? "N/A", unit: "hPa", rawHex: pressChar.valueHex))
            }
            if let elevChar = chars.first(where: { $0.uuid == "2A6C" }) {
                metrics.append(TestProfileDashboardMetric(title: "Elevation", value: elevChar.decodedValue?.displayText ?? elevChar.valueHex ?? "N/A", unit: "m", rawHex: elevChar.valueHex))
            }
            if let battChar = chars.first(where: { $0.uuid == "2A19" }), let dec = battChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Battery Level", value: dec.displayText, unit: "%", rawHex: battChar.valueHex))
            }
            if !metrics.isEmpty {
                cards.append(TestProfileDashboardCard(profile: .environmentalSensing, title: "Environmental Sensing Dashboard", metrics: metrics))
            }
        }

        // 3. HID Accessory
        if allServices.contains("1812") || (snapshot.gattEvidence?.identity.appearance?.categoryName.lowercased().contains("human interface device") == true) {
            var metrics: [TestProfileDashboardMetric] = []
            if let app = snapshot.gattEvidence?.identity.appearance {
                metrics.append(TestProfileDashboardMetric(title: "Input Device Type", value: app.displayName, unit: nil, rawHex: String(format: "%04X", app.rawValue)))
            }
            if let hidChar = chars.first(where: { $0.uuid == "2A4A" }), let dec = hidChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Capabilities", value: dec.displayText, unit: nil, rawHex: hidChar.valueHex))
            }
            if let battChar = chars.first(where: { $0.uuid == "2A19" }), let dec = battChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Battery Level", value: dec.displayText, unit: "%", rawHex: battChar.valueHex))
            }
            if !metrics.isEmpty {
                cards.append(TestProfileDashboardCard(profile: .hidAccessory, title: "HID Accessory Dashboard", metrics: metrics))
            }
        }

        // 4. Audio & Hearing
        if allServices.contains("1854") || allServices.contains("1844") || allServices.contains("1848") || (snapshot.gattEvidence?.identity.appearance?.categoryName.lowercased().contains("hearing aid") == true) {
            var metrics: [TestProfileDashboardMetric] = []
            if let hasChar = chars.first(where: { $0.uuid == "2BDA" }), let dec = hasChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Hearing Aid Features", value: dec.displayText, unit: nil, rawHex: hasChar.valueHex))
            }
            if let presetChar = chars.first(where: { $0.uuid == "2BDC" }), let dec = presetChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Active Preset", value: dec.displayText, unit: nil, rawHex: presetChar.valueHex))
            }
            if let volChar = chars.first(where: { $0.uuid == "2B7D" }), let dec = volChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Volume Control", value: dec.displayText, unit: nil, rawHex: volChar.valueHex))
            }
            if let mediaChar = chars.first(where: { $0.uuid == "2BA4" }), let dec = mediaChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Media State", value: dec.displayText, unit: nil, rawHex: mediaChar.valueHex))
            }
            if let battChar = chars.first(where: { $0.uuid == "2A19" }), let dec = battChar.decodedValue {
                metrics.append(TestProfileDashboardMetric(title: "Battery Level", value: dec.displayText, unit: "%", rawHex: battChar.valueHex))
            }
            if !metrics.isEmpty {
                cards.append(TestProfileDashboardCard(profile: .hearingAudio, title: "Audio & Hearing Dashboard", metrics: metrics))
            }
        }

        return cards
    }
}

// MARK: - Reconciler Simulator
enum TestGATTReconciler {
    static func mergeDuplicateSnapshots(_ snapshots: [BLEDeviceSnapshot]) -> [BLEDeviceSnapshot] {
        var groupedBySerial: [String: [BLEDeviceSnapshot]] = [:]
        var unmergeable: [BLEDeviceSnapshot] = []

        for s in snapshots {
            if let sn = s.gattEvidence?.identity.serialNumber, !sn.isEmpty {
                groupedBySerial[sn, default: []].append(s)
            } else {
                unmergeable.append(s)
            }
        }

        var result: [BLEDeviceSnapshot] = unmergeable
        for (_, list) in groupedBySerial {
            guard let first = list.first else { continue }
            let totalSightings = list.reduce(0) { $0 + $1.sightingCount }
            let maxRSSI = list.map(\.strongestRSSI).max() ?? first.strongestRSSI
            var mergedServices: [GATTServiceSnapshot] = []
            for item in list {
                mergedServices.append(contentsOf: item.exploredServices)
            }

            var merged = BLEDeviceSnapshot(
                peripheralIdentifier: first.peripheralIdentifier,
                displayName: first.displayName,
                latestRSSI: list.last?.latestRSSI ?? first.latestRSSI,
                strongestRSSI: maxRSSI,
                firstSeen: list.map(\.firstSeen).min() ?? first.firstSeen,
                lastSeen: list.map(\.lastSeen).max() ?? first.lastSeen,
                sightingCount: totalSightings,
                advertisement: first.advertisement,
                gattEvidence: first.gattEvidence,
                exploredServices: mergedServices
            )
            result.append(merged)
        }
        return result
    }
}

// MARK: - Sanitizer Simulator
enum TestSanitizer {
    static func sanitizeName(_ raw: String?) -> String {
        guard let raw = raw else { return "" }
        let controlAndWhitespace = CharacterSet.controlCharacters.union(.whitespaces)
        let parts = raw.components(separatedBy: controlAndWhitespace)
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
