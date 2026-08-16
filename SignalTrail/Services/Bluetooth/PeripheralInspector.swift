import Foundation
import CoreBluetooth

protocol PeripheralInspectorDelegate: AnyObject {
    func peripheralInspectorDidUpdate(_ inspector: PeripheralInspector)
    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String)
}

final class PeripheralInspector: NSObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    weak var delegate: PeripheralInspectorDelegate?

    private let scanner: BluetoothScanner
    let peripheral: CBPeripheral
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var services: [GATTServiceSnapshot] = []
    private(set) var evidence = GATTDeviceEvidence()
    private var automaticallyRequestedReads = Set<String>()

    init(scanner: BluetoothScanner, peripheral: CBPeripheral) {
        self.scanner = scanner
        self.peripheral = peripheral
        super.init()
    }

    func connect() {
        connectionState = .connecting
        delegate?.peripheralInspectorDidUpdate(self)
        scanner.connect(peripheral, delegate: self)
    }

    func disconnect() {
        scanner.disconnect(peripheral)
    }

    func read(_ characteristic: CBCharacteristic) {
        peripheral.readValue(for: characteristic)
    }

    func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic) {
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    func write(_ data: Data, to characteristic: CBCharacteristic) {
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    func characteristic(serviceUUID: String, characteristicUUID: String) -> CBCharacteristic? {
        peripheral.services?
            .first(where: { $0.uuid.uuidString == serviceUUID })?
            .characteristics?
            .first(where: { $0.uuid.uuidString == characteristicUUID })
    }

    private func rebuildSnapshots() {
        var updatedEvidence = evidence
        updatedEvidence.setDiscoveredServiceUUIDs(
            (peripheral.services ?? []).map { $0.uuid.uuidString }
        )
        services = (peripheral.services ?? []).map { service in
            let characteristics = (service.characteristics ?? []).map { characteristic in
                let decodedValue = characteristic.value.flatMap {
                    GATTValueDecoder.decode(
                        characteristicUUID: characteristic.uuid.uuidString,
                        data: $0
                    )
                }
                updatedEvidence.merge(
                    characteristicUUID: characteristic.uuid.uuidString,
                    decodedValue: decodedValue
                )
                return GATTCharacteristicSnapshot(
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.displayNames,
                    valueHex: characteristic.value?.hexadecimalString,
                    decodedValue: decodedValue,
                    descriptors: (characteristic.descriptors ?? []).map { descriptor in
                        descriptorSnapshot(descriptor)
                    },
                    isNotifying: characteristic.isNotifying
                )
            }
            return GATTServiceSnapshot(uuid: service.uuid.uuidString, characteristics: characteristics)
        }
        evidence = updatedEvidence
        delegate?.peripheralInspectorDidUpdate(self)
    }

    private func descriptorSnapshot(_ descriptor: CBDescriptor) -> GATTDescriptorSnapshot {
        let uuid = descriptor.uuid.uuidString
        if let data = descriptor.value as? Data {
            let identifier = BluetoothAssignedUUIDLookup.canonical16BitValue(from: uuid)
            let decoded = identifier == 0x2904
                ? GATTValueDecoder.decodePresentationFormatDescriptor(data)
                : nil
            let displayValue = decoded?.displayText ?? (identifier == 0x2901 ? printableString(from: data) : nil)
            return GATTDescriptorSnapshot(
                uuid: uuid,
                displayValue: displayValue,
                rawHex: data.hexadecimalString
            )
        }
        if let string = descriptor.value as? String {
            return GATTDescriptorSnapshot(uuid: uuid, displayValue: string, rawHex: nil)
        }
        if let number = descriptor.value as? NSNumber {
            return GATTDescriptorSnapshot(uuid: uuid, displayValue: number.stringValue, rawHex: nil)
        }
        return GATTDescriptorSnapshot(uuid: uuid, displayValue: nil, rawHex: nil)
    }

    private func printableString(from data: Data) -> String? {
        guard let value = String(data: data, encoding: .utf8),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private func readKey(for characteristic: CBCharacteristic) -> String {
        let serviceUUID = characteristic.service?.uuid.uuidString ?? ""
        return "\(serviceUUID)|\(characteristic.uuid.uuidString)"
    }
}

extension PeripheralInspector: PeripheralConnectionDelegate {
    func peripheralConnectionDidConnect(_ peripheral: CBPeripheral) {
        connectionState = .connected
        automaticallyRequestedReads.removeAll()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        delegate?.peripheralInspectorDidUpdate(self)
    }

    func peripheralConnection(_ peripheral: CBPeripheral, didFail error: Error?) {
        connectionState = .failed(error?.localizedDescription ?? "Connection failed")
        delegate?.peripheralInspector(self, didFail: error?.localizedDescription ?? "Connection failed")
    }

    func peripheralConnectionDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        services = []
        delegate?.peripheralInspectorDidUpdate(self)
    }
}

extension PeripheralInspector: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
            return
        }
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
            return
        }
        for characteristic in service.characteristics ?? [] {
            peripheral.discoverDescriptors(for: characteristic)
            let key = readKey(for: characteristic)
            if characteristic.properties.contains(.read),
               GATTValueDecoder.shouldAutomaticallyRead(
                   characteristicUUID: characteristic.uuid.uuidString
               ),
               automaticallyRequestedReads.insert(key).inserted {
                peripheral.readValue(for: characteristic)
            }
        }
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let wasAutomaticRead = automaticallyRequestedReads.remove(readKey(for: characteristic)) != nil
        if let error = error {
            if wasAutomaticRead {
                rebuildSnapshots()
                return
            }
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
            return
        }
        rebuildSnapshots()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverDescriptorsFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else {
            rebuildSnapshots()
            return
        }
        for descriptor in characteristic.descriptors ?? [] {
            guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(
                from: descriptor.uuid.uuidString
            ), [0x2901, 0x2904, 0x2906].contains(value) else { continue }
            peripheral.readValue(for: descriptor)
        }
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
            return
        }
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
        }
    }
}

private extension CBCharacteristicProperties {
    var displayNames: [String] {
        var values: [String] = []
        if contains(.broadcast) { values.append("Broadcast") }
        if contains(.read) { values.append("Read") }
        if contains(.writeWithoutResponse) { values.append("Write without response") }
        if contains(.write) { values.append("Write") }
        if contains(.notify) { values.append("Notify") }
        if contains(.indicate) { values.append("Indicate") }
        if contains(.authenticatedSignedWrites) { values.append("Signed write") }
        if contains(.extendedProperties) { values.append("Extended") }
        return values
    }
}
