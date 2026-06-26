import UIKit
import CoreBluetooth

final class ServiceDetailViewController: UITableViewController {
    private var service: GATTServiceSnapshot
    private let inspector: PeripheralInspector

    init(service: GATTServiceSnapshot, inspector: PeripheralInspector) {
        self.service = service
        self.inspector = inspector
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = service.uuid
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        inspector.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inspector.delegate = self
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        service.characteristics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let characteristic = service.characteristics[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = characteristic.uuid
        var details = characteristic.properties.joined(separator: " • ")
        if let value = characteristic.valueHex { details += "\nValue: \(value)" }
        if characteristic.isNotifying { details += "\nNotifications enabled" }
        content.secondaryText = details
        content.secondaryTextProperties.numberOfLines = 3
        content.image = UIImage(systemName: characteristic.isNotifying ? "bell.badge.fill" : "slider.horizontal.3")
        content.imageProperties.tintColor = characteristic.isNotifying ? .systemOrange : AppTheme.accent
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let characteristic = service.characteristics[indexPath.row]
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
            tableView.reloadData()
        }
    }

    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String) {
        presentError(message)
    }
}
