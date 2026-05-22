// SceneDelegate.swift
// Purr Machine

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
        _ = AppState.shared  // prime AppState before any API call lands
        // LocalAPIServer is started by ViewController so the connection-info
        // alert can be presented from a view that's actually on-screen.
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}

    /// iOS won't let CHHapticEngine play under the lock screen — that's
    /// system policy. Audio continues thanks to UIBackgroundModes=audio,
    /// but the haptic engine is stopped on suspend. The instant we come
    /// back to the foreground, restart it so the felt purr is there when
    /// the user looks at the phone.
    func sceneWillEnterForeground(_ scene: UIScene) {
        Task { @MainActor in
            AppState.shared.resumeHapticsForForegroundIfNeeded()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {}
}
