// SceneDelegate.swift
// Purr Machine

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    /// Process-wide LocalAPIServer. One instance per app launch.
    private static let api: LocalAPIServer = {
        let s = LocalAPIServer()
        s.start()
        return s
    }()

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
        _ = SceneDelegate.api  // touch the lazy var so the server starts on first scene
        _ = AppState.shared    // prime AppState before any API call lands
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
