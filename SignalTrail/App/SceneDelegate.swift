import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var environment: AppEnvironment?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let environment = AppEnvironment()
        self.environment = environment

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MainTabBarController(environment: environment)
        window.tintColor = AppTheme.accent
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        environment?.scanCoordinator.stop(reason: .enteredBackground)
    }
}
