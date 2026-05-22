# HISTORY.md — Purr Machine
**Chronicle of All Work**
**Started: May 2026**

---

## 2026-05-22 — Phase B feedback round 1: intensity bump + audio processing

Mark felt the haptic for the first time. Report: "felt pretty great! relaxing and bringing up all kinds of happy memories." No-No!'s is the favorite — partly the better audio quality of her recording, partly her bell jingling, which is preserved and irreplaceable. All three were "a little more subtle" than he wanted, and rhythm changes were "hard to feel."

### Haptic intensity bumps (across all three cats)
| field             | before | after |
|-------------------|-------:|------:|
| Floozy intensity  | 0.75   | 0.90  |
| Nacho intensity   | 0.65   | 0.80  |
| No-No! intensity  | 0.60   | 0.76  | (smaller bump — already the favorite)
| breath depth cap  | 0.35   | 0.55  |
| heartbeat S1      | 0.40   | 0.55  |
| heartbeat S2      | 0.25   | 0.35  |

The 0.55 depth cap means trough = (1 - 0.55) × baseIntensity → about 0.4 of peak. That's a meaningful felt swell-and-recede rather than the previous 0.65-of-peak whisper.

### Audio production pipeline (Scripts/process_audio.sh)
New per-file pipeline using ffmpeg on Mark's Mac, written so it's easy to re-run when sources change:

1. **highpass 28 Hz** — strips room rumble below the purr fundamental. All three cats purr at ~28-29 Hz (per our analysis), so the cutoff is just below their voice.
2. **adeclick** — isolates and patches transient pops/clicks (mic bumps from movement). Broader sounds like sheets rustling are preserved because they're not point-spikes.
3. **dynaudnorm** — smooths the volume swings from us moving the mic closer/farther, without flattening the cat's actual dynamics. This is what Mark asked for ("sounds like we're capturing better").
4. **loudnorm to -18 LUFS** — consistent perceived loudness across all three cats.
5. **Seamless loop crossfade** — last 0.5s fades into a copy of the first 0.5s. When AVAudioPlayer loops the file, the seam is silent — no click.
6. **AAC encode @ 96 kbps** — matches source format, in-ear quality.

Originals in `Audio kitty purrs/` are **never written to**. Production files at `Purr Machine/Purr[123].m4a`.

### What was deliberately not touched
- No-No!'s bell jingling. It's HIM.
- Sheets / fabric / kitten-bumping-into-mic sounds. They're the room he was in.
- Underlying recording fidelity. What was captured is the ceiling.

### One snag along the way
First processing pass wrote the files to `Purr Machine/Purr Machine/Purr*.m4a` (the inner synchronized folder). The pbxproj has explicit `PBXFileReference`s for `Purr Machine/Purr*.m4a` at the project root, AND the synchronized folder auto-included the inner copies, so the build saw duplicate resources and failed. Moved the files to the project root and added a comment in the script so this doesn't happen again.

### Verification on processed audio
Autocorrelation on the new files gives the same per-cat rhythms (28.6-28.9 Hz purr, 2.1-3.3 s breath cycles). The processing didn't damage the rhythm content. All three kittens still bring up both purr+heartbeat players cleanly.

---

## 2026-05-22 — Haptic Phase A.2: CC's tuning judgment before handoff to Mark

SC pushed back: stop deferring tuning judgment calls to Mark. Wear all three hats yourself. Don't bring Mark in until you think it's ready. Made the following changes on my own judgment, all with the goal of "cat on chest" not "phone alert":

### Autocorrelation: min lag 1.5 s → 2.0 s
Nacho's first run reported 1.70 s breath cycle — half-period harmonic of his real ~3.4 s rhythm, or simply too fast for relaxed-cat-on-chest. Pushing the min to 2.0 s (30 breaths/min, the upper end of a relaxed cat) puts him on his actual rhythm. After fix: Nacho 2.34 s, almost identical to No-No! at 2.36 s — physically plausible for similarly-sized cats. Floozy at 3.24 s (long-haired, larger) remains the slowest. All three still show purr fundamentals ~28.7 Hz.

### Haptic depth decoupled from measured envelope depth, capped at 0.35
Plugging the raw envelope depth (0.71-0.86) straight into the haptic curve made the trough = base × (1 - depth), which for base 0.85 went to 0.20 — a 4× dynamic range that would feel like the purr drops out during inhale. The research says "slightly fuller exhale," not "purr stops." Capping at 0.35 keeps cross-cat variation while preserving continuity.

