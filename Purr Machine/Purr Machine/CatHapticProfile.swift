// CatHapticProfile.swift
// Purr Machine
//
// Per-kitten haptic parameters. These bundle every knob the two-player
// haptic architecture needs into a single struct. A profile is constructed
// from a `CatAudioAnalysis` (when one is available) plus research-based
// defaults; the analysis fields override their corresponding default
// fields when present and within plausible bounds.
//
// Floozy, Nacho, and No-No! each get their own profile derived from their
// own recording. That is the architectural commitment: the haptic for a
// given cat pulses at that cat's measured rhythm, not at a generic mean.
//
// The profile is the *input* to pattern construction (done elsewhere in
// AppState). Nothing in this file talks to CoreHaptics directly.

import Foundation

// ========== BLOCK 1: CatHapticProfile struct + defaults - START ==========
struct CatHapticProfile {

    // --- Purr layer (continuous events, looped, modulated by breath curve) ---

    /// One full breath cycle in seconds. Loop length of the purr pattern.
    /// Source: envelope autocorrelation; fallback 3.5s (research midpoint).
    var breathPeriodSec: Double

    /// Peak-to-trough modulation depth of the breath envelope, 0..1.
    /// Source: measured envelope; fallback 0.30 (Claude's starter).
    var breathDepth: Float

    /// Baseline intensity for the purr's continuous events, 0..1.
    /// Tuning knob in Phase B.
    var purrBaseIntensity: Float

    /// Sharpness for the purr layer, 0..1. Lower = more "low rumble" feel.
    var purrSharpness: Float

    /// Number of slices the breath cycle is broken into. Each slice is one
    /// CHHapticEvent of `breathPeriodSec / sliceCount` duration. Splitting
    /// gives the engine natural re-articulation points and lets the curve
    /// re-shape per slice. Default 4 (inhale-in, inhale-out, exhale-in,
    /// exhale-out — emotional, not literal).
    var purrSliceCount: Int

    // --- Heartbeat layer (transient lub-dub, separate looped player) ---

    /// Heart rate in BPM. Cats rest 140-180 BPM; default 160.
    var heartRateBPM: Double

    /// Time in seconds between S1 (lub) and S2 (dub). Default 0.080s
    /// matches the anatomical split.
    var s1s2SplitSec: Double

    /// Intensity of S1 (lub). Stronger of the pair.
    var s1Intensity: Float

    /// Intensity of S2 (dub). Weaker, slightly sharper.
    var s2Intensity: Float

    var s1Sharpness: Float
    var s2Sharpness: Float

    /// Derived: one heartbeat cycle in seconds (period between successive
    /// S1 onsets).
    var heartCycleSec: Double { 60.0 / heartRateBPM }
}
// ========== BLOCK 1: CatHapticProfile struct + defaults - END ==========

// ========== BLOCK 2: Research defaults - START ==========
extension CatHapticProfile {

    /// Research-derived starting values. Used directly when no audio analysis
    /// is available, and merged with analysis values otherwise. Tuned in
    /// Phase B with Mark on the chest.
    static var researchDefaults: CatHapticProfile {
        CatHapticProfile(
            breathPeriodSec:    3.5,
            breathDepth:        0.30,
            purrBaseIntensity:  0.85,
            purrSharpness:      0.15,
            purrSliceCount:     4,
            heartRateBPM:       160,
            s1s2SplitSec:       0.080,
            s1Intensity:        0.20,
            s2Intensity:        0.12,
            s1Sharpness:        0.40,
            s2Sharpness:        0.60
        )
    }
}
// ========== BLOCK 2: Research defaults - END ==========

// ========== BLOCK 3: Builder from CatAudioAnalysis - START ==========
extension CatHapticProfile {

    /// Plausible-range guards. If an analysis number falls outside these,
    /// we drop it and use the default — better a generic cat than a glitch.
    private static let kBreathPeriodRange: ClosedRange<Double> = 1.5...5.0
    private static let kBreathDepthRange:  ClosedRange<Float>  = 0.05...0.95

    /// Merge an analysis result with the research defaults. Any analysis
    /// field that's nil or out-of-range is replaced by the default.
    static func from(_ analysis: CatAudioAnalysis?) -> CatHapticProfile {
        var p = researchDefaults
        guard let a = analysis else { return p }
        if let bp = a.breathPeriodSec, kBreathPeriodRange.contains(bp) {
            p.breathPeriodSec = bp
        }
        if let bd = a.breathDepth, kBreathDepthRange.contains(bd) {
            p.breathDepth = bd
        }
        return p
    }

    func dictionary() -> [String: Any] {
        [
            "breathPeriodSec":   breathPeriodSec,
            "breathDepth":       breathDepth,
            "purrBaseIntensity": purrBaseIntensity,
            "purrSharpness":     purrSharpness,
            "purrSliceCount":    purrSliceCount,
            "heartRateBPM":      heartRateBPM,
            "s1s2SplitSec":      s1s2SplitSec,
            "s1Intensity":       s1Intensity,
            "s2Intensity":       s2Intensity,
            "s1Sharpness":       s1Sharpness,
            "s2Sharpness":       s2Sharpness,
            "heartCycleSec":     heartCycleSec,
        ]
    }
}
// ========== BLOCK 3: Builder from CatAudioAnalysis - END ==========
