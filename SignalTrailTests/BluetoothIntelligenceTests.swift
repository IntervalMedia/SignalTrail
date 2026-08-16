import CoreBluetooth
import XCTest

@testable import SignalTrail

final class BluetoothIntelligenceTests: XCTestCase {
    func testAssignedUUIDLookupNamesBluetoothBaseUUIDsByContext() {
        let service = BluetoothAssignedUUIDLookup.metadata(
            for: "0000180F-0000-1000-8000-00805F9B34FB",
            kind: .adoptedService
        )
        let characteristic = BluetoothAssignedUUIDLookup.metadata(for: "2A19", kind: .characteristic)
        let descriptor = BluetoothAssignedUUIDLookup.metadata(for: "2904", kind: .descriptor)
        let unit = BluetoothAssignedUUIDLookup.metadata(for: "27AD", kind: .unit)

        XCTAssertEqual(service?.name, "Battery")
        XCTAssertEqual(characteristic?.name, "Battery Level")
        XCTAssertEqual(descriptor?.name, "Characteristic Presentation Format")
        XCTAssertEqual(unit?.name, "percentage")
    }

    func testAssignedUUIDLookupDistinguishesMemberAndStandardsOrganizationAssignments() {
        let member = BluetoothAssignedUUIDLookup.metadata(
            for: "0000FEEC-0000-1000-8000-00805F9B34FB",
            kind: .member
        )
        let sdo = BluetoothAssignedUUIDLookup.metadata(for: "FFF6", kind: .standardsOrganization)

        XCTAssertEqual(member?.name, "Tile, Inc.")
        XCTAssertEqual(member?.assignmentDescription, "UUID assigned to Tile, Inc.")
        XCTAssertEqual(sdo?.name, "Matter Profile ID")
        XCTAssertEqual(sdo?.kind, .standardsOrganization)
    }

    func testAdvertisementParserRecognizesMemberAssignmentFromServiceDataKey() {
        let advertisement = AdvertisementParser.parse([
            CBAdvertisementDataServiceDataKey: [CBUUID(string: "FEEC"): Data([0x01])],
        ])

        XCTAssertEqual(advertisement.memberServiceUUIDs, ["0xFEEC"])
    }

