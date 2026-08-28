import CoreLocation
import XCTest

@testable import SignalTrail

final class ScanCoordinatorTests: XCTestCase {
  func testMergeSnapshotIgnoresMinorRSSIChangesUntilThresholdIsExceeded() {
    let identifier = UUID()
    let now = Date()
    let firstAdvertisement = BLEAdvertisement(
      localName: "Tracker",
      manufacturerDataHex: "4C0001",
      companyIdentifier: 0x004C,
      serviceUUIDs: [],
      solicitedServiceUUIDs: [],
      serviceData: [:],
      overflowServiceUUIDs: [],
      txPower: nil,
      isConnectable: true
    )
    let initialResult = ScanCoordinator.mergeSnapshot(
      existing: nil,
      identifier: identifier,
      name: "Tracker",
      advertisement: firstAdvertisement,
      rssi: -60,
      timestamp: now
    )

    let minorChangeResult = ScanCoordinator.mergeSnapshot(
      existing: initialResult.snapshot,
      identifier: identifier,
      name: "Tracker",
      advertisement: firstAdvertisement,
      rssi: -62,
      timestamp: now.addingTimeInterval(0.5)
    )

    XCTAssertFalse(minorChangeResult.meaningfulRSSIChange)
    XCTAssertEqual(minorChangeResult.snapshot.latestRSSI, -60)
    XCTAssertEqual(minorChangeResult.snapshot.sightingCount, 2)
    XCTAssertEqual(
      minorChangeResult.snapshot.lastSeenMetadataTag,
      firstAdvertisement.metadataTag
    )

    let updatedAdvertisement = BLEAdvertisement(
      localName: "Tracker v2",
      manufacturerDataHex: "4C0002",
      companyIdentifier: 0x004C,
      serviceUUIDs: [],
      solicitedServiceUUIDs: [],
      serviceData: [:],
      overflowServiceUUIDs: [],
      txPower: nil,
      isConnectable: true
    )
    let significantChangeResult = ScanCoordinator.mergeSnapshot(
      existing: minorChangeResult.snapshot,
      identifier: identifier,
      name: "Tracker v2",
      advertisement: updatedAdvertisement,
      rssi: -54,
      timestamp: now.addingTimeInterval(1)
    )

    XCTAssertTrue(significantChangeResult.metadataChanged)
    XCTAssertTrue(significantChangeResult.meaningfulRSSIChange)
    XCTAssertEqual(significantChangeResult.snapshot.displayName, "Tracker v2")
    XCTAssertEqual(significantChangeResult.snapshot.latestRSSI, -54)
    XCTAssertEqual(
      significantChangeResult.snapshot.lastSeenMetadataTag,
      updatedAdvertisement.metadataTag
    )
  }

  func testShouldRecordObservationCoalescesRepeatedSightings() {
    let now = Date()
    let previous = ScanCoordinator.RecordedObservationState(
      recordedAt: now,
      metadataTag: "alpha",
      rssi: -60
    )

    XCTAssertFalse(
      ScanCoordinator.shouldRecordObservation(
        previous: previous,
        currentTimestamp: now.addingTimeInterval(2),
        metadataTag: "alpha",
        rssi: -62,
        minimumInterval: 5
      )
    )

    XCTAssertTrue(
      ScanCoordinator.shouldRecordObservation(
        previous: previous,
        currentTimestamp: now.addingTimeInterval(2),
        metadataTag: "beta",
        rssi: -62,
        minimumInterval: 5
      )
    )

    XCTAssertTrue(
      ScanCoordinator.shouldRecordObservation(
        previous: previous,
        currentTimestamp: now.addingTimeInterval(6),
        metadataTag: "alpha",
        rssi: -62,
        minimumInterval: 5
      )
    )
  }

