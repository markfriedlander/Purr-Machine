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

### Step 1 — Establish the API ✅ DONE (verified on Mark's iPhone 16 Plus, 2026-05-21)

Verified end-to-end over USB at `169.254.x.x:8767`:
- `/health` 200 (no auth); `/state` 401 without token, 200 with; state matches UI
- `/kitten/select {"name":"Nacho"}` flipped the on-screen button bold and started audio
- `/haptics/pattern` with parameter curves successfully drove an arbitrary CHHapticPattern (felt on device)
- `/timer/cycle`, `/timer/set` worked

Connection details in CLAUDE.md (Build + Deploy and API connection sections). DEBUG-only antenna toggle in the top-left of the UI; alert on first launch shows the connection string.

**Known v0 bug surfaced by the API**: `hapticsActive` returns `false` after `/play`, but `currentHapticIntensity` is updating. This means the v0 audio-sync timer fires but the haptic player itself never comes up cleanly. Confirmed pre-existing behavior — the haptic redesign in Step 3 is meant to replace this entirely.

### Step 2 — Research Phase ✅ DONE (Mark + Claude/claude.ai)
Output: written brief on cat purr/breath/heart, CoreHaptics affordances, and a starter two-player architecture. See HISTORY.md 2026-05-22 for the per-cat measurements.

### Step 3 — Implement Layered Haptic Patterns ✅ Phase A DONE
Two-player architecture (purr+breathing as one player with parameter curve, heartbeat as a second player), looped, per-kitten parameters from audio analysis. Engine kept warm. API extended for live tuning. All Phase A QA passed. See HISTORY.md 2026-05-22.

**Phase B — Mark feels the patterns** is the next step:
- Mark lies down, phone on chest, eyes closed
- Try each kitten in turn — does each feel like that cat?
- One round of feedback per cat. Mark says what's wrong; CC re-tunes; install; Mark feels again.
- **No haptic commit lands without Mark's confirmation.**
- CC has already taken its best swings on the obvious issues (see HISTORY.md 2026-05-22 Phase A.2). What remains is what only a body on a chest can answer.

### Step 3.5 — Lock-screen + background verification (pending Mark)
Engine handlers are installed (`stoppedHandler`/`resetHandler`) but lock-screen behavior is unverified. Mark to confirm whether audio + haptic continue under lock screen and resume on unlock. If not, may need `UIBackgroundModes` audio + audio session category review.

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

## Pre-haptic-research items worth doing soon

### Bundled audio files ✅ FIXED 2026-05-21
Replaced bundled `Purr1/Purr2/Purr3.m4a` with the real recordings from `Audio kitty purrs/`:
- Floozy → Floozy.m4a (922 KB, ~110.9 s)
- Nacho  → Nacho.m4a (700 KB, ~80.3 s)
- No-No! → No-No! 2.m4a (529 KB, ~65.6 s)  ← Mark to confirm this is the right take by listening
Verified via API: distinct `audioDuration` per kitten.

### iPad app-icon warnings (pre-existing)

Asset compilation emits two warnings about missing 76x76@2x and 83.5x83.5@2x iPad icons. Not fixed in the API PR per CLAUDE.md ("App icon: complete"). Options: add the missing slot images, or mark the app iPhone-only (`TARGETED_DEVICE_FAMILY = "1"`).

---

## Parked / Later

- Per-kitten haptic pattern variation (Floozy vs Nacho vs No-No! feel different)
- Improved audio recordings (only if Mark decides to re-record — not a priority)
- iPad support
- Widget / Lock Screen presence
- Apple Watch companion (feel the purr on your wrist)

---

**Note:** Update this file after every meaningful session. It is the live state of the project.
