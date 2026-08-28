import Foundation
import CoreBluetooth

enum BackgroundGATTProbeError: LocalizedError, Equatable {
    case timedOut
    case cancelled
    case connectionFailed(String)
    case disconnected
    case serviceDiscoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "GATT probe timed out."
        case .cancelled:
            return "GATT probe was cancelled."
        case .connectionFailed(let message):
            return "Peripheral connection failed: \(message)"
        case .disconnected:
            return "Peripheral disconnected before GATT probe completed."
        case .serviceDiscoveryFailed(let message):
            return "Service discovery failed: \(message)"
        }
    }
}

class BackgroundGATTProbe: NSObject {
    static let defaultTimeout: TimeInterval = 5.0

    static let targetCharacteristicUUIDs: Set<UInt16> = [
        0x2A00, // Device Name (0x1800)
        0x2A01, // Appearance (0x1800)
        0x2A19, // Battery Level (0x180F)
        0x2A23, // System ID (0x180A)
        0x2A24, // Model Number (0x180A)
        0x2A25, // Serial Number (0x180A)
        0x2A26, // Firmware Revision (0x180A)
        0x2A27, // Hardware Revision (0x180A)
        0x2A28, // Software Revision (0x180A)
        0x2A29, // Manufacturer Name (0x180A)
        0x2A50  // PnP ID (0x180A)
    ]

    private let scanner: BluetoothScanning
    let peripheral: CBPeripheral
    let timeout: TimeInterval
    private let completion: (Result<GATTDeviceEvidence, Error>) -> Void

    private(set) var evidence = GATTDeviceEvidence()
    private(set) var exploredServices: [GATTServiceSnapshot] = []
    private(set) var isStarted = false
    private(set) var isCompleted = false

    private var timeoutTimer: Timer?
    private var pendingServiceDiscoveries = Set<String>()
    private var pendingCharacteristicReads = Set<String>()

    init(
        peripheral: CBPeripheral,
        scanner: BluetoothScanning,
        timeout: TimeInterval = defaultTimeout,
        completion: @escaping (Result<GATTDeviceEvidence, Error>) -> Void
    ) {
        self.peripheral = peripheral
        self.scanner = scanner
        self.timeout = timeout
        self.completion = completion
        super.init()
    }

    convenience init(
        scanner: BluetoothScanning,
        peripheral: CBPeripheral,
        timeout: TimeInterval = defaultTimeout,
        completion: @escaping (Result<GATTDeviceEvidence, Error>) -> Void
    ) {
        self.init(
            peripheral: peripheral,
            scanner: scanner,
            timeout: timeout,
            completion: completion
        )
    }

    func start() {
        guard !isStarted, !isCompleted else { return }
        isStarted = true

        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: timeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleTimeout()
        }

        scanner.connect(peripheral, delegate: self)
    }

    func cancel() {
        guard !isCompleted else { return }
        finish(with: .failure(BackgroundGATTProbeError.cancelled))
    }

    private func handleTimeout() {
        guard !isCompleted else { return }
        finish(with: .failure(BackgroundGATTProbeError.timedOut))
    }

    private func finish(with result: Result<GATTDeviceEvidence, Error>) {
        guard !isCompleted else { return }
        isCompleted = true

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        scanner.disconnect(peripheral)
        completion(result)
    }

    static func isTargetCharacteristic(uuidString: String) -> Bool {
        guard let value = BluetoothAssignedUUIDLookup.canonical16BitValue(from: uuidString) else {
            return false
        }
        return targetCharacteristicUUIDs.contains(value)
    }

    private func readKey(for characteristic: CBCharacteristic) -> String {
        let serviceUUID = characteristic.service?.uuid.uuidString ?? ""
        return "\(serviceUUID)|\(characteristic.uuid.uuidString)"
    }

    private func rebuildExploredServices() {
        var updatedEvidence = evidence
        updatedEvidence.setDiscoveredServiceUUIDs(
            (peripheral.services ?? []).map { $0.uuid.uuidString }
        )
        exploredServices = (peripheral.services ?? []).map { service in
            let characteristics = (service.characteristics ?? []).map { characteristic in
                let decodedValue = characteristic.value.flatMap {
                    GATTValueDecoder.decode(
                        characteristicUUID: characteristic.uuid.uuidString,
                        data: $0
                    )
                }
                return GATTCharacteristicSnapshot(
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.displayNames,
                    valueHex: characteristic.value?.hexadecimalString,
                    decodedValue: decodedValue,
                    descriptors: [],
                    isNotifying: characteristic.isNotifying
                )
            }
            return GATTServiceSnapshot(uuid: service.uuid.uuidString, characteristics: characteristics)
        }
        evidence = updatedEvidence
    }

    private func checkIfAllReadsCompleted() {
        guard pendingServiceDiscoveries.isEmpty, pendingCharacteristicReads.isEmpty else { return }
        finish(with: .success(evidence))
    }
}

extension BackgroundGATTProbe: PeripheralConnectionDelegate {
    func peripheralConnectionDidConnect(_ peripheral: CBPeripheral) {
        guard !isCompleted else { return }
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func peripheralConnection(_ peripheral: CBPeripheral, didFail error: Error?) {
        guard !isCompleted else { return }
        finish(with: .failure(BackgroundGATTProbeError.connectionFailed(error?.localizedDescription ?? "Connection failed")))
    }

    func peripheralConnectionDidDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        guard !isCompleted else { return }
        if evidence.hasValues {
            finish(with: .success(evidence))
        } else {
            finish(with: .failure(BackgroundGATTProbeError.disconnected))
        }
    }
}

extension BackgroundGATTProbe: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !isCompleted else { return }
        if let error = error {
            finish(with: .failure(BackgroundGATTProbeError.serviceDiscoveryFailed(error.localizedDescription)))
            return
        }

        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            finish(with: .success(evidence))
            return
        }

        evidence.setDiscoveredServiceUUIDs(services.map { $0.uuid.uuidString })
        pendingServiceDiscoveries = Set(services.map { $0.uuid.uuidString })

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !isCompleted else { return }
        pendingServiceDiscoveries.remove(service.uuid.uuidString)

        for characteristic in service.characteristics ?? [] {
            if BackgroundGATTProbe.isTargetCharacteristic(uuidString: characteristic.uuid.uuidString),
               characteristic.properties.contains(.read) {
                let key = readKey(for: characteristic)
                if pendingCharacteristicReads.insert(key).inserted {
                    peripheral.readValue(for: characteristic)
                }
            }
        }

        checkIfAllReadsCompleted()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !isCompleted else { return }
        let key = readKey(for: characteristic)
        pendingCharacteristicReads.remove(key)

        if error == nil, let data = characteristic.value {
            let charUUID = characteristic.uuid.uuidString
            let decoded = GATTValueDecoder.decode(characteristicUUID: charUUID, data: data)
            evidence.merge(characteristicUUID: charUUID, decodedValue: decoded)
            rebuildExploredServices()
        }

        checkIfAllReadsCompleted()
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
