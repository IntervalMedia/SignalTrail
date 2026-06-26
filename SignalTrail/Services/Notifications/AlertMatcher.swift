import Foundation

struct AlertMatcher {
    static func matches(rule: AlertRule, device: BLEDeviceSnapshot) -> Bool {
        guard rule.isEnabled else { return false }
        let criteria = rule.criteria
        guard !criteria.isEmpty else { return false }

        switch rule.matchMode {
        case .any:
            return criteria.contains { match in
                matches(match: match, device: device)
            }
        case .all:
            return criteria.allSatisfy { match in
                matches(match: match, device: device)
            }
        }
    }

    private static func matches(match: AlertRuleMatch, device: BLEDeviceSnapshot) -> Bool {
        let value = match.matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        switch match.matchType {
        case .peripheralIdentifier:
            return device.peripheralIdentifier.uuidString.caseInsensitiveCompare(value) == .orderedSame

        case .companyIdentifier:
            let normalized = value.lowercased().replacingOccurrences(of: "0x", with: "")
            let expected = UInt16(normalized, radix: 16) ?? UInt16(value)
            return expected == device.advertisement.companyIdentifier

        case .companyName:
            guard let name = BluetoothCompanyLookup.name(for: device.advertisement.companyIdentifier) else {
                return false
            }
            return name.caseInsensitiveCompare(value) == .orderedSame

        case .localNameContains:
            return device.displayName.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil

        case .manufacturerPrefix:
            guard let manufacturer = device.advertisement.manufacturerDataHex else { return false }
            return manufacturer.normalizedHex.hasPrefix(value.normalizedHex)

        case .memberServiceName:
            return device.advertisement.memberServiceUUIDs.contains { uuid in
                guard let name = BluetoothMemberUUIDLookup.name(for: uuid) else { return false }
                return name.caseInsensitiveCompare(value) == .orderedSame
            }

        case .serviceUUID:
            return device.advertisement.serviceUUIDs.contains {
                $0.caseInsensitiveCompare(value) == .orderedSame
            }
        }
    }
}
