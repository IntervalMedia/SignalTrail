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

        case .detectorProfile:
            guard let profile = BLEDetectorProfile(rawValue: value) else { return false }
            return BLEAdvertisementDetector.matches(profile: profile, device: device)
        }
    }
}

enum BLEAdvertisementDetector {
    private static let flipperServiceIdentifiers: Set<UInt16> = [0x3081, 0x3082, 0x3083]
    private static let metaIdentifiers: Set<UInt16> = [0xFD5F, 0xFEB7, 0xFEB8, 0x01AB, 0x058E, 0x0D53]
    private static let blockedMetaIdentifiers: Set<UInt16> = [0xFD5A, 0xFD69, 0x004C, 0x0006, 0xFEF3]
    private static let suspiciousSerialModuleNames: Set<String> = ["HC-03", "HC-05", "HC-06"]

    static func matches(profile: BLEDetectorProfile, device: BLEDeviceSnapshot) -> Bool {
        matches(profile: profile, advertisement: device.advertisement)
    }

    static func matches(profile: BLEDetectorProfile, advertisement: BLEAdvertisement) -> Bool {
        switch profile {
        case .appleFindMyOfflineFinding:
            return matchesFindMy(advertisement)
        case .flipperZero:
            return matchesFlipperZero(advertisement)
        case .flockPenguinBattery:
            return matchesFlockPenguinBattery(advertisement)
        case .serialBluetoothModuleSkimmer:
            return matchesSerialBluetoothModule(advertisement)
        case .metaSmartGlasses:
            return matchesMetaSmartGlasses(advertisement)
        }
    }

    private static func matchesFindMy(_ advertisement: BLEAdvertisement) -> Bool {
        guard advertisement.companyIdentifier == 0x004C,
              let hex = advertisement.manufacturerDataHex,
              let bytes = Data(hexadecimalString: hex).map({ Array($0) }),
              bytes.count >= 29
        else { return false }

        // CoreBluetooth manufacturer data begins with the little-endian company ID.
        // Find My Offline Finding uses Apple type 0x12 and declares a 25-byte body.
        guard bytes[0] == 0x4C, bytes[1] == 0x00,
              bytes[2] == 0x12, bytes[3] == 0x19
        else { return false }

        let declaredBodyLength = Int(bytes[3])
        return bytes.count >= 4 + declaredBodyLength
    }

    private static func matchesFlipperZero(_ advertisement: BLEAdvertisement) -> Bool {
        !serviceIdentifiers(in: advertisement).isDisjoint(with: flipperServiceIdentifiers)
    }

    private static func matchesFlockPenguinBattery(_ advertisement: BLEAdvertisement) -> Bool {
        guard advertisement.companyIdentifier == 0x09C8 else { return false }
        let name = advertisement.localName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return true }
        if name.caseInsensitiveCompare("FS Ext Battery") == .orderedSame { return true }
        if name.lowercased().hasPrefix("penguin-") {
            return isTenASCIIDigits(String(name.dropFirst("Penguin-".count)))
        }
        return isTenASCIIDigits(name)
    }

    private static func matchesSerialBluetoothModule(_ advertisement: BLEAdvertisement) -> Bool {
        guard let name = advertisement.localName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return false }
        return suspiciousSerialModuleNames.contains(name.uppercased())
    }

    private static func matchesMetaSmartGlasses(_ advertisement: BLEAdvertisement) -> Bool {
        var identifiers = serviceIdentifiers(in: advertisement)
        if let companyIdentifier = advertisement.companyIdentifier { identifiers.insert(companyIdentifier) }
        guard identifiers.isDisjoint(with: blockedMetaIdentifiers) else { return false }
        return !identifiers.isDisjoint(with: metaIdentifiers)
    }

    static func serviceIdentifiers(in advertisement: BLEAdvertisement) -> Set<UInt16> {
        let values = advertisement.memberServiceUUIDs
            + advertisement.serviceUUIDs
            + advertisement.solicitedServiceUUIDs
            + advertisement.overflowServiceUUIDs
            + Array(advertisement.serviceData.keys)
        return Set(values.compactMap(identifier16(from:)))
    }

    static func identifier16(from value: String) -> UInt16? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().replacingOccurrences(of: "0X", with: "")
        if normalized.count == 4 { return UInt16(normalized, radix: 16) }
        let compact = normalized.filter { $0.isHexDigit }
        if compact.count == 8, compact.hasPrefix("0000") { return UInt16(compact.suffix(4), radix: 16) }
        let bluetoothBaseSuffix = "00001000800000805F9B34FB"
        if compact.count == 32, compact.hasPrefix("0000"), compact.hasSuffix(bluetoothBaseSuffix) {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(start, offsetBy: 4)
            return UInt16(compact[start..<end], radix: 16)
        }
        return nil
    }

    private static func isTenASCIIDigits(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 10 && bytes.allSatisfy { (0x30...0x39).contains($0) }
    }
}