### Per-kitten haptic personalities (tasteful defaults)
Each cat now feels different:
| Cat    | purrBaseIntensity | purrSharpness | heartRateBPM |
|--------|------------------:|--------------:|-------------:|
| Floozy | 0.75 (richer)     | 0.12 (softer) | 145          |
| Nacho  | 0.65 (lighter)    | 0.18 (brighter)| 170         |
| No-No! | 0.60 (gentle)     | 0.14          | 155          |
Reasoning: Floozy was a long-haired tortoiseshell — larger, slower heart, denser purr. Nacho is a sleek young orange tabby — smaller, faster heart, lighter purr. No-No! was at end of life — gentle, mid-rate (honors his condition without making a strong claim about it).

### Heartbeat intensity 0.20/0.12 → 0.40/0.25
The original values would be mathematically lost under a 0.70+ continuous purr. New values are heard-but-subtle. Phase B will tell us if "subtle" landed where I think it did.

### Baseline purr intensity 0.85 → research default 0.70
0.85 felt like "phone alert" pitch; 0.70 is the upper-mid of felt intensity. The breath curve modulates 0.7 × 0.65 (=0.46) → 0.7 × 1.0 (=0.70) over the cycle. Still very present, just not aggressive.

This is the version I think is ready for Mark to feel for the first time.

---

## 2026-05-22 — Haptic Phase A: two-player architecture + per-cat rhythm

### What landed
The v0 haptic codepath is gone. Replaced by:

- **Engine kept warm** — `isAutoShutdownEnabled = false`, `playsHapticsOnly = true`, `stoppedHandler` and `resetHandler` recover from system events. No stop/restart "to refresh" dance.
- **Two named looped players** running simultaneously when a kitten plays:
  - `purr` — continuous events sliced over one breath cycle, with a `CHHapticParameterCurve` baking the inhale/exhale envelope straight into the pattern. `loopEnabled = true`, `loopEnd = breathPeriodSec`.
  - `heartbeat` — transient lub-dub at S1 + S1+0.080s, `loopEnd = 60 / heartRateBPM`.
- **Third `api` player slot** for arbitrary patterns submitted via `/haptics/pattern` — the Phase B tuning surface.
- **Per-kitten haptic profiles** from `CatHapticProfile`, built from the cat's measured audio plus research defaults.

