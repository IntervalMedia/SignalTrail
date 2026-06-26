import UIKit

final class AlertRulesViewController: UITableViewController {
    private let environment: AppEnvironment
    private var rules: [AlertRule] = []
    private let emptyState = EmptyStateView(
        symbol: "bell",
        title: "No alerts",
        message: "Create a rule to be notified when an advertisement matches a company, identifier, name, manufacturer prefix, or service UUID."
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        rules = environment.store.loadAlertRules()
        tableView.backgroundView = rules.isEmpty ? emptyState : nil
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rules.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rule = rules[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = rule.name
        content.secondaryText = "\(rule.matchType.title): \(rule.matchValue)"
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: rule.isEnabled ? "bell.fill" : "bell.slash")
        content.imageProperties.tintColor = rule.isEnabled ? .systemOrange : .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
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
            name: "Police Device detected",
            matchType: .companyIdentifier,
            matchValue: "004C",
            isEnabled: true,
            notifyOncePerSession: true,
            cooldownSeconds: 300
        )
        navigationController?.pushViewController(AlertRuleEditorViewController(rule: rule, environment: environment), animated: true)
    }
}
