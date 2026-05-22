# NEXT.md — Purr Machine
**Current State and Immediate Next Steps**
**Last Updated: May 2026**

---

## Current State — Submitted for App Store Review

**Purr Machine 1.0 (1) is in Apple's review queue as of 2026-05-22 ~4:51 PM PT.** ETA up to 48 hours; Mark will get email when review completes. See HISTORY.md for full submission details.

Marketing site live at https://markfriedlander.github.io/Purr-Machine/.

Local path: `/Users/markfriedlander/Desktop/Fun/Purr Machine`.

**The app, as shipped:**
- Three real cats (Floozy/Nacho/No-No!) with their actual recordings, seamlessly looped with equal-power crossfade
- Per-cat haptic profiles drawn from each recording's measured breath cycle (autocorrelation); per-cat heart rate, purr intensity, sharpness
- Two-player CoreHaptics architecture (purr + heartbeat) running simultaneously
- Vignetted face crops fade in above the kitten buttons on selection
- Sleep timer (10/20/30/∞); audio continues under lock; haptic resumes on unlock
- LocalAPIServer compiled out of Release
- iPhone only; no data collection; no subscription; free

---

## Immediate Next Steps — In Order

### Step 0 — Wait for Apple Review (in progress)
Submitted 2026-05-22 ~4:51 PM PT. ETA up to 48 hours. Mark gets email when complete. If Apple rejects, address feedback and resubmit. If approved, decide manual vs automatic release.

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

### Step 6 — App Store Prep ✅ DONE 2026-05-22

- Privacy policy page ✅ at https://markfriedlander.github.io/Purr-Machine/privacy.html
- Support page ✅ at https://markfriedlander.github.io/Purr-Machine/support.html
- Marketing index page ✅ at https://markfriedlander.github.io/Purr-Machine/
- App Store screenshots ✅ (3 captured, resized to 1242×2688)
- App description / metadata ✅ submitted
- Clean Release build (zero warnings) ✅
- Archive + upload ✅ via Xcode Organizer
- Submit for Review ✅ in Apple's queue

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
