import UIKit

final class AlertRulesViewController: UITableViewController {
    private static let cellReuseIdentifier = "AlertRuleCell"

    private let environment: AppEnvironment
    private var rules: [AlertRule] = []
    private var needsReload = false
    private let emptyState = EmptyStateView(
        symbol: "bell",
        title: "No alerts",
        message: "Create a rule with one or more criteria to match identifiers, names, manufacturer prefixes, company names, or service UUIDs."
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detection Alerts"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(AlertRuleCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        needsReload = true
        reloadIfNeeded()
    }

    private func reload() {
        rules = environment.store.loadAlertRules()
        tableView.backgroundView = rules.isEmpty ? emptyState : nil
        tableView.reloadData()
    }

    private func reloadIfNeeded() {
        guard needsReload, isViewLoaded, view.window != nil else { return }
        needsReload = false
        reload()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rules.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rule = rules[indexPath.row]
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.cellReuseIdentifier,
            for: indexPath
        ) as? AlertRuleCell else {
            return UITableViewCell()
        }

        cell.configure(with: rule)
        cell.onToggleChanged = { [weak self, weak cell] isEnabled in
            self?.setRuleEnabled(ruleID: rule.id, isEnabled: isEnabled, cell: cell)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(AlertRuleEditorViewController(rule: rules[indexPath.row], environment: environment), animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let rule = rules[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            do {
                try self?.environment.store.deleteAlertRule(rule)
                self?.reload()
                completion(true)
            } catch {
                completion(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func addTapped() {
        let rule = AlertRule(
            id: UUID(),
            name: "",
            matchType: .localNameContains,
            matchValue: "",
            isEnabled: true,
            notifyOncePerSession: true,
            cooldownSeconds: 300
        )
        navigationController?.pushViewController(AlertRuleEditorViewController(rule: rule, environment: environment), animated: true)
    }

    private func setRuleEnabled(ruleID: UUID, isEnabled: Bool, cell: AlertRuleCell?) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }

        let originalRule = rules[index]
        rules[index].isEnabled = isEnabled

        do {
            try environment.store.upsertAlertRule(rules[index])
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        } catch {
            rules[index] = originalRule
            cell?.setToggle(isOn: originalRule.isEnabled)
            presentError(error.localizedDescription)
        }
    }
}

private final class AlertRuleCell: UITableViewCell {
    var onToggleChanged: ((Bool) -> Void)?

    private let enabledSwitch = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryView = enabledSwitch
        enabledSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onToggleChanged?(self.enabledSwitch.isOn)
        }, for: .valueChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggleChanged = nil
    }

    func configure(with rule: AlertRule) {
        var content = defaultContentConfiguration()
        content.text = rule.name
        content.secondaryText = rule.matchSummary
        content.secondaryTextProperties.numberOfLines = 3
        content.image = UIImage(systemName: rule.isEnabled ? "bell.fill" : "bell.slash")
        content.imageProperties.tintColor = rule.isEnabled ? .systemOrange : .secondaryLabel
        contentConfiguration = content
        setToggle(isOn: rule.isEnabled)
    }

    func setToggle(isOn: Bool) {
        enabledSwitch.setOn(isOn, animated: false)
    }
}
