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

protocol BluetoothScanning: AnyObject {
    func connect(_ peripheral: CBPeripheral, delegate: PeripheralConnectionDelegate)
    func disconnect(_ peripheral: CBPeripheral)
    func peripheral(for identifier: UUID) -> CBPeripheral?
}

final class BluetoothScanner: NSObject, BluetoothScanning {
    weak var delegate: BluetoothScannerDelegate?

    private lazy var centralManager = CBCentralManager(delegate: self, queue: .main)
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectionDelegates: [UUID: WeakConnectionDelegate] = [:]
    private var observers: [WeakScannerDelegate] = []

    private(set) var isScanning = false
    var stateOverride: CBManagerState? {
        didSet {
            notifyDelegate { $0.bluetoothScannerDidChangeState(self) }
        }
    }

    var state: CBManagerState { stateOverride ?? centralManager.state }
    var isReady: Bool { state == .poweredOn }

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
        notifyDelegate { $0.bluetoothScannerDidChangeState(self) }
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        notifyDelegate { $0.bluetoothScannerDidChangeState(self) }
    }

    func peripheral(for identifier: UUID) -> CBPeripheral? {
        peripherals[identifier]
    }

    func cachePeripheral(_ peripheral: CBPeripheral) {
        peripherals[peripheral.identifier] = peripheral
    }

    func trimCachedPeripherals(to identifiers: Set<UUID>) {
        guard !peripherals.isEmpty else { return }
        peripherals = peripherals.filter { identifiers.contains($0.key) }
    }

    func clearCachedPeripherals() {
        peripherals.removeAll()
    }

    func addObserver(_ observer: BluetoothScannerDelegate) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakScannerDelegate(observer))
    }

    func removeObserver(_ observer: BluetoothScannerDelegate) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    func connect(_ peripheral: CBPeripheral, delegate: PeripheralConnectionDelegate) {
        connectionDelegates[peripheral.identifier] = WeakConnectionDelegate(delegate)
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(_ peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func notifyConnectionDelegate(
        for peripheral: CBPeripheral,
        _ callback: @escaping (PeripheralConnectionDelegate) -> Void
    ) {
        if Thread.isMainThread {
            if let delegate = connectionDelegates[peripheral.identifier]?.value {
                callback(delegate)
            }
        } else {
            DispatchQueue.main.async { [weak self, weak peripheral] in
                guard let self,
                      let peripheral,
                      let delegate = self.connectionDelegates[peripheral.identifier]?.value else {
                    return
                }
                callback(delegate)
            }
        }
    }

    private func notifyDelegate(_ callback: @escaping (BluetoothScannerDelegate) -> Void) {
        if Thread.isMainThread {
            if let delegate {
                callback(delegate)
            }
            observers.removeAll { $0.value == nil }
            observers.compactMap(\.value).forEach(callback)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let delegate = self.delegate { callback(delegate) }
                self.observers.removeAll { $0.value == nil }
                self.observers.compactMap(\.value).forEach(callback)
            }
        }
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            isScanning = false
        }
        notifyDelegate { $0.bluetoothScannerDidChangeState(self) }
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
        let advertisement = AdvertisementParser.parse(advertisementData)
        let timestamp = Date()
        notifyDelegate {
            $0.bluetoothScanner(
                self,
                didDiscover: peripheral,
                advertisement: advertisement,
                rssi: rssi,
                timestamp: timestamp
            )
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        notifyConnectionDelegate(for: peripheral) {
            $0.peripheralConnectionDidConnect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        notifyConnectionDelegate(for: peripheral) {
            $0.peripheralConnection(peripheral, didFail: error)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        notifyConnectionDelegate(for: peripheral) {
            $0.peripheralConnectionDidDisconnect(peripheral, error: error)
        }
    }
}

private final class WeakConnectionDelegate {
    weak var value: PeripheralConnectionDelegate?
    init(_ value: PeripheralConnectionDelegate) { self.value = value }
}

private final class WeakScannerDelegate {
    weak var value: BluetoothScannerDelegate?
    init(_ value: BluetoothScannerDelegate) { self.value = value }
}
