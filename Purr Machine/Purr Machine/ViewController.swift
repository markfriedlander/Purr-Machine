// ViewController.swift
// Purr Machine
//
// This ViewController handles the entire user interface and logic for the Purr Machine app,
// which plays looping audio of cat purrs, delivers synchronized haptic feedback,
// manages sleep timers, and allows selection between multiple recorded kittens.

import UIKit
import AVFoundation
import CoreHaptics

class ViewController: UIViewController {

    // MARK: - Properties

    // Currently selected kitten's audio filename (default to "Purr1")
    var selectedKitten: String = "Purr1"  // Default to Floozy

    // Timer for managing sleep countdown
    var sleepTimer: Timer?

    // Timer to sync haptic feedback with audio playback
    var hapticSyncTimer: Timer?

    // Audio player for purring sound playback
    var audioPlayer: AVAudioPlayer?

    // Core Haptics engine instance for generating haptic feedback
    var hapticsEngine: CHHapticEngine?

    // Flag indicating whether haptics are currently active
    var hapticsActive = false

    // Current intensity value for haptic feedback (0.0 to 1.0)
    var currentHapticIntensity: Float = 0.0

    // Advanced haptic pattern player to enable dynamic haptic patterns
    var hapticPlayer: CHHapticAdvancedPatternPlayer?

    // Tag of the currently playing kitten button (nil if none playing)
    var currentlyPlayingKittenTag: Int?

    // Stack view containing the kitten selection buttons
    var stackView: UIStackView!
    
    // Main vertical stack view that holds kitten buttons and timer button
    var mainStackView: UIStackView!

    // Button used to toggle and display sleep timer duration
    var timerButton: UIButton!

    // Index to track current selected timer duration in timerOptions array
    var timerIndex = 3 // Updated index for ∞ now that 0 was removed

    // Available timer durations in seconds; -1 represents infinite (no timer)
    let timerOptions: [Int] = [600, 1200, 1800, -1] // Removed 0 = no timer

    // Timer counting down the remaining time for sleep timer
    var countdownTimer: Timer?

    // Remaining time in seconds for the sleep timer
    var remainingTime: Int = 0

    // Flag indicating whether the timer is currently paused
    var isTimerPaused = false

    // MARK: - User Interaction

