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

// ========== BLOCK 2: Research + per-kitten defaults - START ==========
extension CatHapticProfile {

    /// Research-derived starting values, neutral. Used as the base for
    /// per-kitten profiles and as the fallback when no kitten is specified.
    ///
    /// Notes on tuned values (from CC's judgment, 2026-05-22):
    ///  - purrBaseIntensity 0.70 (not 0.85): "cat on chest" not "phone alert".
    ///    The breath curve modulates this between (1 - depth) and 1.0 ×
    ///    purrBaseIntensity, so 0.70 is the upper-mid range of felt intensity.
    ///  - breathDepth 0.25: gentle "slightly-fuller-exhale" modulation, not
    ///    the dramatic envelope of the raw audio. Higher values made the
    ///    purr feel like it was dropping out during inhale.
    ///  - heartbeat intensities 0.40 / 0.25 (not 0.20 / 0.12): heard-but-
    ///    subtle, mathematically present under a 0.70 continuous purr.
    static var researchDefaults: CatHapticProfile {
        CatHapticProfile(
            breathPeriodSec:    3.5,
            breathDepth:        0.25,
            purrBaseIntensity:  0.70,
            purrSharpness:      0.15,
            purrSliceCount:     4,
            heartRateBPM:       160,
            s1s2SplitSec:       0.080,
            s1Intensity:        0.40,
            s2Intensity:        0.25,
            s1Sharpness:        0.40,
            s2Sharpness:        0.60
        )
    }

    /// Per-kitten defaults — tasteful judgment calls based on what we know
    /// about each cat. Floozy was a long-haired tortoiseshell (larger, slower
    /// heart, denser purr). Nacho is a sleek young orange tabby (lighter,
    /// faster heart). No-No! was at end of life with cancer (gentler, mid-
    /// rate). These will be tuned in Phase B when Mark feels them.
    static func defaultFor(_ kitten: Kitten) -> CatHapticProfile {
        var p = researchDefaults
        switch kitten {
        case .floozy:
            p.purrBaseIntensity = 0.75   // richer
            p.purrSharpness     = 0.12   // softer
            p.heartRateBPM      = 145
        case .nacho:
            p.purrBaseIntensity = 0.65   // lighter
            p.purrSharpness     = 0.18   // brighter
            p.heartRateBPM      = 170
        case .noNo:
            p.purrBaseIntensity = 0.60   // gentle
            p.purrSharpness     = 0.14
            p.heartRateBPM      = 155
        }
        return p
    }
}
// ========== BLOCK 2: Research + per-kitten defaults - END ==========

// ========== BLOCK 3: Builder from CatAudioAnalysis - START ==========
extension CatHapticProfile {

    /// Plausible-range guards. The breath period range matches the
    /// autocorrelation search band (2-5 s). The depth range is wider than
    /// what we actually use for haptic modulation — see below.
    private static let kBreathPeriodRange: ClosedRange<Double> = 2.0...5.0
    private static let kHapticDepthMaxFromAudio: Float = 0.35

    /// Merge an analysis result with the per-kitten default. The measured
    /// breath PERIOD is plugged in directly (this is the architectural
    /// commitment: Nacho's haptic pulses at Nacho's measured rhythm). The
    /// measured envelope DEPTH is capped at `kHapticDepthMaxFromAudio`
    /// before being used — the raw audio envelope can be very deep
    /// (0.7-0.9), but a haptic modulation that deep makes the purr feel
    /// like it disappears during inhale. The capped value preserves
    /// "this cat modulates more than that cat" without going dramatic.
    static func from(_ analysis: CatAudioAnalysis?, kitten: Kitten) -> CatHapticProfile {
        var p = defaultFor(kitten)
        guard let a = analysis else { return p }
        if let bp = a.breathPeriodSec, kBreathPeriodRange.contains(bp) {
            p.breathPeriodSec = bp
        }
        if let bd = a.breathDepth, bd > 0 {
            p.breathDepth = min(bd, kHapticDepthMaxFromAudio)
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
