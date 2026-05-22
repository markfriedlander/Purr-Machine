// AudioAnalysis.swift
// Purr Machine
//
// Derives each cat's actual rhythm from the bundled .m4a recording. The
// haptic loop period for each kitten is the cat's measured breath cycle —
// not a generic 4-second placeholder. Floozy's haptic pulses at Floozy's
// rhythm. Nacho's at Nacho's. That is the point of having three buttons.
//
// Two signals are extracted per file:
//
//   1. Breath cycle period (seconds)
//      Computed by autocorrelating the slow amplitude envelope. This is
//      the dominant low-frequency modulation — what a person on the chest
//      perceives as "rising and falling." Drives the haptic loop length.
//
//   2. Purr fundamental frequency (Hz)
//      Computed by autocorrelating the raw waveform at purr-range lags.
//      Diagnostic only — the Taptic engine cannot reproduce frequencies
//      directly, but reporting this lets us sanity-check that we found a
//      real cat purr (~25-40 Hz) and not a numerical artifact.
//
// Both analyses are defensive: if the peak-to-mean ratio of the search
// region is below `kMinPeakRatio`, the result is nil and the caller falls
// back to a research default.

import Foundation
import AVFoundation

// ========== BLOCK 1: CatAudioAnalysis result struct - START ==========
struct CatAudioAnalysis {
    let resourceName: String         // "Purr1" / "Purr2" / "Purr3"
    let durationSeconds: Double
    let sampleRate: Double
    let breathPeriodSec: Double?     // 1.5-5 s, nil if no clear peak
    let breathDepth: Float?          // 0..1, peak-trough / peak of envelope cycle
    let purrFundamentalHz: Double?   // 20-50 Hz, nil if no clear peak
    let analysisMillis: Int

    /// Compact diagnostic line for the console log.
    var summary: String {
        let b = breathPeriodSec.map { String(format: "%.2fs", $0) } ?? "n/a"
        let d = breathDepth.map     { String(format: "%.2f",  $0) } ?? "n/a"
        let f = purrFundamentalHz.map { String(format: "%.1fHz", $0) } ?? "n/a"
        return "[\(resourceName)] dur=\(String(format: "%.1f", durationSeconds))s "
             + "breath=\(b) depth=\(d) purr=\(f) (analysis \(analysisMillis)ms)"
    }

    func dictionary() -> [String: Any] {
        [
            "resource":          resourceName,
            "durationSeconds":   durationSeconds,
            "sampleRate":        sampleRate,
            "breathPeriodSec":   breathPeriodSec as Any? ?? NSNull(),
            "breathDepth":       breathDepth     as Any? ?? NSNull(),
            "purrFundamentalHz": purrFundamentalHz as Any? ?? NSNull(),
            "analysisMillis":    analysisMillis,
        ]
    }
}
// ========== BLOCK 1: CatAudioAnalysis result struct - END ==========

// ========== BLOCK 2: AudioAnalyzer - file loading - START ==========
enum AudioAnalyzer {

    /// Lower bound on (peak / mean) of the autocorrelation search band before
    /// we trust a detected period. 1.4 is generous — these recordings are
    /// short and noisy, and we'd rather report a slightly fuzzy peak than
    /// constantly fall back to defaults.
    private static let kMinPeakRatio: Float = 1.4

    /// Analyze a bundled resource. Returns nil only if the file cannot be
    /// loaded; otherwise returns a struct with whatever fields we could
    /// determine (others nil).
    static func analyze(resourceName: String, fileExtension: String = "m4a") -> CatAudioAnalysis? {
        let t0 = Date()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            print("AudioAnalyzer: missing bundle resource \(resourceName).\(fileExtension)")
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = file.length
            // Analyze at most the first 30 seconds — plenty of cycles for both
            // analyses, keeps memory + CPU bounded.
            let maxFrames = AVAudioFrameCount(min(Int64(sampleRate * 30), totalFrames))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames) else {
                print("AudioAnalyzer: failed to allocate buffer for \(resourceName)")
                return nil
            }
            try file.read(into: buffer, frameCount: maxFrames)
            let mono = monoSamples(from: buffer)
            let durSec = Double(mono.count) / sampleRate

            let (breathPeriod, breathDepth) = detectBreathCycle(samples: mono, sampleRate: sampleRate)
            let purrHz = detectPurrFundamental(samples: mono, sampleRate: sampleRate)

            let dt = Int(Date().timeIntervalSince(t0) * 1000)
            return CatAudioAnalysis(
                resourceName: resourceName,
                durationSeconds: durSec,
                sampleRate: sampleRate,
                breathPeriodSec: breathPeriod,
                breathDepth: breathDepth,
                purrFundamentalHz: purrHz,
                analysisMillis: dt
            )
        } catch {
            print("AudioAnalyzer: failed to analyze \(resourceName): \(error)")
            return nil
        }
    }

    /// Average all channels into a single Float array.
    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let chData = buffer.floatChannelData else { return [] }
        let nChans = Int(buffer.format.channelCount)
        let n = Int(buffer.frameLength)
        if nChans == 1 {
            return Array(UnsafeBufferPointer(start: chData[0], count: n))
        }
        var out = [Float](repeating: 0, count: n)
        for c in 0..<nChans {
            let ch = chData[c]
            for i in 0..<n { out[i] += ch[i] }
        }
        let inv = 1.0 / Float(nChans)
        for i in 0..<n { out[i] *= inv }
        return out
    }
}
// ========== BLOCK 2: AudioAnalyzer - file loading - END ==========

// ========== BLOCK 3: AudioAnalyzer - breath cycle detection - START ==========
extension AudioAnalyzer {

