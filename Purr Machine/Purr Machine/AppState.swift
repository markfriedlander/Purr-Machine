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
// Haptic architecture (Phase A, 2026-05-22):
//
//   * Engine is started once and kept warm (isAutoShutdownEnabled = false).
//     A stoppedHandler / resetHandler pair recovers from system events;
//     no stop/restart "to refresh" dance like the v0 code did.
//
//   * Two named looped players run simultaneously when a kitten is playing:
//     "purr"      — continuous events sliced over one breath cycle, with a
//                   CHHapticParameterCurve baking the inhale/exhale envelope
//                   straight into the pattern (no timer-driven updates).
//     "heartbeat" — transient lub-dub pair, looped at the cat's heart rate.
//
//   * A third "api" player slot is reserved for arbitrary patterns submitted
//     via /haptics/pattern (the Phase B tuning surface).
//
//   * Per-kitten parameters come from CatHapticProfile, which is built from
//     CatAudioAnalysis (run once at launch) merged with research defaults.
//     Floozy's haptic pulses at Floozy's measured rhythm; Nacho at Nacho's;
//     No-No! at No-No!'s. That is the architectural commitment.

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

// ========== BLOCK 2: AppState - properties & init - START ==========
@MainActor
final class AppState {

    static let shared = AppState()

    /// Posted whenever observable state changes (selection, play/stop, timer
    /// tick, analysis completion). ViewController listens for this.
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

    // --- Audio analysis + per-kitten profiles ---
    private(set) var audioAnalysisByKitten: [Kitten: CatAudioAnalysis] = [:]
    private(set) var profilesByKitten: [Kitten: CatHapticProfile] = [:]

    /// Resolves the profile for a kitten, falling back to per-kitten
    /// defaults until analysis completes (early in launch).
    func profile(for k: Kitten) -> CatHapticProfile {
        profilesByKitten[k] ?? .defaultFor(k)
    }

    // --- Haptics ---
    var hapticsSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    private var hapticsEngine: CHHapticEngine?
    private var engineStartedAt: Date?

    /// Three named player slots — see file header. Each may be nil when not
    /// in use. The API addresses these by name.
    private var purrPlayer:      CHHapticAdvancedPatternPlayer?
    private var heartbeatPlayer: CHHapticAdvancedPatternPlayer?
    private var apiPlayer:       CHHapticAdvancedPatternPlayer?

    /// True if any player is currently active.
    var hapticsActive: Bool {
        purrPlayer != nil || heartbeatPlayer != nil || apiPlayer != nil
    }

    /// Last seen intensity/sharpness values applied through the API. Useful
    /// telemetry for Phase B tuning. Note: these reflect the most-recent
    /// /haptics/dynamic update; they are NOT a continuous readback of the
    /// engine's live output (Apple doesn't expose that).
    private(set) var currentHapticIntensity: Float = 0.0
    private(set) var currentHapticSharpness: Float = 0.2

    /// Names of currently-running players, in stable order. Used by /state
    /// and /haptics/players.
    var activePlayerNames: [String] {
        var names: [String] = []
        if purrPlayer      != nil { names.append("purr")      }
        if heartbeatPlayer != nil { names.append("heartbeat") }
        if apiPlayer       != nil { names.append("api")       }
        return names
    }

    private init() {
        bootstrapHapticEngine()
        kickOffAudioAnalysis()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: AppState.didChange, object: self)
    }
}
// ========== BLOCK 2: AppState - properties & init - END ==========

// ========== BLOCK 3: AppState - playback actions - START ==========
extension AppState {

    /// Mirrors a tap on a kitten button: toggle off if already playing,
    /// otherwise stop any current playback and start this kitten.
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
        audioPlayer?.stop()
        audioPlayer = nil
        stopAllHapticPlayersInternal()
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
            startCatHapticsInternal(for: kitten)
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

// ========== BLOCK 5: AppState - haptic engine lifecycle - START ==========
extension AppState {

    /// Create the engine, install handlers, and start it. Called once from
    /// init and on demand if the engine has gone away. The engine is kept
    /// warm — we never call `engine.stop` ourselves.
    fileprivate func bootstrapHapticEngine() {
        guard hapticsSupported else {
            print("AppState: haptics not supported on this device")
            return
        }
        if hapticsEngine != nil { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.playsHapticsOnly = true

            engine.stoppedHandler = { reason in
                print("AppState: haptic engine stopped — reason=\(reason.rawValue)")
                Task { @MainActor in
                    AppState.shared.handleEngineStopped(reason: reason)
                }
            }
            engine.resetHandler = {
                print("AppState: haptic engine reset — rebuilding")
                Task { @MainActor in
                    AppState.shared.handleEngineReset()
                }
            }

            try engine.start()
            hapticsEngine = engine
            engineStartedAt = Date()
        } catch {
            print("AppState: haptic engine bootstrap failed: \(error)")
        }
    }

