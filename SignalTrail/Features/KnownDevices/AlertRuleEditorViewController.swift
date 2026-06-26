import UIKit

final class AlertRuleEditorViewController: UITableViewController {
  private var rule: AlertRule
  private let environment: AppEnvironment
  private let nameField = UITextField()
  private let valueField = UITextField()
  private let enabledSwitch = UISwitch()
  private let onceSwitch = UISwitch()

  init(rule: AlertRule, environment: AppEnvironment) {
    self.rule = rule
    self.environment = environment
    super.init(style: .insetGrouped)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Alert Rule"
    navigationItem.largeTitleDisplayMode = .never
    tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

    nameField.text = rule.name
    nameField.placeholder = "Alert name"
    valueField.text = rule.matchValue
    valueField.placeholder = "Match value"
    valueField.autocorrectionType = .no
    valueField.autocapitalizationType = .allCharacters
    enabledSwitch.isOn = rule.isEnabled
    onceSwitch.isOn = rule.notifyOncePerSession

    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .save, target: self, action: #selector(saveTapped))
  }

  override func numberOfSections(in tableView: UITableView) -> Int { 3 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    if section == 1 { return usesCompanyPicker ? 3 : 2 }
    return section == 0 ? 1 : 2
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  {
    ["Alert", "Match", "Behaviour"][section]
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
  {
    if section == 1 {
      let description: String
      switch rule.matchType {
      case .peripheralIdentifier:
        description = "Use the app-scoped UUID shown by iOS. Hardware BLE MAC addresses are unavailable."
      case .companyIdentifier:
        description =
          "Enter a Bluetooth SIG company identifier in hexadecimal, for example 004C for Apple. Manufacturer data must be advertised."
      case .companyName:
        description =
          "Exact case-insensitive match against the Bluetooth SIG company name derived from manufacturer data."
      case .localNameContains:
        description = "Case-insensitive partial match against the advertised or peripheral name."
      case .manufacturerPrefix:
        description =
          "Hexadecimal prefix match against manufacturer data, including the company identifier bytes."
      case .memberServiceName:
        description =
          "Exact case-insensitive match against derived Bluetooth SIG 16-bit member UUID names in the advertisement."
      case .serviceUUID:
        description = "Exact case-insensitive advertised service UUID match."
      }

      guard !rule.additionalMatches.isEmpty else { return description }
      let noun = rule.additionalMatches.count == 1 ? "condition" : "conditions"
      return "\(description)\n\nThis alert also includes \(rule.additionalMatches.count) additional match \(noun)."
    }
    return nil
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
    cell.selectionStyle = .none
    cell.accessoryView = nil
    cell.accessoryType = .none
    var content = cell.defaultContentConfiguration()

    if indexPath.section == 0 {
      nameField.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
      content.text = "Name"
      cell.accessoryView = nameField
    } else if indexPath.section == 1 {
      if indexPath.row == 0 {
        content.text = "Match type"
        content.secondaryText = rule.matchType.title
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      } else if indexPath.row == 1 {
        valueField.frame = CGRect(x: 0, y: 0, width: 230, height: 34)
        content.text = "Value"
        cell.accessoryView = valueField
      } else {
        content.text = "Choose common company"
        content.image = UIImage(systemName: "building.2")
        content.imageProperties.tintColor = AppTheme.accent
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
      }
    } else {
      if indexPath.row == 0 {
        content.text = "Enabled"
        cell.accessoryView = enabledSwitch
      } else {
        content.text = "Once per session"
        cell.accessoryView = onceSwitch
      }
    }
    cell.contentConfiguration = content
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard indexPath.section == 1 else { return }
    if indexPath.row == 0 {
      presentMatchTypePicker(from: indexPath)
    } else if indexPath.row == 2, usesCompanyPicker {
      presentCompanyPicker()
    }
  }

  private func presentMatchTypePicker(from indexPath: IndexPath) {
    let alert = UIAlertController(title: "Match type", message: nil, preferredStyle: .actionSheet)
    AlertMatchType.allCases.forEach { type in
      alert.addAction(
        UIAlertAction(title: type.title, style: .default) { [weak self] _ in
          self?.rule.matchType = type
          self?.tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
        })
    }
    anchor(alert, to: indexPath)
    present(alert, animated: true)
  }

  private func presentCompanyPicker() {
    let picker = BluetoothCompanyPickerViewController(style: .insetGrouped)
    picker.onSelect = { [weak self] identifier, _ in
      guard let self else { return }
      if self.rule.matchType == .companyIdentifier {
        self.valueField.text = String(format: "%04X", identifier)
      } else {
        self.valueField.text = BluetoothCompanyLookup.name(for: identifier)
      }
    }
    navigationController?.pushViewController(picker, animated: true)
  }

  private var usesCompanyPicker: Bool {
    rule.matchType == .companyIdentifier || rule.matchType == .companyName
  }

  private func anchor(_ alert: UIAlertController, to indexPath: IndexPath) {
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = tableView.cellForRow(at: indexPath)
      popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
    }
  }

  @objc private func saveTapped() {
    let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let value = valueField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !name.isEmpty, !value.isEmpty else {
      presentError("Enter both a rule name and match value.")
      return
    }
    rule.name = name
    rule.matchValue = value
    rule.isEnabled = enabledSwitch.isOn
    rule.notifyOncePerSession = onceSwitch.isOn
    do {
      try environment.store.upsertAlertRule(rule)
      if environment.settingsStore.settings.requestNotificationPermissionOnRuleCreation {
        environment.notificationService.requestAuthorization()
      }
      navigationController?.popViewController(animated: true)
    } catch {
      presentError(error.localizedDescription)
    }
  }
}