    func testPresentationFormatDescriptorUsesAssignedUnitName() {
        let decoded = GATTValueDecoder.decodePresentationFormatDescriptor(
            Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x00, 0x00])
        )

        XCTAssertEqual(decoded?.displayText, "uint8 • percentage • exponent 0")
        XCTAssertEqual(decoded?.fields[2].value, "percentage (0x27AD)")
    }

    func testBatteryLevelDecoderUsesAssignedPercentageSemantics() {
        let decoded = GATTValueDecoder.decode(characteristicUUID: "2A19", data: Data([85]))

        XCTAssertEqual(decoded?.displayText, "85%")
        XCTAssertEqual(decoded?.fields, [GATTDecodedField(name: "Battery Level", value: "85%")])
        XCTAssertNil(decoded?.warning)
    }

    func testAppearanceDecoderReturnsDeclaredCategoryAndSubcategory() {
        let decoded = GATTValueDecoder.decode(characteristicUUID: "2A01", data: Data([0xC2, 0x00]))

        XCTAssertEqual(decoded?.displayText, "Smartwatch")
        XCTAssertEqual(decoded?.appearance?.categoryName, "Watch")
        XCTAssertEqual(decoded?.appearance?.subcategoryName, "Smartwatch")
        XCTAssertEqual(decoded?.provenance, .deviceReported)
    }

    func testPnPIDDecoderUsesVendorNamespaceBeforeResolvingCompany() {
        let decoded = GATTValueDecoder.decode(
            characteristicUUID: "2A50",
            data: Data([0x01, 0x4C, 0x00, 0x34, 0x12, 0x02, 0x01])
        )

        XCTAssertEqual(decoded?.displayText, "Bluetooth SIG vendor 0x004C • product 0x1234 • version 0x0102")
        XCTAssertEqual(decoded?.fields.first?.value, "Bluetooth SIG Company Identifier")
        XCTAssertEqual(decoded?.fields[1].value, "Apple, Inc. (0x004C)")
    }

    func testMalformedKnownValueKeepsRawBytesAndExplainsFailure() {
        let decoded = GATTValueDecoder.decode(characteristicUUID: "2A50", data: Data([0x01, 0x4C]))

        XCTAssertEqual(decoded?.displayText, "014C")
        XCTAssertEqual(decoded?.rawHex, "014C")
        XCTAssertTrue(decoded?.warning?.contains("7-byte PnP ID") == true)
    }

    func testHeartRateDecoderHandlesFlagDependentFields() {
        let decoded = GATTValueDecoder.decode(
            characteristicUUID: "2A37",
            data: Data([0x10, 72, 0x00, 0x04])
        )

        XCTAssertEqual(decoded?.displayText, "72 bpm")
        XCTAssertEqual(decoded?.fields.last, GATTDecodedField(name: "RR Interval", value: "1.000 s"))
    }

    func testHIDInformationDecoderExposesVersionCountryAndCapabilities() {
        let decoded = GATTValueDecoder.decode(
            characteristicUUID: "2A4A",
            data: Data([0x11, 0x01, 0x00, 0x03])
        )

        XCTAssertEqual(decoded?.displayText, "HID 1.11 • Remote wake • Normally connectable")
        XCTAssertEqual(decoded?.fields[1], GATTDecodedField(name: "Country Code", value: "0"))
        XCTAssertNil(decoded?.warning)
    }

    func testCyclingAndRunningFeatureDecodersExposeSupportedCapabilities() {
        let cycling = GATTValueDecoder.decode(
            characteristicUUID: "2A65",
            data: Data([0x05, 0x00, 0x00, 0x00])
        )
        let running = GATTValueDecoder.decode(
            characteristicUUID: "2A54",
            data: Data([0x15, 0x00])
        )

        XCTAssertEqual(
            cycling?.fields.map(\.value),
            ["Pedal Power Balance", "Wheel Revolution Data"]
        )
        XCTAssertEqual(
            running?.fields.map(\.value),
            ["Instantaneous Stride Length Measurement", "Walking or Running Status", "Multiple Sensor Locations"]
        )
    }

    func testFitnessMachineFeatureDecoderSeparatesMachineAndTargetCapabilities() {
        let decoded = GATTValueDecoder.decode(
            characteristicUUID: "2ACC",
            data: Data([0x03, 0x00, 0x00, 0x00, 0x11, 0x00, 0x00, 0x00])
        )

        XCTAssertEqual(decoded?.fields, [
            GATTDecodedField(name: "Machine feature", value: "Average Speed"),
            GATTDecodedField(name: "Machine feature", value: "Cadence"),
            GATTDecodedField(name: "Target setting", value: "Speed"),
            GATTDecodedField(name: "Target setting", value: "Heart Rate"),
        ])
    }

    func testFeatureDecoderRejectsWrongLengthWithoutLosingRawBytes() {
        let decoded = GATTValueDecoder.decode(
            characteristicUUID: "2A65",
            data: Data([0x01, 0x00])
        )

        XCTAssertEqual(decoded?.rawHex, "0100")
        XCTAssertTrue(decoded?.warning?.contains("4-byte Cycling Power Feature") == true)
    }

    func testDeviceInformationDecoderBuildsEvidenceWithoutReplacingRawBytes() {
        let manufacturer = GATTValueDecoder.decode(
            characteristicUUID: "2A29",
            data: Data("Acme Devices".utf8)
        )
        let model = GATTValueDecoder.decode(
            characteristicUUID: "2A24",
            data: Data("AppleTV14,1".utf8)
        )
        var evidence = GATTDeviceEvidence()

        evidence.merge(characteristicUUID: "2A29", decodedValue: manufacturer)
        evidence.merge(characteristicUUID: "2A24", decodedValue: model)

        XCTAssertEqual(evidence.identity.manufacturerName, "Acme Devices")
        XCTAssertEqual(evidence.identity.modelNumber, "AppleTV14,1")
        XCTAssertEqual(model?.rawHex, "4170706C65545631342C31")
    }

    func testDeviceReportedAppearanceOutweighsNameHeuristicsWithVisibleProvenance() {
        let advertisement = BLEAdvertisement(
            localName: "Living Room Speaker",
            manufacturerDataHex: nil,
            companyIdentifier: nil,
            serviceUUIDs: [],
            solicitedServiceUUIDs: [],
            serviceData: [:],
            overflowServiceUUIDs: [],
            txPower: nil,
            isConnectable: true
        )
        var evidence = GATTDeviceEvidence()
        evidence.identity.appearance = GATTAppearance(
            rawValue: 0x00C2,
            categoryName: "Watch",
            subcategoryName: "Smartwatch"
        )

        let intelligence = DeviceIntelligenceEngine().analyze(advertisement, gattEvidence: evidence)

        XCTAssertEqual(intelligence.category, .smartWatch)
        XCTAssertEqual(intelligence.evidence.first?.kind, .gattAppearance)
        XCTAssertTrue(intelligence.evidence.first?.description.contains("device reported") == true)
    }

    func testDiscoveredAdoptedServiceProvidesCapabilityEvidence() {
        var evidence = GATTDeviceEvidence()
        evidence.setDiscoveredServiceUUIDs(["180D"])

        let intelligence = DeviceIntelligenceEngine().analyze(.empty, gattEvidence: evidence)

        XCTAssertEqual(intelligence.category, .healthFitness)
        XCTAssertEqual(intelligence.evidence.first?.kind, .gattService)
        XCTAssertTrue(intelligence.evidence.first?.description.contains("discovered after connection") == true)
    }
}
