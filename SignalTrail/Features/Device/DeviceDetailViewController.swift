import CoreBluetooth
import UIKit

final class DeviceDetailViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case summary
        case actions
        case advertisement
        case serviceData
        case services
        case rawValues

        var title: String {
            switch self {
            case .summary: return "Summary"
            case .actions: return "Actions"
            case .advertisement: return "Observed advertisement"
            case .serviceData: return "Observed service data"
            case .services: return "Discovered GATT capabilities"
            case .rawValues: return "Observed identifiers"
            }
        }

        var isTechnical: Bool {
            switch self {
            case .advertisement, .serviceData, .services, .rawValues: return true
            default: return false
            }
        }
    }

    private var device: BLEDeviceSnapshot
    private let environment: AppEnvironment
    private var inspector: PeripheralInspector?
    private var services: [GATTServiceSnapshot] = []
    private var expandedSections = Set<Section>()

    init(device: BLEDeviceSnapshot, environment: AppEnvironment) {
        self.device = device
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = device.presentationName
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        configureToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        inspector?.delegate = self
        configureToolbar()
        tableView.reloadData()
    }

    private func configureToolbar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: isKnown ? "star.fill" : "star"),
            style: .plain,
            target: self,
            action: #selector(saveKnownTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "Save device"
    }

    private var isKnown: Bool {
        environment.store.loadKnownDevices().contains { $0.peripheralIdentifier == device.peripheralIdentifier }
    }

    private var hasAlertMatch: Bool {
        environment.store.loadAlertRules().contains { AlertMatcher.matches(rule: $0, device: device) }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .summary:
            return 3
        case .actions:
            return 3
        case .advertisement, .serviceData, .rawValues:
            return expandedSections.contains(section) ? max(rows(for: section).count, 1) : 1
        case .services:
            return expandedSections.contains(section) ? max(services.count, 1) : 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .summary:
            return "Observed and device-reported values are facts from this interaction. Inferences may be wrong. Observation locations are where this phone heard a signal, not verified device positions."
        case .services:
            return expandedSections.contains(.services)
                ? (services.isEmpty ? "Connect to discover services and characteristics." : "Select a service to inspect characteristics.")
                : nil
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .none
        cell.accessoryView = nil
        content.secondaryTextProperties.numberOfLines = 4

        guard let section = Section(rawValue: indexPath.section) else {
            cell.contentConfiguration = content
            return cell
        }

        if section.isTechnical && !expandedSections.contains(section) {
            content.text = "Show \(section.title.lowercased())"
            content.image = UIImage(systemName: "chevron.right.circle")
            content.imageProperties.tintColor = AppTheme.accent
            cell.selectionStyle = .default
            cell.contentConfiguration = content
            return cell
        }

        switch section {
        case .summary:
            configureSummaryCell(content: &content, row: indexPath.row)

        case .actions:
            configureActionCell(cell, content: &content, row: indexPath.row)

        case .advertisement, .serviceData, .rawValues:
            let rowData = rows(for: section)
            if rowData.isEmpty {
                content.text = emptyText(for: section)
                content.textProperties.color = .secondaryLabel
            } else {
                let row = rowData[indexPath.row]
                content.text = row.title
                content.secondaryText = row.value
                content.secondaryTextProperties.font = row.copyable
                    ? .monospacedSystemFont(ofSize: 13, weight: .regular)
                    : .preferredFont(forTextStyle: .body)
                if row.copyable {
                    content.image = UIImage(systemName: "doc.on.doc")
                    content.imageProperties.tintColor = AppTheme.accent
                    cell.selectionStyle = .default
                }
            }

        case .services:
            if services.isEmpty {
                content.text = "No services discovered"
                content.textProperties.color = .secondaryLabel
            } else {
                let service = services[indexPath.row]
                let metadata = BluetoothAssignedUUIDLookup.serviceMetadata(for: service.uuid)
                content.text = metadata?.name ?? "Vendor-specific service"
                content.secondaryText = [
                    "UUID \(service.uuid) • discovered after connection",
                    metadata?.assignmentDescription,
                    "\(service.characteristics.count) characteristic\(service.characteristics.count == 1 ? "" : "s")",
                ].compactMap { $0 }.joined(separator: "\n")
                content.secondaryTextProperties.numberOfLines = 4
                content.image = UIImage(systemName: "square.stack.3d.up")
                content.imageProperties.tintColor = AppTheme.accent
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default
            }
        }

        cell.contentConfiguration = content
        return cell
    }

    private func configureSummaryCell(
        content: inout UIListContentConfiguration,
        row: Int
    ) {
        switch row {
        case 0:
            content.secondaryTextProperties.numberOfLines = 4
            content.text = "Observed"
            content.secondaryText = [
                device.presentationName,
                "Current \(device.latestRSSI) dBm • strongest \(device.strongestRSSI) dBm",
                "Last seen \(DateFormatter.signalTrailTime.string(from: device.lastSeen)) • \(device.sightingCount) observation\(device.sightingCount == 1 ? "" : "s")",
                "\(isKnown ? "Saved device" : "Not saved") • \(hasAlertMatch ? "Alert matched" : "No alert match")",
            ].joined(separator: "\n")
            content.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
            content.imageProperties.tintColor = AppTheme.accent
        case 1:
            content.secondaryTextProperties.numberOfLines = 0
            content.text = "Device-reported"
            content.secondaryText = deviceReportedSummary
            content.image = UIImage(systemName: "dot.radiowaves.left.and.right")
            content.imageProperties.tintColor = .systemTeal
        default:
            let intelligence = device.intelligence
            content.text = "Inference"
            content.secondaryText = [
                "\(intelligence.confidenceLabel): \(intelligence.categoryTitle)",
                intelligence.modelFamily.map { "Model family: \($0)" },
                intelligence.evidence.first.map { "Evidence: \($0.description)" },
            ].compactMap { $0 }.joined(separator: "\n")
            content.image = UIImage(systemName: "sparkles")
            content.imageProperties.tintColor = .systemBlue
        }
    }

    private var deviceReportedSummary: String {
        guard let identity = device.gattEvidence?.identity, identity.hasValues else {
            return "Connect to read GAP Appearance and Device Information when the peripheral exposes them."
        }
        return [
            identity.appearance.map { "Appearance: \($0.displayName)" },
            identity.manufacturerName.map { "Manufacturer name: \($0)" },
            identity.modelNumber.map { "Model number: \($0)" },
            identity.serialNumber.map { "Serial number: \($0)" },
            identity.firmwareRevision.map { "Firmware: \($0)" },
            identity.hardwareRevision.map { "Hardware: \($0)" },
            identity.softwareRevision.map { "Software: \($0)" },
            identity.pnpIdentifier.map(pnpSummary),
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private func pnpSummary(_ identifier: GATTPnPIdentifier) -> String {
        let vendor: String
        switch identifier.vendorIDSource {
        case .bluetoothSIG:
            vendor = "Bluetooth SIG company ID assigned to \(BluetoothCompanyLookup.displayName(for: identifier.vendorID))"
        case .usbImplementersForum:
            vendor = String(format: "USB-IF vendor 0x%04X", identifier.vendorID)
        case nil:
            vendor = String(
                format: "unassigned vendor namespace 0x%02X, vendor 0x%04X",
                identifier.rawVendorIDSource,
                identifier.vendorID
            )
        }
        return String(
            format: "PnP ID: %@ • product 0x%04X • version 0x%04X",
            vendor,
            identifier.productID,
            identifier.productVersion
        )
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        if section.isTechnical && !expandedSections.contains(section) {
            expandedSections.insert(section)
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            return
        }

        switch section {
        case .actions:
            if indexPath.row == 0 {
                saveKnownTapped()
            } else if indexPath.row == 1 {
                showAlertTemplates()
            } else {
                toggleConnection()
            }

        case .advertisement, .serviceData, .rawValues:
            let row = rows(for: section)[indexPath.row]
            guard row.copyable else { return }
            UIPasteboard.general.string = row.value

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

    private func configureActionCell(
        _ cell: UITableViewCell,
        content: inout UIListContentConfiguration,
        row: Int
    ) {
        cell.selectionStyle = .default
        switch row {
        case 0:
            content.text = isKnown ? "Edit saved device" : "Save device"
            content.image = UIImage(systemName: isKnown ? "star.fill" : "star")
            content.imageProperties.tintColor = .systemYellow
        case 1:
            content.text = "Create alert"
            content.image = UIImage(systemName: "bell.badge")
            content.imageProperties.tintColor = .systemOrange
        default:
            content.text = connectionActionTitle
            content.image = UIImage(systemName: connectionActionSymbol)
            content.imageProperties.tintColor = inspector?.connectionState == .connected ? .systemRed : AppTheme.accent
        }
    }

    private func rows(for section: Section) -> [(title: String, value: String, copyable: Bool)] {
        switch section {
        case .advertisement:
            let memberUUIDSummary = device.advertisement.memberServiceUUIDs.isEmpty
                ? "None"
                : device.advertisement.memberServiceUUIDs.compactMap {
                    BluetoothAssignedUUIDLookup.metadata(for: $0, kind: .member)?.assignmentDescription
                }.sorted().joined(separator: ", ")
            return [
                ("Local name", device.advertisement.localName ?? "Not advertised", false),
                ("Company identifier assignment", BluetoothCompanyLookup.displayName(for: device.advertisement.companyIdentifier), false),
                ("Manufacturer data", device.advertisement.manufacturerDataHex ?? "Not advertised", device.advertisement.manufacturerDataHex != nil),
                ("Member UUID assignments", memberUUIDSummary, !device.advertisement.memberServiceUUIDs.isEmpty),
                ("Service UUIDs", assignedServiceList(device.advertisement.serviceUUIDs), !device.advertisement.serviceUUIDs.isEmpty),
                ("TX power", device.advertisement.txPower.map { "\($0) dBm" } ?? "Not advertised", false)
            ]
        case .serviceData:
            return device.advertisement.serviceData
                .sorted { $0.key < $1.key }
                .map {
                    let name = BluetoothAssignedUUIDLookup.serviceMetadata(for: $0.key)?.name
                    return (name.map { "\($0) service data" } ?? "Service \($0.key)", $0.value, true)
                }
        case .rawValues:
            return [
                ("App-scoped UUID", device.peripheralIdentifier.uuidString, true),
                ("Metadata tag", device.lastSeenMetadataTag, true),
                ("Solicited service UUIDs", device.advertisement.solicitedServiceUUIDs.joined(separator: ", "), !device.advertisement.solicitedServiceUUIDs.isEmpty),
                ("Overflow service UUIDs", device.advertisement.overflowServiceUUIDs.joined(separator: ", "), !device.advertisement.overflowServiceUUIDs.isEmpty)
            ].filter { !$0.value.isEmpty }
        default:
            return []
        }
    }

    private func assignedServiceList(_ uuids: [String]) -> String {
        guard !uuids.isEmpty else { return "None" }
        return uuids.map { uuid in
            BluetoothAssignedUUIDLookup.serviceMetadata(for: uuid)?.displayName ?? uuid
        }.joined(separator: ", ")
    }

    private func emptyText(for section: Section) -> String {
        switch section {
        case .serviceData: return "No service data advertised"
        case .rawValues: return "No raw values available"
        default: return "No data advertised"
        }
    }

    private var connectionActionTitle: String {
        switch inspector?.connectionState ?? .disconnected {
        case .disconnected: return "Connect"
        case .connecting: return "Connecting..."
        case .connected: return "Disconnect"
        case .failed(let message): return "Retry connection - \(message)"
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
        expandedSections.insert(.services)
        tableView.reloadSections(IndexSet([Section.actions.rawValue, Section.services.rawValue]), with: .automatic)
    }

    @objc private func saveKnownTapped() {
        if let existing = environment.store.loadKnownDevices().first(where: { $0.peripheralIdentifier == device.peripheralIdentifier }) {
            showKnownDeviceEditor(existing)
            return
        }
        let known = KnownDevice(
            id: UUID(),
            peripheralIdentifier: device.peripheralIdentifier,
            nickname: device.presentationName,
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
        controller.onSave = { [weak self] in
            self?.configureToolbar()
            self?.tableView.reloadData()
        }
        let navigation = UINavigationController(rootViewController: controller)
        present(navigation, animated: true)
    }

    private func showAlertTemplates() {
        let alert = UIAlertController(title: "Create Alert", message: nil, preferredStyle: .actionSheet)
        for template in alertTemplates(for: device) {
            alert.addAction(UIAlertAction(title: template.title, style: .default) { [weak self] _ in
                self?.openAlertEditor(rule: template.rule)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func openAlertEditor(rule: AlertRule) {
        let controller = AlertRuleEditorViewController(rule: rule, environment: environment, isNewRule: true)
        controller.onSave = { [weak self] _ in self?.tableView.reloadData() }
        navigationController?.pushViewController(controller, animated: true)
    }
}

extension DeviceDetailViewController: PeripheralInspectorDelegate {
    func peripheralInspectorDidUpdate(_ inspector: PeripheralInspector) {
        services = inspector.services
        if inspector.evidence.hasValues {
            device.gattEvidence = inspector.evidence
            environment.scanCoordinator.enrichDevice(
                device.peripheralIdentifier,
                with: inspector.evidence
            )
        }
        tableView.reloadSections(
            IndexSet([Section.summary.rawValue, Section.actions.rawValue, Section.services.rawValue]),
            with: .automatic
        )
    }

    func peripheralInspector(_ inspector: PeripheralInspector, didFail message: String) {
        presentError(message)
        tableView.reloadSections(IndexSet([Section.actions.rawValue, Section.services.rawValue]), with: .automatic)
    }
}
