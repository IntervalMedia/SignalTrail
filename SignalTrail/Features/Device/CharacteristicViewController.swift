import UIKit
import CoreBluetooth

final class CharacteristicViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case properties
        case value
        case read
        case notify
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
        title = snapshot.uuid
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        inspector.delegate = self
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = Row(rawValue: indexPath.row)!
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.selectionStyle = .none
        cell.accessoryType = .none

        switch row {
        case .properties:
            content.text = "Properties"
            content.secondaryText = snapshot.properties.joined(separator: ", ")
        case .value:
            content.text = "Latest value"
            content.secondaryText = snapshot.valueHex ?? "No value read"
            content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
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
        case .writeText:
            content.text = "Write UTF-8 text"
            content.image = UIImage(systemName: "text.cursor")
            let allowed = canWrite
            content.textProperties.color = allowed ? AppTheme.accent : .secondaryLabel
            cell.selectionStyle = allowed ? .default : .none
        case .writeHex:
            content.text = "Write hexadecimal"
            content.image = UIImage(systemName: "number")
            let allowed = canWrite
            content.textProperties.color = allowed ? AppTheme.accent : .secondaryLabel
            cell.selectionStyle = allowed ? .default : .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Row(rawValue: indexPath.row)! {
        case .read where characteristic.properties.contains(.read):
            inspector.read(characteristic)
        case .notify where characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate):
            inspector.setNotify(!snapshot.isNotifying, for: characteristic)
        case .writeText where canWrite:
            presentWritePrompt(hex: false)
        case .writeHex where canWrite:
            presentWritePrompt(hex: true)
        default:
            break
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
        alert.addAction(UIAlertAction(title: "Write", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let text = alert?.textFields?.first?.text else { return }
            let data = hex ? Data(hexadecimalString: text) : text.data(using: .utf8)
            guard let data = data else {
                self.presentError("The value could not be encoded.")
                return
            }
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
