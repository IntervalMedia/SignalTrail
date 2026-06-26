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

  func testCompanyNameMatch() {
    let taserDevice = BLEDeviceSnapshot(
      peripheralIdentifier: UUID(),
      displayName: "Camera",
      latestRSSI: -60,
      strongestRSSI: -55,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: nil,
        manufacturerDataHex: "4D03AABBCCDD",
        companyIdentifier: 0x034D,
        serviceUUIDs: [],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )

    let rule = makeRule(type: .companyName, value: "TASER International, Inc.")
    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: taserDevice))
  }

  func testMemberServiceNameMatch() {
    let taserDevice = BLEDeviceSnapshot(
      peripheralIdentifier: UUID(),
      displayName: "Axon Sensor",
      latestRSSI: -60,
      strongestRSSI: -55,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: nil,
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        memberServiceUUIDs: ["0xFE6B"],
        serviceUUIDs: ["FE6B"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )

    let rule = makeRule(type: .memberServiceName, value: "TASER International, Inc.")
    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: taserDevice))
  }

  func testAdditionalMatchesAllowSingleRuleToMatchAnyConfiguredIdentifier() {
    let axonDevice = BLEDeviceSnapshot(
      peripheralIdentifier: UUID(),
      displayName: "Axon Camera",
      latestRSSI: -58,
      strongestRSSI: -58,
      firstSeen: Date(),
      lastSeen: Date(),
      sightingCount: 1,
      advertisement: BLEAdvertisement(
        localName: nil,
        manufacturerDataHex: nil,
        companyIdentifier: nil,
        memberServiceUUIDs: ["0xFC81"],
        serviceUUIDs: ["FC81"],
        solicitedServiceUUIDs: [],
        serviceData: [:],
        overflowServiceUUIDs: [],
        txPower: nil,
        isConnectable: true
      )
    )

    let rule = AlertRule(
      id: UUID(),
      name: "Axon / TASER detected",
      matchType: .manufacturerPrefix,
      matchValue: "0025DF",
      additionalMatches: [
        AlertRuleMatch(matchType: .memberServiceName, matchValue: "Axon Enterprise, Inc.")
      ],
      matchMode: .any,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )

    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: axonDevice))
  }

  func testMatchAllRequiresEveryCriterionToMatch() {
    let rule = AlertRule(
      id: UUID(),
      name: "Apple accessories",
      matchType: .localNameContains,
      matchValue: "demo",
      additionalMatches: [
        AlertRuleMatch(matchType: .companyIdentifier, matchValue: "004C")
      ],
      matchMode: .all,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )

    XCTAssertTrue(AlertMatcher.matches(rule: rule, device: device))
  }

  func testMatchAllFailsWhenOneCriterionDoesNotMatch() {
    let rule = AlertRule(
      id: UUID(),
      name: "Apple accessories",
      matchType: .localNameContains,
      matchValue: "demo",
      additionalMatches: [
        AlertRuleMatch(matchType: .memberServiceName, matchValue: "Apple, Inc.")
      ],
      matchMode: .all,
      isEnabled: true,
      notifyOncePerSession: true,
      cooldownSeconds: 300
    )

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
