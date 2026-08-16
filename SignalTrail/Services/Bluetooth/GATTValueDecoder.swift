import Foundation

// Curated, length-checked decoders based on Bluetooth SIG GSS YAML at commit
// 1415ddd9db5770dd21ecbe53173fbfc09e2943b6 and adopted HID/FTMS service
// specifications. Unknown or malformed values retain their raw bytes.

extension GATTDeviceEvidence {
    mutating func merge(characteristicUUID: String, decodedValue: GATTDecodedValue?) {
        guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: characteristicUUID),
              let decodedValue,
              decodedValue.warning == nil else { return }

        switch value {
        case 0x2A00: identity.deviceName = decodedValue.displayText
        case 0x2A01: identity.appearance = decodedValue.appearance
        case 0x2A23: identity.systemID = decodedValue.displayText
        case 0x2A24: identity.modelNumber = decodedValue.displayText
        case 0x2A25: identity.serialNumber = decodedValue.displayText
        case 0x2A26: identity.firmwareRevision = decodedValue.displayText
        case 0x2A27: identity.hardwareRevision = decodedValue.displayText
        case 0x2A28: identity.softwareRevision = decodedValue.displayText
        case 0x2A29: identity.manufacturerName = decodedValue.displayText
        case 0x2A50: identity.pnpIdentifier = decodedValue.pnpIdentifier
        default: break
        }
    }

}

enum GATTValueDecoder {
    static let automaticallyReadableCharacteristicValues: Set<UInt16> = [
        0x2A00, 0x2A01, 0x2A19, 0x2A23, 0x2A24, 0x2A25, 0x2A26,
        0x2A27, 0x2A28, 0x2A29, 0x2A4A, 0x2A50, 0x2A54, 0x2A5C,
        0x2A65, 0x2ACC,
    ]

