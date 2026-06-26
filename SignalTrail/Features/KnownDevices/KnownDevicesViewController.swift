import UIKit

final class KnownDevicesViewController: UITableViewController {
    private let environment: AppEnvironment
    private var devices: [KnownDevice] = []
    private let emptyState = EmptyStateView(
        symbol: "star",
        title: "No known devices",
        message: "Save a device from the Scan tab to give it a nickname and create matching alerts."
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Known Devices"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Alerts",
            style: .plain,
            target: self,
            action: #selector(alertsTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        devices = environment.store.loadKnownDevices().sorted { $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending }
        tableView.backgroundView = devices.isEmpty ? emptyState : nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { devices.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let device = devices[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = device.nickname
        content.secondaryText = [
            device.lastKnownName,
            BluetoothCompanyLookup.name(for: device.companyIdentifier),
            device.peripheralIdentifier.uuidString
        ].compactMap { $0 }.joined(separator: " • ")
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "star.fill")
        content.imageProperties.tintColor = .systemYellow
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = KnownDeviceEditorViewController(device: devices[indexPath.row], environment: environment)
        controller.onSave = { [weak self] in self?.reload() }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
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
    }

    @objc private func alertsTapped() {
        navigationController?.pushViewController(AlertRulesViewController(environment: environment), animated: true)
    }
}
