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

extension UIViewController {
    func presentError(_ message: String) {
        let alert = UIAlertController(title: "SignalTrail", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