    /// Returns the engine, recreating it if needed. Returns nil only on
    /// unsupported hardware or unrecoverable failure.
    fileprivate func liveEngine() -> CHHapticEngine? {
        if hapticsEngine == nil { bootstrapHapticEngine() }
        // Defensive: re-call start() even if the engine exists. CHHapticEngine.start()
        // is a no-op when already running and recovers a stopped engine.
        if let e = hapticsEngine {
            do { try e.start() } catch {
                print("AppState: engine.start() recovery failed: \(error)")
                hapticsEngine = nil
                bootstrapHapticEngine()
            }
        }
        return hapticsEngine
    }

    /// Called from the engine's stoppedHandler. Tears down player references
    /// (they're invalid after the engine stops) and posts a state change.
    ///
    /// Note on background haptics: iOS does NOT permit CHHapticEngine to
    /// play with the screen locked or the app backgrounded. This is a
    /// system-level restriction (see Apple docs for
    /// `CHHapticEngine.StoppedReason.applicationSuspended`). We get audio
    /// background playback via `UIBackgroundModes = audio`, but the haptic
    /// engine stops the moment we suspend and cannot be restarted until
    /// the app returns to the foreground. The foreground transition is
    /// handled by `resumeHapticsForForegroundIfNeeded()` below.
    fileprivate func handleEngineStopped(reason: CHHapticEngine.StoppedReason) {
        purrPlayer      = nil
        heartbeatPlayer = nil
        apiPlayer       = nil
        notifyChange()
    }

    /// Call when the app returns to the foreground. If a kitten is still
    /// playing (audio kept going under lock thanks to UIBackgroundModes),
    /// restart the haptic engine and rebuild patterns so the felt purr is
    /// back the instant the user looks at the phone.
    func resumeHapticsForForegroundIfNeeded() {
        guard let k = currentlyPlaying else { return }
        guard purrPlayer == nil && heartbeatPlayer == nil else { return }
        do {
            try hapticsEngine?.start()
            startCatHapticsInternal(for: k)
            print("AppState: haptics resumed on foreground")
        } catch {
            print("AppState: haptic resume on foreground failed: \(error)")
        }
    }

    /// Called from the engine's resetHandler. Restart the engine and rebuild
    /// whatever should be playing right now (if a kitten is selected).
    fileprivate func handleEngineReset() {
        purrPlayer      = nil
        heartbeatPlayer = nil
        apiPlayer       = nil
        do {
            try hapticsEngine?.start()
        } catch {
            print("AppState: engine restart after reset failed: \(error)")
            return
        }
        if let k = currentlyPlaying {
            startCatHapticsInternal(for: k)
        }
        notifyChange()
    }
}
// ========== BLOCK 5: AppState - haptic engine lifecycle - END ==========

// ========== BLOCK 6: AppState - cat haptic patterns (purr + heartbeat) - START ==========
extension AppState {

    /// Build the per-kitten patterns and start both looped players. Stops
    /// any previously-running purr/heartbeat players first. Engine recovery
    /// is handled inside `liveEngine()`.
    fileprivate func startCatHapticsInternal(for kitten: Kitten) {
        stopPlayerInternal(name: "purr")
        stopPlayerInternal(name: "heartbeat")
        guard let engine = liveEngine() else { return }
        let prof = profile(for: kitten)
        do {
            let purrPat  = try buildPurrPattern(from: prof)
            let purr     = try engine.makeAdvancedPlayer(with: purrPat)
            purr.loopEnabled = true
            purr.loopEnd     = prof.breathPeriodSec
            try purr.start(atTime: 0)
            purrPlayer = purr

            let heartPat = try buildHeartbeatPattern(from: prof)
            let heart    = try engine.makeAdvancedPlayer(with: heartPat)
            heart.loopEnabled = true
            heart.loopEnd     = prof.heartCycleSec
            try heart.start(atTime: 0)
            heartbeatPlayer = heart

            currentHapticIntensity = prof.purrBaseIntensity
            currentHapticSharpness = prof.purrSharpness
        } catch {
            print("AppState: startCatHaptics failed for \(kitten.displayName): \(error)")
        }
        notifyChange()
    }

