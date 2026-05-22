# NEXT.md — Purr Machine
**Current State and Immediate Next Steps**
**Last Updated: May 2026**

---

## Current State

Project has working v0 code in a single `ViewController.swift`. Core loop functional:
- Three kitten buttons (Floozy / Nacho / No-No!) → audio playback → haptics → sleep timer
- Sleep timer cycles through 10min / 20min / 30min / ∞
- Basic haptic sync attempt (ramps intensity with audio position)
- App icon complete (meditating cat, already in Assets)
- GitHub repo created: https://github.com/markfriedlander/Purr-Machine
- Local path: `/Users/markfriedlander/Desktop/Fun/Purr Machine`

**What's not working yet:**
- Haptics don't feel like a cat — single continuous buzz, no rhythm, stops/restarts every 0.25s causing stutter
- No layered rhythms (purr + breathing + heartbeat)
- Audio loops may have click artifacts at loop points (not yet verified)
- ViewController has LEGO block structure now; the rest of the app does not yet (only AppState + LocalAPIServer + ViewController are blocked)

**Now working:**
- LocalAPIServer on port 8767 — full API for read/control, including arbitrary CHHapticPattern submission. State extracted into `AppState` (single source of truth). UI behavior unchanged.

---

## Immediate Next Steps — In Order

### Step 1 — Establish the API (First Priority) ✅ code complete, device verify pending

Implemented as `LocalAPIServer` on port **8767**. Bearer-token auth (Keychain-persisted, generated on first launch). Shared state extracted into `AppState`.

API surface (full table in HISTORY.md 2026-05-21):
- GET  /health, /state
- POST /kitten/select, /play, /stop
- POST /timer/cycle, /timer/set
- POST /haptics/pattern (arbitrary CHHapticPattern), /haptics/dynamic, /haptics/stop

Still to do for Step 1:
1. Mark runs `xcrun devicectl list devices` → share UDID
2. Install Debug build on iPhone, confirm token + address print to console and land on pasteboard
3. CC curls each endpoint, confirms state matches what's on screen
4. Once verified, fill in device UDID + connection cheat-sheet in CLAUDE.md

### Step 2 — Research Phase (Before Writing Haptic Code)

Do not write haptic code until this is done.

Research needed:
- Cat purr physiology: frequency range (25–50Hz), inhale/exhale variation, amplitude envelope
- Breathing rate at rest: 4–6 second cycle, rise/fall shape
- Cat heartbeat at rest: 120–140 BPM (cats have faster hearts than humans — verify)
- CoreHaptics capabilities: can we do true 25Hz continuous? What are the engine limits?
- CHHapticDynamicParameter for real-time intensity/sharpness updates (vs stop/restart)
- Prior art: any open-source iOS haptic libraries worth reusing?
- WWDC sessions on CoreHaptics design

Output: a written haptic pattern design (rhythm, frequency, layering approach) reviewed by Mark before any code.

### Step 3 — Implement Layered Haptic Patterns

Only after Step 2 design is approved.

Target: three simultaneous layers
1. Purr layer — primary, ~25Hz, rhythmic with inhale/exhale modulation
2. Breathing layer — slow 4–6s rise/fall envelope modulating purr intensity
3. Heartbeat layer — subtle double-pulse at ~120–140 BPM underlying the purr

Each layer potentially different per kitten (Floozy may have had a different purr character than Nacho).

Verification: Mark lies down, phone on chest, eyes closed. Does it feel like a cat?

### Step 4 — Audio Loop Cleanup

Verify each .m4a file loops seamlessly (no click or gap at loop point).
If there are artifacts, address at the audio level — do not process or alter the recordings themselves. Crossfade at loop point only if needed.

### Step 5 — Add LEGO Block Structure to ViewController.swift

Refactor into clearly bounded blocks before the file grows further. Do not change behavior — structural only.

### Step 6 — App Store Prep

- Privacy policy page
- Support page  
- App Store screenshots
- App description / metadata
- Version bump
- Clean Release build (zero warnings)
- Archive + submit

---

## Parked / Later

- Per-kitten haptic pattern variation (Floozy vs Nacho vs No-No! feel different)
- Improved audio recordings (only if Mark decides to re-record — not a priority)
- iPad support
- Widget / Lock Screen presence
- Apple Watch companion (feel the purr on your wrist)

---

**Note:** Update this file after every meaningful session. It is the live state of the project.
