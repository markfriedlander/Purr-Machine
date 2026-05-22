# CLAUDE.md — Purr Machine
**Operational Reference for Claude Code**
**Last Updated: May 2026**

---

## What This Project Actually Is

Purr Machine simulates the physical comfort of a purring cat. The phone lies on your chest. The Taptic engine vibrates. The real recordings of real cats play. The goal is to feel — not just hear — a cat purring on you.

This is a deeply personal project. The three cats are:
- **Nacho** — orange tabby, Heather's cat in Atlanta. Still with us. Mark is in LA and misses him.
- **No-No!** — grey tabby, Heather's other cat. Recently passed from cancer.
- **Floozy** — long-haired tortoiseshell with green eyes, Mark's parents' cat. Recently passed from cancer.

The audio recordings are of the actual cats. They are imperfect recordings and that is intentional and irreplaceable. Do not suggest replacing, processing, or "improving" them. They are the point.

The haptic experience is the soul of the app. Getting it right means the phone actually feels like a cat — not just vibrates. Multiple simultaneous rhythms: purr, breathing, heartbeat. This is the hardest problem and the most important one.

Keep this in mind on every decision. When in doubt: does this make the phone feel more like a cat?

---

## Two Standing Rules — Read Before Anything Else

### Rule 1 — Search Before You Fail Twice

If you don't know how to solve something, **search the web for the proven pattern before your second failed attempt**. Do not write a third guess. Do not iterate on your own intuition past the second attempt. The second failure is the signal that you don't know the answer; the response is to find it, not to keep guessing.

This applies especially to:
- CoreHaptics / CHHapticEngine behavior (poorly documented, many quirks)
- Taptic engine capabilities and limits on specific iPhone hardware
- AVFoundation audio session management
- Any "I think this is how it works" hunch that turns out to be wrong once

The Taptic engine is notoriously under-documented. When something doesn't work, search first. Apple WWDC sessions, developer forums, and open-source haptic libraries are all fair game.

### Rule 2 — Two Pieces of Hardware Before You Commit

Do not commit any change that touches haptic or audio behavior until you have verified it on the **connected iPhone** (not just simulator). Haptics do not run in the simulator. This is non-negotiable for this project — the entire experience is physical and can only be evaluated on real hardware.

For UI-only changes: simulator + iPhone. For haptic changes: iPhone only, and Mark must feel it.

Do not declare a haptic pattern "working" based on logs or lack of errors. The only verification is: does it feel right?

### Rule 3 — Resize Screenshots Before Reading Them Into Context

All screenshots must be resized to ≤300px wide before being read into context. Run `sips -Z 300 <file>.png` immediately after any screenshot capture. Never read a full-resolution screenshot directly.

### Rule 4 — Zero Warnings, Zero Errors, Always

The bar is zero warnings, zero errors on every commit. Run a clean Release build before declaring any feature done. A warning is a real defect. Fix it before committing.

---

## The API — First-Class Citizen

The iPhone API is as important as the user-facing app. It should be set up before any feature work and treated as a core part of the product, not an afterthought.

**Golden rule: there should be no difference between what a human can experience with the app and what Claude Code can read from the app. The hope is that CC can actually see more.**

This means:
- Every user-visible state should be queryable via the API
- Every user action should be triggerable via the API
- Haptic intensity, audio playback position, timer state, selected cat — all readable
- Kitten selection, play/stop, timer control — all triggerable
- If CC needs information that the API doesn't expose, **add the verb immediately** — don't work around it

The API enables CC to iterate on haptic patterns autonomously: trigger a pattern, query what's happening, adjust, repeat. This is the core development loop for haptics. Do not skip it.

---

## Haptics — The Hard Problem

CoreHaptics and the Taptic engine have significant quirks. Known issues from prior work on this project:
- Stopping and recreating the haptic player every 0.25 seconds causes stuttering
- Engine restart sequences are fragile
- Pattern timing drifts