    /// One full breath cycle, sliced into `purrSliceCount` continuous events,
    /// modulated by a CHHapticParameterCurve baking the inhale/exhale envelope
    /// into the pattern.
    fileprivate func buildPurrPattern(from prof: CatHapticProfile) throws -> CHHapticPattern {
        let period   = prof.breathPeriodSec
        let slices   = max(1, prof.purrSliceCount)
        let sliceLen = period / Double(slices)
        var events: [CHHapticEvent] = []
        events.reserveCapacity(slices)
        for i in 0..<slices {
            let t = Double(i) * sliceLen
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: prof.purrBaseIntensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: prof.purrSharpness),
                ],
                relativeTime: t,
                duration: sliceLen
            ))
        }

        // Breath envelope: starter shape per Claude's research notes —
        //   t=0      → 0.85 (mid)
        //   t=0.25T  → low  (deep-inhale dip)
        //   t=0.50T  → 0.92 (rising into exhale)
        //   t=0.75T  → 1.00 (exhale peak)
        //   t=T      → 0.85 (return to mid)
        // Multiplied onto the per-event intensity by the IntensityControl
        // parameter (the run-time engine multiplies event intensity by the
        // current control-parameter value).
        let low: Float = max(0.05, 1.0 - prof.breathDepth)
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0,              value: 0.85),
                CHHapticParameterCurve.ControlPoint(relativeTime: period * 0.25,  value: low),
                CHHapticParameterCurve.ControlPoint(relativeTime: period * 0.50,  value: 0.92),
                CHHapticParameterCurve.ControlPoint(relativeTime: period * 0.75,  value: 1.00),
                CHHapticParameterCurve.ControlPoint(relativeTime: period,         value: 0.85),
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: events, parameterCurves: [curve])
    }

    /// Two transient events spaced by the S1-S2 split. The player's loopEnd
    /// is set to the full heart cycle, so the lub-dub repeats with silence
    /// between cycles.
    fileprivate func buildHeartbeatPattern(from prof: CatHapticProfile) throws -> CHHapticPattern {
        let events: [CHHapticEvent] = [
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: prof.s1Intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: prof.s1Sharpness),
            ], relativeTime: 0),
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: prof.s2Intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: prof.s2Sharpness),
            ], relativeTime: prof.s1s2SplitSec),
        ]
        return try CHHapticPattern(events: events, parameters: [])
    }
}
// ========== BLOCK 6: AppState - cat haptic patterns (purr + heartbeat) - END ==========

// ========== BLOCK 7: AppState - named player ops (API surface) - START ==========
extension AppState {

    /// Stop one named player and clear its slot. No-op if already nil.
    /// Recognizes "purr" / "heartbeat" / "api".
    func stopPlayerInternal(name: String) {
        switch name {
        case "purr":
            if let p = purrPlayer { try? p.stop(atTime: 0) }
            purrPlayer = nil
        case "heartbeat":
            if let p = heartbeatPlayer { try? p.stop(atTime: 0) }
            heartbeatPlayer = nil
        case "api":
            if let p = apiPlayer { try? p.stop(atTime: 0) }
            apiPlayer = nil
        default:
            break
        }
    }

    /// Stop every active player. Engine is left running.
    func stopAllHapticPlayersInternal() {
        stopPlayerInternal(name: "purr")
        stopPlayerInternal(name: "heartbeat")
        stopPlayerInternal(name: "api")
    }

    /// Stop one named player (API path: POST /haptics/stop {player}).
    /// If `name` is nil, stop all.
    func stopHapticPlayer(named name: String?) {
        if let n = name {
            stopPlayerInternal(name: n)
        } else {
            stopAllHapticPlayersInternal()
        }
        notifyChange()
    }

