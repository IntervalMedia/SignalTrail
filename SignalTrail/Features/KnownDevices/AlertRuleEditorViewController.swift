import UIKit

final class AlertRuleEditorViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case alert
        case criteria
        case behaviour

        var title: String {
            switch self {
            case .alert: return "Alert"
            case .criteria: return "Criteria"
            case .behaviour: return "Behaviour"
            }
        }
    }

    private var rule: AlertRule
    private let environment: AppEnvironment
    private let nameField = UITextField()
    private let enabledSwitch = UISwitch()
    private let onceSwitch = UISwitch()
    private let modeControl = UISegmentedControl(items: AlertRuleMatchMode.allCases.map(\.shortTitle))
    private var needsCriteriaReload = false

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
        tableView.keyboardDismissMode = .onDrag

        nameField.text = rule.name
        nameField.placeholder = "Alert name"
        nameField.autocorrectionType = .no
        nameField.clearButtonMode = .whileEditing

        enabledSwitch.isOn = rule.isEnabled
        onceSwitch.isOn = rule.notifyOncePerSession

        modeControl.selectedSegmentIndex = rule.matchMode == .any ? 0 : 1
        modeControl.addAction(UIAction { [weak self] _ in
            self?.rule.matchMode = self?.modeControl.selectedSegmentIndex == 0 ? .any : .all
        }, for: .valueChanged)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard needsCriteriaReload else { return }
        needsCriteriaReload = false
        tableView.reloadSections(IndexSet(integer: Section.criteria.rawValue), with: .none)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .alert:
            return 1
        case .criteria:
            return 2 + rule.criteria.count
        case .behaviour:
            return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .criteria:
            return """
            Use Match Any to trigger when any saved criterion matches. Use Match All to require every criterion to match the same device.

            Example: name contains "apple" plus member UUID name "Apple, Inc."
            """
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil

        guard let section = Section(rawValue: indexPath.section) else { return cell }
        var content = cell.defaultContentConfiguration()

        switch section {
        case .alert:
            nameField.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
            content.text = "Name"
            cell.accessoryView = nameField

        case .criteria:
            configureCriteriaCell(cell, content: &content, row: indexPath.row)

        case .behaviour:
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
        guard Section(rawValue: indexPath.section) == .criteria else { return }

        if indexPath.row == 0 {
            return
        }

        let criteria = rule.criteria
        if indexPath.row == criteria.count + 1 {
            editCriterion(AlertRuleMatch(matchType: .localNameContains, matchValue: ""), at: nil)
        } else {
            editCriterion(criteria[indexPath.row - 1], at: indexPath.row - 1)
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard Section(rawValue: indexPath.section) == .criteria else { return false }
        let criteria = rule.criteria
        guard criteria.count > 1 else { return false }
        return indexPath.row > 0 && indexPath.row <= criteria.count
    }

    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, Section(rawValue: indexPath.section) == .criteria else { return }
        var criteria = rule.criteria
        criteria.remove(at: indexPath.row - 1)
        rule.replaceCriteria(with: criteria)
        tableView.reloadSections(IndexSet(integer: Section.criteria.rawValue), with: .automatic)
    }

    private func configureCriteriaCell(
        _ cell: UITableViewCell,
        content: inout UIListContentConfiguration,
        row: Int
    ) {
        let criteria = rule.criteria
        if row == 0 {
            content.text = "Trigger when"
            cell.accessoryView = modeControl
            return
        }

        if row == criteria.count + 1 {
            content.text = "Add criterion"
            content.secondaryText = "Add another device match condition"
            content.image = UIImage(systemName: "plus.circle.fill")
            content.imageProperties.tintColor = AppTheme.accent
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            return
        }

        let criterion = criteria[row - 1]
        let value = criterion.matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
        content.text = criterion.matchType.title
        content.secondaryText = value.isEmpty ? "No value" : value
        content.secondaryTextProperties.numberOfLines = 2
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
    }

    private func editCriterion(_ criterion: AlertRuleMatch, at index: Int?) {
        let controller = AlertCriterionEditorViewController(criterion: criterion)
        controller.onSave = { [weak self] updatedCriterion in
            guard let self else { return }
            var criteria = self.rule.criteria
            if let index {
                criteria[index] = updatedCriterion
            } else {
                criteria.append(updatedCriterion)
            }
            self.rule.replaceCriteria(with: criteria)
            self.needsCriteriaReload = true
        }
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let criteria = rule.criteria.map {
            AlertRuleMatch(
                matchType: $0.matchType,
                matchValue: $0.matchValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard !name.isEmpty else {
            presentError("Enter an alert name.")
            return
        }

        guard !criteria.isEmpty, criteria.allSatisfy({ !$0.matchValue.isEmpty }) else {
            presentError("Add at least one complete criterion before saving.")
            return
        }

        rule.name = name
        rule.matchMode = modeControl.selectedSegmentIndex == 0 ? .any : .all
        rule.replaceCriteria(with: criteria)
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

private final class AlertCriterionEditorViewController: UITableViewController {
    var onSave: ((AlertRuleMatch) -> Void)?

    private var criterion: AlertRuleMatch
    private let valueField = UITextField()

    init(criterion: AlertRuleMatch) {
        self.criterion = criterion
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Criterion"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        valueField.text = criterion.matchValue
        valueField.autocorrectionType = .no
        valueField.clearButtonMode = .whileEditing
        applyValueFieldConfiguration()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        criterion.matchType.usesCompanyPicker ? 3 : 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Match condition"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "\(criterion.matchType.guidance)\n\nExample: \(criterion.matchType.exampleValue)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil

        var content = cell.defaultContentConfiguration()

        if indexPath.row == 0 {
            content.text = "Match type"
            content.secondaryText = criterion.matchType.title
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        } else if indexPath.row == 1 {
            valueField.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
            content.text = "Value"
            cell.accessoryView = valueField
        } else {
            content.text = "Choose common company"
            content.secondaryText = "Fill from bundled Bluetooth SIG data"
            content.image = UIImage(systemName: "building.2")
            content.imageProperties.tintColor = AppTheme.accent
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }

        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            let picker = AlertMatchTypePickerViewController(selectedType: criterion.matchType)
            picker.onSelect = { [weak self] type in
                guard let self else { return }
                self.criterion.matchType = type
                self.applyValueFieldConfiguration()
                self.tableView.reloadData()
            }
            navigationController?.pushViewController(picker, animated: true)
        } else if indexPath.row == 2, criterion.matchType.usesCompanyPicker {
            let picker = BluetoothCompanyPickerViewController(style: .insetGrouped)
            picker.onSelect = { [weak self] identifier, name in
                guard let self else { return }
                self.valueField.text = self.criterion.matchType == .companyIdentifier
                    ? String(format: "%04X", identifier)
                    : name
            }
            navigationController?.pushViewController(picker, animated: true)
        }
    }

    private func applyValueFieldConfiguration() {
        valueField.placeholder = criterion.matchType.exampleValue

        switch criterion.matchType {
        case .companyIdentifier, .manufacturerPrefix, .serviceUUID:
            valueField.autocapitalizationType = .allCharacters
        default:
            valueField.autocapitalizationType = .none
        }
    }

    @objc private func saveTapped() {
        let value = valueField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else {
            presentError("Enter a match value.")
            return
        }

        criterion.matchValue = value
        onSave?(criterion)
        navigationController?.popViewController(animated: true)
    }
}

private final class AlertMatchTypePickerViewController: UITableViewController {
    var onSelect: ((AlertMatchType) -> Void)?

    private var selectedType: AlertMatchType

    init(selectedType: AlertMatchType) {
        self.selectedType = selectedType
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Match Type"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        AlertMatchType.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let type = AlertMatchType.allCases[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = type.title
        content.secondaryText = type.exampleValue
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2

        cell.contentConfiguration = content
        cell.accessoryType = type == selectedType ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let type = AlertMatchType.allCases[indexPath.row]
        selectedType = type
        onSelect?(type)
        navigationController?.popViewController(animated: true)
    }
}
