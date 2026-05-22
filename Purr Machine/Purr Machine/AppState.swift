// AppState.swift
// Purr Machine
//
// Single source of truth for the app's runtime state. Owns the audio player,
// haptic engine, and timers. ViewController is a thin view over this object.
// LocalAPIServer reads and mutates state through the same surface a tap would.
//
// All public surface is @MainActor — the audio player, haptic engine, and
// AVAudioSession are touched only on the main thread. The HTTP server hops
// onto MainActor when it needs to read state or invoke an action.
//
// IMPORTANT: This file extracts existing v0 behavior verbatim. The known-broken
// v0 haptic (stop/restart every 0.25s) is preserved as-is — its redesign is the
// next phase per Docs/NEXT.md. Do not change haptic behavior in this file.

import Foundation
import AVFoundation
@preconcurrency import CoreHaptics
import UIKit

// ========== BLOCK 1: Kitten model - START ==========
enum Kitten: Int, CaseIterable {
    case floozy = 1
    case nacho  = 2
    case noNo   = 3

    var displayName: String {
        switch self {
        case .floozy: return "Floozy"
        case .nacho:  return "Nacho"
        case .noNo:   return "No-No!"
        }
    }

    /// Bundled audio resource name (without extension).
    var audioFile: String {
        switch self {
        case .floozy: return "Purr1"
        case .nacho:  return "Purr2"
        case .noNo:   return "Purr3"
        }
    }

    /// Tolerant lookup: matches by display name (case-insensitive) or by raw tag string.
    static func from(name: String) -> Kitten? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for k in Kitten.allCases where k.displayName.lowercased() == needle {
            return k
        }
        if let tag = Int(needle), let k = Kitten(rawValue: tag) { return k }
        return nil
    }
}
// ========== BLOCK 1: Kitten model - END ==========

// ========== BLOCK 2: AppState - properties & observers - START ==========
@MainActor
final class AppState {

    static let shared = AppState()

    /// Posted whenever observable state changes (selection, play/stop, timer tick).
    /// ViewController listens for this to refresh button styling and timer label.
    static let didChange = Notification.Name("com.HeatherAndMark.PurrMachine.AppState.didChange")

    // --- Selection / playback ---
    private(set) var currentlyPlaying: Kitten? = nil
    private(set) var selectedKitten: Kitten = .floozy

    // --- Timer ---
    let timerOptions: [Int] = [600, 1200, 1800, -1] // seconds; -1 == infinite
    private(set) var timerIndex: Int = 3            // default ∞
    private(set) var remainingTime: Int = 0
    private(set) var isTimerPaused: Bool = false
    private var countdownTimer: Timer?

    // --- Audio ---
    private var audioPlayer: AVAudioPlayer?
    var audioCurrentTime: TimeInterval { audioPlayer?.currentTime ?? 0 }
    var audioDuration: TimeInterval { audioPlayer?.duration ?? 0 }
    var isPlaying: Bool { audioPlayer?.isPlaying ?? false }

    // --- Haptics ---
    private var hapticsEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var hapticSyncTimer: Timer?
    private(set) var hapticsActive: Bool = false
    private(set) var currentHapticIntensity: Float = 0.0
    private(set) var currentHapticSharpness: Float = 0.2
    var hapticsSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    /// Tracks whether the live haptic pattern is being driven by the v0 audio-sync
    /// timer (true) or by an API-supplied pattern (false). Used so the API can
    /// take over haptic control without the audio-sync timer fighting it back.
    private(set) var hapticDrivenByAudioSync: Bool = true

    private init() {
        setupHapticEngineIfPossible()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AppState.didChange, object: self)
    }
}
// ========== BLOCK 2: AppState - properties & observers - END ==========

// ========== BLOCK 3: AppState - playback actions - START ==========
extension AppState {

    /// Mirrors a tap on a kitten button: toggle off if already playing, otherwise
    /// stop any current playback and start this kitten. Preserves v0 behavior
    /// including the timer reset on switching between kittens.
    func toggle(_ kitten: Kitten) {
        if currentlyPlaying == kitten {
            stop()
            return
        }
        let switching = (currentlyPlaying != nil) && (currentlyPlaying != kitten)
        _stopPlaybackInternal(resetTimerUI: false)

        if switching {
            countdownTimer?.invalidate()
            countdownTimer = nil
            isTimerPaused = false
            let selectedSeconds = timerOptions[timerIndex]
            remainingTime = max(0, selectedSeconds)
        }

        selectedKitten = kitten
        playInternal(kitten)

        if timerOptions[timerIndex] > 0 {
            startSleepTimerInternal()
        }

        currentlyPlaying = kitten
        notifyChange()
    }

    /// Start playback of a specific kitten unconditionally (used by API /play).
    func play(_ kitten: Kitten) {
        if currentlyPlaying == kitten && isPlaying { return }
        _stopPlaybackInternal(resetTimerUI: false)
        selectedKitten = kitten
        playInternal(kitten)
        if timerOptions[timerIndex] > 0 { startSleepTimerInternal() }
        currentlyPlaying = kitten
        notifyChange()
    }

