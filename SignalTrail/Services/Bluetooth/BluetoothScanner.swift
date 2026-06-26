import Foundation
import CoreBluetooth

protocol BluetoothScannerDelegate: AnyObject {
    func bluetoothScannerDidChangeState(_ scanner: BluetoothScanner)
    func bluetoothScanner(
        _ scanner: BluetoothScanner,
        didDiscover peripheral: CBPeripheral,
        advertisement: BLEAdvertisement,
        rssi: Int,
        timestamp: Date
    )
}

protocol PeripheralConnectionDelegate: AnyObject {
    func peripheralConnectionDidConnect(_ peripheral: CBPeripheral)
    func peripheralConnection(_ peripheral: CBPeripheral, didFail error: Error?)
    func peripheralConnectionDidDisconnect(_ peripheral: CBPeripheral, error: Error?)
}

final class BluetoothScanner: NSObject {
    weak var delegate: BluetoothScannerDelegate?

    private lazy var centralManager = CBCentralManager(delegate: self, queue: .main)
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectionDelegates: [UUID: WeakConnectionDelegate] = [:]

    private(set) var isScanning = false

    var state: CBManagerState { centralManager.state }
    var isReady: Bool { centralManager.state == .poweredOn }

    override init() {
        super.init()
        _ = centralManager
    }

    func startScanning(allowDuplicates: Bool = true) {
        guard isReady, !isScanning else { return }
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
        isScanning = true
        delegate?.bluetoothScannerDidChangeState(self)
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        delegate?.bluetoothScannerDidChangeState(self)
    }

    func peripheral(for identifier: UUID) -> CBPeripheral? {
        peripherals[identifier]
    }

    func connect(_ peripheral: CBPeripheral, delegate: PeripheralConnectionDelegate) {
        connectionDelegates[peripheral.identifier] = WeakConnectionDelegate(delegate)
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            isScanning = false
        }
        delegate?.bluetoothScannerDidChangeState(self)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        guard rssi != 127 else { return }
        peripherals[peripheral.identifier] = peripheral
        delegate?.bluetoothScanner(
            self,
            didDiscover: peripheral,
            advertisement: AdvertisementParser.parse(advertisementData),
            rssi: rssi,
            timestamp: Date()
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionDelegates[peripheral.identifier]?.value?.peripheralConnectionDidConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionDelegates[peripheral.identifier]?.value?.peripheralConnection(peripheral, didFail: error)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionDelegates[peripheral.identifier]?.value?.peripheralConnectionDidDisconnect(peripheral, error: error)
    }
}

private final class WeakConnectionDelegate {
    weak var value: PeripheralConnectionDelegate?
    init(_ value: PeripheralConnectionDelegate) { self.value = value }
}
