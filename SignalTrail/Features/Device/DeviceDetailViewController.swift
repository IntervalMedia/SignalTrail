import UIKit
import CoreBluetooth

final class DeviceDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case identity
        case advertisement
        case actions
        case services
    }

    private let device: BLEDeviceSnapshot
    private let environment: AppEnvironment
    private var inspector: PeripheralInspector?
    private var services: [GATTServiceSnapshot] = []

    init(device: BLEDeviceSnapshot, environment: AppEnvironment) {
        self.device = device
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = device.displayName
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        configureToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inspector?.delegate = self
        configureToolbar()
    }

    private func configureToolbar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: isKnown ? "star.fill" : "star"),
            style: .plain,
            target: self,
            action: #selector(saveKnownTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Save known device"
    }

    private var isKnown: Bool {
        environment.store.loadKnownDevices().contains { $0.peripheralIdentifier == device.peripheralIdentifier }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .identity: return 5
        case .advertisement:
            var count = 5
            if !device.advertisement.serviceData.isEmpty { count += device.advertisement.serviceData.count }
            return count
        case .actions: return 1
        case .services: return max(services.count, 1)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .identity: return "Device"
        case .advertisement: return "Latest advertisement"
        case .actions: return "Connection"
        case .services: return "GATT services"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .identity:
            return "iOS exposes an app-scoped peripheral identifier, not the hardware BLE MAC address."
        case .services:
            return services.isEmpty ? "Connect to discover services and characteristics." : "Select a service to inspect its characteristics."
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        content.secondaryTextProperties.numberOfLines = 2

        switch Section(rawValue: indexPath.section)! {
        case .identity:
            let rows: [(String, String)] = [
                ("Name", device.displayName),
                ("Identifier", device.peripheralIdentifier.uuidString),
                ("Signal", "\(device.latestRSSI) dBm • \(device.signalLevel.title)"),
                ("Company", BluetoothCompanyLookup.displayName(for: device.advertisement.companyIdentifier)),
                ("Connectable", device.advertisement.isConnectable ? "Yes" : "No")
            ]
            content.text = rows[indexPath.row].0
            content.secondaryText = rows[indexPath.row].1

        case .advertisement:
            let memberUUIDSummary = device.advertisement.memberServiceUUIDs.isEmpty
                ? "None"
                : BluetoothMemberUUIDLookup.displayList(for: device.advertisement.memberServiceUUIDs).joined(separator: ", ")
            var rows: [(String, String)] = [
                ("Local name", device.advertisement.localName ?? "Not advertised"),
                ("Manufacturer data", device.advertisement.manufacturerDataHex ?? "Not advertised"),
                ("Member UUIDs", memberUUIDSummary),
                ("Service UUIDs", device.advertisement.serviceUUIDs.isEmpty ? "None" : device.advertisement.serviceUUIDs.joined(separator: ", ")),
                ("TX power", device.advertisement.txPower.map { "\($0) dBm" } ?? "Not advertised")
            ]
            rows.append(contentsOf: device.advertisement.serviceData.sorted(by: { $0.key < $1.key }).map {
                ("Service data \($0.key)", $0.value)
            })
            content.text = rows[indexPath.row].0
            content.secondaryText = rows[indexPath.row].1

        case .actions:
            content.text = connectionActionTitle
            content.image = UIImage(systemName: connectionActionSymbol)
            content.imageProperties.tintColor = inspector?.connectionState == .connected ? .systemRed : AppTheme.accent
            cell.selectionStyle = .default

        case .services:
            if services.isEmpty {
                content.text = "No services discovered"
                content.textProperties.color = .secondaryLabel
            } else {
                let service = services[indexPath.row]
                content.text = service.uuid
                content.secondaryText = "\(service.characteristics.count) characteristic\(service.characteristics.count == 1 ? "" : "s")"
                content.image = UIImage(systemName: "square.stack.3d.up")
                content.imageProperties.tintColor = AppTheme.accent
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            }
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .actions:
            toggleConnection()
        case .services where !services.isEmpty:
            guard let inspector = inspector else { return }
            let service = services[indexPath.row]
            navigationController?.pushViewController(
                ServiceDetailViewController(service: service, inspector: inspector),
                animated: true
            )
        default:
            break
        }
    }

    private var connectionActionTitle: String {
        switch inspector?.connectionState ?? .disconnected {
        case .disconnected: return "Connect and discover services"
        case .connecting: return "Connecting…"
        case .connected: return "Disconnect"
        case .failed(let message): return "Retry connection • \(message)"
        }
    }

    private var connectionActionSymbol: String {
        inspector?.connectionState == .connected ? "link.badge.minus" : "link"
    }

    private func toggleConnection() {
        if inspector?.connectionState == .connected {
            inspector?.disconnect()
            return
        }
        guard device.advertisement.isConnectable else {
            presentError("This advertisement reports that the device is not connectable.")
            return
        }
        guard let peripheral = environment.scanCoordinator.peripheral(for: device.peripheralIdentifier) else {
            presentError("The peripheral is no longer available. Return to Scan and observe it again.")
            return
        }
        let inspector = PeripheralInspector(scanner: environment.bluetoothScanner, peripheral: peripheral)
        inspector.delegate = self
        self.inspector = inspector
        inspector.connect()
        tableView.reloadSections(IndexSet(integer: Section.actions.rawValue), with: .automatic)
    }

    @objc private func saveKnownTapped() {
        if let existing = environment.store.loadKnownDevices().first(where: { $0.peripheralIdentifier == device.peripheralIdentifier }) {
            showKnownDeviceEditor(existing)
            return
        }
        let known = KnownDevice(
            id: UUID(),
            peripheralIdentifier: device.peripheralIdentifier,
            nickname: device.displayName,
            lastKnownName: device.displayName,
            companyIdentifier: device.advertisement.companyIdentifier,
            manufacturerPrefixHex: device.advertisement.manufacturerDataHex.map { String($0.prefix(8)) },
            notes: "",
            createdAt: Date(),
            lastSeenAt: device.lastSeen
        )
        showKnownDeviceEditor(known)
    }

    private func showKnownDeviceEditor(_ known: KnownDevice) {
        let controller = KnownDeviceEditorViewController(device: known, environment: environment)
        controller.onSave = { [weak self] in self?.configureToolbar() }
        let navigation = UINavigationController(rootViewController: controller)
        present(navigation, animated: true)
    }
}

extension DeviceDetailViewController: PeripheralInspectorDelegate {
    func peripheralInspectorDidUpdate(_ inspector: PeripheralInspector) {
        services = inspector.services
        tableView.reloadSections(IndexSet([Section.actions.rawValue, Section.services.rawValue]), with: .automatic)
    }

    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String) {
        presentError(message)
        tableView.reloadSections(IndexSet([Section.actions.rawValue, Section.services.rawValue]), with: .automatic)
    }
}
