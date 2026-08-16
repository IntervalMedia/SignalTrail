import UIKit
import CoreBluetooth

final class CharacteristicViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case properties
        case value
        case read
        case notify
    }

    private enum AdvancedRow: Int, CaseIterable {
        case writeText
        case writeHex
    }

    private let serviceUUID: String
    private var snapshot: GATTCharacteristicSnapshot
    private let characteristic: CBCharacteristic
    private let inspector: PeripheralInspector

    init(
        serviceUUID: String,
        snapshot: GATTCharacteristicSnapshot,
        characteristic: CBCharacteristic,
        inspector: PeripheralInspector
    ) {
        self.serviceUUID = serviceUUID
        self.snapshot = snapshot
        self.characteristic = characteristic
        self.inspector = inspector
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = BluetoothAssignedUUIDLookup.metadata(
            for: snapshot.uuid,
            kind: .characteristic
        )?.name ?? "Vendor-specific characteristic"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        inspector.delegate = self
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return Row.allCases.count
        case 1: return max(1, snapshot.descriptors.count)
        default: return AdvancedRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Device-reported characteristic"
        case 1: return "Descriptors"
        default: return "Advanced tools"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Decoded values follow Bluetooth SIG definitions when available. Raw bytes are retained."
        case 1: return "Descriptors provide device-reported format and presentation metadata."
        default: return "Writing to a GATT characteristic can change device behaviour."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none
        cell.accessoryType = .none

        if indexPath.section == 0 {
            let row = Row(rawValue: indexPath.row)!
            switch row {
            case .properties:
                content.text = "Properties"
                content.secondaryText = snapshot.properties.joined(separator: ", ")
            case .value:
                content.text = "Latest value"
                if let decoded = snapshot.decodedValue {
                    content.secondaryText = [
                        "Device reported: \(decoded.displayText)",
                        decoded.fields.isEmpty ? nil : decoded.fields
                            .map { "\($0.name): \($0.value)" }
                            .joined(separator: "\n"),
                        "Raw bytes: \(decoded.rawHex)",
                        decoded.warning,
                    ].compactMap { $0 }.joined(separator: "\n")
                } else {
                    content.secondaryText = snapshot.valueHex.map { "Raw bytes: \($0)" }
                        ?? "No value read"
                }
                content.secondaryTextProperties.numberOfLines = 0
                content.image = snapshot.valueHex == nil ? nil : UIImage(systemName: "doc.on.doc")
                content.imageProperties.tintColor = AppTheme.accent
                cell.selectionStyle = snapshot.valueHex == nil ? .none : .default
            case .read:
                content.text = "Read value"
                content.image = UIImage(systemName: "arrow.down.circle")
                content.textProperties.color = characteristic.properties.contains(.read) ? AppTheme.accent : .secondaryLabel
                cell.selectionStyle = characteristic.properties.contains(.read) ? .default : .none
            case .notify:
                content.text = snapshot.isNotifying ? "Disable notifications" : "Enable notifications"
                content.image = UIImage(systemName: snapshot.isNotifying ? "bell.slash" : "bell")
                let allowed = characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)
                content.textProperties.color = allowed ? AppTheme.accent : .secondaryLabel
                cell.selectionStyle = allowed ? .default : .none
            }
        } else if indexPath.section == 1 {
            if snapshot.descriptors.isEmpty {
                content.text = "No descriptors discovered"
                content.textProperties.color = .secondaryLabel
            } else {
                let descriptor = snapshot.descriptors[indexPath.row]
                let metadata = BluetoothAssignedUUIDLookup.metadata(
                    for: descriptor.uuid,
                    kind: .descriptor
                )
                content.text = metadata?.name ?? "Vendor-specific descriptor"
                content.secondaryText = [
                    "UUID \(descriptor.uuid)",
                    descriptor.displayValue.map { "Device reported: \($0)" },
                    descriptor.rawHex.map { "Raw bytes: \($0)" },
                ].compactMap { $0 }.joined(separator: "\n")
                content.secondaryTextProperties.numberOfLines = 4
            }
        } else {
            let row = AdvancedRow(rawValue: indexPath.row)!
            switch row {
            case .writeText:
                content.text = "Write UTF-8 text"
                content.image = UIImage(systemName: "text.cursor")
            case .writeHex:
                content.text = "Write hexadecimal"
                content.image = UIImage(systemName: "number")
            }
            let allowed = canWrite
            content.textProperties.color = allowed ? AppTheme.accent : .secondaryLabel
            content.imageProperties.tintColor = allowed ? AppTheme.accent : .secondaryLabel
            cell.selectionStyle = allowed ? .default : .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            switch Row(rawValue: indexPath.row)! {
            case .value:
                guard let value = snapshot.valueHex else { return }
                UIPasteboard.general.string = value
            case .read where characteristic.properties.contains(.read):
                inspector.read(characteristic)
            case .notify where characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate):
                inspector.setNotify(!snapshot.isNotifying, for: characteristic)
            default:
                break
            }
        } else if indexPath.section == 2 {
            switch AdvancedRow(rawValue: indexPath.row)! {
            case .writeText where canWrite:
                presentWritePrompt(hex: false)
            case .writeHex where canWrite:
                presentWritePrompt(hex: true)
            default:
                break
            }
        }
    }

    private var canWrite: Bool {
        characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)
    }

    private func presentWritePrompt(hex: Bool) {
        let alert = UIAlertController(
            title: hex ? "Write hexadecimal" : "Write UTF-8 text",
            message: hex ? "Enter pairs such as 01 FF A0." : "The text will be encoded as UTF-8.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.autocapitalizationType = hex ? .allCharacters : .sentences
            field.autocorrectionType = .no
            field.placeholder = hex ? "01 FF A0" : "Value"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text else { return }
            let data = hex ? Data(hexadecimalString: text) : text.data(using: .utf8)
            guard let data = data else {
                self.presentError("The value could not be encoded.")
                return
            }
            self.confirmWrite(data)
        })
        present(alert, animated: true)
    }

    private func confirmWrite(_ data: Data) {
        let alert = UIAlertController(
            title: "Write to characteristic?",
            message: "This will send \(data.hexadecimalString) to \(snapshot.uuid). Device behaviour may change.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Write", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.inspector.write(data, to: self.characteristic)
        })
        present(alert, animated: true)
    }
}

extension CharacteristicViewController: PeripheralInspectorDelegate {
    func peripheralInspectorDidUpdate(_ inspector: PeripheralInspector) {
        guard let service = inspector.services.first(where: { $0.uuid == serviceUUID }),
              let updated = service.characteristics.first(where: { $0.uuid == snapshot.uuid }) else { return }
        snapshot = updated
        tableView.reloadData()
    }

    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String) {
        presentError(message)
    }
}
