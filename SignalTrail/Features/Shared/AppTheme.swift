import UIKit

struct AppTheme {
    static let canvas = UIColor(red: 0.035, green: 0.043, blue: 0.051, alpha: 1)
    static let surface = UIColor(red: 0.065, green: 0.076, blue: 0.088, alpha: 1)
    static let raisedSurface = UIColor(red: 0.085, green: 0.098, blue: 0.112, alpha: 1)
    static let separator = UIColor.white.withAlphaComponent(0.11)
    static let secondaryText = UIColor(red: 0.64, green: 0.68, blue: 0.73, alpha: 1)

    static let accent = UIColor.systemBlue
    static let risk = UIColor.systemRed
    static let watch = UIColor.systemOrange
    static let known = UIColor.systemGreen

    static let brandBackground = canvas
    static let cardBackground = surface
    static let groupedBackground = canvas

    static func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = canvas
        appearance.shadowColor = separator
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = accent
    }
}

final class GhostBustaBustBarButtonItem: UIBarButtonItem {
    private weak var coordinator: ScanCoordinator?

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
        super.init()
        title = "BUST"
        style = .plain
        target = self
        action = #selector(tapped)
        accessibilityHint = "Starts or stops the current Bluetooth scan"
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scanStateChanged),
            name: .ghostBustaScanStateDidChange,
            object: coordinator
        )
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func tapped() {
        guard let coordinator else { return }
        if coordinator.state.isRunning {
            coordinator.stop(reason: .user)
        } else {
            coordinator.startActive()
        }
        refresh()
    }

    @objc private func scanStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let coordinator else { return }
        let running = coordinator.state.isRunning
        tintColor = running ? AppTheme.risk : AppTheme.accent
        accessibilityLabel = running ? "Stop BUST scan" : "BUST nearby devices"
        accessibilityValue = running ? "Scanning" : "Ready"
    }
}

extension UIView {
    func pinEdges(to view: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

extension UIButton {
    func configureAsInfoButton(accessibilityLabel: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "info.circle")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        self.configuration = configuration
        self.accessibilityLabel = accessibilityLabel
        accessibilityHint = "Shows more information"
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }
}

extension UIViewController {
    func installBustAction(environment: AppEnvironment, additionalItems: [UIBarButtonItem] = []) {
        navigationItem.rightBarButtonItems = [
            GhostBustaBustBarButtonItem(coordinator: environment.scanCoordinator)
        ] + additionalItems
    }

    func presentError(_ message: String) {
        let alert = UIAlertController(title: "GhostBusta", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func presentInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default))
        present(alert, animated: true)
    }

    func makeInfoButton(
        accessibilityLabel: String,
        handler: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { _ in handler() }
        )
        button.configureAsInfoButton(accessibilityLabel: accessibilityLabel)
        return button
    }

    func makeInfoSectionHeader(
        title: String,
        accessibilityLabel: String,
        handler: @escaping () -> Void
    ) -> UIView {
        let label = UILabel()
        label.text = title.uppercased()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true

        let button = makeInfoButton(accessibilityLabel: accessibilityLabel, handler: handler)
        let stack = UIStackView(arrangedSubviews: [label, UIView(), button])
        stack.axis = .horizontal
        stack.alignment = .center

        let container = UIView()
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
}
