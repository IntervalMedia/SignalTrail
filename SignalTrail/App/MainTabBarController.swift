import UIKit

final class MainTabBarController: UITabBarController {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureAppearance()
        configureTabs()
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
    }

    private func configureTabs() {
        let scan = ScanViewController(environment: environment)
        scan.tabBarItem = UITabBarItem(title: "Scan", image: UIImage(systemName: "dot.radiowaves.left.and.right"), tag: 0)

        let sessions = SessionsViewController(environment: environment)
        sessions.tabBarItem = UITabBarItem(title: "Sessions", image: UIImage(systemName: "map"), tag: 2)

        let hunter = HunterViewController(environment: environment)
        hunter.tabBarItem = UITabBarItem(title: "Hunter", image: UIImage(systemName: "scope"), tag: 1)

        let known = KnownDevicesViewController(environment: environment)
        known.tabBarItem = UITabBarItem(title: "Library", image: UIImage(systemName: "star"), tag: 3)

        let settings = SettingsViewController(environment: environment)
        settings.tabBarItem = UITabBarItem(title: "Settings", image: UIImage(systemName: "gearshape"), tag: 4)

        viewControllers = [scan, hunter, sessions, known, settings].map {
            let navigationController = UINavigationController(rootViewController: $0)
            navigationController.navigationBar.prefersLargeTitles = true
            return navigationController
        }
    }
}