    static func shouldAutomaticallyRead(characteristicUUID: String) -> Bool {
        guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: characteristicUUID) else {
            return false
        }
        return automaticallyReadableCharacteristicValues.contains(value)
    }

    static func decode(characteristicUUID: String, data: Data) -> GATTDecodedValue? {
        guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: characteristicUUID) else {
            return nil
        }

        switch value {
        case 0x2A00: return decodeString(data, fieldName: "Device Name")
        case 0x2A01: return decodeAppearance(data)
        case 0x2A19: return decodeBatteryLevel(data)
        case 0x2A23: return decodeSystemID(data)
        case 0x2A24: return decodeString(data, fieldName: "Model Number")
        case 0x2A25: return decodeString(data, fieldName: "Serial Number")
        case 0x2A26: return decodeString(data, fieldName: "Firmware Revision")
        case 0x2A27: return decodeString(data, fieldName: "Hardware Revision")
        case 0x2A28: return decodeString(data, fieldName: "Software Revision")
        case 0x2A29: return decodeString(data, fieldName: "Manufacturer Name")
        case 0x2A4A: return decodeHIDInformation(data)
        case 0x2A4B: return decodeHIDReportMap(data)
        case 0x2A37: return decodeHeartRateMeasurement(data)
        case 0x2A38: return decodeBodySensorLocation(data)
        case 0x2A50: return decodePnPID(data)
        case 0x2A54: return decodeRSCFeature(data)
        case 0x2A5C: return decodeCSCFeature(data)
        case 0x2A65: return decodeCyclingPowerFeature(data)
        case 0x2A6E: return decodeTemperature(data)
        case 0x2A6F: return decodeHumidity(data)
        case 0x2ACC: return decodeFitnessMachineFeature(data)
        default: return nil
        }
    }

    static func decodePresentationFormatDescriptor(_ data: Data) -> GATTDecodedValue? {
        let bytes = [UInt8](data)
        guard bytes.count == 7 else {
            return invalidValue(data, expected: "7-byte Characteristic Presentation Format")
        }

        let format = presentationFormatName(bytes[0])
        let exponent = Int(Int8(bitPattern: bytes[1]))
        let unitValue = uint16(bytes, at: 2)
        let unit = BluetoothAssignedUUIDLookup.metadata(
            for: String(format: "%04X", unitValue),
            kind: .unit
        )
        let namespace = bytes[4] == 1 ? "Bluetooth SIG" : String(format: "0x%02X", bytes[4])
        let description = uint16(bytes, at: 5)
        let unitName = unit?.name ?? String(format: "unit 0x%04X", unitValue)

        return GATTDecodedValue(
            displayText: "\(format) • \(unitName) • exponent \(exponent)",
            rawHex: data.hexadecimalString,
            fields: [
                GATTDecodedField(name: "Format", value: format),
                GATTDecodedField(name: "Exponent", value: String(exponent)),
                GATTDecodedField(name: "Unit", value: unit?.displayName ?? unitName),
                GATTDecodedField(name: "Namespace", value: namespace),
                GATTDecodedField(name: "Description", value: String(format: "0x%04X", description)),
            ]
        )
    }

    private static func decodeString(_ data: Data, fieldName: String) -> GATTDecodedValue {
        let trimmed = Data(data.dropLast(data.reversed().prefix(while: { $0 == 0 }).count))
        guard !trimmed.isEmpty,
              let value = String(data: trimmed, encoding: .utf8),
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0) || $0 == "\t"
              }) else {
            return invalidValue(data, expected: "printable UTF-8")
        }

        return GATTDecodedValue(
            displayText: value,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: fieldName, value: value)]
        )
    }

    private static func decodeAppearance(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 2 else {
            return invalidValue(data, expected: "2-byte GAP Appearance")
        }

        let rawValue = uint16(bytes, at: 0)
        guard let metadata = BluetoothAppearanceLookup.metadata(for: rawValue) else {
            return GATTDecodedValue(
                displayText: String(format: "Unknown appearance (0x%04X)", rawValue),
                rawHex: data.hexadecimalString,
                fields: [GATTDecodedField(name: "Appearance", value: String(format: "0x%04X", rawValue))],
                warning: "The device reported an unassigned Appearance value."
            )
        }

        let appearance = GATTAppearance(
            rawValue: rawValue,
            categoryName: metadata.categoryName,
            subcategoryName: metadata.subcategoryName
        )
        var fields = [GATTDecodedField(name: "Category", value: metadata.categoryName)]
        if let subcategoryName = metadata.subcategoryName {
            fields.append(GATTDecodedField(name: "Subcategory", value: subcategoryName))
        }
        return GATTDecodedValue(
            displayText: metadata.displayName,
            rawHex: data.hexadecimalString,
            fields: fields,
            appearance: appearance
        )
    }

    private static func decodeBatteryLevel(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 1, bytes[0] <= 100 else {
            return invalidValue(data, expected: "one byte in the assigned range 0–100")
        }
        let display = "\(bytes[0])%"
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Battery Level", value: display)]
        )
    }

    private static func decodeSystemID(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 8 else {
            return invalidValue(data, expected: "8-byte EUI-64")
        }
        let display = bytes.reversed().map { String(format: "%02X", $0) }.joined(separator: ":")
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "EUI-64", value: display)]
        )
    }

    private static func decodePnPID(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 7 else {
            return invalidValue(data, expected: "7-byte PnP ID")
        }

        let sourceValue = bytes[0]
        let source = GATTPnPIdentifier.VendorIDSource(rawValue: sourceValue)
        let vendorID = uint16(bytes, at: 1)
        let productID = uint16(bytes, at: 3)
        let productVersion = uint16(bytes, at: 5)
        let identifier = GATTPnPIdentifier(
            vendorIDSource: source,
            rawVendorIDSource: sourceValue,
            vendorID: vendorID,
            productID: productID,
            productVersion: productVersion
        )

        let sourceLabel = source?.displayName ?? String(format: "Unassigned source 0x%02X", sourceValue)
        let vendorLabel: String
        if source == .bluetoothSIG {
            vendorLabel = BluetoothCompanyLookup.displayName(for: vendorID)
        } else {
            vendorLabel = String(format: "0x%04X", vendorID)
        }
        let namespaceLabel = source == .bluetoothSIG ? "Bluetooth SIG vendor" : "Vendor"
        let display = String(
            format: "%@ 0x%04X • product 0x%04X • version 0x%04X",
            namespaceLabel, vendorID, productID, productVersion
        )

        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [
                GATTDecodedField(name: "Vendor ID Source", value: sourceLabel),
                GATTDecodedField(name: "Vendor ID", value: vendorLabel),
                GATTDecodedField(name: "Product ID", value: String(format: "0x%04X", productID)),
                GATTDecodedField(name: "Product Version", value: String(format: "0x%04X", productVersion)),
            ],
            warning: source == nil ? "The device reported an unassigned Vendor ID Source." : nil,
            pnpIdentifier: identifier
        )
    }

    private static func decodeHIDInformation(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 4 else {
            return invalidValue(data, expected: "4-byte HID Information")
        }

        let version = uint16(bytes, at: 0)
        let versionText = String(format: "%X.%02X", version >> 8, version & 0xFF)
        var capabilities: [String] = []
        if bytes[3] & 0x01 != 0 { capabilities.append("Remote wake") }
        if bytes[3] & 0x02 != 0 { capabilities.append("Normally connectable") }
        let suffix = capabilities.isEmpty ? "" : " • " + capabilities.joined(separator: " • ")
        var fields = [
            GATTDecodedField(name: "HID Version", value: versionText),
            GATTDecodedField(name: "Country Code", value: String(bytes[2])),
        ]
        fields.append(contentsOf: capabilities.map { GATTDecodedField(name: "Capability", value: $0) })

        return GATTDecodedValue(
            displayText: "HID \(versionText)\(suffix)",
            rawHex: data.hexadecimalString,
            fields: fields,
            warning: bytes[3] & 0xFC == 0 ? nil : "Reserved HID Information flag bits are set."
        )
    }

    private static func decodeHIDReportMap(_ data: Data) -> GATTDecodedValue {
        guard !data.isEmpty else {
            return invalidValue(data, expected: "non-empty HID Report Map")
        }
        return GATTDecodedValue(
            displayText: "\(data.count)-byte HID Report Map",
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Length", value: "\(data.count) bytes")]
        )
    }

    private static func decodeRSCFeature(_ data: Data) -> GATTDecodedValue {
        decodeFeatureBits(
            data,
            expectedLength: 2,
            expectedDescription: "2-byte RSC Feature",
            names: [
                "Instantaneous Stride Length Measurement",
                "Total Distance Measurement",
                "Walking or Running Status",
                "Calibration Procedure",
                "Multiple Sensor Locations",
            ]
        )
    }

    private static func decodeCSCFeature(_ data: Data) -> GATTDecodedValue {
        decodeFeatureBits(
            data,
            expectedLength: 2,
            expectedDescription: "2-byte CSC Feature",
            names: [
                "Wheel Revolution Data",
                "Crank Revolution Data",
                "Multiple Sensor Locations",
            ]
        )
    }

    private static func decodeCyclingPowerFeature(_ data: Data) -> GATTDecodedValue {
        decodeFeatureBits(
            data,
            expectedLength: 4,
            expectedDescription: "4-byte Cycling Power Feature",
            names: [
                "Pedal Power Balance", "Accumulated Torque", "Wheel Revolution Data",
                "Crank Revolution Data", "Extreme Magnitudes", "Extreme Angles",
                "Top and Bottom Dead Spot Angles", "Accumulated Energy",
                "Offset Compensation Indicator", "Offset Compensation",
                "Measurement Content Masking", "Multiple Sensor Locations",
                "Crank Length Adjustment", "Chain Length Adjustment", "Chain Weight Adjustment",
                "Span Length Adjustment", "Torque-based Measurement Context",
                "Instantaneous Measurement Direction", "Factory Calibration Date",
                "Enhanced Offset Compensation Procedure",
            ]
        )
    }

    private static func decodeFitnessMachineFeature(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 8 else {
            return invalidValue(data, expected: "8-byte Fitness Machine Feature")
        }
        let machineNames = [
            "Average Speed", "Cadence", "Total Distance", "Inclination", "Elevation Gain",
            "Pace", "Step Count", "Resistance Level", "Stride Count", "Expended Energy",
            "Heart Rate Measurement", "Metabolic Equivalent", "Elapsed Time", "Remaining Time",
            "Power Measurement", "Force on Belt and Power Output", "User Data Retention",
        ]
        let targetNames = [
            "Speed", "Inclination", "Resistance", "Power", "Heart Rate", "Expended Energy",
            "Number of Steps", "Number of Strides", "Distance", "Training Time",
            "Time in Two Heart Rate Zones", "Time in Three Heart Rate Zones",
            "Time in Five Heart Rate Zones", "Indoor Bike Simulation", "Wheel Circumference",
            "Spin Down Control", "Cadence",
        ]
        let machineBits = uint32(bytes, at: 0)
        let targetBits = uint32(bytes, at: 4)
        let fields = enabledFields(value: machineBits, names: machineNames, fieldName: "Machine feature")
            + enabledFields(value: targetBits, names: targetNames, fieldName: "Target setting")
        return GATTDecodedValue(
            displayText: fields.isEmpty ? "No optional features reported" : "\(fields.count) supported feature\(fields.count == 1 ? "" : "s")",
            rawHex: data.hexadecimalString,
            fields: fields
        )
    }

    private static func decodeFeatureBits(
        _ data: Data,
        expectedLength: Int,
        expectedDescription: String,
        names: [String]
    ) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == expectedLength else {
            return invalidValue(data, expected: expectedDescription)
        }
        let value = expectedLength == 2 ? UInt32(uint16(bytes, at: 0)) : uint32(bytes, at: 0)
        let fields = enabledFields(value: value, names: names, fieldName: "Supported feature")
        return GATTDecodedValue(
            displayText: fields.isEmpty ? "No optional features reported" : "\(fields.count) supported feature\(fields.count == 1 ? "" : "s")",
            rawHex: data.hexadecimalString,
            fields: fields
        )
    }

    private static func enabledFields(
        value: UInt32,
        names: [String],
        fieldName: String
    ) -> [GATTDecodedField] {
        names.enumerated().compactMap { bit, name in
            value & (UInt32(1) << UInt32(bit)) == 0
                ? nil
                : GATTDecodedField(name: fieldName, value: name)
        }
    }

    private static func decodeHeartRateMeasurement(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else {
            return invalidValue(data, expected: "Heart Rate Measurement fields")
        }

        let flags = bytes[0]
        var offset = 1
        let heartRate: UInt16
        if flags & 0x01 == 0x01 {
            guard bytes.count >= 3 else {
                return invalidValue(data, expected: "16-bit heart-rate value")
            }
            heartRate = uint16(bytes, at: offset)
            offset += 2
        } else {
            heartRate = UInt16(bytes[offset])
            offset += 1
        }

        var fields = [GATTDecodedField(name: "Heart Rate", value: "\(heartRate) bpm")]
        if flags & 0x08 == 0x08 {
            guard bytes.count >= offset + 2 else {
                return invalidValue(data, expected: "Energy Expended field selected by flags")
            }
            let energy = uint16(bytes, at: offset)
            fields.append(GATTDecodedField(name: "Energy Expended", value: "\(energy) J"))
            offset += 2
        }
        if flags & 0x10 == 0x10 {
            guard (bytes.count - offset).isMultiple(of: 2) else {
                return invalidValue(data, expected: "complete RR Interval fields")
            }
            while offset < bytes.count {
                let interval = Double(uint16(bytes, at: offset)) / 1024.0
                fields.append(GATTDecodedField(
                    name: "RR Interval",
                    value: String(format: "%.3f s", interval)
                ))
                offset += 2
            }
        } else if offset != bytes.count {
            return invalidValue(data, expected: "no trailing fields not selected by flags")
        }

        return GATTDecodedValue(
            displayText: "\(heartRate) bpm",
            rawHex: data.hexadecimalString,
            fields: fields
        )
    }

    private static func decodeBodySensorLocation(_ data: Data) -> GATTDecodedValue {
        let names = ["Other", "Chest", "Wrist", "Finger", "Hand", "Ear Lobe", "Foot"]
        let bytes = [UInt8](data)
        guard bytes.count == 1, Int(bytes[0]) < names.count else {
            return invalidValue(data, expected: "assigned Body Sensor Location value")
        }
        let display = names[Int(bytes[0])]
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Body Sensor Location", value: display)]
        )
    }

    private static func decodeTemperature(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 2 else {
            return invalidValue(data, expected: "2-byte signed temperature")
        }
        let raw = Int16(bitPattern: uint16(bytes, at: 0))
        let display = String(format: "%.2f °C", Double(raw) / 100.0)
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Temperature", value: display)]
        )
    }

    private static func decodeHumidity(_ data: Data) -> GATTDecodedValue {
        let bytes = [UInt8](data)
        guard bytes.count == 2 else {
            return invalidValue(data, expected: "2-byte humidity")
        }
        let display = String(format: "%.2f%%", Double(uint16(bytes, at: 0)) / 100.0)
        return GATTDecodedValue(
            displayText: display,
            rawHex: data.hexadecimalString,
            fields: [GATTDecodedField(name: "Humidity", value: display)]
        )
    }

    private static func invalidValue(_ data: Data, expected: String) -> GATTDecodedValue {
        GATTDecodedValue(
            displayText: data.hexadecimalString,
            rawHex: data.hexadecimalString,
            fields: [],
            warning: "Could not decode as \(expected); showing raw bytes."
        )
    }

    private static func uint16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func presentationFormatName(_ value: UInt8) -> String {
        switch value {
        case 0x01: return "boolean"
        case 0x04: return "uint8"
        case 0x06: return "uint16"
        case 0x08: return "uint32"
        case 0x0C: return "sint8"
        case 0x0E: return "sint16"
        case 0x10: return "sint32"
        case 0x14: return "float32"
        case 0x15: return "float64"
        case 0x16: return "medfloat16"
        case 0x17: return "medfloat32"
        case 0x19: return "UTF-8 string"
        case 0x1A: return "UTF-16 string"
        case 0x1B: return "structure"
        default: return String(format: "format 0x%02X", value)
        }
    }
}