    /// Compute the slow amplitude envelope of the signal at 50 Hz (one
    /// envelope sample per 20 ms hop, RMS over a 50 ms window). Then
    /// autocorrelate the envelope at lags corresponding to 1.5-5 second
    /// periods — that band brackets cat-resting breathing rates (12-40 BPM).
    /// Returns (period in seconds, depth 0..1) — both nil if no clear peak.
    fileprivate static func detectBreathCycle(samples: [Float], sampleRate: Double)
        -> (period: Double?, depth: Float?)
    {
        let envHz: Double = 50
        let hopSamples = Int(sampleRate / envHz)
        let winSamples = Int(sampleRate * 0.05)  // 50 ms RMS window
        guard hopSamples > 0, winSamples > 0, samples.count > winSamples + hopSamples else {
            return (nil, nil)
        }
        var env: [Float] = []
        env.reserveCapacity(samples.count / hopSamples)
        var i = 0
        while i + winSamples <= samples.count {
            var sumSq: Float = 0
            for j in 0..<winSamples {
                let s = samples[i + j]
                sumSq += s * s
            }
            env.append((sumSq / Float(winSamples)).squareRoot())
            i += hopSamples
        }
        guard env.count > 100 else { return (nil, nil) }

        // De-mean the envelope so the autocorrelation captures variation,
        // not absolute level.
        let mean = env.reduce(0, +) / Float(env.count)
        var de = env
        for k in 0..<de.count { de[k] -= mean }

        // Lag range: 2.0 s .. 5.0 s → envelope-sample range.
        // 2.0 s = 30 breaths/min, the upper end of cat-resting breath rate.
        // The lower bound deliberately excludes half-period harmonics that
        // can be stronger than the fundamental in noisy short recordings.
        let minLag = Int(envHz * 2.0)
        let maxLag = min(Int(envHz * 5.0), de.count / 2)
        guard maxLag > minLag + 5 else { return (nil, nil) }

        var bestLag = minLag
        var bestVal: Float = -Float.infinity
        var sumVal: Float = 0
        var counted = 0
        for lag in minLag...maxLag {
            var s: Float = 0
            let end = de.count - lag
            for k in 0..<end { s += de[k] * de[k + lag] }
            s /= Float(end)
            sumVal += s
            counted += 1
            if s > bestVal { bestVal = s; bestLag = lag }
        }
        let meanVal = sumVal / Float(counted)
        // Peak must clearly stand above the search-band mean. Negative means
        // also fail (peak below the average — no coherent period).
        guard bestVal > 0, meanVal != 0,
              (bestVal / max(abs(meanVal), 1e-9)) >= kMinPeakRatio else {
            return (nil, nil)
        }

        // Depth estimate: take one cycle from the envelope (length = bestLag),
        // measure peak-to-trough. Use the original envelope, not de-meaned.
        let cycleStart = env.count / 4   // skip transient onset
        let cycleEnd = min(cycleStart + bestLag, env.count)
        let cycle = Array(env[cycleStart..<cycleEnd])
        let cMax = cycle.max() ?? 1
        let cMin = cycle.min() ?? 0
        let depth: Float? = cMax > 0 ? (cMax - cMin) / cMax : nil

        return (Double(bestLag) / envHz, depth)
    }
}
// ========== BLOCK 3: AudioAnalyzer - breath cycle detection - END ==========

// ========== BLOCK 4: AudioAnalyzer - purr fundamental detection - START ==========
extension AudioAnalyzer {

    /// Autocorrelate raw audio at lags corresponding to 20-50 Hz. Operates on
    /// the central 2 seconds of the file for speed. Returns Hz if a clear
    /// peak exists, else nil. Diagnostic only — not used to drive the haptic.
    fileprivate static func detectPurrFundamental(samples: [Float], sampleRate: Double) -> Double? {
        // Take a 2-second window from the middle of the file (skip onset
        // transients and any fade-out).
        let winLen = min(Int(sampleRate * 2), samples.count)
        let startIdx = max(0, (samples.count - winLen) / 2)
        guard winLen > 4000 else { return nil }
        let window = Array(samples[startIdx..<(startIdx + winLen)])

        let mean = window.reduce(0, +) / Float(window.count)
        var x = window
        for k in 0..<x.count { x[k] -= mean }

        // Lag range: 20 Hz .. 50 Hz → period 0.020 .. 0.050 s → samples:
        let minLag = max(1, Int(sampleRate / 50))
        let maxLag = Int(sampleRate / 20)
        guard maxLag > minLag + 2, maxLag < x.count / 2 else { return nil }

        var bestLag = minLag
        var bestVal: Float = -Float.infinity
        var sumVal: Float = 0
        var counted = 0
        for lag in minLag...maxLag {
            var s: Float = 0
            let end = x.count - lag
            // Stride for speed — 1.45M ops at lag worst-case is fine, but a
            // stride of 2 cuts it in half with negligible accuracy loss for
            // detecting the dominant low-frequency peak.
            var k = 0
            while k < end {
                s += x[k] * x[k + lag]
                k += 2
            }
            s /= Float(end / 2)
            sumVal += s
            counted += 1
            if s > bestVal { bestVal = s; bestLag = lag }
        }
        let meanVal = sumVal / Float(counted)
        guard bestVal > 0, meanVal != 0,
              (bestVal / max(abs(meanVal), 1e-9)) >= kMinPeakRatio else {
            return nil
        }
        return sampleRate / Double(bestLag)
    }
}
// ========== BLOCK 4: AudioAnalyzer - purr fundamental detection - END ==========