    /// Handles taps on kitten selection buttons.
    /// Starts or stops the purring sound and manages timer and button UI accordingly.
    /// - Parameter sender: The UIButton that was tapped.
    @objc func kittenButtonTapped(_ sender: UIButton) {
        // Map button tags to kitten audio filenames
        let kittenMap = [1: "Purr1", 2: "Purr2", 3: "Purr3"]
        guard let selected = kittenMap[sender.tag] else { return }

        // If the tapped kitten is already playing, stop playback
        if currentlyPlayingKittenTag == sender.tag {
            stopPurringSound()
            currentlyPlayingKittenTag = nil
        } else {
            // Determine if switching between different kittens
            let switchingKitten = currentlyPlayingKittenTag != nil && currentlyPlayingKittenTag != sender.tag
            stopPurringSound()

            // Reset all kitten buttons to default font appearance
            for button in stackView.arrangedSubviews.compactMap({ $0 as? UIButton }) {
                button.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .regular)
            }

            if switchingKitten {
                // If switching kittens, reset and start timer as needed
                countdownTimer?.invalidate()
                countdownTimer = nil
                isTimerPaused = false
                let selectedSeconds = timerOptions[timerIndex]
                remainingTime = selectedSeconds
                updateTimerButtonTitle()
                if selectedSeconds > 0 {
                    startSleepTimer()
                } else {
                    // If timer is infinite, show infinity symbol
                    timerButton.setTitle("∞", for: .normal)
                }
            }

            // Update selected kitten and start playback
            selectedKitten = selected
            playPurringSound()

            // Start timer if a positive duration is selected
            if timerOptions[timerIndex] > 0 {
                startSleepTimer()
            }

            currentlyPlayingKittenTag = sender.tag

            // Highlight selected button with bold font and larger size
            sender.titleLabel?.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        }
    }

    // MARK: - Sleep Timer Management

    /// Starts the sleep timer countdown based on the currently selected timer duration.
    /// Handles timer invalidation and UI updates.
    func startSleepTimer() {
        isTimerPaused = false
        countdownTimer?.invalidate()
        sleepTimer?.invalidate()

        let selectedSeconds = timerOptions[timerIndex]
        if selectedSeconds <= 0 { return } // No timer or infinite timer selected

        remainingTime = selectedSeconds
        updateTimerButtonTitle()

        // Schedule a timer that fires every second to update countdown
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.remainingTime -= 1
            self.updateTimerButtonTitle()

            // When time runs out, invalidate timer and stop playback
            if self.remainingTime <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.stopPurringSound()
                self.timerButton.setTitle("Timer", for: .normal)
            }
        }
    }

    /// Resumes the sleep timer if it was previously paused and time remains.
    func resumeSleepTimer() {
        if remainingTime <= 0 { return }
        isTimerPaused = false
        updateTimerButtonTitle()

        // Restart countdown timer with remaining time
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.remainingTime -= 1
            self.updateTimerButtonTitle()

            if self.remainingTime <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.stopPurringSound()
                self.timerButton.setTitle("Timer", for: .normal)
            }
        }
    }

    /// Updates the timer button's title to show remaining time in minutes and seconds.
    func updateTimerButtonTitle() {
        let minutes = remainingTime / 60
        let seconds = remainingTime % 60
        let newTitle = String(format: "%d:%02d", minutes, seconds)
        // Only update UI if title changed to reduce unnecessary UI updates
        if timerButton.title(for: .normal) != newTitle {
            timerButton.setTitle(newTitle, for: .normal)
        }
    }

    // MARK: - Haptics Setup and Playback

    /// Configures the haptic engine if the device supports haptics.
    /// Logs support status and handles errors during engine startup.
    func setupHaptics() {
        let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        print("Supports haptics: \(supportsHaptics)")
        guard supportsHaptics else { return }

        do {
            hapticsEngine = try CHHapticEngine()
            try hapticsEngine?.start()
        } catch {
            print("Haptic engine failed to start: \(error)")
        }
    }

    /// Starts the haptic purring feedback pattern.
    /// Handles engine restarts and fallback attempts on failure.
    func startHapticPurring() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("Haptics not supported on this device")
            return
        }

        // Initialize engine if needed
        if hapticsEngine == nil {
            do {
                hapticsEngine = try CHHapticEngine()
                try hapticsEngine?.start()
            } catch {
                print("Failed to create or start haptic engine: \(error)")
                return
            }
        }

        guard let engine = hapticsEngine else {
            print("Haptic engine still unavailable")
            return
        }

        print("Restarting haptics engine...")

        // Stop and restart engine to ensure clean state before playing pattern
        engine.stop { _ in
            do {
                try engine.start()
                print("Haptics engine restarted successfully.")
                self.playHapticPattern()
            } catch {
                print("Failed to restart haptics engine: \(error)")
                print("Attempting full engine reset...")

                // Attempt full engine reset on failure
                do {
                    self.hapticsEngine = try CHHapticEngine()
                    try self.hapticsEngine?.start()
                    print("Haptics engine fully reinitialized.")
                    self.playHapticPattern()
                } catch {
                    print("Final haptics failure: \(error)")
                }
            }
        }
    }

    /// Creates and plays the initial haptic pattern for purring feedback.
    private func playHapticPattern() {
        guard let engine = hapticsEngine else { return }

        do {
            print("Starting haptics")

            // Define two continuous haptic events with varying intensity and sharpness
            let events = [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0, duration: 0.4),

                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ], relativeTime: 0.4, duration: 0.3)
            ]

            // Create pattern and player, then start playback immediately
            let pattern = try CHHapticPattern(events: events, parameters: [])
            hapticPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)
            hapticsActive = true

        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }

    /// Stops any ongoing haptic feedback and marks haptics as inactive.
    func stopHapticPurring() {
        hapticsEngine?.stop(completionHandler: nil)
        hapticsActive = false
    }

    // MARK: - Audio Playback

    /// Starts playing the selected kitten's purring sound in a loop.
    /// Also sets up audio session and starts syncing haptics with audio.
    func playPurringSound() {
        guard let url = Bundle.main.url(forResource: selectedKitten, withExtension: "m4a") else {
            print("Audio file not found")
            return
        }

        do {
            // Configure audio session for playback and mixing with other audio
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.play()

            print("Attempting to play \(selectedKitten)")
            syncHapticsWithAudio()
            startHapticPurring()

        } catch {
            print("Error loading audio file: \(error)")
        }
    }

    /// Stops the purring sound, cancels timers, and stops haptic feedback.
    func stopPurringSound() {
        isTimerPaused = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        hapticSyncTimer?.invalidate()
        sleepTimer?.invalidate()
        audioPlayer?.stop()
        stopHapticPurring()
    }

    // MARK: - Haptic Synchronization with Audio

    /// Sets up a timer to periodically adjust haptic intensity based on audio playback progress.
    /// Creates a dynamic haptic experience that follows the audio's purring pattern.
    func syncHapticsWithAudio() {
        guard let audioPlayer = audioPlayer else { return }

        let totalDuration = audioPlayer.duration
        let interval = totalDuration / 2

        // Invalidate any existing sync timer before starting a new one
        hapticSyncTimer?.invalidate()

        // Timer fires every 0.25 seconds to update haptic intensity dynamically
        hapticSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let currentTime = audioPlayer.currentTime

            // Calculate intensity: ramp up during first half, then ramp down during second half
            if currentTime < interval {
                self.currentHapticIntensity = Float(currentTime / interval) * 0.6
            } else {
                self.currentHapticIntensity = 0.6 - Float((currentTime - interval) / interval) * 0.3
            }

            self.updateHapticsIntensity()

            // Stop timer when audio playback reaches end of loop
            if currentTime >= totalDuration {
                timer.invalidate()
                self.hapticSyncTimer = nil
            }
        }
    }

    /// Updates the haptic pattern intensity dynamically based on the currentHapticIntensity value.
    /// Stops and recreates the haptic player with the new pattern.
    func updateHapticsIntensity() {
        guard hapticsActive, let hapticsEngine = hapticsEngine else { return }

        do {
            // Create a continuous haptic event with updated intensity and fixed sharpness
            let events = [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: currentHapticIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                ], relativeTime: 0, duration: 0.4)
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])

            // Stop existing haptic player before starting a new one
            if let player = hapticPlayer {
                do {
                    try player.stop(atTime: 0)
                } catch {
                    print("Failed to stop haptic player: \(error)")
                }
            }

            // Create new player with updated pattern and start immediately
            hapticPlayer = try hapticsEngine.makeAdvancedPlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)

        } catch {
            print("Failed to update haptic: \(error)")
        }
    }

    // MARK: - View Lifecycle and UI Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHaptics()

        // Titles for the kitten selection buttons
        let buttonTitles = ["Floozy", "Nacho", "No-No!"]

        var buttons = [UIButton]()
        // Create buttons for each kitten with styling and tags for identification
        for (index, title) in buttonTitles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = .black
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .regular)
            button.layer.cornerRadius = 10
            button.tag = index + 1
            button.addTarget(self, action: #selector(kittenButtonTapped(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
            buttons.append(button)
        }

        // Vertical stack view to hold the kitten buttons
        stackView = UIStackView(arrangedSubviews: buttons)
        stackView.axis = .vertical
        stackView.distribution = .fillEqually
        stackView.spacing = 15

        // Timer button setup with initial title and styling
        timerButton = UIButton(type: .system)
        timerButton.setTitle("∞", for: .normal)
        timerButton.setTitleColor(.white, for: .normal)
        timerButton.backgroundColor = .black
        timerButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .regular)
        timerButton.layer.cornerRadius = 10
        timerButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        timerButton.addTarget(self, action: #selector(timerButtonTapped), for: .touchUpInside)

        // Main stack view holds both the kitten buttons stack and the timer button
        mainStackView = UIStackView(arrangedSubviews: [stackView, timerButton])
        mainStackView.axis = .vertical
        mainStackView.spacing = 40
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStackView)

        // Center main stack view in the view with width constraints
        NSLayoutConstraint.activate([
            mainStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mainStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mainStackView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])

        // Set background color to black for aesthetic consistency
        view.backgroundColor = .black
    }
    
    // MARK: - Timer Button Action

    /// Handles taps on the timer button to cycle through available timer durations.
    /// Updates the button title and manages timer state accordingly.
    @objc func timerButtonTapped() {
        // Cycle timer index and get corresponding seconds value
        timerIndex = (timerIndex + 1) % timerOptions.count
        let seconds = timerOptions[timerIndex]

        switch seconds {
        case -1:
            // Infinite timer selected: show infinity symbol and cancel any running timer
            timerButton.setTitle("∞", for: .normal)
            countdownTimer?.invalidate()
            countdownTimer = nil
            remainingTime = 0
            isTimerPaused = false
            return
        default:
            // Show timer duration in minutes on button title
            timerButton.setTitle("\(seconds / 60) min", for: .normal)
        }

        // Reset any existing timers and pause state
        countdownTimer?.invalidate()
        countdownTimer = nil
        isTimerPaused = false

        // If a kitten is playing and a positive timer is selected, start the timer
        if currentlyPlayingKittenTag != nil && seconds > 0 {
            remainingTime = seconds
            startSleepTimer()
        }
    }

    // MARK: - Orientation Handling

    /// Adjusts the stack view axis based on device orientation changes.
    /// Uses horizontal layout for landscape and vertical for portrait.
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            if size.width > size.height {
                self.stackView.axis = .horizontal
            } else {
                self.stackView.axis = .vertical
            }
        })
    }
}
