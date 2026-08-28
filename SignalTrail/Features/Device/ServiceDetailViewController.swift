import UIKit
import CoreBluetooth

final class ServiceDetailViewController: UITableViewController {
    private var service: GATTServiceSnapshot
    private let inspector: PeripheralInspector
    private var sections: [ServiceDetailSection] = []

    init(service: GATTServiceSnapshot, inspector: PeripheralInspector) {
        self.service = service
        self.inspector = inspector
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = BluetoothAssignedUUIDLookup.serviceMetadata(for: service.uuid)?.name
            ?? "Vendor-specific service"
        sections = ServiceDetailViewModel.buildSections(
            serviceUUID: service.uuid,
            characteristics: service.characteristics
        )
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        inspector.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inspector.delegate = self
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections.isEmpty ? 1 : sections[section].characteristics.count
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        max(sections.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections.isEmpty ? "Discovered Characteristics" : sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        guard !sections.isEmpty else {
            var content = cell.defaultContentConfiguration()
            content.text = "No characteristics discovered"
            content.textProperties.color = .secondaryLabel
            cell.contentConfiguration = content
            return cell
        }
        let characteristic = sections[indexPath.section].characteristics[indexPath.row]
        let metadata = BluetoothAssignedUUIDLookup.metadata(
            for: characteristic.uuid,
            kind: .characteristic
        )
        var content = cell.defaultContentConfiguration()
        content.text = metadata?.name ?? "Vendor-specific characteristic"
        var details = "UUID \(characteristic.uuid)\n\(characteristic.properties.joined(separator: " • "))"
        if let decoded = characteristic.decodedValue {
            details += "\nDevice reported: \(decoded.displayText)"
        } else if let value = characteristic.valueHex {
            details += "\nRaw value: \(value)"
        }
        if characteristic.isNotifying { details += "\nNotifications enabled" }
        content.secondaryText = details
        content.secondaryTextProperties.numberOfLines = 5
        content.image = UIImage(systemName: characteristic.isNotifying ? "bell.badge.fill" : "slider.horizontal.3")
        content.imageProperties.tintColor = characteristic.isNotifying ? .systemOrange : AppTheme.accent
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Services and characteristics describe capabilities exposed by the device; they do not authenticate its manufacturer or model."
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sections.isEmpty else { return }
        let characteristic = sections[indexPath.section].characteristics[indexPath.row]
        guard let cbCharacteristic = inspector.characteristic(
            serviceUUID: service.uuid,
            characteristicUUID: characteristic.uuid
        ) else { return }
        navigationController?.pushViewController(
            CharacteristicViewController(
                serviceUUID: service.uuid,
                snapshot: characteristic,
                characteristic: cbCharacteristic,
                inspector: inspector
            ),
            animated: true
        )
    }
}

extension ServiceDetailViewController: PeripheralInspectorDelegate {
    func peripheralInspectorDidUpdate(_ inspector: PeripheralInspector) {
        if let updated = inspector.services.first(where: { $0.uuid == service.uuid }) {
            service = updated
            sections = ServiceDetailViewModel.buildSections(
                serviceUUID: service.uuid,
                characteristics: service.characteristics
            )
            tableView.reloadData()
        }
    }

    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String) {
        presentError(message)
    }
}
