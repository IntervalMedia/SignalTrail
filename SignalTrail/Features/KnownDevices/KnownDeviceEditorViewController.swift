import UIKit

final class KnownDeviceEditorViewController: UITableViewController {
    var onSave: (() -> Void)?

    private var device: KnownDevice
    private let environment: AppEnvironment
    private let nicknameField = UITextField()
    private let notesField = UITextField()

    init(device: KnownDevice, environment: AppEnvironment) {
        self.device = device
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Known Device"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        nicknameField.text = device.nickname
        nicknameField.placeholder = "Nickname"
        nicknameField.clearButtonMode = .whileEditing
        notesField.text = device.notes
        notesField.placeholder = "Optional notes"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
        if navigationController?.presentingViewController != nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        [2, 4, 1][section]
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Details", "Matching data", "Alerts"][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 1 ? "The identifier is assigned by iOS for this app. It is not a hardware MAC address." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none
        var content = cell.defaultContentConfiguration()

        if indexPath.section == 0 {
            let field = indexPath.row == 0 ? nicknameField : notesField
            field.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
            cell.accessoryView = field
            content.text = indexPath.row == 0 ? "Nickname" : "Notes"
        } else if indexPath.section == 1 {
            let rows: [(String, String)] = [
                ("Observed name", device.lastKnownName),
                ("Identifier", device.peripheralIdentifier.uuidString),
                ("Company", BluetoothCompanyLookup.displayName(for: device.companyIdentifier)),
                ("Manufacturer prefix", device.manufacturerPrefixHex ?? "Not available")
            ]
            content.text = rows[indexPath.row].0
            content.secondaryText = rows[indexPath.row].1
            content.secondaryTextProperties.numberOfLines = 2
        } else {
            content.text = "Create alert for this device"
            content.image = UIImage(systemName: "bell.badge")
            content.imageProperties.tintColor = AppTheme.accent
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2 else { return }
        let rule = AlertRule(
            id: UUID(),
            name: "\(device.nickname) detected",
            matchType: .peripheralIdentifier,
            matchValue: device.peripheralIdentifier.uuidString,
            isEnabled: true,
            notifyOncePerSession: true,
            cooldownSeconds: 300
        )
        navigationController?.pushViewController(AlertRuleEditorViewController(rule: rule, environment: environment), animated: true)
    }

    @objc private func saveTapped() {
        let nickname = nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !nickname.isEmpty else {
            presentError("Enter a nickname for the device.")
            return
        }
        device.nickname = nickname
        device.notes = notesField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try environment.store.upsertKnownDevice(device)
            onSave?()
            if navigationController?.presentingViewController != nil { dismiss(animated: true) }
            else { navigationController?.popViewController(animated: true) }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func cancelTapped() { dismiss(animated: true) }
}
