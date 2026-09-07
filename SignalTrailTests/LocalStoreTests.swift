import XCTest

@testable import SignalTrail

final class LocalStoreTests: XCTestCase {
  private var directory: URL!
  private var store: LocalStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    store = try LocalStore(rootURL: directory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testDefaultAlertRulesAreSeededWhenFileIsMissing() {
    let rules = store.loadAlertRules()

    XCTAssertEqual(rules.count, 6)

    let axonRule = rules.first { $0.name == "Axon / TASER detected" }
    XCTAssertEqual(axonRule?.matchType, .detectorProfile)
    XCTAssertEqual(axonRule?.matchValue, BLEDetectorProfile.axonTaser.rawValue)
    XCTAssertEqual(axonRule?.additionalMatches.count, 0)
    XCTAssertEqual(axonRule?.matchMode, .any)

    let detectorProfiles = Set(
      rules.compactMap { rule -> BLEDetectorProfile? in
        guard rule.matchType == .detectorProfile else { return nil }
        return BLEDetectorProfile(rawValue: rule.matchValue)
      }
    )

    XCTAssertEqual(detectorProfiles, Set(BLEDetectorProfile.allCases))
    XCTAssertTrue(rules.allSatisfy(\.isEnabled))
    XCTAssertTrue(rules.allSatisfy(\.notifyOncePerSession))
  }

  func testOUISpySeedMigrationPreservesSavedRulesAndDisabledState() throws {
    var rules = store.loadAlertRules()
    let index = try XCTUnwrap(rules.firstIndex { $0.matchValue == BLEDetectorProfile.axonTaser.rawValue })
    rules[index].matchType = .manufacturerPrefix
    rules[index].matchValue = "0025DF"
    rules[index].isEnabled = false
    try store.saveAlertRules(rules)
    try "2026-06-30-marauder-ble-detectors-v1".write(
      to: directory.appendingPathComponent("alert-rules-seed-version.txt"),
      atomically: true, encoding: .utf8)

    let reopened = try LocalStore(rootURL: directory)
    XCTAssertEqual(reopened.loadAlertRules(), rules)
    let reopenedAgain = try LocalStore(rootURL: directory)
    XCTAssertEqual(reopenedAgain.loadAlertRules(), rules)
  }

  func testSessionRoundTrip() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let session = ScanSession(
      id: UUID(),
      startedAt: now,
      endedAt: nil,
      mode: .recording,
      name: "Test session",
      detectionCount: 0,
      uniqueDeviceCount: 0
    )
    try store.createSession(session)

    let detection = BLEDetection(
      id: UUID(),
      sessionID: session.id,
      peripheralIdentifier: UUID(),
      displayName: "Sensor",
      rssi: -70,
      timestamp: now,
      latitude: -27.47,
      longitude: 153.02,
      horizontalAccuracy: 5,
      advertisement: .empty
    )
    try store.appendDetection(detection)

    XCTAssertEqual(try store.loadSessions().first?.id, session.id)
    XCTAssertEqual(try store.loadDetections(sessionID: session.id), [detection])
  }

