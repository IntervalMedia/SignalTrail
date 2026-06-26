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

    XCTAssertEqual(rules.count, 1)
    XCTAssertEqual(rules.first?.name, "Axon / TASER detected")
    XCTAssertEqual(rules.first?.matchType, .manufacturerPrefix)
    XCTAssertEqual(rules.first?.matchValue, "0025DF")
    XCTAssertEqual(rules.first?.additionalMatches.count, 3)
    XCTAssertEqual(rules.first?.matchMode, .any)
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
}