### Per-cat rhythm — extracted from the actual recordings
`AudioAnalyzer` runs once at launch, off-main. Decodes each `.m4a` to PCM mono, computes a 50 Hz amplitude envelope, autocorrelates the envelope at 1.5–5 s lags for breath period, and autocorrelates raw PCM at 20–50 Hz lags for the purr fundamental (diagnostic only — the Taptic engine can't reproduce a frequency directly).

Measured values on first run:

| Cat | Purr fundamental | Breath cycle | Breath depth |
|---|---|---|---|
| Floozy | 28.9 Hz | 3.24 s | 0.76 |
| Nacho  | 28.6 Hz | 1.70 s | 0.86 |
| No-No! | 28.7 Hz | 2.36 s | 0.71 |

All three purr fundamentals land in the research-stated 25–30 Hz band — the detector found real cat purrs, not noise. Floozy's 3.24 s breath cycle is right at the research-stated midpoint for a relaxed cat. **Nacho's 1.70 s is fast** — possibly real (animated cat in the recording), possibly the half-period harmonic. Phase B (Mark on chest) will tell us. If it feels fluttery, we widen the search-band minimum.

### API additions
- `GET /audio/analysis` — per-kitten analysis + resolved haptic profile
- `GET /haptics/players` — supported / active / activePlayers / current intensity & sharpness
- `POST /haptics/pattern` — now accepts `player` (defaults to `api`), `loop`, `loopEnd`
- `POST /haptics/dynamic` — now accepts optional `player` (defaults to all active)
- `POST /haptics/stop` — now accepts optional `player` (defaults to all)
- Schema reconciliation: accept both `parameter`/`parameterID`, `controlPoints`/`keyframes`, `time`/`relativeTime`. Claude's proposal JSON works as-is.

### Phase A QA (no Mark required) — all passed
- 12 rapid kitten swaps in <2s → engine survives, lands cleanly, both players active
- 6 s soak with five live `/haptics/dynamic` updates while patterns loop → intensity tracks, audio continues uninterrupted
- Stop one named player → others survive
- Stop all → every slot cleared
- Bogus player name → 500 with explanatory error
- Looped `api` pattern (Claude's keyframe-spelled JSON) accepted and runs alongside `purr`
- Zero warnings introduced

### What Phase A intentionally does NOT do
- Tune the patterns. The defaults are Claude's research starters. Phase B happens with Mark lying down, phone on chest, CC driving live tweaks via `/haptics/dynamic` and `/haptics/pattern`. No haptic commit will be made without Mark's confirmation.
- Address background/lock-screen behavior. The engine has the right handlers installed, but I can't confirm lock-screen behavior without Mark physically locking the phone. Needs verification when Mark comes back.

### Files
- New: `AudioAnalysis.swift` — file loading + RMS envelope + autocorrelation, defensive peak-ratio guard
- New: `CatHapticProfile.swift` — per-kitten parameter struct + research defaults + builder from analysis
- Rewritten: `AppState.swift` blocks 5–8 (engine lifecycle, cat patterns, named-player ops, audio analysis at launch). Blocks 1–4 (kitten model, properties, playback actions, timer) unchanged.
- Extended: `LocalAPIServer.swift` (player names, loop, schema reconciliation, two new GET endpoints).

---

## 2026-05-21 — Bundled audio corrected; Wi-Fi IP discovery fixed

### Wrong-audio bug fixed
The bundled `Purr1/Purr2/Purr3.m4a` files were byte-identical to each other and didn't match any of the real recordings — every kitten button played the same wrong recording. Replaced them in place with the real takes from `Audio kitty purrs/`:

| Kitten  | Source file in `Audio kitty purrs/` | Size  | Duration |
|---------|-------------------------------------|-------|----------|
| Floozy  | `Floozy.m4a`                        | 922 KB| 110.9 s  |
| Nacho   | `Nacho.m4a`                         | 700 KB| 80.3 s   |
| No-No!  | `No-No! 2.m4a`                      | 529 KB| 65.6 s   |

For No-No! there were three candidate takes; CC picked #2 (the middle take by size). Mark to verify by listening; trivial to swap to #1 or #3 if a different take feels better. The "Floozy test.m4a" and "Floozy.m4a" source files are byte-identical, so "test" is redundant (left in place, not in the bundle).

Verified via API by playing each kitten and reading `audioDuration` — three distinct values, all matching the source files.

### Wi-Fi IP discovery
`LocalAPIServer.localIPAddress()` previously took the last `en*` interface it iterated, which on a USB-tethered iPhone resolved to the 169.254/16 link-local address — only reachable from the host Mac via cable. New scoring prefers `en0` (iPhone Wi-Fi), then any non-link-local address, then RFC1918 ranges. Verified over Wi-Fi alone (cable unplugged): `192.168.12.206:8767` reachable from the Mac.

---

## 2026-05-21 — LocalAPIServer Established (Step 1 of NEXT.md)

### Context
First CC session on the project. Read the doc set, studied the Hal Universal `LocalAPIServer` pattern, agreed an API surface with Mark, then executed.

### Git
- Initialized local repo (was not yet a git checkout)
- First commit: v0 state (`ViewController.swift`, audio, app icon, docs, source recordings)
- Merged the GitHub auto-generated README on top (unrelated histories, single merge commit)
- Second commit: AppState + LocalAPIServer + Info.plist + ViewController refactor
- Pushed to `origin/main`

### Code changes
- **AppState.swift (new)** — `@MainActor` single source of truth. Owns audio player, haptic engine, sleep timer, kitten selection. ViewController is now a thin view over it. v0 haptic behavior preserved byte-for-byte (the redesign comes in Step 2/3).
- **LocalAPIServer.swift (new)** — `NWListener` HTTP/JSON server on port **8767**. Bearer-token auth (Keychain-persisted). Token + address printed to console and copied to pasteboard on launch.
- **ViewController.swift** — refactored to use AppState. Behavior identical for the user.
- **SceneDelegate.swift** — starts the API server on first scene attach.
- **Info.plist** — added `NSLocalNetworkUsageDescription` and `NSBonjourServices`.

### API surface (port 8767, all but /health require Bearer token)
| Method | Path | Purpose |
|---|---|---|
| GET  | /health           | liveness (no auth) |
| GET  | /state            | full snapshot |
| POST | /kitten/select    | `{name}` or `{tag}`; toggles like a tap |
| POST | /play             | start playback |
| POST | /stop             | stop |
| POST | /timer/cycle      | same as tapping timer button |
| POST | /timer/set        | `{index}` or `{seconds}` |
| POST | /haptics/pattern  | full arbitrary CHHapticPattern |
| POST | /haptics/dynamic  | live `intensity`/`sharpness` via `CHHapticDynamicParameter` |
| POST | /haptics/stop     | stop haptics only |

### Verification
Clean Release build, zero warnings introduced. Two pre-existing iPad app-icon warnings (76x76@2x, 83.5x83.5@2x missing) noted — not touched per CLAUDE.md ("App icon: complete").

Verified end-to-end on Mark's iPhone 16 Plus (UDID `D24FB384-9C55-5D33-9B0D-DAEBFA6528D6`) over USB at `169.254.x.x:8767`:
- `/health` 200 no-auth; `/state` 401 without token, 200 with; state matched UI
- `/kitten/select {"name":"Nacho"}` updated UI + started audio
- `/haptics/pattern` drove an arbitrary CHHapticPattern with parameter curve — felt on device, `hapticsActive=true`, `hapticDrivenByAudioSync=false`
- `/timer/cycle`, `/timer/set`, `/stop` worked

A second DEBUG-only commit followed the first API commit, adding the antenna-toggle pattern from Posey:
- Top-left antenna icon in the UI (DEBUG only) toggles the API on/off
- Auto-start on first `viewDidAppear` shows an `API ready` alert with `<ip>:<port>:<token>`, also copied to clipboard
- `LocalAPIServer` writes `api_connection.txt` to `Documents/` on start (useful on simulator)
- `LocalAPIServer.shared` singleton; SceneDelegate no longer owns startup

### Surfaced bugs (not fixed in this session — see NEXT.md)
1. **Bundled audio**: `Purr1/Purr2/Purr3.m4a` are byte-identical (325 KB) and don't match any file in `Audio kitty purrs/`. All three kittens play the same wrong recording.
2. **v0 haptic startup is racy**: `/state` reports `hapticsActive=false` after `/play`, even though `currentHapticIntensity` is updating. The audio-sync timer fires; the haptic player itself never comes up cleanly. This is the exact problem the haptic redesign is meant to fix.

### Decisions worth preserving
- Port **8767** assigned to Purr Machine (Posey 8765, Hal 8766).
- `/haptics/pattern` accepts arbitrary patterns including parameter curves and dynamic parameters — maximum flexibility for the haptic-design iteration loop.
- Two-commit history (v0, then API) gives a clean before/after.

---

## 2026-05-21 — Project Restarted; Strategy Session with Claude (claude.ai)

### Context

Mark restarted the Purr Machine project after a long hiatus. Original v0 code existed in a single `ViewController.swift`. Project is deeply personal: the app simulates the physical comfort of a purring cat, using the iPhone's Taptic engine to make the phone vibrate on your chest. The three cats are Nacho (Heather's cat, still with us in Atlanta), No-No! (Heather's cat, recently passed from cancer), and Floozy (Mark's parents' cat, recently passed from cancer). The audio recordings are of the actual cats and are intentionally preserved as-is.

### Strategy Session Decisions

Working with Claude (claude.ai) to plan before spinning up Claude Code:

1. **API is first-class and first priority.** Established pattern from Hal Universal and Posey — the API must be built before feature work, not retrofitted. CC needs to be able to trigger kitten selection, play/stop, read all state, and observe haptic intensity in real time. No gap between what a human experiences and what CC can read.

2. **Haptic experience is the soul of the app.** Current implementation (single continuous buzz, intensity ramped with audio position, player stopped and recreated every 0.25s) is not good enough. Target: three layered simultaneous rhythms — purr (~25Hz), breathing (4–6s cycle), heartbeat (~120–140 BPM). Research phase required before any haptic code is written.

3. **Audio recordings stay as-is.** They are the real cats. Imperfect and irreplaceable.

4. **App icon is complete.** Meditating cat, already in Assets.xcassets.

5. **GitHub repo established.** https://github.com/markfriedlander/Purr-Machine

6. **Document system established.** CLAUDE.md, NEXT.md, HISTORY.md, HANDOFF.md modeled on Hal Universal / Posey patterns.

7. **Order of operations agreed:**
   - Step 1: API setup (first)
   - Step 2: Research (cat physiology + CoreHaptics capabilities)
   - Step 3: Haptic pattern design (written, reviewed by Mark)
   - Step 4: Implement layered haptics
   - Step 5: Audio loop verification
   - Step 6: LEGO block refactor of ViewController.swift
   - Step 7: App Store prep

### Current Code State (v0 assessment)

**What works:**
- Three kitten buttons → audio playback (looping .m4a) → haptics → sleep timer
- Sleep timer: 10min / 20min / 30min / ∞ cycling
- Orientation handling (landscape → horizontal button layout)
- Basic haptic sync concept (intensity ramps with audio position)

**Known problems:**
- Haptic player stopped and recreated every 0.25s → stuttering, expensive
- No layered rhythms
- Single continuous buzz doesn't feel like a cat
- No API
- No LEGO block structure
- Audio loop artifacts unknown (not yet checked)

---

*This file will be updated after every meaningful session. Newest entries at top.*
