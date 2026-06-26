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
        services = (peripheral.services ?? []).map { service in
            let characteristics = (service.characteristics ?? []).map { characteristic in
                GATTCharacteristicSnapshot(
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.displayNames,
                    valueHex: characteristic.value?.hexadecimalString,
                    isNotifying: characteristic.isNotifying
                )
            }
            return GATTServiceSnapshot(uuid: service.uuid.uuidString, characteristics: characteristics)
        }
        delegate?.peripheralInspectorDidUpdate(self)
    }
}

extension PeripheralInspector: PeripheralConnectionDelegate {
    func peripheralConnectionDidConnect(_ peripheral: CBPeripheral) {
        connectionState = .connected
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
        rebuildSnapshots()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            delegate?.peripheralInspector(self, didFail: error.localizedDescription)
            return
        }
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
