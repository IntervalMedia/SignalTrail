import CoreBluetooth
import CoreLocation
import XCTest

@testable import SignalTrail

// MARK: - Fake CBPeripheral for Unit Testing
@objc final class FakeCBPeripheral: NSObject {
    @objc let identifier: UUID
    @objc let name: String?

    init(identifier: UUID = UUID(), name: String? = "Test Peripheral") {
        self.identifier = identifier
        self.name = name
        super.init()
    }

    var asCBPeripheral: CBPeripheral {
        unsafeBitCast(self, to: CBPeripheral.self)
    }
}

// MARK: - Mock Background GATT Probe
final class MockBackgroundGATTProbe: BackgroundGATTProbe {
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    var isCancelledMock = false
    private let mockCompletion: (Result<GATTDeviceEvidence, Error>) -> Void
    private var mockExploredServices: [GATTServiceSnapshot] = []

    override init(
        peripheral: CBPeripheral,
        scanner: BluetoothScanning,
        timeout: TimeInterval = 5.0,
        completion: @escaping (Result<GATTDeviceEvidence, Error>) -> Void
    ) {
        self.mockCompletion = completion
        super.init(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
    }

    override func start() {
        onStart?()
    }

    override func cancel() {
        isCancelledMock = true
        onCancel?()
    }

    func completeWithSuccess(evidence: GATTDeviceEvidence, exploredServices: [GATTServiceSnapshot] = []) {
        self.mockExploredServices = exploredServices
        mockCompletion(.success(evidence))
    }

    func completeWithFailure(error: Error = BackgroundGATTProbeError.connectionFailed("Failed")) {
        mockCompletion(.failure(error))
    }

    func completeWithTimeout() {
        mockCompletion(.failure(BackgroundGATTProbeError.timedOut))
    }

    override var exploredServices: [GATTServiceSnapshot] {
        mockExploredServices
    }
}

// MARK: - AutoProbeQueueTests Suite
final class AutoProbeQueueTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: LocalStore!
    private var settingsStore: SettingsStore!
    private var scanner: BluetoothScanner!
    private var coordinator: ScanCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoProbeQueueTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = try LocalStore(rootURL: tempDirectory)
        settingsStore = SettingsStore()
        scanner = BluetoothScanner()
        scanner.stateOverride = .poweredOn
        coordinator = ScanCoordinator(
            scanner: scanner,
            locationProvider: MockLocationProvider(),
            store: store,
            settingsStore: settingsStore,
            notificationService: NotificationService()
        )
    }

    override func tearDownWithError() throws {
        coordinator.stop()
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func makeConnectableAdvertisement(name: String = "Test Device", serviceUUIDs: [String] = []) -> BLEAdvertisement {
        BLEAdvertisement(
            localName: name,
            manufacturerDataHex: nil,
            companyIdentifier: nil,
            memberServiceUUIDs: [],
            serviceUUIDs: serviceUUIDs,
            solicitedServiceUUIDs: [],
            serviceData: [:],
            overflowServiceUUIDs: [],
            txPower: nil,
            isConnectable: true
        )
    }

    private func makeNonConnectableAdvertisement(name: String = "Beacon") -> BLEAdvertisement {
        BLEAdvertisement(
            localName: name,
            manufacturerDataHex: nil,
            companyIdentifier: nil,
            memberServiceUUIDs: [],
            serviceUUIDs: [],
            solicitedServiceUUIDs: [],
            serviceData: [:],
            overflowServiceUUIDs: [],
            txPower: nil,
            isConnectable: false
        )
    }

    private func discoverPeripheral(
        id: UUID = UUID(),
        name: String = "Test Device",
        isConnectable: Bool = true,
        rssi: Int = -60,
        timestamp: Date = Date()
    ) -> FakeCBPeripheral {
        let fake = FakeCBPeripheral(identifier: id, name: name)
        let cbPeripheral = fake.asCBPeripheral
        scanner.cachePeripheral(cbPeripheral)
        let adv = isConnectable ? makeConnectableAdvertisement(name: name) : makeNonConnectableAdvertisement(name: name)
        coordinator.bluetoothScanner(scanner, didDiscover: cbPeripheral, advertisement: adv, rssi: rssi, timestamp: timestamp)
        return fake
    }

    // =========================================================================
    // MARK: - 1. Concurrency Limit (Strictly 1 Concurrent Connection)
    // =========================================================================

    func testStrictlyOneConcurrentBackgroundGATTProbe() {
        var activeProbes: [UUID: MockBackgroundGATTProbe] = [:]

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            activeProbes[peripheral.identifier] = probe
            return probe
        }

        // Put coordinator into Quick Scan mode
        coordinator.startActive()
        XCTAssertTrue(coordinator.state.isRunning)

        let dev1 = discoverPeripheral(name: "Device 1")
        let dev2 = discoverPeripheral(name: "Device 2")
        let dev3 = discoverPeripheral(name: "Device 3")

        // 1. Only dev1 should be active
        XCTAssertNotNil(coordinator.activeGATTProbe, "Active probe should be running for Device 1")
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev1.identifier)
        XCTAssertEqual(coordinator.pendingGATTProbeQueue, [dev2.identifier, dev3.identifier])
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers, [dev1.identifier])

        // 2. Complete probe for dev1 -> dev2 must become active
        var evidence1 = GATTDeviceEvidence()
        evidence1.identity.deviceName = "Enriched Device 1"
        activeProbes[dev1.identifier]?.completeWithSuccess(evidence: evidence1)

        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev2.identifier)
        XCTAssertEqual(coordinator.pendingGATTProbeQueue, [dev3.identifier])
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers, [dev1.identifier, dev2.identifier])

        // 3. Complete probe for dev2 -> dev3 must become active
        var evidence2 = GATTDeviceEvidence()
        evidence2.identity.deviceName = "Enriched Device 2"
        activeProbes[dev2.identifier]?.completeWithSuccess(evidence: evidence2)

        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev3.identifier)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers, [dev1.identifier, dev2.identifier, dev3.identifier])

        // 4. Complete probe for dev3 -> active probe must be nil and queue empty
        var evidence3 = GATTDeviceEvidence()
        evidence3.identity.deviceName = "Enriched Device 3"
        activeProbes[dev3.identifier]?.completeWithSuccess(evidence: evidence3)

        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
    }

    // =========================================================================
    // MARK: - 2. Session Cap (Max 20 Probed Devices per Quick Scan Session)
    // =========================================================================

    func testSessionCapEnforcesMaximumOfTwentyProbedDevices() {
        var createdProbeCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            createdProbeCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.modelNumber = "Model-\(createdProbeCount)"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()

        // Discover 30 connectable peripherals
        var discoveredIDs: [UUID] = []
        for i in 1...30 {
            let fake = discoverPeripheral(name: "Device \(i)")
            discoveredIDs.append(fake.identifier)
        }

        // Exactly 20 probes should have been executed
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20, "Must cap at 20 probed devices per session")
        XCTAssertEqual(createdProbeCount, 20, "Must not create more than 20 probes")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty, "Excess devices beyond cap must not remain in queue")
        XCTAssertNil(coordinator.activeGATTProbe)

        // Device 21..30 were discovered but never probed
        for i in 20..<30 {
            let id = discoveredIDs[i]
            let snapshot = coordinator.device(for: id)
            XCTAssertNotNil(snapshot)
            XCTAssertNil(snapshot?.gattEvidence, "Device \(i + 1) must not have GATT evidence because session cap was reached")
        }
    }

    // =========================================================================
    // MARK: - 3. Deduplication per Session
    // =========================================================================

    func testDeduplicationPreventsReQueuingSameDeviceInSameSession() {
        var probeCount = 0
        var activeProbe: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            probeCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            activeProbe = probe
            return probe
        }

        coordinator.startActive()
        let fake = FakeCBPeripheral(identifier: UUID(), name: "Repeating Device")
        scanner.cachePeripheral(fake.asCBPeripheral)
        let adv = makeConnectableAdvertisement(name: "Repeating Device")

        // Advertise the same peripheral 10 times in a row
        for _ in 1...10 {
            coordinator.bluetoothScanner(scanner, didDiscover: fake.asCBPeripheral, advertisement: adv, rssi: -55, timestamp: Date())
        }

        XCTAssertEqual(probeCount, 1, "Repeated discoveries of active/pending peripheral must only trigger 1 probe")
        XCTAssertEqual(coordinator.pendingGATTProbeQueue.count, 0)

        // Complete the probe
        var evidence = GATTDeviceEvidence()
        evidence.identity.deviceName = "Enriched Repeating Device"
        activeProbe?.completeWithSuccess(evidence: evidence)

        // Advertise 5 more times after probe completion
        for _ in 1...5 {
            coordinator.bluetoothScanner(scanner, didDiscover: fake.asCBPeripheral, advertisement: adv, rssi: -50, timestamp: Date())
        }

        XCTAssertEqual(probeCount, 1, "Already probed peripheral in the same session must never be probed a second time")
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 1)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
    }

    // =========================================================================
    // MARK: - 4. Timeout Handling (Queue Advances on 5.0s Timeout)
    // =========================================================================

    func testQueueAdvancesWhenProbeTimesOut() {
        var probe1: MockBackgroundGATTProbe?
        var probe2: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            if probe1 == nil {
                probe1 = probe
            } else {
                probe2 = probe
            }
            return probe
        }

        coordinator.startActive()

        let dev1 = discoverPeripheral(name: "Stalling Device")
        let dev2 = discoverPeripheral(name: "Unnamed device")

        XCTAssertEqual(coordinator.currentProbeIdentifier, dev1.identifier)
        XCTAssertEqual(coordinator.pendingGATTProbeQueue, [dev2.identifier])

        // Simulate timeout on dev1
        probe1?.completeWithTimeout()

        // Queue must immediately advance to dev2
        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev2.identifier)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)

        // dev2 completes successfully
        var evidence2 = GATTDeviceEvidence()
        evidence2.identity.deviceName = "Responsive Device Enriched"
        probe2?.completeWithSuccess(evidence: evidence2)

        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)
        XCTAssertEqual(coordinator.device(for: dev2.identifier)?.presentationName, "Responsive Device Enriched")
    }

    // =========================================================================
    // MARK: - 5. Scan Stop Cancellation
    // =========================================================================

    func testScanStopCancelsInFlightProbeAndClearsQueue() {
        var activeProbe: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            activeProbe = probe
            return probe
        }

        coordinator.startActive()

        _ = discoverPeripheral(name: "Device 1")
        _ = discoverPeripheral(name: "Device 2")
        _ = discoverPeripheral(name: "Device 3")

        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.pendingGATTProbeQueue.count, 2)

        // Stop the scan
        coordinator.stop()

        XCTAssertFalse(coordinator.state.isRunning)
        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertTrue(activeProbe?.isCancelledMock == true, "In-flight probe must be cancelled on scan stop")
    }

    // =========================================================================
    // MARK: - 6. Clear Results Resets Probe Session
    // =========================================================================

    func testClearResultsResetsProbedIdentifiers() {
        var completedProbe = false

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.deviceName = "Enriched Device"
                probe.completeWithSuccess(evidence: evidence)
                completedProbe = true
            }
            return probe
        }

        coordinator.startActive()
        _ = discoverPeripheral(name: "Device 1")
        XCTAssertTrue(completedProbe)
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 1)

        coordinator.stop()
        coordinator.clearResults()

        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 0, "clearResults must reset probed peripherals set")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertTrue(coordinator.devices.isEmpty, "Live devices list must be cleared by clearResults")
    }

    // =========================================================================
    // MARK: - 7. Live Intelligence Enrichment (Apple TV, Battery, PresentationName)
    // =========================================================================

    func testLiveIntelligenceEnrichmentRefinesTelevisionAndPersistsToDisk() throws {
        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.deviceName = "Living Room Apple TV"
                evidence.identity.modelNumber = "AppleTV14,1"
                evidence.identity.manufacturerName = "Apple Inc."
                evidence.identity.serialNumber = "C02G998877"
                evidence.setDiscoveredServiceUUIDs(["1800", "180A", "180F"])

                let battChar = GATTCharacteristicSnapshot(
                    uuid: "2A19",
                    properties: ["Read"],
                    valueHex: "64",
                    decodedValue: GATTDecodedValue(displayText: "100%", rawHex: "64", fields: [GATTDecodedField(name: "Battery Level", value: "100%")]),
                    descriptors: [],
                    isNotifying: false
                )
                let battService = GATTServiceSnapshot(uuid: "180F", characteristics: [battChar])

                probe.completeWithSuccess(evidence: evidence, exploredServices: [battService])
            }
            return probe
        }

        coordinator.startActive()

        // Discovered as generic unnamed device initially
        let fake = discoverPeripheral(name: "Unnamed device")
        let devID = fake.identifier

        // 1. In-memory snapshot enrichment
        guard let snapshot = coordinator.device(for: devID) else {
            XCTFail("Snapshot must exist")
            return
        }

        XCTAssertEqual(snapshot.presentationName, "Living Room Apple TV")
        XCTAssertEqual(snapshot.intelligence.category, .television)
        XCTAssertGreaterThanOrEqual(snapshot.intelligence.probability, 92)
        XCTAssertEqual(snapshot.exploredServices.count, 1)
        XCTAssertEqual(snapshot.exploredServices.first?.uuid, "180F")

        // 2. Persistent storage verification
        coordinator.stop()
        let onDisk = store.loadDeviceRecord(for: devID)
        XCTAssertNotNil(onDisk, "Enriched device record must be persisted to LocalStore")
        XCTAssertEqual(onDisk?.gattEvidence?.identity.modelNumber, "AppleTV14,1")
        XCTAssertEqual(onDisk?.gattEvidence?.identity.serialNumber, "C02G998877")
        XCTAssertEqual(onDisk?.intelligence.category, .television)
        XCTAssertEqual(onDisk?.presentationName, "Living Room Apple TV")
    }

    // =========================================================================
    // MARK: - 8. Dynamic Classification for Smartwatch Appearance
    // =========================================================================

    func testDynamicClassificationForSmartwatchAppearance() {
        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.appearance = GATTAppearance(
                    rawValue: 0x00C2,
                    categoryName: "Watch",
                    subcategoryName: "Smartwatch"
                )
                evidence.identity.manufacturerName = "Garmin"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()
        let fake = discoverPeripheral(name: "Unnamed device")
        let devID = fake.identifier

        guard let snapshot = coordinator.device(for: devID) else {
            XCTFail("Snapshot must exist")
            return
        }

        XCTAssertEqual(snapshot.intelligence.category, .smartWatch)
        XCTAssertGreaterThanOrEqual(snapshot.intelligence.probability, 96)
        XCTAssertEqual(snapshot.presentationName, "Smartwatch")
    }

    // =========================================================================
    // MARK: - 9. Settings Toggle Disables / Enables Auto-Probing
    // =========================================================================

    func testSettingsToggleDisablesAndEnablesAutoProbing() {
        var probeCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            probeCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                probe.completeWithSuccess(evidence: GATTDeviceEvidence())
            }
            return probe
        }

        // 1. Disable setting
        settingsStore.settings.isAutomaticGATTEnrichmentEnabled = false
        coordinator.startActive()

        _ = discoverPeripheral(name: "Device A")
        _ = discoverPeripheral(name: "Device B")

        XCTAssertEqual(probeCount, 0, "No probes should be created when setting is disabled")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertNil(coordinator.activeGATTProbe)

        // 2. Re-enable setting
        settingsStore.settings.isAutomaticGATTEnrichmentEnabled = true

        _ = discoverPeripheral(name: "Device C")

        XCTAssertEqual(probeCount, 1, "Probe should be created when setting is enabled")
    }

    // =========================================================================
    // MARK: - 10. Mode Gating (No Probing in Recording or Idle)
    // =========================================================================

    func testAutoProbeQueueIgnoredDuringRecordingAndIdle() {
        var probeCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            probeCount += 1
            return MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
        }

        // 1. Idle mode
        XCTAssertEqual(coordinator.state, .idle)
        _ = discoverPeripheral(name: "Device in Idle")

        XCTAssertEqual(probeCount, 0, "Must not probe during idle")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)

        // 2. Recording mode
        coordinator.startRecording()
        XCTAssertEqual(coordinator.state.mode, .recording)

        _ = discoverPeripheral(name: "Device in Recording")

        XCTAssertEqual(probeCount, 0, "Must not probe during recording mode")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
    }

    // =========================================================================
    // MARK: - 11. Unconnectable Devices Are Ignored
    // =========================================================================

    func testUnconnectableDevicesAreIgnoredByAutoProbeQueue() {
        var probeCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            probeCount += 1
            return MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
        }

        coordinator.startActive()

        _ = discoverPeripheral(name: "Broadcast Beacon", isConnectable: false)

        XCTAssertEqual(probeCount, 0, "Non-connectable devices must not be probed")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertNil(coordinator.activeGATTProbe)
    }

    // =========================================================================
    // MARK: - 12. GATT Identity Duplicate Reconciliation During Auto-Probing
    // =========================================================================

    func testGATTIdentityDuplicateReconciliationMergesRotatingRPAs() {
        let serialNumber = "HARDWARE-SN-998877"

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.serialNumber = serialNumber
                evidence.identity.manufacturerName = "Nordic Semi"
                evidence.identity.deviceName = "Nordic Sensor"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()

        // Sighting 1 under UUID 1
        let dev1 = discoverPeripheral(name: "Unnamed device", rssi: -70)
        XCTAssertEqual(coordinator.device(for: dev1.identifier)?.presentationName, "Nordic Sensor")

        // Sighting 2 under UUID 2 (RPA address rotated)
        let dev2 = discoverPeripheral(name: "Unnamed device", rssi: -55)

        // Both UUIDs resolve to the same reconciled snapshot
        let resolvedFrom1 = coordinator.device(for: dev1.identifier)
        let resolvedFrom2 = coordinator.device(for: dev2.identifier)

        XCTAssertNotNil(resolvedFrom1)
        XCTAssertNotNil(resolvedFrom2)
        XCTAssertEqual(resolvedFrom1?.peripheralIdentifier, resolvedFrom2?.peripheralIdentifier)
        XCTAssertEqual(resolvedFrom1?.gattEvidence?.identity.serialNumber, serialNumber)
        XCTAssertEqual(resolvedFrom1?.sightingCount, 2)
    }

    // =========================================================================
    // MARK: - 13. Probe Failure Advances Queue
    // =========================================================================

    func testProbeFailureAdvancesQueueToNextDevice() {
        var probe1: MockBackgroundGATTProbe?
        var probe2: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            if probe1 == nil {
                probe1 = probe
            } else {
                probe2 = probe
            }
            return probe
        }

        coordinator.startActive()

        let dev1 = discoverPeripheral(name: "Failing Device")
        let dev2 = discoverPeripheral(name: "Unnamed device")

        XCTAssertEqual(coordinator.currentProbeIdentifier, dev1.identifier)

        // Probe 1 fails with connection error
        probe1?.completeWithFailure(error: BackgroundGATTProbeError.connectionFailed("Link lost"))

        // Queue advances to dev2
        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev2.identifier)

        // Probe 2 completes with success
        var evidence2 = GATTDeviceEvidence()
        evidence2.identity.deviceName = "Successful Device Enriched"
        probe2?.completeWithSuccess(evidence: evidence2)

        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.device(for: dev2.identifier)?.presentationName, "Successful Device Enriched")
    }

    // =========================================================================
    // MARK: - 14. Empirical Challenge: AppleTV14,1 Dynamic Classification & Naming
    // =========================================================================

    func testDynamicIntelligenceClassification_AppleTVVariantsAndNamingHierarchy() throws {
        let testCases: [(advertisedName: String, gattDeviceName: String?, modelNumber: String, expectedPresentation: String, expectedCategory: DeviceCategory)] = [
            ("Unnamed device", nil, "AppleTV14,1", "AppleTV14,1", .television),
            ("Unnamed device", "Living Room TV", "AppleTV14,1", "Living Room TV", .television),
            ("Custom Local Name", nil, "AppleTV14,1", "Custom Local Name", .television),
            ("Unnamed device", nil, "appletv11,1", "appletv11,1", .television),
            ("Unnamed device", nil, "AppleTV6,2", "AppleTV6,2", .television),
            ("Unnamed device", nil, "Apple TV 4K", "Apple TV 4K", .television),
            ("   ", nil, "AppleTV14,1", "AppleTV14,1", .television),
        ]

        for (idx, tc) in testCases.enumerated() {
            var activeProbe: MockBackgroundGATTProbe?
            coordinator.probeFactory = { peripheral, scanner, timeout, completion in
                let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
                activeProbe = probe
                return probe
            }

            coordinator.startActive()
            let fake = discoverPeripheral(name: tc.advertisedName)

            var evidence = GATTDeviceEvidence()
            evidence.identity.modelNumber = tc.modelNumber
            evidence.identity.manufacturerName = "Apple Inc."
            if let gattName = tc.gattDeviceName {
                evidence.identity.deviceName = gattName
            }
            activeProbe?.completeWithSuccess(evidence: evidence)

            guard let snapshot = coordinator.device(for: fake.identifier) else {
                XCTFail("Snapshot for case \(idx) must exist")
                continue
            }

            XCTAssertEqual(snapshot.intelligence.category, tc.expectedCategory, "Case \(idx) failed category")
            XCTAssertEqual(snapshot.presentationName, tc.expectedPresentation, "Case \(idx) failed presentationName")
            XCTAssertGreaterThanOrEqual(snapshot.intelligence.probability, 92, "Case \(idx) probability must be high")

            // Verify immediate persistence
            let persisted = store.loadDeviceRecord(for: fake.identifier)
            XCTAssertNotNil(persisted, "Case \(idx) must be persisted to disk")
            XCTAssertEqual(persisted?.presentationName, tc.expectedPresentation)
            XCTAssertEqual(persisted?.intelligence.category, tc.expectedCategory)
            XCTAssertEqual(persisted?.gattEvidence?.identity.modelNumber, tc.modelNumber)

            coordinator.stop()
            coordinator.clearResults()
        }
    }

    // =========================================================================
    // MARK: - 15. Empirical Challenge: Smart Device Diversity Dynamic Classification
    // =========================================================================

    func testDynamicIntelligenceClassification_SmartDeviceCategories() {
        struct SmartDeviceTestCase {
            let label: String
            let model: String?
            let appearance: GATTAppearance?
            let exploredServices: [String]
            let expectedCategory: DeviceCategory
            let expectedMinProbability: Int
        }

        let cases: [SmartDeviceTestCase] = [
            SmartDeviceTestCase(
                label: "Garmin Smartwatch (Appearance)",
                model: nil,
                appearance: GATTAppearance(rawValue: 0x00C2, categoryName: "Watch", subcategoryName: "Smartwatch"),
                exploredServices: [],
                expectedCategory: .smartWatch,
                expectedMinProbability: 96
            ),
            SmartDeviceTestCase(
                label: "Apple Watch (Model)",
                model: "AppleWatch8,1",
                appearance: nil,
                exploredServices: [],
                expectedCategory: .smartWatch,
                expectedMinProbability: 92
            ),
            SmartDeviceTestCase(
                label: "iPhone (Model)",
                model: "iPhone15,2",
                appearance: nil,
                exploredServices: [],
                expectedCategory: .mobilePhone,
                expectedMinProbability: 92
            ),
            SmartDeviceTestCase(
                label: "Phone (Appearance)",
                model: nil,
                appearance: GATTAppearance(rawValue: 0x0040, categoryName: "Phone", subcategoryName: "Generic Phone"),
                exploredServices: [],
                expectedCategory: .mobilePhone,
                expectedMinProbability: 96
            ),
            SmartDeviceTestCase(
                label: "MacBook Pro (Model)",
                model: "MacBookPro18,1",
                appearance: nil,
                exploredServices: [],
                expectedCategory: .computer,
                expectedMinProbability: 92
            ),
            SmartDeviceTestCase(
                label: "Computer (Appearance)",
                model: nil,
                appearance: GATTAppearance(rawValue: 0x0080, categoryName: "Computer", subcategoryName: "Desktop Workstation"),
                exploredServices: [],
                expectedCategory: .computer,
                expectedMinProbability: 96
            ),
            SmartDeviceTestCase(
                label: "AirPods (Model)",
                model: "AirPods Pro",
                appearance: nil,
                exploredServices: [],
                expectedCategory: .audio,
                expectedMinProbability: 92
            ),
            SmartDeviceTestCase(
                label: "Audio Sink (Appearance)",
                model: nil,
                appearance: GATTAppearance(rawValue: 0x0841, categoryName: "Audio Sink", subcategoryName: "Standalone Speaker"),
                exploredServices: [],
                expectedCategory: .audio,
                expectedMinProbability: 96
            ),
            SmartDeviceTestCase(
                label: "LE Audio Service",
                model: nil,
                appearance: nil,
                exploredServices: ["1844"],
                expectedCategory: .audio,
                expectedMinProbability: 82
            ),
            SmartDeviceTestCase(
                label: "Heart Rate Service",
                model: nil,
                appearance: nil,
                exploredServices: ["180D"],
                expectedCategory: .healthFitness,
                expectedMinProbability: 88
            ),
            SmartDeviceTestCase(
                label: "HID Keyboard Service",
                model: nil,
                appearance: nil,
                exploredServices: ["1812"],
                expectedCategory: .peripheral,
                expectedMinProbability: 86
            ),
            SmartDeviceTestCase(
                label: "Automation Service",
                model: nil,
                appearance: nil,
                exploredServices: ["1815"],
                expectedCategory: .smartHome,
                expectedMinProbability: 79
            ),
        ]

        for tc in cases {
            var activeProbe: MockBackgroundGATTProbe?
            coordinator.probeFactory = { peripheral, scanner, timeout, completion in
                let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
                activeProbe = probe
                return probe
            }

            coordinator.startActive()
            let fake = discoverPeripheral(name: "Unnamed device")

            var evidence = GATTDeviceEvidence()
            evidence.identity.modelNumber = tc.model
            evidence.identity.appearance = tc.appearance
            evidence.setDiscoveredServiceUUIDs(tc.exploredServices)

            let serviceSnapshots = tc.exploredServices.map { uuid in
                GATTServiceSnapshot(uuid: uuid, characteristics: [])
            }

            activeProbe?.completeWithSuccess(evidence: evidence, exploredServices: serviceSnapshots)

            guard let snapshot = coordinator.device(for: fake.identifier) else {
                XCTFail("Snapshot for \(tc.label) must exist")
                continue
            }

            XCTAssertEqual(snapshot.intelligence.category, tc.expectedCategory, "Failed category for \(tc.label)")
            XCTAssertGreaterThanOrEqual(snapshot.intelligence.probability, tc.expectedMinProbability, "Failed probability for \(tc.label)")

            coordinator.stop()
            coordinator.clearResults()
        }
    }

    // =========================================================================
    // MARK: - 16. Empirical Challenge: Real-Time Delegate Notification & Subsequent Adv Preservation
    // =========================================================================

    func testRealTimeEnrichmentNotifiesDelegateAndPreservesGATTOnSubsequentAdvertisements() {
        class MockScanCoordinatorDelegate: ScanCoordinatorDelegate {
            var updatedDeviceLists: [[BLEDeviceSnapshot]] = []
            var stateChanges: [ScanCoordinator.State] = []
            var encounteredErrors: [String] = []

            func scanCoordinator(_ coordinator: ScanCoordinator, didUpdate devices: [BLEDeviceSnapshot]) {
                updatedDeviceLists.append(devices)
            }
            func scanCoordinatorDidChangeState(_ coordinator: ScanCoordinator) {
                stateChanges.append(coordinator.state)
            }
            func scanCoordinator(_ coordinator: ScanCoordinator, didEncounter message: String) {
                encounteredErrors.append(message)
            }
        }

        let mockDelegate = MockScanCoordinatorDelegate()
        coordinator.delegate = mockDelegate

        var activeProbe: MockBackgroundGATTProbe?
        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            activeProbe = probe
            return probe
        }

        coordinator.startActive()

        // 1. Initial discovery of an unnamed device
        let fake = discoverPeripheral(name: "Unnamed device", rssi: -75)
        let initialUpdatesCount = mockDelegate.updatedDeviceLists.count

        // 2. Probe completes in real time with Apple TV 14,1
        var evidence = GATTDeviceEvidence()
        evidence.identity.modelNumber = "AppleTV14,1"
        evidence.identity.manufacturerName = "Apple Inc."
        evidence.identity.deviceName = "Bedroom Apple TV"
        evidence.identity.serialNumber = "SERIAL-TV-12345"

        activeProbe?.completeWithSuccess(evidence: evidence)

        // Delegate must have been notified with enriched snapshot
        XCTAssertGreaterThan(mockDelegate.updatedDeviceLists.count, initialUpdatesCount, "Delegate must be notified in real-time when probe enriches snapshot")
        let latestDevices = mockDelegate.updatedDeviceLists.last ?? []
        let enrichedInList = latestDevices.first { $0.peripheralIdentifier == fake.identifier }
        XCTAssertNotNil(enrichedInList)
        XCTAssertEqual(enrichedInList?.presentationName, "Bedroom Apple TV")
        XCTAssertEqual(enrichedInList?.intelligence.category, .television)
        XCTAssertEqual(enrichedInList?.gattEvidence?.identity.serialNumber, "SERIAL-TV-12345")

        // 3. Subsequent BLE Advertisement arrives for same peripheral
        let adv2 = makeConnectableAdvertisement(name: "Unnamed device")
        coordinator.bluetoothScanner(scanner, didDiscover: fake.asCBPeripheral, advertisement: adv2, rssi: -60, timestamp: Date())

        // Enriched metadata must be preserved
        let updatedSnapshot = coordinator.device(for: fake.identifier)
        XCTAssertNotNil(updatedSnapshot)
        XCTAssertEqual(updatedSnapshot?.presentationName, "Bedroom Apple TV", "Subsequent advertisement must not revert enriched presentation name")
        XCTAssertEqual(updatedSnapshot?.intelligence.category, .television, "Subsequent advertisement must not revert enriched category")
        XCTAssertEqual(updatedSnapshot?.gattEvidence?.identity.modelNumber, "AppleTV14,1")
        XCTAssertEqual(updatedSnapshot?.gattEvidence?.identity.serialNumber, "SERIAL-TV-12345")
        XCTAssertEqual(updatedSnapshot?.latestRSSI, -60, "Latest RSSI must be updated")
        XCTAssertEqual(updatedSnapshot?.sightingCount, 2, "Sighting count must increment")
    }

    // =========================================================================
    // MARK: - 17. Empirical Challenge: High-Volume Rapid Sequential Probe Stress
    // =========================================================================

    func testHighVolumeRapidSequentialProbingStress() throws {
        var createdProbes: [UUID: MockBackgroundGATTProbe] = [:]
        var completedProbeCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            createdProbes[peripheral.identifier] = probe
            return probe
        }

        coordinator.startActive()

        // Discover 25 connectable peripherals rapidly
        var fakes: [FakeCBPeripheral] = []
        for i in 1...25 {
            let fake = discoverPeripheral(name: "Unnamed device", rssi: -60 - i)
            fakes.append(fake)
        }

        // Drain the queue item by item
        for i in 0..<20 {
            let expectedID = fakes[i].identifier
            guard let probe = createdProbes[expectedID] else {
                XCTFail("Probe for item \(i) (id: \(expectedID)) must be active")
                return
            }

            var evidence = GATTDeviceEvidence()
            if i % 2 == 0 {
                evidence.identity.modelNumber = "AppleTV14,\(i)"
                evidence.identity.deviceName = "Apple TV \(i)"
            } else {
                evidence.identity.appearance = GATTAppearance(rawValue: 0x00C2, categoryName: "Watch", subcategoryName: "Smartwatch")
                evidence.identity.deviceName = "Watch \(i)"
            }
            probe.completeWithSuccess(evidence: evidence)
            completedProbeCount += 1
        }

        // Exactly 20 probes completed (capped at 20)
        XCTAssertEqual(completedProbeCount, 20)
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20)
        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)

        // Verify all 20 devices are enriched in memory and on disk
        for i in 0..<20 {
            let id = fakes[i].identifier
            let memorySnap = coordinator.device(for: id)
            let diskSnap = store.loadDeviceRecord(for: id)

            XCTAssertNotNil(memorySnap)
            XCTAssertNotNil(diskSnap)

            if i % 2 == 0 {
                XCTAssertEqual(memorySnap?.intelligence.category, .television)
                XCTAssertEqual(memorySnap?.presentationName, "Apple TV \(i)")
                XCTAssertEqual(diskSnap?.intelligence.category, .television)
            } else {
                XCTAssertEqual(memorySnap?.intelligence.category, .smartWatch)
                XCTAssertEqual(memorySnap?.presentationName, "Watch \(i)")
                XCTAssertEqual(diskSnap?.intelligence.category, .smartWatch)
            }
        }

        // Devices 20..24 were not probed
        for i in 20..<25 {
            let id = fakes[i].identifier
            let snap = coordinator.device(for: id)
            XCTAssertNotNil(snap)
            XCTAssertNil(snap?.gattEvidence)
        }
    }

    // =========================================================================
    // MARK: - 18. Challenger Stress: Queue Flooding with 500 Peripherals Burst
    // =========================================================================

    func testQueueFloodingStressWithFiveHundredPeripherals() {
        var createdProbesCount = 0
        var completedProbesCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            createdProbesCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.modelNumber = "Model-\(createdProbesCount)"
                probe.completeWithSuccess(evidence: evidence)
                completedProbesCount += 1
            }
            return probe
        }

        coordinator.startActive()

        // Flood with 500 connectable peripherals
        var discoveredIDs: [UUID] = []
        for i in 1...500 {
            let fake = discoverPeripheral(name: "Flooded Device \(i)")
            discoveredIDs.append(fake.identifier)
        }

        // Must strictly enforce cap of 20
        XCTAssertEqual(createdProbesCount, 20, "Must strictly create only 20 probes despite 500 queued devices")
        XCTAssertEqual(completedProbesCount, 20, "Must strictly complete 20 probes")
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty, "Queue must be completely drained after cap reached")
        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)

        // Verify first 20 have GATT evidence, 21..500 do not
        for i in 0..<20 {
            let id = discoveredIDs[i]
            let snap = coordinator.device(for: id)
            XCTAssertNotNil(snap)
            XCTAssertNotNil(snap?.gattEvidence, "Device \(i + 1) must have GATT evidence")
        }
        for i in 20..<500 {
            let id = discoveredIDs[i]
            let snap = coordinator.device(for: id)
            XCTAssertNotNil(snap)
            XCTAssertNil(snap?.gattEvidence, "Device \(i + 1) beyond cap must not have GATT evidence")
        }
    }

    // =========================================================================
    // MARK: - 19. Challenger Stress: 1000 Non-Connectable Beacons Interleaved
    // =========================================================================

    func testQueueFloodingOneThousandNonConnectableBeaconsInterleaved() {
        var createdProbesCount = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            createdProbesCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.deviceName = "Connectable Enriched"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()

        // Interleave 1000 non-connectable beacons with 30 connectable devices
        for i in 1...1000 {
            _ = discoverPeripheral(name: "Beacon \(i)", isConnectable: false)
            if i % 35 == 0 {
                _ = discoverPeripheral(name: "Connectable \(i / 35)", isConnectable: true)
            }
        }

        // Only connectable devices should be probed up to 20
        XCTAssertEqual(createdProbesCount, 20, "Only connectable devices up to cap of 20 should be probed")
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertNil(coordinator.activeGATTProbe)
    }

    // =========================================================================
    // MARK: - 20. Challenger Stress: Concurrency Invariant Under Async Interleaving
    // =========================================================================

    func testConcurrencyInvariantMaxOneActiveProbeDuringAsyncInterleaving() {
        var activeConnectionCount = 0
        var maxObservedConcurrentConnections = 0
        var activeProbes: [UUID: MockBackgroundGATTProbe] = [:]

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                activeConnectionCount += 1
                maxObservedConcurrentConnections = max(maxObservedConcurrentConnections, activeConnectionCount)
            }
            activeProbes[peripheral.identifier] = probe
            return probe
        }

        coordinator.startActive()

        var fakes: [FakeCBPeripheral] = []
        for i in 1...15 {
            let fake = discoverPeripheral(name: "Async Device \(i)")
            fakes.append(fake)
        }

        // Interleave completions and new discoveries
        for i in 0..<15 {
            let id = fakes[i].identifier
            guard let probe = activeProbes[id] else {
                XCTFail("Probe \(i) must be registered")
                return
            }

            XCTAssertEqual(activeConnectionCount, 1, "At every point before completion, active connections must be exactly 1")

            // Complete probe
            activeConnectionCount -= 1
            var evidence = GATTDeviceEvidence()
            evidence.identity.deviceName = "Enriched \(i)"
            probe.completeWithSuccess(evidence: evidence)

            // Discover another device while queue is draining
            if i < 5 {
                let extraFake = discoverPeripheral(name: "Extra Async Device \(i)")
                fakes.append(extraFake)
            }
        }

        // Drain any remaining in fakes up to 20
        let remainingCount = min(fakes.count, 20)
        for i in 15..<remainingCount {
            let id = fakes[i].identifier
            if let probe = activeProbes[id] {
                activeConnectionCount -= 1
                probe.completeWithSuccess(evidence: GATTDeviceEvidence())
            }
        }

        XCTAssertEqual(maxObservedConcurrentConnections, 1, "Max concurrent connections must NEVER exceed 1")
        XCTAssertEqual(activeConnectionCount, 0, "All connections must be terminated after draining")
        XCTAssertNil(coordinator.activeGATTProbe)
    }

    // =========================================================================
    // MARK: - 21. Challenger Stress: Timeout Progression Across All 20 Devices
    // =========================================================================

    func testTimeoutProgressionAcrossAllTwentyDevices() {
        var timeoutCount = 0
        var createdProbes: [UUID: MockBackgroundGATTProbe] = [:]

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            createdProbes[peripheral.identifier] = probe
            return probe
        }

        coordinator.startActive()

        var fakes: [FakeCBPeripheral] = []
        for i in 1...25 {
            let fake = discoverPeripheral(name: "Timing Out Device \(i)")
            fakes.append(fake)
        }

        // Force timeout on each device one by one
        for i in 0..<20 {
            let id = fakes[i].identifier
            guard let probe = createdProbes[id] else {
                XCTFail("Probe \(i) must be active for device \(id)")
                return
            }

            XCTAssertEqual(coordinator.currentProbeIdentifier, id)
            timeoutCount += 1
            probe.completeWithTimeout()
        }

        // All 20 timed out, queue must be clear, session cap reached
        XCTAssertEqual(timeoutCount, 20)
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)
        XCTAssertTrue(coordinator.state.isRunning, "Coordinator must remain running and healthy after 20 timeouts")
    }

    // =========================================================================
    // MARK: - 22. Challenger Stress: Cancellation During Active Probe with Queued Items
    // =========================================================================

    func testCancellationDuringActiveProbeWithQueuedItemsDoesNotStartNewProbe() {
        var createdProbeCount = 0
        var activeProbeInstance: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            createdProbeCount += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onCancel = {
                probe.completeWithFailure(error: BackgroundGATTProbeError.cancelled)
            }
            activeProbeInstance = probe
            return probe
        }

        coordinator.startActive()

        let dev1 = discoverPeripheral(name: "Device 1")
        let dev2 = discoverPeripheral(name: "Device 2")
        let dev3 = discoverPeripheral(name: "Device 3")

        XCTAssertEqual(createdProbeCount, 1, "Only Device 1 should have an active probe created initially")
        XCTAssertEqual(coordinator.pendingGATTProbeQueue, [dev2.identifier, dev3.identifier])
        XCTAssertNotNil(coordinator.activeGATTProbe)

        // Stop the coordinator while probe 1 is in-flight and dev2, dev3 are queued
        coordinator.stop()

        XCTAssertFalse(coordinator.state.isRunning, "Coordinator must be idle after stop")
        XCTAssertNil(coordinator.activeGATTProbe, "Active probe must be nil after stop")
        XCTAssertNil(coordinator.currentProbeIdentifier, "Current probe identifier must be nil after stop")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty, "Queue must be empty after stop")
        XCTAssertEqual(createdProbeCount, 1, "No secondary probe (for Device 2 or 3) should have been created during stop")
    }

    // =========================================================================
    // MARK: - 23. Challenger Stress: Rapid Scan Start/Stop Flapping
    // =========================================================================

    func testRapidScanStartStopFlappingStress() {
        for cycle in 1...15 {
            var probesInCycle = 0
            coordinator.probeFactory = { peripheral, scanner, timeout, completion in
                probesInCycle += 1
                let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
                probe.onStart = {
                    var evidence = GATTDeviceEvidence()
                    evidence.identity.deviceName = "Cycle \(cycle) Device"
                    probe.completeWithSuccess(evidence: evidence)
                }
                return probe
            }

            coordinator.startActive()
            XCTAssertTrue(coordinator.state.isRunning)

            for i in 1...5 {
                _ = discoverPeripheral(name: "Flapping Device \(cycle)_\(i)")
            }

            XCTAssertEqual(probesInCycle, 5)
            XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 5)

            coordinator.stop()
            XCTAssertFalse(coordinator.state.isRunning)
            XCTAssertNil(coordinator.activeGATTProbe)
            XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        }
    }

    // =========================================================================
    // MARK: - 24. Challenger Stress: Duplicate RPA Multi-Hop Aliasing Resolution
    // =========================================================================

    func testDuplicateRPAMultiHopResolutionAcrossThreeGenerations() {
        let hardwareSerialNumber = "HARDWARE-SN-TRIPLE-HOP-001"

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.serialNumber = hardwareSerialNumber
                evidence.identity.manufacturerName = "Nordic Semiconductor"
                evidence.identity.deviceName = "Unified Sensor"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()

        // Sighting 1 under UUID 1
        let dev1 = discoverPeripheral(name: "Unnamed device", rssi: -70)
        let snap1 = coordinator.device(for: dev1.identifier)
        XCTAssertEqual(snap1?.presentationName, "Unified Sensor")
        XCTAssertEqual(snap1?.sightingCount, 1)

        // Sighting 2 under UUID 2 (RPA rotated)
        let dev2 = discoverPeripheral(name: "Unnamed device", rssi: -65)
        let snap2 = coordinator.device(for: dev2.identifier)
        XCTAssertEqual(snap2?.presentationName, "Unified Sensor")
        XCTAssertEqual(snap2?.sightingCount, 2)

        // Sighting 3 under UUID 3 (RPA rotated again)
        let dev3 = discoverPeripheral(name: "Unnamed device", rssi: -50)
        let snap3 = coordinator.device(for: dev3.identifier)
        XCTAssertEqual(snap3?.presentationName, "Unified Sensor")
        XCTAssertEqual(snap3?.sightingCount, 3)

        // Multi-hop resolution: querying UUID 1, UUID 2, and UUID 3 should all resolve to latest unified record
        let queryFrom3 = coordinator.device(for: dev3.identifier)
        let queryFrom2 = coordinator.device(for: dev2.identifier)
        let queryFrom1 = coordinator.device(for: dev1.identifier)

        XCTAssertNotNil(queryFrom3)
        XCTAssertNotNil(queryFrom2)
        XCTAssertNotNil(queryFrom1, "Querying original UUID 1 after two rotations must resolve")
        XCTAssertEqual(queryFrom3?.gattEvidence?.identity.serialNumber, hardwareSerialNumber)
        XCTAssertEqual(queryFrom2?.gattEvidence?.identity.serialNumber, hardwareSerialNumber)
        XCTAssertEqual(queryFrom1?.gattEvidence?.identity.serialNumber, hardwareSerialNumber)
        XCTAssertEqual(queryFrom1?.sightingCount, 3, "Original UUID 1 must resolve to latest snapshot with sightingCount 3")
    }

    // =========================================================================
    // MARK: - 25. Challenger Stress: Scanner Cache Eviction Before Probe Starts
    // =========================================================================

    func testScannerCacheEvictionBeforeProbeStartsDoesNotStallQueue() {
        var probe1: MockBackgroundGATTProbe?
        var probe3: MockBackgroundGATTProbe?

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            if probe1 == nil {
                probe1 = probe
            } else {
                probe3 = probe
            }
            return probe
        }

        coordinator.startActive()

        let dev1 = discoverPeripheral(name: "Device 1")
        let dev2 = discoverPeripheral(name: "Device 2")
        let dev3 = discoverPeripheral(name: "Device 3")

        XCTAssertEqual(coordinator.currentProbeIdentifier, dev1.identifier)
        XCTAssertEqual(coordinator.pendingGATTProbeQueue, [dev2.identifier, dev3.identifier])

        // Evict dev2 from scanner cache before its probe starts
        scanner.trimCachedPeripherals(to: [dev1.identifier, dev3.identifier])
        XCTAssertNil(scanner.peripheral(for: dev2.identifier))

        // Complete probe 1
        var evidence1 = GATTDeviceEvidence()
        evidence1.identity.deviceName = "Enriched 1"
        probe1?.completeWithSuccess(evidence: evidence1)

        // Coordinator must skip evicted dev2 and advance directly to dev3
        XCTAssertNotNil(coordinator.activeGATTProbe)
        XCTAssertEqual(coordinator.currentProbeIdentifier, dev3.identifier, "Queue must advance to dev3 after skipping evicted dev2")
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)

        // Complete probe 3
        var evidence3 = GATTDeviceEvidence()
        evidence3.identity.deviceName = "Enriched 3"
        probe3?.completeWithSuccess(evidence: evidence3)

        XCTAssertNil(coordinator.activeGATTProbe)
        XCTAssertNil(coordinator.currentProbeIdentifier)
    }

    // =========================================================================
    // MARK: - 26. Challenger Stress: Reentrant Synchronous Probe Completion
    // =========================================================================

    func testReentrantImmediateSynchronousProbeCompletionStress() {
        var probesCreated = 0

        coordinator.probeFactory = { peripheral, scanner, timeout, completion in
            probesCreated += 1
            let probe = MockBackgroundGATTProbe(peripheral: peripheral, scanner: scanner, timeout: timeout, completion: completion)
            probe.onStart = {
                var evidence = GATTDeviceEvidence()
                evidence.identity.modelNumber = "Sync-Model-\(probesCreated)"
                probe.completeWithSuccess(evidence: evidence)
            }
            return probe
        }

        coordinator.startActive()

        // Discover 25 peripherals
        for i in 1...25 {
            _ = discoverPeripheral(name: "Sync Device \(i)")
        }

        XCTAssertEqual(probesCreated, 20, "Must create and synchronously complete exactly 20 probes")
        XCTAssertEqual(coordinator.probedPeripheralIdentifiers.count, 20)
        XCTAssertTrue(coordinator.pendingGATTProbeQueue.isEmpty)
        XCTAssertNil(coordinator.activeGATTProbe)
    }
}