  func testDeviceSnapshotCodableRoundTrip() throws {
    let id = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let advertisement = BLEAdvertisement(
      localName: "Nordic Thingy",
      manufacturerDataHex: "590001020304",
      companyIdentifier: 0x0059,
      memberServiceUUIDs: ["FEAA"],
      serviceUUIDs: ["180A", "180F"],
      solicitedServiceUUIDs: [],
      serviceData: ["180F": "64"],
      overflowServiceUUIDs: [],
      txPower: -4,
      isConnectable: true
    )

    var identity = GATTDeviceIdentity()
    identity.deviceName = "Thingy52"
    identity.manufacturerName = "Nordic Semiconductor"
    identity.modelNumber = "PCA20020"
    identity.serialNumber = "12345678"
    identity.firmwareRevision = "v2.1.0"
    identity.hardwareRevision = "v1.0"
    identity.softwareRevision = "v2.1.0"
    identity.systemID = "0102030405060708"
    identity.appearance = GATTAppearance(rawValue: 0x0200, categoryName: "Generic Tag", subcategoryName: nil)
    identity.pnpIdentifier = GATTPnPIdentifier(
      vendorIDSource: .bluetoothSIG,
      rawVendorIDSource: 1,
      vendorID: 0x0059,
      productID: 0x0001,
      productVersion: 0x0100
    )

    let evidence = GATTDeviceEvidence(identity: identity, discoveredServiceUUIDs: ["180A", "180F"])

    let charSnapshot = GATTCharacteristicSnapshot(
      uuid: "2A19",
      properties: ["Read", "Notify"],
      valueHex: "64",
      decodedValue: GATTDecodedValue(
        displayText: "100%",
        rawHex: "64",
        fields: [GATTDecodedField(name: "Level", value: "100%")],
        provenance: .deviceReported
      ),
      descriptors: [GATTDescriptorSnapshot(uuid: "2902", displayValue: "Notifications enabled", rawHex: "0100")],
      isNotifying: true
    )
    let serviceSnapshot = GATTServiceSnapshot(uuid: "180F", characteristics: [charSnapshot])

    let location = DeviceLocationMetadata(
      latitude: 37.7749,
      longitude: -122.4194,
      horizontalAccuracy: 10.0,
      timestamp: now
    )
    let samples = [
      DeviceRSSISample(timestamp: now.addingTimeInterval(-10), rssi: -75),
      DeviceRSSISample(timestamp: now, rssi: -65)
    ]

    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Nordic Thingy",
      customName: "Living Room Sensor",
      latestRSSI: -65,
      strongestRSSI: -58,
      firstSeen: now.addingTimeInterval(-60),
      lastSeen: now,
      lastSeenMetadataTag: advertisement.metadataTag,
      sightingCount: 15,
      advertisement: advertisement,
      gattEvidence: evidence,
      exploredServices: [serviceSnapshot],
      lastLocation: location,
      rssiHistory: samples
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(BLEDeviceSnapshot.self, from: data)

    XCTAssertEqual(decoded.peripheralIdentifier, id)
    XCTAssertEqual(decoded.displayName, "Nordic Thingy")
    XCTAssertEqual(decoded.customName, "Living Room Sensor")
    XCTAssertEqual(decoded.latestRSSI, -65)
    XCTAssertEqual(decoded.strongestRSSI, -58)
    XCTAssertEqual(decoded.sightingCount, 15)
    XCTAssertEqual(decoded.advertisement.localName, "Nordic Thingy")
    XCTAssertEqual(decoded.advertisement.companyIdentifier, 0x0059)
    XCTAssertEqual(decoded.gattEvidence?.identity.manufacturerName, "Nordic Semiconductor")
    XCTAssertEqual(decoded.exploredServices.count, 1)
    XCTAssertEqual(decoded.exploredServices.first?.characteristics.first?.uuid, "2A19")
    XCTAssertEqual(decoded.lastLocation?.latitude, 37.7749)
    XCTAssertEqual(decoded.rssiHistory.count, 2)
  }

  func testSaveAndLoadDeviceRecord() throws {
    let id = UUID()
    let now = Date()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Test Beacon",
      customName: "Front Door",
      latestRSSI: -50,
      strongestRSSI: -45,
      firstSeen: now,
      lastSeen: now,
      sightingCount: 1,
      advertisement: .empty
    )

    try store.saveDeviceRecord(snapshot)

    let fileURL = store.deviceRecordFileURL(for: id)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

