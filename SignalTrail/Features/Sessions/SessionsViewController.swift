import UIKit

final class SessionsViewController: UITableViewController {
    private let environment: AppEnvironment
    private var sessions: [ScanSession] = []
    private let emptyState = EmptyStateView(
        symbol: "map",
        title: "No recorded sessions",
        message: "Use Record mode on the Scan tab to save timestamped BLE observations and phone locations."
    )

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sessions"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        do {
            sessions = try environment.store.loadSessions()
            tableView.backgroundView = sessions.isEmpty ? emptyState : nil
            tableView.reloadData()
        } catch {
            presentError("Unable to load sessions: \(error.localizedDescription)")
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sessions.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let session = sessions[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = session.name
        content.secondaryText = "\(session.duration.clockString) • \(session.uniqueDeviceCount) devices • \(session.detectionCount) observations"
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "map.fill")
        content.imageProperties.tintColor = AppTheme.accent
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(
            SessionDetailViewController(session: sessions[indexPath.row], environment: environment),
            animated: true
        )
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let session = sessions[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            do {
                try self?.environment.store.deleteSession(session)
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
