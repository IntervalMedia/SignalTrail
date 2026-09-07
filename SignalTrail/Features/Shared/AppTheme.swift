import UIKit

struct AppTheme {
    static let accent = UIColor(named: "AccentColor") ?? UIColor.systemTeal
    static let brandBackground = UIColor(named: "BrandBackground") ?? UIColor.systemIndigo
    static let cardBackground = UIColor.secondarySystemGroupedBackground
    static let groupedBackground = UIColor.systemGroupedBackground

    static func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
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
    func presentError(_ message: String) {
        let alert = UIAlertController(title: "SignalTrail", message: message, preferredStyle: .alert)
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