    /// Stop all audio + haptic playback.
    func stop() {
        _stopPlaybackInternal(resetTimerUI: true)
        currentlyPlaying = nil
        notifyChange()
    }

    private func _stopPlaybackInternal(resetTimerUI: Bool) {
        isTimerPaused = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        hapticSyncTimer?.invalidate()
        hapticSyncTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        stopHapticsInternal()
        if resetTimerUI && timerOptions[timerIndex] > 0 {
            remainingTime = 0
        }
    }

    private func playInternal(_ kitten: Kitten) {
        guard let url = Bundle.main.url(forResource: kitten.audioFile, withExtension: "m4a") else {
            print("AppState: audio file not found for \(kitten.displayName)")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.play()
            audioPlayer = player
            startAudioSyncedHapticsInternal()
        } catch {
            print("AppState: error starting audio: \(error)")
        }
    }
}
// ========== BLOCK 3: AppState - playback actions - END ==========

// ========== BLOCK 4: AppState - timer actions - START ==========
extension AppState {

    /// Cycle to the next timer option (mirrors a tap on the timer button).
    /// Returns the seconds value of the new option (-1 == ∞).
    @discardableResult
    func cycleTimer() -> Int {
        timerIndex = (timerIndex + 1) % timerOptions.count
        let seconds = timerOptions[timerIndex]
        countdownTimer?.invalidate()
        countdownTimer = nil
        isTimerPaused = false
        if seconds == -1 {
            remainingTime = 0
        } else if currentlyPlaying != nil {
            remainingTime = seconds
            startSleepTimerInternal()
        } else {
            remainingTime = seconds
        }
        notifyChange()
        return seconds
    }

    /// Explicit timer index set (used by API /timer/set).
    func setTimerIndex(_ index: Int) {
        guard timerOptions.indices.contains(index) else { return }
        timerIndex = index
        countdownTimer?.invalidate()
        countdownTimer = nil
        let seconds = timerOptions[index]
        if seconds == -1 {
            remainingTime = 0
        } else {
            remainingTime = seconds
            if currentlyPlaying != nil { startSleepTimerInternal() }
        }
        notifyChange()
    }

    private func startSleepTimerInternal() {
        isTimerPaused = false
        countdownTimer?.invalidate()
        let seconds = timerOptions[timerIndex]
        guard seconds > 0 else { return }
        remainingTime = seconds
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                self.remainingTime -= 1
                if self.remainingTime <= 0 {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.stop()
                } else {
                    self.notifyChange()
                }
            }
        }
    }
}
// ========== BLOCK 4: AppState - timer actions - END ==========

// ========== BLOCK 5: AppState - haptics (v0 behavior preserved) - START ==========
extension AppState {

    private func setupHapticEngineIfPossible() {
        guard hapticsSupported else {
            print("AppState: haptics not supported on this device")
            return
        }
        do {
            hapticsEngine = try CHHapticEngine()
            try hapticsEngine?.start()
        } catch {
            print("AppState: haptic engine failed to start: \(error)")
        }
    }

    /// Drives the v0 haptic-follows-audio behavior. KNOWN BROKEN — preserved
    /// verbatim so the user-visible behavior is unchanged. Redesign happens
    /// in the haptic-research phase (NEXT.md Step 2/3).
    private func startAudioSyncedHapticsInternal() {
        hapticDrivenByAudioSync = true
        startHapticPurringInternal()
        guard let player = audioPlayer else { return }
        let totalDuration = player.duration
        let interval = totalDuration / 2
        hapticSyncTimer?.invalidate()
        hapticSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                guard self.hapticDrivenByAudioSync, let p = self.audioPlayer else {
                    timer.invalidate()
                    return
                }
                let t = p.currentTime
                if t < interval {
                    self.currentHapticIntensity = Float(t / interval) * 0.6
                } else {
                    self.currentHapticIntensity = 0.6 - Float((t - interval) / interval) * 0.3
                }
                self.updateHapticsIntensityInternal()
                if t >= totalDuration {
                    timer.invalidate()
                    self.hapticSyncTimer = nil
                }
            }
        }
    }

    private func startHapticPurringInternal() {
        guard hapticsSupported else { return }
        if hapticsEngine == nil { setupHapticEngineIfPossible() }
        guard let engine = hapticsEngine else { return }
        engine.stop { _ in
            do {
                try engine.start()
                Task { @MainActor in self.playInitialHapticPatternInternal() }
            } catch {
                print("AppState: haptic engine restart failed: \(error)")
            }
        }
    }

    private func playInitialHapticPatternInternal() {
        guard let engine = hapticsEngine else { return }
        do {
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
            let pattern = try CHHapticPattern(events: events, parameters: [])
            hapticPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)
            hapticsActive = true
        } catch {
            print("AppState: failed to play initial haptic pattern: \(error)")
        }
    }

    private func updateHapticsIntensityInternal() {
        guard hapticsActive, let engine = hapticsEngine else { return }
        do {
            let events = [
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: currentHapticIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: currentHapticSharpness)
                ], relativeTime: 0, duration: 0.4)
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            if let player = hapticPlayer { try? player.stop(atTime: 0) }
            hapticPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)
        } catch {
            print("AppState: failed to update haptic intensity: \(error)")
        }
    }

    private func stopHapticsInternal() {
        hapticSyncTimer?.invalidate()
        hapticSyncTimer = nil
        if let player = hapticPlayer { try? player.stop(atTime: 0) }
        hapticPlayer = nil
        hapticsEngine?.stop(completionHandler: nil)
        hapticsActive = false
        hapticDrivenByAudioSync = true
    }
}
// ========== BLOCK 5: AppState - haptics (v0 behavior preserved) - END ==========