  func testPruneSnapshotsDropsDevicesOutsideRetentionWindow() {
    let now = Date()
    let recent = makeSnapshot(name: "Recent", lastSeen: now.addingTimeInterval(-10), rssi: -55)
    let stale = makeSnapshot(name: "Stale", lastSeen: now.addingTimeInterval(-120), rssi: -45)

    let pruned = ScanCoordinator.pruneSnapshots(
      [
        recent.peripheralIdentifier: recent,
        stale.peripheralIdentifier: stale,
      ],
      now: now,
      maximumAge: 90,
      maximumCount: 10
    )

    XCTAssertEqual(pruned.count, 1)
    XCTAssertEqual(pruned[recent.peripheralIdentifier]?.displayName, "Recent")
    XCTAssertNil(pruned[stale.peripheralIdentifier])
  }

  func testPruneSnapshotsKeepsMostRecentDevicesWhenCountIsExceeded() {
    let now = Date()
    let newest = makeSnapshot(name: "Newest", lastSeen: now, rssi: -70)
    let newer = makeSnapshot(name: "Newer", lastSeen: now.addingTimeInterval(-1), rssi: -65)
    let older = makeSnapshot(name: "Older", lastSeen: now.addingTimeInterval(-2), rssi: -40)

    let pruned = ScanCoordinator.pruneSnapshots(
      [
        newest.peripheralIdentifier: newest,
        newer.peripheralIdentifier: newer,
        older.peripheralIdentifier: older,
      ],
      now: now,
      maximumAge: 90,
      maximumCount: 2
    )

    XCTAssertEqual(pruned.count, 2)
    XCTAssertNotNil(pruned[newest.peripheralIdentifier])
    XCTAssertNotNil(pruned[newer.peripheralIdentifier])
    XCTAssertNil(pruned[older.peripheralIdentifier])
  }

  func testReconcileGATTIdentityDuplicatesKeepsEstablishedDeviceName() {
    let now = Date()
    let modelIdentifier = UUID()
    let namedIdentifier = UUID()
    let evidence = makeMacBookEvidence(deviceName: "Jm1", modelNumber: "MacBookPro18,3")

    var modelSnapshot = makeSnapshot(
      identifier: modelIdentifier,
      name: "MacBookPro18,3",
      lastSeen: now.addingTimeInterval(-1),
      rssi: -60
    )
    modelSnapshot.gattEvidence = evidence

    var namedSnapshot = makeSnapshot(
      identifier: namedIdentifier,
      name: "Jm1",
      lastSeen: now,
      rssi: -64
    )
    namedSnapshot.gattEvidence = evidence

    let reconciled = ScanCoordinator.reconcileGATTIdentityDuplicates(
      [
        modelIdentifier: modelSnapshot,
        namedIdentifier: namedSnapshot,
      ],
      preferredIdentifier: modelIdentifier
    )

    XCTAssertEqual(reconciled.count, 1)
    XCTAssertEqual(reconciled.values.first?.displayName, "Jm1")
    XCTAssertEqual(reconciled.values.first?.presentationName, "Jm1")
    XCTAssertEqual(reconciled.values.first?.sightingCount, 2)
  }

  func testPresentationNamePrefersGATTDeviceNameBeforeModelNumber() {
    var snapshot = makeSnapshot(name: "Unnamed device", lastSeen: Date(), rssi: -60)
    snapshot.gattEvidence = makeMacBookEvidence(deviceName: "Jm1", modelNumber: "MacBookPro18,3")

    XCTAssertEqual(snapshot.presentationName, "Jm1")
  }

