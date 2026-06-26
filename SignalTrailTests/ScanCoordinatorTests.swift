import XCTest

@testable import SignalTrail

final class ScanCoordinatorTests: XCTestCase {
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

  private func makeSnapshot(name: String, lastSeen: Date, rssi: Int) -> BLEDeviceSnapshot {
    BLEDeviceSnapshot(
      peripheralIdentifier: UUID(),
      displayName: name,
      latestRSSI: rssi,
      strongestRSSI: rssi,
      firstSeen: lastSeen,
      lastSeen: lastSeen,
      sightingCount: 1,
      advertisement: .empty
    )
  }
}
