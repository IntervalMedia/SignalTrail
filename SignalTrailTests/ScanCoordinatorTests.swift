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