  func testScanCoordinatorUpdateCustomNameAndPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let locationProvider = MockLocationProvider()
    let settingsStore = SettingsStore()
    let notificationService = NotificationService()

    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: locationProvider,
      store: store,
      settingsStore: settingsStore,
      notificationService: notificationService
    )

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Beacon",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot)

    coordinator.updateCustomName("Front Porch Beacon", for: id)

    XCTAssertEqual(coordinator.device(for: id)?.customName, "Front Porch Beacon")
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Front Porch Beacon")
    XCTAssertEqual(store.loadDeviceRecord(for: id)?.customName, "Front Porch Beacon")

    coordinator.updateCustomName(nil, for: id)
    XCTAssertNil(coordinator.device(for: id)?.customName)
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Beacon")
    XCTAssertNil(store.loadDeviceRecord(for: id)?.customName)
  }

  func testScanCoordinatorClearStoredDataPurgesDiskAndPreservesLiveAdvertisedState() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let locationProvider = MockLocationProvider()
    let settingsStore = SettingsStore()
    let notificationService = NotificationService()

    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: locationProvider,
      store: store,
      settingsStore: settingsStore,
      notificationService: notificationService
    )

    let id = UUID()
    let charSnapshot = GATTCharacteristicSnapshot(
      uuid: "2A19",
      properties: ["Read"],
      valueHex: "64",
      isNotifying: false
    )
    let serviceSnapshot = GATTServiceSnapshot(uuid: "180F", characteristics: [charSnapshot])
    var evidence = GATTDeviceEvidence()
    evidence.identity.deviceName = "Sensor Device"

    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Sensor Device",
      customName: "My Sensor",
      latestRSSI: -55,
      strongestRSSI: -50,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 5,
      advertisement: BLEAdvertisement(
        localName: "Sensor Device",
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        serviceUUIDs: ["180F"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      ),
      gattEvidence: evidence,
      exploredServices: [serviceSnapshot],
      rssiHistory: [DeviceRSSISample(rssi: -55)]
    )

    try store.saveDeviceRecord(snapshot)
    coordinator.updateCustomName("My Sensor", for: id)
    XCTAssertNotNil(store.loadDeviceRecord(for: id))

    coordinator.clearStoredData(for: id)

    // Disk file must be purged
    XCTAssertNil(store.loadDeviceRecord(for: id))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))

    // In-memory snapshot should be retained with exploratory data cleared and basic advertised info intact
    let retained = coordinator.device(for: id)
    XCTAssertNotNil(retained)
    XCTAssertNil(retained?.customName)
    XCTAssertNil(retained?.gattEvidence)
    XCTAssertEqual(retained?.exploredServices.count, 0)
    XCTAssertEqual(retained?.rssiHistory.count, 0)
    XCTAssertEqual(retained?.advertisement.localName, "Sensor Device")
    XCTAssertEqual(retained?.presentationName, "Sensor Device")
  }

  func testScanCoordinatorExportDeviceJSON() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let locationProvider = MockLocationProvider()
    let settingsStore = SettingsStore()
    let notificationService = NotificationService()

    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: locationProvider,
      store: store,
      settingsStore: settingsStore,
      notificationService: notificationService
    )

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Export Device",
      customName: "Export Alias",
      latestRSSI: -65,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 3,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot)

    guard let exportURL = coordinator.exportDeviceJSON(for: id) else {
      XCTFail("Export URL should not be nil")
      return
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    let data = try Data(contentsOf: exportURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let str = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
    }
    let decoded = try decoder.decode(BLEDeviceSnapshot.self, from: data)
    XCTAssertEqual(decoded.peripheralIdentifier, id)
    XCTAssertEqual(decoded.customName, "Export Alias")
  }

  func testScanCoordinatorEnrichDeviceWithGATTAndExploredServices() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let locationProvider = MockLocationProvider()
    let settingsStore = SettingsStore()
    let notificationService = NotificationService()

    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: locationProvider,
      store: store,
      settingsStore: settingsStore,
      notificationService: notificationService
    )

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Generic Peripheral",
      latestRSSI: -70,
      strongestRSSI: -70,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot)

    var evidence = GATTDeviceEvidence()
    evidence.identity.deviceName = "Smart Thermostat"
    evidence.identity.manufacturerName = "Acme Sensors"

    let charSnapshot = GATTCharacteristicSnapshot(
      uuid: "2A6E",
      properties: ["Read"],
      valueHex: "0018",
      isNotifying: false
    )
    let serviceSnapshot = GATTServiceSnapshot(uuid: "181A", characteristics: [charSnapshot])

    coordinator.enrichDevice(id, with: evidence, exploredServices: [serviceSnapshot])

    let updated = coordinator.device(for: id)
    XCTAssertEqual(updated?.gattEvidence?.identity.deviceName, "Smart Thermostat")
    XCTAssertEqual(updated?.exploredServices.count, 1)
    XCTAssertEqual(updated?.exploredServices.first?.uuid, "181A")

    let onDisk = store.loadDeviceRecord(for: id)
    XCTAssertEqual(onDisk?.gattEvidence?.identity.manufacturerName, "Acme Sensors")
    XCTAssertEqual(onDisk?.exploredServices.first?.characteristics.first?.uuid, "2A6E")
  }

  func testClearStoredDataForNonExistentDeviceDoesNotCrashOrCorruptState() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let existingID = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: existingID,
      displayName: "Existing Device",
      customName: "Existing Alias",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot)

    let nonExistentID = UUID()
    coordinator.clearStoredData(for: nonExistentID)

    let retained = store.loadDeviceRecord(for: existingID)
    XCTAssertNotNil(retained)
    XCTAssertEqual(retained?.customName, "Existing Alias")
  }

  func testScanCoordinatorCacheIndexingAndHydration() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let id1 = UUID()
    let id2 = UUID()

    let snapshot1 = BLEDeviceSnapshot(
      peripheralIdentifier: id1,
      displayName: "Device One",
      customName: "Office Sensor",
      latestRSSI: -65,
      strongestRSSI: -65,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: "Device One",
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        serviceUUIDs: ["180A"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )

    var evidence2 = GATTDeviceEvidence()
    evidence2.identity.deviceName = "Hydro Gauge"
    let service2 = GATTServiceSnapshot(uuid: "181B", characteristics: [])
    let snapshot2 = BLEDeviceSnapshot(
      peripheralIdentifier: id2,
      displayName: "Device Two",
      customName: "Water Tank Gauge",
      latestRSSI: -80,
      strongestRSSI: -75,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 5,
      advertisement: BLEAdvertisement(
        localName: "Device Two",
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        serviceUUIDs: ["181B"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      ),
      gattEvidence: evidence2,
      exploredServices: [service2]
    )

    try store.saveDeviceRecord(snapshot1)
    try store.saveDeviceRecord(snapshot2)

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let dev1 = coordinator.device(for: id1)
    let dev2 = coordinator.device(for: id2)

    XCTAssertNotNil(dev1)
    XCTAssertEqual(dev1?.customName, "Office Sensor")
    XCTAssertEqual(dev1?.presentationName, "Office Sensor")

    XCTAssertNotNil(dev2)
    XCTAssertEqual(dev2?.customName, "Water Tank Gauge")
    XCTAssertEqual(dev2?.gattEvidence?.identity.deviceName, "Hydro Gauge")
    XCTAssertEqual(dev2?.exploredServices.first?.uuid, "181B")

    coordinator.updateCustomName("HQ Lab Sensor", for: id1)
    XCTAssertEqual(coordinator.device(for: id1)?.customName, "HQ Lab Sensor")
    XCTAssertEqual(store.loadDeviceRecord(for: id1)?.customName, "HQ Lab Sensor")

    coordinator.clearStoredData(for: id2)
    XCTAssertNil(store.loadDeviceRecord(for: id2))
    let clearedDev2 = coordinator.device(for: id2)
    XCTAssertNil(clearedDev2?.customName)
    XCTAssertNil(clearedDev2?.gattEvidence)
    XCTAssertEqual(clearedDev2?.exploredServices.count, 0)
    XCTAssertEqual(clearedDev2?.displayName, "Device Two")
  }

  func testScanCoordinatorMultipleDeviceMutationsStress() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    var ids: [UUID] = []
    for i in 1...20 {
      let id = UUID()
      ids.append(id)
      let snapshot = BLEDeviceSnapshot(
        peripheralIdentifier: id,
        displayName: "Batch Dev \(i)",
        latestRSSI: -50 - i,
        strongestRSSI: -50,
        firstSeen: Date(),
        lastSeen: Date(),
        sightingCount: 1,
        advertisement: .empty
      )
      try store.saveDeviceRecord(snapshot)
    }

    for (index, id) in ids.enumerated() {
      coordinator.updateCustomName("Custom Alias \(index)", for: id)
    }

    for i in 0..<10 {
      var ev = GATTDeviceEvidence()
      ev.identity.modelNumber = "Model-\(i)"
      coordinator.enrichDevice(ids[i], with: ev)
    }

    for i in 0..<10 {
      let exportURL = coordinator.exportDeviceJSON(for: ids[i])
      XCTAssertNotNil(exportURL)
      guard let url = exportURL else { continue }
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
      let data = try Data(contentsOf: url)
      XCTAssertTrue(data.count > 0)
    }

    for i in 15..<20 {
      coordinator.clearStoredData(for: ids[i])
      XCTAssertNil(store.loadDeviceRecord(for: ids[i]))
    }

    for i in 0..<15 {
      let rec = store.loadDeviceRecord(for: ids[i])
      XCTAssertNotNil(rec)
      XCTAssertEqual(rec?.customName, "Custom Alias \(i)")
    }
  }

  func testClearStoredDataDeletesDiskFileAndPurgesExploratoryMetadataWhilePreservingLiveAdvertisedSnapshot() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let locationProvider = MockLocationProvider()
    let settingsStore = SettingsStore()
    let notificationService = NotificationService()

    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: locationProvider,
      store: store,
      settingsStore: settingsStore,
      notificationService: notificationService
    )

    let id = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let firstSeen = now.addingTimeInterval(-120)
    let lastSeen = now

    let charSnapshot = GATTCharacteristicSnapshot(
      uuid: "2A19",
      properties: ["Read", "Notify"],
      valueHex: "64",
      decodedValue: GATTDecodedValue(
        displayText: "100%",
        rawHex: "64",
        fields: [GATTDecodedField(name: "Level", value: "100%")]
      ),
      descriptors: [GATTDescriptorSnapshot(uuid: "2902", displayValue: "Enabled", rawHex: "0100")],
      isNotifying: true
    )
    let serviceSnapshot = GATTServiceSnapshot(uuid: "180F", characteristics: [charSnapshot])
    var evidence = GATTDeviceEvidence()
    evidence.identity.deviceName = "Sensor Device"
    evidence.identity.manufacturerName = "Nordic Semiconductor"
    evidence.identity.modelNumber = "PCA10056"
    evidence.identity.serialNumber = "SN-998877"

    let advertisement = BLEAdvertisement(
      localName: "Sensor Device",
      manufacturerDataHex: "5900010203",
      companyIdentifier: 0x0059,
      memberServiceUUIDs: ["FEAA"],
      serviceUUIDs: ["180F"],
      solicitedServiceUUIDs: [],
      serviceData: ["180F": "64"],
      overflowServiceUUIDs: [],
      txPower: -4,
      isConnectable: true
    )

    let samples = [
      DeviceRSSISample(timestamp: now.addingTimeInterval(-60), rssi: -70),
      DeviceRSSISample(timestamp: now, rssi: -55)
    ]

    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Sensor Device",
      customName: "Living Room Beacon",
      latestRSSI: -55,
      strongestRSSI: -50,
      firstSeen: firstSeen,
      lastSeen: lastSeen,
      lastSeenMetadataTag: advertisement.metadataTag,
      sightingCount: 5,
      advertisement: advertisement,
      gattEvidence: evidence,
      exploredServices: [serviceSnapshot],
      lastLocation: DeviceLocationMetadata(latitude: 37.77, longitude: -122.41),
      rssiHistory: samples
    )

    try store.saveDeviceRecord(snapshot)
    coordinator.updateCustomName("Living Room Beacon", for: id)
    coordinator.enrichDevice(id, with: evidence, exploredServices: [serviceSnapshot])

    XCTAssertTrue(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))
    XCTAssertEqual(coordinator.device(for: id)?.customName, "Living Room Beacon")
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Living Room Beacon")
    XCTAssertEqual(coordinator.device(for: id)?.exploredServices.count, 1)
    XCTAssertEqual(coordinator.device(for: id)?.gattEvidence?.identity.manufacturerName, "Nordic Semiconductor")

    coordinator.clearStoredData(for: id)

    // 1. Verify disk file is purged
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))
    XCTAssertNil(store.loadDeviceRecord(for: id))

    // 2. Verify exploratory metadata in memory is purged
    let retained = coordinator.device(for: id)
    XCTAssertNotNil(retained)
    XCTAssertNil(retained?.customName)
    XCTAssertNil(retained?.gattEvidence)
    XCTAssertEqual(retained?.exploredServices.count, 0)
    XCTAssertEqual(retained?.rssiHistory.count, 0)

    // 3. Verify live advertised information is preserved
    XCTAssertEqual(retained?.peripheralIdentifier, id)
    XCTAssertEqual(retained?.latestRSSI, -55)
    XCTAssertEqual(retained?.strongestRSSI, -50)
    XCTAssertEqual(retained?.sightingCount, 5)
    XCTAssertEqual(retained?.firstSeen, firstSeen)
    XCTAssertEqual(retained?.lastSeen, lastSeen)
    XCTAssertEqual(retained?.advertisement.localName, "Sensor Device")
    XCTAssertEqual(retained?.advertisement.companyIdentifier, 0x0059)
    XCTAssertEqual(retained?.advertisement.serviceUUIDs, ["180F"])
    XCTAssertEqual(retained?.displayName, "Sensor Device")
    XCTAssertEqual(retained?.presentationName, "Sensor Device")

    // 4. Verify presence in coordinator.devices list
    XCTAssertTrue(coordinator.devices.contains(where: { $0.peripheralIdentifier == id }))
  }

  func testClearStoredDataCancelsPendingDebouncedPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let scanner = BluetoothScanner()
    let coordinator = ScanCoordinator(
      scanner: scanner,
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Debounced Device",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot)
    coordinator.updateCustomName("Temporary Name", for: id)

    coordinator.clearStoredData(for: id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))

    coordinator.stop()

    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))
    XCTAssertNil(store.loadDeviceRecord(for: id))
  }

  func testClearStoredDataIsIsolatedToTargetDevice() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let idA = UUID()
    let idB = UUID()

    let snapshotA = BLEDeviceSnapshot(
      peripheralIdentifier: idA,
      displayName: "Device A",
      customName: "Alias A",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 2,
      advertisement: .empty
    )

    let snapshotB = BLEDeviceSnapshot(
      peripheralIdentifier: idB,
      displayName: "Device B",
      customName: "Alias B",
      latestRSSI: -70,
      strongestRSSI: -70,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 4,
      advertisement: .empty
    )

    try store.saveDeviceRecord(snapshotA)
    try store.saveDeviceRecord(snapshotB)
    coordinator.updateCustomName("Alias A", for: idA)
    coordinator.updateCustomName("Alias B", for: idB)

    coordinator.clearStoredData(for: idA)

    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: idA).path))
    XCTAssertNil(store.loadDeviceRecord(for: idA))
    XCTAssertNil(coordinator.device(for: idA)?.customName)

    XCTAssertTrue(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: idB).path))
    let loadedB = store.loadDeviceRecord(for: idB)
    XCTAssertNotNil(loadedB)
    XCTAssertEqual(loadedB?.customName, "Alias B")
    XCTAssertEqual(coordinator.device(for: idB)?.customName, "Alias B")
    XCTAssertEqual(coordinator.device(for: idB)?.presentationName, "Alias B")
  }

  func testCustomNameMutationReactivityAndDiskPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Adv Beacon",
      latestRSSI: -55,
      strongestRSSI: -55,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: "Adv Beacon",
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        serviceUUIDs: [],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )
    try store.saveDeviceRecord(snapshot)

    // 1. Initial custom name
    coordinator.updateCustomName("Front Door Sensor", for: id)
    XCTAssertEqual(coordinator.device(for: id)?.customName, "Front Door Sensor")
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Front Door Sensor")
    XCTAssertEqual(store.loadDeviceRecord(for: id)?.customName, "Front Door Sensor")

    // 2. Update custom name
    coordinator.updateCustomName("Back Door Sensor", for: id)
    XCTAssertEqual(coordinator.device(for: id)?.customName, "Back Door Sensor")
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Back Door Sensor")
    XCTAssertEqual(store.loadDeviceRecord(for: id)?.customName, "Back Door Sensor")

    // 3. Set whitespace-only string (should trim and revert)
    coordinator.updateCustomName("   ", for: id)
    XCTAssertNil(coordinator.device(for: id)?.customName)
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Adv Beacon")
    XCTAssertNil(store.loadDeviceRecord(for: id)?.customName)

    // 4. Set non-empty again then nil
    coordinator.updateCustomName("Side Gate", for: id)
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Side Gate")
    coordinator.updateCustomName(nil, for: id)
    XCTAssertNil(coordinator.device(for: id)?.customName)
    XCTAssertEqual(coordinator.device(for: id)?.presentationName, "Adv Beacon")
    XCTAssertNil(store.loadDeviceRecord(for: id)?.customName)
  }

  func testCustomNameMutationOnDeviceNotInActiveScanUpdatesStorageAndCache() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let id = UUID()
    let offlineSnapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Offline Peripheral",
      latestRSSI: -80,
      strongestRSSI: -80,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(offlineSnapshot)

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    coordinator.updateCustomName("Offline Custom Name", for: id)

    let loaded = store.loadDeviceRecord(for: id)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.customName, "Offline Custom Name")
    XCTAssertEqual(loaded?.presentationName, "Offline Custom Name")

    let fromCoordinator = coordinator.device(for: id)
    XCTAssertNotNil(fromCoordinator)
    XCTAssertEqual(fromCoordinator?.customName, "Offline Custom Name")
    XCTAssertEqual(fromCoordinator?.presentationName, "Offline Custom Name")
  }

  func testExportDeviceJSONMatchesSnapshotAndIsValidJSON() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: SettingsStore(),
      notificationService: NotificationService()
    )

    let id = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let char = GATTCharacteristicSnapshot(
      uuid: "2A37",
      properties: ["Notify"],
      valueHex: "0048",
      decodedValue: GATTDecodedValue(displayText: "72 bpm", rawHex: "0048", fields: [GATTDecodedField(name: "Rate", value: "72")]),
      isNotifying: true
    )
    let service = GATTServiceSnapshot(uuid: "180D", characteristics: [char])
    var evidence = GATTDeviceEvidence()
    evidence.identity.deviceName = "Heart Rate Monitor"
    evidence.identity.manufacturerName = "Cardio Health"

    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Heart Rate Monitor",
      customName: "Chest Strap HR",
      latestRSSI: -62,
      strongestRSSI: -58,
      firstSeen: now.addingTimeInterval(-300),
      lastSeen: now,
      lastSeenMetadataTag: "HRM|0059|180D",
      sightingCount: 20,
      advertisement: BLEAdvertisement(
        localName: "Heart Rate Monitor",
        manufacturerDataHex: "5900",
        companyIdentifier: 0x0059,
        serviceUUIDs: ["180D"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: 0,
        isConnectable: true
      ),
      gattEvidence: evidence,
      exploredServices: [service],
      lastLocation: DeviceLocationMetadata(latitude: 40.7128, longitude: -74.0060, horizontalAccuracy: 5.0, timestamp: now),
      rssiHistory: [DeviceRSSISample(timestamp: now, rssi: -62)]
    )

    try store.saveDeviceRecord(snapshot)
    coordinator.updateCustomName("Chest Strap HR", for: id)
    coordinator.enrichDevice(id, with: evidence, exploredServices: [service])

    guard let exportURL = coordinator.exportDeviceJSON(for: id) else {
      XCTFail("Export URL should not be nil")
      return
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: exportURL.path))
    XCTAssertEqual(exportURL.lastPathComponent, "\(id.uuidString).json")

    let data = try Data(contentsOf: exportURL)
    XCTAssertTrue(data.count > 0)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let str = try container.decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
    }

    let decoded = try decoder.decode(BLEDeviceSnapshot.self, from: data)
    XCTAssertEqual(decoded.peripheralIdentifier, id)
    XCTAssertEqual(decoded.displayName, "Heart Rate Monitor")
    XCTAssertEqual(decoded.customName, "Chest Strap HR")
    XCTAssertEqual(decoded.presentationName, "Chest Strap HR")
    XCTAssertEqual(decoded.latestRSSI, -62)
    XCTAssertEqual(decoded.strongestRSSI, -58)
    XCTAssertEqual(decoded.sightingCount, 20)
    XCTAssertEqual(decoded.advertisement.companyIdentifier, 0x0059)
    XCTAssertEqual(decoded.gattEvidence?.identity.manufacturerName, "Cardio Health")
    XCTAssertEqual(decoded.exploredServices.count, 1)
    XCTAssertEqual(decoded.exploredServices.first?.characteristics.first?.uuid, "2A37")
    XCTAssertEqual(decoded.lastLocation?.latitude, 40.7128)
    XCTAssertEqual(decoded.rssiHistory.count, 1)

    let unknownID = UUID()
    XCTAssertNil(coordinator.exportDeviceJSON(for: unknownID))
  }

  func testScanViewModelReactivityForCustomNameAndClearStoredData() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try LocalStore(rootURL: tempDir)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let settingsStore = SettingsStore()
    let coordinator = ScanCoordinator(
      scanner: BluetoothScanner(),
      locationProvider: MockLocationProvider(),
      store: store,
      settingsStore: settingsStore,
      notificationService: NotificationService()
    )

    let viewModel = ScanViewModel(coordinator: coordinator, store: store, settingsStore: settingsStore)

    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "ViewModel Test Beacon",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: "ViewModel Test Beacon",
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        serviceUUIDs: [],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )
    try store.saveDeviceRecord(snapshot)

    viewModel.updateCustomName("Custom Beacon Label", for: id)
    XCTAssertEqual(store.loadDeviceRecord(for: id)?.customName, "Custom Beacon Label")

    let exportURL = viewModel.exportDeviceJSON(for: id)
    XCTAssertNotNil(exportURL)

    viewModel.clearStoredData(for: id)
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))
    XCTAssertNil(store.loadDeviceRecord(for: id))
  }

  private func makeSnapshot(name: String, lastSeen: Date, rssi: Int) -> BLEDeviceSnapshot {
    makeSnapshot(identifier: UUID(), name: name, lastSeen: lastSeen, rssi: rssi)
  }

  private func makeSnapshot(
    identifier: UUID,
    name: String,
    lastSeen: Date,
    rssi: Int
  ) -> BLEDeviceSnapshot {
    BLEDeviceSnapshot(
      peripheralIdentifier: identifier,
      displayName: name,
      latestRSSI: rssi,
      strongestRSSI: rssi,
      firstSeen: lastSeen,
      lastSeen: lastSeen,
      lastSeenMetadataTag: BLEAdvertisement.empty.metadataTag,
      sightingCount: 1,
      advertisement: .empty
    )
  }

  private func makeMacBookEvidence(deviceName: String, modelNumber: String) -> GATTDeviceEvidence {
    var evidence = GATTDeviceEvidence()
    evidence.identity.deviceName = deviceName
    evidence.identity.manufacturerName = "Apple Inc."
    evidence.identity.modelNumber = modelNumber
    return evidence
  }
}

final class MockLocationProvider: LocationProviding {
  var currentLocation: CLLocation?
  var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
  var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?

  func requestWhenInUseAuthorization() {}
  func startUpdating() {}
  func stopUpdating() {}
}
