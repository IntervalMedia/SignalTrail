import UIKit

final class KnownDevicesViewController: UITableViewController {
    private enum Segment: Int {
        case devices
        case alerts
    }

    private let environment: AppEnvironment
    private var devices: [KnownDevice] = []
    private var rules: [AlertRule] = []
    private let segmentControl = UISegmentedControl(items: ["Devices", "Alerts"])
    private let emptyDevicesState = EmptyStateView(
        symbol: "star",
        title: "No saved devices",
        message: "Save a device from the Scan tab to give it a nickname and create matching alerts."
    )
    private let emptyAlertsState = EmptyStateView(
        symbol: "bell",
        title: "No alerts",
        message: "Create alerts from a scan result, device detail screen, recorded session, or this Library."
    )

    private var segment: Segment {
        Segment(rawValue: segmentControl.selectedSegmentIndex) ?? .devices
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        segmentControl.selectedSegmentIndex = 0
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        configureHeader()
        configureNavigation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func configureHeader() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56))
        container.addSubview(segmentControl)
        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segmentControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            segmentControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            segmentControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            segmentControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        tableView.tableHeaderView = container
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = segment == .alerts
            ? UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addAlertTapped))
            : nil
    }

    private func reload() {
        devices = environment.store.loadKnownDevices()
            .sorted { $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending }
        rules = environment.store.loadAlertRules()
        tableView.backgroundView =
            segment == .devices
            ? (devices.isEmpty ? emptyDevicesState : nil)
            : (rules.isEmpty ? emptyAlertsState : nil)
        configureNavigation()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        segment == .alerts ? 2 : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch segment {
        case .devices:
            return devices.count
        case .alerts:
            return section == 0 ? 1 : rules.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch segment {
        case .devices:
            return nil
        case .alerts:
            return section == 0 ? "Status" : "Rules"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        var content = cell.defaultContentConfiguration()
        content.secondaryTextProperties.numberOfLines = 3

        switch segment {
        case .devices:
            let device = devices[indexPath.row]
            content.text = device.nickname
            content.secondaryText = [
                device.lastKnownName,
                BluetoothCompanyLookup.name(for: device.companyIdentifier),
                device.peripheralIdentifier.uuidString
            ].compactMap { $0 }.joined(separator: " • ")
            content.image = UIImage(systemName: "star.fill")
            content.imageProperties.tintColor = .systemYellow
            cell.accessoryType = .disclosureIndicator

        case .alerts:
            if indexPath.section == 0 {
                let enabled = rules.filter(\.isEnabled).count
                let disabled = rules.count - enabled
                let currentMatches = environment.scanCoordinator.devices.reduce(0) { count, device in
                    count + (rules.contains { AlertMatcher.matches(rule: $0, device: device) } ? 1 : 0)
                }
                content.text = "\(enabled) enabled • \(disabled) disabled"
                content.secondaryText = "\(currentMatches) recent match\(currentMatches == 1 ? "" : "es") in current live results"
                content.image = UIImage(systemName: "bell.badge")
                content.imageProperties.tintColor = .systemOrange
                cell.selectionStyle = .none
            } else {
                let rule = rules[indexPath.row]
                content.text = rule.name
                content.secondaryText = rule.matchSummary
                content.image = UIImage(systemName: rule.isEnabled ? "bell.fill" : "bell.slash")
                content.imageProperties.tintColor = rule.isEnabled ? .systemOrange : .secondaryLabel
                cell.accessoryType = .disclosureIndicator
            }
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch segment {
        case .devices:
            let controller = KnownDeviceEditorViewController(device: devices[indexPath.row], environment: environment)
            controller.onSave = { [weak self] in self?.reload() }
            navigationController?.pushViewController(controller, animated: true)
        case .alerts:
            guard indexPath.section == 1 else { return }
            let controller = AlertRuleEditorViewController(
                rule: rules[indexPath.row],
                environment: environment,
                isNewRule: false
            )
            controller.onSave = { [weak self] _ in self?.reload() }
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        switch segment {
        case .devices:
            let device = devices[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                do {
                    try self?.environment.store.deleteKnownDevice(device)
                    self?.reload()
                    completion(true)
                } catch {
                    completion(false)
                    self?.presentError(error.localizedDescription)
                }
            }
            return UISwipeActionsConfiguration(actions: [delete])

        case .alerts:
            guard indexPath.section == 1 else { return nil }
            let rule = rules[indexPath.row]
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                do {
                    try self?.environment.store.deleteAlertRule(rule)
                    self?.reload()
                    completion(true)
                } catch {
                    completion(false)
                    self?.presentError(error.localizedDescription)
                }
            }
            return UISwipeActionsConfiguration(actions: [delete])
        }
    }

    @objc private func segmentChanged() {
        reload()
    }

    @objc private func addAlertTapped() {
        let rule = AlertRule(
            id: UUID(),
            name: "",
            matchType: .localNameContains,
            matchValue: "",
            isEnabled: true,
            notifyOncePerSession: true,
            cooldownSeconds: 300
        )
        let controller = AlertRuleEditorViewController(rule: rule, environment: environment, isNewRule: true)
        controller.onSave = { [weak self] _ in self?.reload() }
        navigationController?.pushViewController(controller, animated: true)
    }
}
