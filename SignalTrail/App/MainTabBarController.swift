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
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppTheme.surface
        appearance.shadowColor = AppTheme.separator
        appearance.stackedLayoutAppearance.normal.iconColor = AppTheme.secondaryText
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: AppTheme.secondaryText
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = AppTheme.accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: AppTheme.accent
        ]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.itemPositioning = .fill
    }

    private func configureTabs() {
        let ghosts = ScanViewController(environment: environment)
        ghosts.tabBarItem = UITabBarItem(
            title: "GHOSTS",
            image: UIImage(systemName: "wave.3.right"),
            selectedImage: UIImage(systemName: "wave.3.right.circle.fill")
        )

        let known = KnownDevicesViewController(environment: environment)
        known.tabBarItem = UITabBarItem(
            title: "KNOWN",
            image: UIImage(systemName: "checkmark.seal"),
            selectedImage: UIImage(systemName: "checkmark.seal.fill")
        )

        let haunts = HunterViewController(environment: environment)
        haunts.tabBarItem = UITabBarItem(
            title: "HAUNTS",
            image: UIImage(systemName: "scope"),
            selectedImage: UIImage(systemName: "scope")
        )

        let trail = SessionsViewController(environment: environment)
        trail.tabBarItem = UITabBarItem(
            title: "TRAIL",
            image: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath"),
            selectedImage: UIImage(systemName: "point.topleft.down.to.point.bottomright.curvepath")
        )

        let intel = IntelViewController(environment: environment)
        intel.tabBarItem = UITabBarItem(
            title: "INTEL",
            image: UIImage(systemName: "doc.text.magnifyingglass"),
            selectedImage: UIImage(systemName: "doc.text.magnifyingglass")
        )

        viewControllers = [ghosts, known, haunts, trail, intel].map {
            let navigationController = UINavigationController(rootViewController: $0)
            navigationController.navigationBar.prefersLargeTitles = false
            return navigationController
        }
    }
}
