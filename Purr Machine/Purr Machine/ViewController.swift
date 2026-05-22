// ViewController.swift
// Purr Machine
//
// Thin view layer over AppState. All audio, haptic, and timer logic lives in
// AppState; this file owns the UI (kitten buttons, timer button, layout) and
// dispatches taps into AppState. State changes flow back via the
// AppState.didChange notification, which drives button styling and the
// timer label.
//
// Behavior is byte-for-byte equivalent to the v0 single-file ViewController.
// The extraction is structural only.

import UIKit

// ========== BLOCK 1: ViewController - properties - START ==========
class ViewController: UIViewController {

    private let state = AppState.shared

    private var stackView: UIStackView!
    private var mainStackView: UIStackView!
    private var timerButton: UIButton!
    private var kittenButtons: [UIButton] = []

    #if DEBUG
    private var apiToggleButton: UIButton!
    private var didAutoStartAPI = false
    #endif

    /// Maps a button tag to the corresponding Kitten case. Tags 1/2/3 == raw values.
    private func kitten(for tag: Int) -> Kitten? { Kitten(rawValue: tag) }
}
// ========== BLOCK 1: ViewController - properties - END ==========

// ========== BLOCK 2: ViewController - view lifecycle - START ==========
extension ViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(stateDidChange),
            name: AppState.didChange, object: nil
        )
        refreshFromState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        if !didAutoStartAPI {
            didAutoStartAPI = true
            startAPIAndShowInfo(showAlert: true)
        }
        #endif
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.stackView.axis = (size.width > size.height) ? .horizontal : .vertical
        })
    }
}
// ========== BLOCK 2: ViewController - view lifecycle - END ==========

// ========== BLOCK 3: ViewController - UI construction - START ==========
extension ViewController {

    private func buildUI() {
        let titles: [(Kitten, String)] = [
            (.floozy, "Floozy"),
            (.nacho,  "Nacho"),
            (.noNo,   "No-No!"),
        ]
        kittenButtons = titles.map { kitten, title in
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.backgroundColor = .black
            b.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .regular)
            b.layer.cornerRadius = 10
            b.tag = kitten.rawValue
            b.addTarget(self, action: #selector(kittenButtonTapped(_:)), for: .touchUpInside)
            return b
        }

        stackView = UIStackView(arrangedSubviews: kittenButtons)
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 15

        timerButton = UIButton(type: .system)
        timerButton.setTitle("∞", for: .normal)
        timerButton.setTitleColor(.white, for: .normal)
        timerButton.backgroundColor = .black
        timerButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .regular)
        timerButton.layer.cornerRadius = 10
        timerButton.addTarget(self, action: #selector(timerButtonTapped), for: .touchUpInside)

        mainStackView = UIStackView(arrangedSubviews: [stackView, timerButton])
        mainStackView.axis = .vertical
        mainStackView.spacing = 40
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStackView)

        NSLayoutConstraint.activate([
            mainStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mainStackView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])

        #if DEBUG
        buildAPIToggleButton()
        #endif
    }
}
// ========== BLOCK 3: ViewController - UI construction - END ==========

// ========== BLOCK 6: ViewController - DEBUG API toggle - START ==========
#if DEBUG
extension ViewController {

    private func buildAPIToggleButton() {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        b.setImage(UIImage(systemName: "antenna.radiowaves.left.and.right", withConfiguration: cfg), for: .normal)
        b.tintColor = .white.withAlphaComponent(0.25)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(apiToggleTapped), for: .touchUpInside)
        b.accessibilityLabel = "API toggle"
        view.addSubview(b)
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            b.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            b.widthAnchor.constraint(equalToConstant: 44),
            b.heightAnchor.constraint(equalToConstant: 44),
        ])
        apiToggleButton = b
        refreshAPIToggleAppearance()
    }

    @objc private func apiToggleTapped() {
        let server = LocalAPIServer.shared
        if server.isRunning {
            server.stop()
        } else {
            startAPIAndShowInfo(showAlert: true)
        }
        refreshAPIToggleAppearance()
    }

    fileprivate func startAPIAndShowInfo(showAlert: Bool) {
        let server = LocalAPIServer.shared
        if !server.isRunning { server.start() }
        let info = server.connectionInfo
        print("PurrAPI(VC): \(info)")
        UIPasteboard.general.string = info
        refreshAPIToggleAppearance()
        guard showAlert else { return }
        let alert = UIAlertController(
            title: "API ready",
            message: "Address (also copied to clipboard):\n\n\(info)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Copy again", style: .default) { _ in
            UIPasteboard.general.string = info
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func refreshAPIToggleAppearance() {
        guard let b = apiToggleButton else { return }
        b.tintColor = LocalAPIServer.shared.isRunning
            ? .white
            : .white.withAlphaComponent(0.25)
    }
}
#endif
// ========== BLOCK 6: ViewController - DEBUG API toggle - END ==========

// ========== BLOCK 4: ViewController - actions - START ==========
extension ViewController {

    @objc private func kittenButtonTapped(_ sender: UIButton) {
        guard let k = kitten(for: sender.tag) else { return }
        Task { @MainActor in state.toggle(k) }
    }

    @objc private func timerButtonTapped() {
        Task { @MainActor in state.cycleTimer() }
    }
}
// ========== BLOCK 4: ViewController - actions - END ==========

// ========== BLOCK 5: ViewController - state -> UI - START ==========
extension ViewController {

    @objc private func stateDidChange() {
        Task { @MainActor in refreshFromState() }
    }

    private func refreshFromState() {
        for b in kittenButtons {
            let isActive = (state.currentlyPlaying?.rawValue == b.tag)
            b.titleLabel?.font = isActive
                ? UIFont.systemFont(ofSize: 26, weight: .bold)
                : UIFont.systemFont(ofSize: 24, weight: .regular)
        }

        let seconds = state.timerOptions[state.timerIndex]
        let title: String
        if seconds == -1 {
            title = "∞"
        } else if state.remainingTime > 0 && state.currentlyPlaying != nil {
            let m = state.remainingTime / 60
            let s = state.remainingTime % 60
            title = String(format: "%d:%02d", m, s)
        } else {
            title = "\(seconds / 60) min"
        }
        if timerButton.title(for: .normal) != title {
            timerButton.setTitle(title, for: .normal)
        }
    }
}
// ========== BLOCK 5: ViewController - state -> UI - END ==========
