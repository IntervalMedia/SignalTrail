import XCTest

@testable import SignalTrail

final class AlertMatcherTests: XCTestCase {
  private let device = BLEDeviceSnapshot(
    peripheralIdentifier: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
    displayName: "Demo Sensor",
    latestRSSI: -62,
    strongestRSSI: -55,
    firstSeen: Date(),
    lastSeen: Date(),
    sightingCount: 3,
    advertisement: BLEAdvertisement(
      localName: "Demo Sensor",
      manufacturerDataHex: "4C000215AABBCCDD",
      companyIdentifier: 0x004C,
      serviceUUIDs: ["180F"],
      solicitedServiceUUIDs: [],
      serviceData: [:],
      overflowServiceUUIDs: [],
      txPower: -8,
      isConnectable: true
    )
  )

  func testCompanyIdentifierHexMatch() {
    let rule = makeRule(type: .companyIdentifier, value: "004C")
    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: device))
  }

  func testPeripheralIdentifierMatch() {
    let rule = makeRule(
      type: .peripheralIdentifier, value: device.peripheralIdentifier.uuidString.lowercased())
    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: device))
  }

  func testManufacturerPrefixIgnoresSeparators() {
    let rule = makeRule(type: .manufacturerPrefix, value: "4C:00:02:15")
    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: device))
  }

  func testDisabledRuleDoesNotMatch() {
    var rule = makeRule(type: .localNameContains, value: "sensor")
    rule.isEnabled = false
    XCTAssertFalse(AlertMatcher.matches(rule: rule, device: device))
  }

  private func makeRule(type: AlertMatchType, value: String) -> AlertRule {
    AlertRule(
      id: UUID(),
      name: "Test",
      matchType: type,
      matchValue: value,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )
  }
}
