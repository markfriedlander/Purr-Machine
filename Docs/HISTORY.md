# HISTORY.md — Purr Machine
**Chronicle of All Work**
**Started: May 2026**

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