The target experience is **layered simultaneous rhythms**:
1. **Purr** — the primary low-frequency rumble, ~25Hz, rhythmic cycles
2. **Breathing** — slow rise and fall, ~4–6 second cycle
3. **Heartbeat** — subtle double-pulse, ~60–80 BPM

Research cat purr physiology before implementing. Real cat purrs are 25–50Hz with inhale/exhale variation. The breathing and heartbeat layers must feel subordinate to the purr, not compete with it.

When a haptic pattern doesn't feel right, search for prior art before iterating blindly. WWDC sessions on CoreHaptics, Apple's Haptic Design documentation, and open-source haptic pattern libraries are good starting points.

**Mark must feel every haptic change on his actual phone before it is committed.**

---

## Three Hats — Developer, QA, and User

Before declaring any feature done, wear three hats:

**Hat 1 — Developer:** Did it build? Zero warnings? Architecture correct?

**Hat 2 — QA:** Does it actually work? Did I try to break it? Did I test edges and error cases?

**Hat 3 — User:** Lie down. Put the phone on your chest. Close your eyes. Does it feel like a cat? That is the only test that matters for this app.

All three must pass before any feature is done.

---

## The LEGO Block System

All Swift files use clearly bounded, numbered sections:
```swift
// ========== BLOCK [N]: [DESCRIPTION] - START ==========
[code]
// ========== BLOCK [N]: [DESCRIPTION] - END ==========
```

Maximum ~100 lines per block. Optimal 50–75. This enables surgical edits and prevents corruption in large files. Preserve this in all new and edited files.

---

## How We Work Together

**Golden rules:**
1. Discussion before code — explain your plan, get approval, then implement
2. Complete implementations only — no stubs, no placeholders
3. No assumptions — if something is unclear, ask
4. Read the relevant code before proposing changes to it
5. Commit and push to GitHub immediately — commit and push are one action

**Starting a session:**
1. Read this file
2. Read NEXT.md and HISTORY.md
3. Ask Mark what we're working on, or share your read of what needs attention
4. If touching existing code, read it first
5. Explain your plan before writing code
6. Wait for explicit go-ahead before implementing consequential changes

**After every meaningful commit:**
- Update HISTORY.md with what was done and why
- Update NEXT.md if any planned item's status changed
- Push to `origin/main` immediately

**Ending a session:**
- Confirm HISTORY.md and NEXT.md are current
- Commit and push

---

## Build + Deploy

```bash
# Build
xcodebuild build \
  -project "/Users/markfriedlander/Desktop/Fun/Purr Machine/Purr Machine.xcodeproj" \
  -scheme "Purr Machine" \
  -destination "id=<DEVICE_UDID>" \
  -configuration Debug

# Install
xcrun devicectl device install app --device <DEVICE_UDID> \
  "<DERIVED_DATA_PATH>/Build/Products/Debug-iphoneos/Purr Machine.app"

# Launch
xcrun devicectl device process launch --device <DEVICE_UDID> com.MarkFriedlander.PurrMachine
```

Device UDID and API details to be filled in once API is established — update this file when they are known.

---

## Project Structure

```
Purr Machine/
├── ViewController.swift     — All UI and logic (single-file for now)
├── AppDelegate.swift
├── SceneDelegate.swift
├── Purr1.m4a               — Floozy recording (Mark's parents' cat)
├── Purr2.m4a               — Nacho recording (Heather's cat, Atlanta)
├── Purr3.m4a               — No-No! recording (Heather's cat, passed)
└── Assets.xcassets/        — App icon (meditating cat, already done)

Docs/
├── CLAUDE.md               — This file
├── NEXT.md                 — Current state and immediate next steps
├── HISTORY.md              — Chronicle of all work
└── HANDOFF.md              — State preservation for context loss
```

---

## What We Don't Want

- Touching the audio recordings — they are the real cats, they stay as-is
- Wholesale rewrites when surgical changes would do
- Code written before direction is agreed on for consequential changes
- Assumptions about state, intent, or anything not directly observable
- Haptic patterns committed without Mark feeling them on his phone
- The API treated as optional or deferred

---

**Status:** Living document. Update as the project evolves.