// ========== BLOCK 6: AppState - API-driven haptics - START ==========
extension AppState {

    /// Play an arbitrary CHHapticPattern supplied via the API. Hands haptic
    /// control off from the v0 audio-sync timer until the next playback or
    /// /haptics/stop. Returns nothing; throws on engine/pattern errors.
    func playAPIHapticPattern(events: [CHHapticEvent],
                              parameterCurves: [CHHapticParameterCurve],
                              dynamicParameters: [CHHapticDynamicParameter]) throws {
        if hapticsEngine == nil { setupHapticEngineIfPossible() }
        guard let engine = hapticsEngine else {
            throw NSError(domain: "PurrMachine.API", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Haptic engine unavailable"])
        }
        try engine.start()
        let pattern = try CHHapticPattern(events: events, parameterCurves: parameterCurves)
        hapticDrivenByAudioSync = false
        hapticSyncTimer?.invalidate()
        hapticSyncTimer = nil
        if let player = hapticPlayer { try? player.stop(atTime: 0) }
        hapticPlayer = try engine.makeAdvancedPlayer(with: pattern)
        for p in dynamicParameters {
            try? hapticPlayer?.sendParameters([p], atTime: 0)
        }
        try hapticPlayer?.start(atTime: 0)
        hapticsActive = true
        notifyChange()
    }

    /// Send dynamic intensity/sharpness updates to the currently running
    /// haptic player without stopping/restarting it.
    func sendDynamicHaptic(intensity: Float?, sharpness: Float?) throws {
        guard let player = hapticPlayer else {
            throw NSError(domain: "PurrMachine.API", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No active haptic player"])
        }
        var params: [CHHapticDynamicParameter] = []
        if let i = intensity {
            params.append(CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: i, relativeTime: 0))
            currentHapticIntensity = i
        }
        if let s = sharpness {
            params.append(CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: s, relativeTime: 0))
            currentHapticSharpness = s
        }
        guard !params.isEmpty else { return }
        try player.sendParameters(params, atTime: 0)
        notifyChange()
    }

    /// Stop haptics only; leaves audio playing.
    func stopHapticsOnly() {
        stopHapticsInternal()
        notifyChange()
    }
}
// ========== BLOCK 6: AppState - API-driven haptics - END ==========

// ========== BLOCK 7: AppState - state snapshot - START ==========
extension AppState {

    /// JSON-serialisable snapshot of every observable state field. Used by
    /// the API's /state endpoint and returned from every mutating endpoint.
    func snapshotDictionary() -> [String: Any] {
        let kittens: [[String: Any]] = Kitten.allCases.map { k in
            ["tag": k.rawValue, "name": k.displayName, "file": k.audioFile]
        }
        let timerSeconds = timerOptions[timerIndex]
        let info = Bundle.main.infoDictionary ?? [:]
        let appVersion  = info["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = info["CFBundleVersion"] as? String ?? ""
        let device      = UIDevice.current
        return [
            "selectedKittenName":      selectedKitten.displayName,
            "selectedKittenTag":       selectedKitten.rawValue,
            "currentlyPlayingTag":     currentlyPlaying?.rawValue as Any? ?? NSNull(),
            "currentlyPlayingName":    currentlyPlaying?.displayName as Any? ?? NSNull(),
            "isPlaying":               isPlaying,
            "audioCurrentTime":        audioCurrentTime,
            "audioDuration":           audioDuration,
            "audioFile":               currentlyPlaying?.audioFile as Any? ?? NSNull(),
            "timerIndex":              timerIndex,
            "timerOptionSeconds":      timerSeconds,
            "timerOptions":            timerOptions,
            "remainingTime":           remainingTime,
            "isTimerPaused":           isTimerPaused,
            "hapticsSupported":        hapticsSupported,
            "hapticsActive":           hapticsActive,
            "hapticDrivenByAudioSync": hapticDrivenByAudioSync,
            "currentHapticIntensity":  currentHapticIntensity,
            "currentHapticSharpness":  currentHapticSharpness,
            "kittens":                 kittens,
            "appVersion":              appVersion,
            "buildNumber":             buildNumber,
            "deviceModel":             device.model,
            "iosVersion":              device.systemVersion,
        ]
    }
}
// ========== BLOCK 7: AppState - state snapshot - END ==========
