import Foundation

struct AlertMatcher {
    static func matches(rule: AlertRule, device: BLEDeviceSnapshot) -> Bool {
        guard rule.isEnabled else { return false }
        let value = rule.matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        switch rule.matchType {
        case .peripheralIdentifier:
            return device.peripheralIdentifier.uuidString.caseInsensitiveCompare(value) == .orderedSame

        case .companyIdentifier:
            let normalized = value.lowercased().replacingOccurrences(of: "0x", with: "")
            let expected = UInt16(normalized, radix: 16) ?? UInt16(value)
            return expected == device.advertisement.companyIdentifier

        case .localNameContains:
            return device.displayName.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil

        case .manufacturerPrefix:
            guard let manufacturer = device.advertisement.manufacturerDataHex else { return false }
            return manufacturer.normalizedHex.hasPrefix(value.normalizedHex)

        case .serviceUUID:
            return device.advertisement.serviceUUIDs.contains {
                $0.caseInsensitiveCompare(value) == .orderedSame
            }
        }
    }
}