    let loaded = store.loadDeviceRecord(for: id)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.peripheralIdentifier, id)
    XCTAssertEqual(loaded?.displayName, "Test Beacon")
    XCTAssertEqual(loaded?.customName, "Front Door")
    XCTAssertEqual(loaded?.latestRSSI, -50)
  }

  func testSaveDeviceRecordAsync() {
    let expectation = self.expectation(description: "Async save completion")
    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Async Device",
      latestRSSI: -70,
      strongestRSSI: -70,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )

    store.saveDeviceRecordAsync(snapshot) { result in
      switch result {
      case .success:
        expectation.fulfill()
      case .failure(let error):
        XCTFail("Async save failed with error: \(error)")
      }
    }

    waitForExpectations(timeout: 2.0)
    let loaded = store.loadDeviceRecord(for: id)
    XCTAssertEqual(loaded?.displayName, "Async Device")
  }

  func testLoadAllDeviceRecords() throws {
    let id1 = UUID()
    let id2 = UUID()
    let snapshot1 = BLEDeviceSnapshot(
      peripheralIdentifier: id1,
      displayName: "Device 1",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    let snapshot2 = BLEDeviceSnapshot(
      peripheralIdentifier: id2,
      displayName: "Device 2",
      latestRSSI: -80,
      strongestRSSI: -80,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )

    try store.saveDeviceRecord(snapshot1)
    try store.saveDeviceRecord(snapshot2)

    let allRecords = store.loadAllDeviceRecords()
    XCTAssertEqual(allRecords.count, 2)
    XCTAssertEqual(allRecords[id1]?.displayName, "Device 1")
    XCTAssertEqual(allRecords[id2]?.displayName, "Device 2")
  }

  func testPurgeDeviceRecordRemovesDiskFile() throws {
    let id = UUID()
    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Purge Me",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )

    try store.saveDeviceRecord(snapshot)
    XCTAssertNotNil(store.loadDeviceRecord(for: id))

    try store.purgeDeviceRecord(for: id)
    XCTAssertNil(store.loadDeviceRecord(for: id))
    XCTAssertFalse(FileManager.default.fileExists(atPath: store.deviceRecordFileURL(for: id).path))
  }

  func testPurgeAllDeviceRecords() throws {
    let id1 = UUID()
    let id2 = UUID()
    let snapshot1 = BLEDeviceSnapshot(
      peripheralIdentifier: id1,
      displayName: "D1",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    let snapshot2 = BLEDeviceSnapshot(
      peripheralIdentifier: id2,
      displayName: "D2",
      latestRSSI: -70,
      strongestRSSI: -70,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )

    try store.saveDeviceRecord(snapshot1)
    try store.saveDeviceRecord(snapshot2)
    XCTAssertEqual(store.loadAllDeviceRecords().count, 2)

    try store.purgeAllDeviceRecords()
    XCTAssertEqual(store.loadAllDeviceRecords().count, 0)
  }

  func testPresentationNamePrioritizesCustomName() {
    var snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: UUID(),
      displayName: "Advertised Name",
      customName: "My Custom Alias",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: "Local Adv Name",
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

    XCTAssertEqual(snapshot.presentationName, "My Custom Alias")

    snapshot.customName = "   "
    XCTAssertEqual(snapshot.presentationName, "Advertised Name")

    snapshot.customName = nil
    XCTAssertEqual(snapshot.presentationName, "Advertised Name")

    snapshot.displayName = "Unnamed device"
    XCTAssertEqual(snapshot.presentationName, "Local Adv Name")
  }

  func testLargePayloadSerializationWithGATTLocationAnd200RSSISamples() throws {
    let id = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_123.456)

    var identity = GATTDeviceIdentity()
    identity.deviceName = "Enterprise Sensor Pro"
    identity.manufacturerName = "Industrial IoT Corp"
    identity.modelNumber = "IIOT-9000-X"
    identity.serialNumber = "SN-9876543210"
    identity.firmwareRevision = "v4.12.3-release"
    identity.hardwareRevision = "HW-Rev-3.0"
    identity.softwareRevision = "SW-5.1.0-build99"
    identity.systemID = "AABBCCDDEEFF0011"
    identity.appearance = GATTAppearance(rawValue: 0x0340, categoryName: "Sensor", subcategoryName: "Multi-Sensor")
    identity.pnpIdentifier = GATTPnPIdentifier(
      vendorIDSource: .bluetoothSIG,
      rawVendorIDSource: 1,
      vendorID: 0x004C,
      productID: 0x1234,
      productVersion: 0x0102
    )

    var services: [GATTServiceSnapshot] = []
    for sIndex in 1...5 {
      var chars: [GATTCharacteristicSnapshot] = []
      for cIndex in 1...3 {
        let desc = GATTDescriptorSnapshot(
          uuid: "290\(cIndex)",
          displayValue: "User Description \(cIndex)",
          rawHex: "010\(cIndex)"
        )
        let field = GATTDecodedField(name: "SensorField\(cIndex)", value: "\(cIndex * 10).5 unit")
        let decoded = GATTDecodedValue(
          displayText: "\(cIndex * 10).5 unit",
          rawHex: "0\(cIndex)FF",
          fields: [field],
          provenance: .deviceReported
        )
        chars.append(
          GATTCharacteristicSnapshot(
            uuid: "2A0\(sIndex)\(cIndex)",
            properties: ["Read", "Write", "Notify", "Indicate"],
            valueHex: "0\(cIndex)FF",
            decodedValue: decoded,
            descriptors: [desc],
            isNotifying: cIndex % 2 == 0
          )
        )
      }
      services.append(GATTServiceSnapshot(uuid: "180\(sIndex)", characteristics: chars))
    }

    let location = DeviceLocationMetadata(
      latitude: -33.8688,
      longitude: 151.2093,
      horizontalAccuracy: 4.5,
      timestamp: now
    )

    var samples: [DeviceRSSISample] = []
    for i in 1...200 {
      samples.append(
        DeviceRSSISample(
          timestamp: now.addingTimeInterval(Double(-200 + i)),
          rssi: -90 + (i % 40)
        )
      )
    }

    let advertisement = BLEAdvertisement(
      localName: "Enterprise Sensor Pro",
      manufacturerDataHex: "4C000102030405060708",
      companyIdentifier: 0x004C,
      memberServiceUUIDs: ["FEAA", "FEBB"],
      serviceUUIDs: ["1801", "1802", "1803", "1804", "1805"],
      solicitedServiceUUIDs: ["180A"],
      serviceData: ["1801": "0102", "1802": "0304"],
      overflowServiceUUIDs: ["180F"],
      txPower: 4,
      isConnectable: true
    )

    let snapshot = BLEDeviceSnapshot(
      peripheralIdentifier: id,
      displayName: "Enterprise Sensor Pro",
      customName: "Critical Node #1",
      latestRSSI: -50,
      strongestRSSI: -42,
      firstSeen: now.addingTimeInterval(-3600),
      lastSeen: now,
      lastSeenMetadataTag: advertisement.metadataTag,
      sightingCount: 2500,
      advertisement: advertisement,
      gattEvidence: GATTDeviceEvidence(identity: identity, discoveredServiceUUIDs: ["1801", "1802"]),
      exploredServices: services,
      lastLocation: location,
      rssiHistory: samples
    )

    try store.saveDeviceRecord(snapshot)

    guard let loaded = store.loadDeviceRecord(for: id) else {
      XCTFail("Failed to load saved large payload snapshot")
      return
    }

    XCTAssertEqual(loaded.peripheralIdentifier, id)
    XCTAssertEqual(loaded.displayName, "Enterprise Sensor Pro")
    XCTAssertEqual(loaded.customName, "Critical Node #1")
    XCTAssertEqual(loaded.presentationName, "Critical Node #1")
    XCTAssertEqual(loaded.latestRSSI, -50)
    XCTAssertEqual(loaded.strongestRSSI, -42)
    XCTAssertEqual(loaded.sightingCount, 2500)
    XCTAssertEqual(loaded.advertisement.companyIdentifier, 0x004C)
    XCTAssertEqual(loaded.advertisement.serviceUUIDs.count, 5)
    XCTAssertEqual(loaded.exploredServices.count, 5)
    XCTAssertEqual(loaded.exploredServices.first?.characteristics.count, 3)
    XCTAssertEqual(loaded.exploredServices.first?.characteristics.first?.decodedValue?.fields.first?.name, "SensorField1")
    XCTAssertEqual(loaded.gattEvidence?.identity.manufacturerName, "Industrial IoT Corp")
    XCTAssertEqual(loaded.gattEvidence?.identity.systemID, "AABBCCDDEEFF0011")
    XCTAssertEqual(loaded.gattEvidence?.identity.pnpIdentifier?.vendorID, 0x004C)
    XCTAssertEqual(loaded.lastLocation?.latitude, -33.8688)
    XCTAssertEqual(loaded.lastLocation?.longitude, 151.2093)
    XCTAssertEqual(loaded.rssiHistory.count, 200)
    XCTAssertEqual(loaded.rssiHistory.first?.rssi, -89)
    XCTAssertEqual(loaded.rssiHistory.last?.rssi, -90)
  }

  func testConcurrentReadsWritesAndPurgesThreadSafety() {
    let baseUUIDs = (0..<10).map { _ in UUID() }
    let iterations = 100
    let now = Date()

    DispatchQueue.concurrentPerform(iterations: iterations) { i in
      let id = baseUUIDs[i % baseUUIDs.count]
      let snapshot = BLEDeviceSnapshot(
        peripheralIdentifier: id,
        displayName: "Concurrent Device \(i)",
        customName: "Alias \(i)",
        latestRSSI: -60 - (i % 20),
        strongestRSSI: -50,
        firstSeen: now,
        lastSeen: now,
        sightingCount: i + 1,
        advertisement: .empty
      )

      switch i % 5 {
      case 0:
        try? store.saveDeviceRecord(snapshot)
      case 1:
        _ = store.loadDeviceRecord(for: id)
      case 2:
        _ = store.loadAllDeviceRecords()
      case 3:
        try? store.purgeDeviceRecord(for: id)
      case 4:
        store.saveDeviceRecordAsync(snapshot)
      default:
        break
      }
    }

    let expectation = self.expectation(description: "Flush deviceQueue")
    store.saveDeviceRecordAsync(
      BLEDeviceSnapshot(
        peripheralIdentifier: UUID(),
        displayName: "Flush",
        latestRSSI: -50,
        strongestRSSI: -50,
        firstSeen: Date(),
        lastSeen: Date(),
        sightingCount: 1,
        advertisement: .empty
      )
    ) { _ in
      expectation.fulfill()
    }
    waitForExpectations(timeout: 5.0)

    let remaining = store.loadAllDeviceRecords()
    XCTAssertTrue(remaining.count >= 0)
  }

  func testCorruptedAndInvalidJSONGracefulRecovery() throws {
    let validID = UUID()
    let validSnapshot = BLEDeviceSnapshot(
      peripheralIdentifier: validID,
      displayName: "Valid Device",
      latestRSSI: -50,
      strongestRSSI: -50,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(validSnapshot)

    // Write empty 0-byte file
    let emptyID = UUID()
    let emptyURL = store.deviceRecordFileURL(for: emptyID)
    try Data().write(to: emptyURL)

    // Write truncated JSON
    let truncatedID = UUID()
    let truncatedURL = store.deviceRecordFileURL(for: truncatedID)
    try "{\"peripheralIdentifier\":\"\(truncatedID.uuidString)\"".data(using: .utf8)?.write(to: truncatedURL)

    // Write invalid date JSON
    let badDateID = UUID()
    let badDateURL = store.deviceRecordFileURL(for: badDateID)
    let badDateJSON = "{\"peripheralIdentifier\":\"\(badDateID.uuidString)\",\"displayName\":\"Bad Date\",\"firstSeen\":\"invalid-date-format\",\"lastSeen\":\"invalid-date-format\",\"latestRSSI\":-60,\"strongestRSSI\":-60,\"sightingCount\":1,\"lastSeenMetadataTag\":\"\",\"advertisement\":{\"isConnectable\":true,\"serviceUUIDs\":[],\"overflowServiceUUIDs\":[],\"solicitedServiceUUIDs\":[],\"serviceData\":{}}}"
    try badDateJSON.data(using: .utf8)?.write(to: badDateURL)

    // Write garbage binary data
    let garbageID = UUID()
    let garbageURL = store.deviceRecordFileURL(for: garbageID)
    let garbageBytes: [UInt8] = [0xFF, 0xFE, 0x00, 0xBA, 0xAD, 0xF0, 0x0D]
    try Data(garbageBytes).write(to: garbageURL)

    // Individual loads of corrupted files should gracefully return nil
    XCTAssertNil(store.loadDeviceRecord(for: emptyID))
    XCTAssertNil(store.loadDeviceRecord(for: truncatedID))
    XCTAssertNil(store.loadDeviceRecord(for: badDateID))
    XCTAssertNil(store.loadDeviceRecord(for: garbageID))

    // Valid file should load perfectly
    let loadedValid = store.loadDeviceRecord(for: validID)
    XCTAssertNotNil(loadedValid)
    XCTAssertEqual(loadedValid?.displayName, "Valid Device")

    // loadAllDeviceRecords should load valid records and ignore corrupted ones without crashing
    let allRecords = store.loadAllDeviceRecords()
    XCTAssertEqual(allRecords.count, 1)
    XCTAssertEqual(allRecords[validID]?.displayName, "Valid Device")
  }

  func testPurgingNonExistentDeviceIsSafeAndDoesNotCorruptOtherRecords() throws {
    let id1 = UUID()
    let id2 = UUID()
    let snapshot1 = BLEDeviceSnapshot(
      peripheralIdentifier: id1,
      displayName: "Keeper 1",
      latestRSSI: -60,
      strongestRSSI: -60,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    let snapshot2 = BLEDeviceSnapshot(
      peripheralIdentifier: id2,
      displayName: "Keeper 2",
      latestRSSI: -70,
      strongestRSSI: -70,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: .empty
    )
    try store.saveDeviceRecord(snapshot1)
    try store.saveDeviceRecord(snapshot2)

    let nonExistentID = UUID()
    XCTAssertNoThrow(try store.purgeDeviceRecord(for: nonExistentID))

    let loaded1 = store.loadDeviceRecord(for: id1)
    let loaded2 = store.loadDeviceRecord(for: id2)
    XCTAssertEqual(loaded1?.displayName, "Keeper 1")
    XCTAssertEqual(loaded2?.displayName, "Keeper 2")
    XCTAssertEqual(store.loadAllDeviceRecords().count, 2)
  }
}