    /// Load and play an arbitrary pattern into a named slot. Defaults to
    /// "api" if no slot is specified. Replaces whatever was in that slot.
    func playAPIHapticPattern(events: [CHHapticEvent],
                              parameterCurves: [CHHapticParameterCurve],
                              dynamicParameters: [CHHapticDynamicParameter],
                              loop: Bool,
                              loopEnd: Double?,
                              player slot: String = "api") throws {
        guard let engine = liveEngine() else {
            throw NSError(domain: "PurrMachine.API", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Haptic engine unavailable"])
        }
        let pattern = try CHHapticPattern(events: events, parameterCurves: parameterCurves)
        let p = try engine.makeAdvancedPlayer(with: pattern)
        p.loopEnabled = loop
        if let le = loopEnd, le > 0 { p.loopEnd = le }
        for dp in dynamicParameters { try? p.sendParameters([dp], atTime: 0) }
        // Replace the named slot
        stopPlayerInternal(name: slot)
        try p.start(atTime: 0)
        switch slot {
        case "purr":      purrPlayer      = p
        case "heartbeat": heartbeatPlayer = p
        default:          apiPlayer       = p     // "api" or anything else
        }
        notifyChange()
    }

    /// Send dynamic intensity/sharpness updates. If `name` is given, sends
    /// only to that slot. If nil, sends to every active player.
    func sendDynamicHaptic(intensity: Float?, sharpness: Float?, player name: String?) throws {
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
        let targets: [CHHapticAdvancedPatternPlayer?] = {
            if let n = name {
                switch n {
                case "purr":      return [purrPlayer]
                case "heartbeat": return [heartbeatPlayer]
                case "api":       return [apiPlayer]
                default:          return []
                }
            }
            return [purrPlayer, heartbeatPlayer, apiPlayer]
        }()
        let live = targets.compactMap { $0 }
        guard !live.isEmpty else {
            throw NSError(domain: "PurrMachine.API", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "No active haptic player\(name.map { " for slot '\($0)'" } ?? "")"])
        }
        for p in live { try p.sendParameters(params, atTime: 0) }
        notifyChange()
    }

    /// Stop haptics only; audio (if any) keeps playing.
    func stopHapticsOnly() {
        stopAllHapticPlayersInternal()
        notifyChange()
    }
}
// ========== BLOCK 7: AppState - named player ops (API surface) - END ==========

// ========== BLOCK 8: AppState - audio analysis at launch - START ==========
extension AppState {

    /// Kick off background analysis of all three bundled recordings. Results
    /// are merged with research defaults into per-kitten haptic profiles.
    /// Analysis is launch-time only — these files don't change at runtime.
    fileprivate func kickOffAudioAnalysis() {
        // Seed profiles with per-kitten defaults so anything that asks before
        // analysis completes still gets a usable, cat-appropriate answer.
        for k in Kitten.allCases {
            profilesByKitten[k] = .defaultFor(k)
        }
        Task.detached(priority: .userInitiated) {
            // Sendable: enum + struct of primitives.
            let pairs: [(Kitten, CatAudioAnalysis?)] = Kitten.allCases.map { k in
                (k, AudioAnalyzer.analyze(resourceName: k.audioFile))
            }
            await MainActor.run {
                AppState.shared.applyAnalyses(pairs)
            }
        }
    }

    @MainActor
    fileprivate func applyAnalyses(_ pairs: [(Kitten, CatAudioAnalysis?)]) {
        for (k, a) in pairs {
            audioAnalysisByKitten[k] = a
            profilesByKitten[k] = .from(a, kitten: k)
            if let a { print("AudioAnalysis: \(a.summary)") }
            else     { print("AudioAnalysis: [\(k.displayName)] no result — defaults") }
        }
        // If a kitten is already playing, rebuild patterns with the
        // freshly-derived profile so the user feels the right rhythm.
        if let k = currentlyPlaying {
            startCatHapticsInternal(for: k)
        }
        notifyChange()
    }
}
// ========== BLOCK 8: AppState - audio analysis at launch - END ==========

// ========== BLOCK 9: AppState - state snapshot - START ==========
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

        // Per-kitten audio + profile dictionaries
        var analyses: [[String: Any]] = []
        var profiles: [[String: Any]] = []
        for k in Kitten.allCases {
            var a = audioAnalysisByKitten[k]?.dictionary() ?? [
                "resource":          k.audioFile,
                "durationSeconds":   NSNull(),
                "sampleRate":        NSNull(),
                "breathPeriodSec":   NSNull(),
                "breathDepth":       NSNull(),
                "purrFundamentalHz": NSNull(),
                "analysisMillis":    NSNull(),
            ]
            a["kitten"] = k.displayName
            analyses.append(a)
            var p = profile(for: k).dictionary()
            p["kitten"] = k.displayName
            profiles.append(p)
        }

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
            "activePlayers":           activePlayerNames,
            "currentHapticIntensity":  currentHapticIntensity,
            "currentHapticSharpness":  currentHapticSharpness,
            "audioAnalyses":           analyses,
            "hapticProfiles":          profiles,
            "kittens":                 kittens,
            "appVersion":              appVersion,
            "buildNumber":             buildNumber,
            "deviceModel":             device.model,
            "iosVersion":              device.systemVersion,
        ]
    }
}
// ========== BLOCK 9: AppState - state snapshot - END ==========
