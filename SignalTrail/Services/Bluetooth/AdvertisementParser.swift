import Foundation
import CoreBluetooth

struct AdvertisementParser {
    static func parse(_ data: [String: Any]) -> BLEAdvertisement {
        let manufacturerData = data[CBAdvertisementDataManufacturerDataKey] as? Data

        let serviceUUIDs = normalizeUUIDs(
            (data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        )
        let solicited = normalizeUUIDs(
            (data[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        )
        let overflow = normalizeUUIDs(
            (data[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        )

        let rawServiceData = data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let serviceData = rawServiceData.reduce(into: [String: String]()) { dict, entry in
            dict[normalizeUUID(entry.key.uuidString)] = entry.value.hexadecimalString
        }

        let isConnectable: Bool
        if let boolValue = data[CBAdvertisementDataIsConnectable] as? Bool {
            isConnectable = boolValue
        } else if let numberValue = data[CBAdvertisementDataIsConnectable] as? NSNumber {
            isConnectable = numberValue.boolValue
        } else {
            isConnectable = false
        }

        let memberServiceUUIDs = Array(
            Set((serviceUUIDs + solicited + overflow).compactMap(memberUUID16Hex(from:)))
        ).sorted()

        return BLEAdvertisement(
            localName: normalizedLocalName(from: data),
            manufacturerDataHex: manufacturerData?.hexadecimalString,
            companyIdentifier: manufacturerData.flatMap { companyIdentifier(from: $0) },
            memberServiceUUIDs: memberServiceUUIDs,
            serviceUUIDs: serviceUUIDs,
            solicitedServiceUUIDs: solicited,
            serviceData: serviceData,
            overflowServiceUUIDs: overflow,
            txPower: txPower(from: data),
            isConnectable: isConnectable
        )
    }

    private static func companyIdentifier(from data: Data) -> UInt16? {
        guard data.count >= 2 else { return nil }
        return UInt16(data[data.startIndex]) | (UInt16(data[data.index(after: data.startIndex)]) << 8)
    }

    private static func normalizedLocalName(from data: [String: Any]) -> String? {
        guard let raw = data[CBAdvertisementDataLocalNameKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func txPower(from data: [String: Any]) -> Int? {
        if let value = data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            return value.intValue
        }
        if let value = data[CBAdvertisementDataTxPowerLevelKey] as? Int {
            return value
        }
        if let value = data[CBAdvertisementDataTxPowerLevelKey] as? String,
           let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return parsed
        }
        return nil
    }

    private static func normalizeUUID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizeUUIDs(_ values: [String]) -> [String] {
        Array(Set(values.map(normalizeUUID))).sorted()
    }

    private static func memberUUID16Hex(from uuid: String) -> String? {
        // The Bluetooth Base UUID embeds 16-bit assigned numbers at bytes 12-13 (first 4 hex chars).
        let normalized = normalizeUUID(uuid)
        let shortHex: String?

        if normalized.count == 4 {
            shortHex = normalized
        } else if normalized.count == 36,
                  normalized.hasSuffix("-0000-1000-8000-00805F9B34FB")
        {
            shortHex = String(normalized.prefix(4))
        } else {
            shortHex = nil
        }

        guard let shortHex, let value = UInt16(shortHex, radix: 16) else { return nil }
        let canonical = String(format: "0x%04X", value)
        guard BluetoothMemberUUIDLookup.contains(canonical) else { return nil }
        return canonical
    }
}
