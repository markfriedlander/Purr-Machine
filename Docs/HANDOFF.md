# HANDOFF.md — Purr Machine
**State Preservation for Context Loss**
**Last Updated: May 2026**

---

## Purpose

This document exists in case Claude Code loses context or a new CC session starts cold. It contains the minimum information needed to resume without losing ground. Read CLAUDE.md first, then this file, then NEXT.md.

---

## The Project in One Paragraph

Purr Machine makes your iPhone feel like a purring cat lying on your chest. Three kitten buttons select between recordings of three real cats: Floozy (Mark's parents' cat, passed from cancer), No-No! (Heather's cat, passed from cancer), and Nacho (Heather's cat, still alive in Atlanta — Mark is in LA and misses him). The Taptic engine provides haptic feedback layered to simulate purr + breathing + heartbeat simultaneously. This is deeply personal, not just a novelty app.

---

## Current State Snapshot

**Repo:** https://github.com/markfriedlander/Purr-Machine  
**Local:** `/Users/markfriedlander/Desktop/Fun/Purr Machine`  
**Main file:** `ViewController.swift` — single file, all logic  
**API:** Not yet established (first priority for CC)

**Device:** Pending — Mark to share UDID via `xcrun devicectl list devices`
**API host:** the iPhone's local Wi-Fi IP (printed by the app on launch)
**API port:** 8767
**API token:** generated on first launch, persisted in Keychain, printed/pasteboarded on every launch
**Bundle ID:** `com.HeatherAndMark.PurrMachine.Purr-Machine`

---

## What Is Done

- v0 code: working audio playback, basic haptics, sleep timer, kitten selection
- App icon: complete (meditating cat in lotus position)
- GitHub repo: created and connected (two commits on `origin/main`)
- Document system: established
- Strategy: agreed (see HISTORY.md 2026-05-21)
- **LocalAPIServer**: port 8767, verified end-to-end on Mark's iPhone 16 Plus over Wi-Fi (see HISTORY.md 2026-05-21). DEBUG antenna toggle + alert dialog + clipboard + Documents file.
- **AppState extraction**: ViewController is now a thin view over `AppState.shared`. UI behavior unchanged.
- **Bundled audio**: corrected — Floozy/Nacho/No-No! now each play their own real recording (see HISTORY.md 2026-05-21).
- **Haptic Phase A**: two-player architecture (purr+breathing as one looped player with parameter curve; heartbeat as a second looped player). Per-cat breath cycles measured from each recording via autocorrelation. Engine kept warm. API extended (named players, loop, schema reconciliation). All Phase A QA passed. See HISTORY.md 2026-05-22.

## What Is Not Done (in priority order)

1. **Mark listens to confirm No-No! take #2 is the right recording** (vs #1 or #3)
2. **Haptic Phase B — tuning with Mark on chest.** Drive `/haptics/dynamic` + `/haptics/pattern` live based on Mark's feedback. No haptic commit without his confirmation.
3. **Haptic pattern design** — written design reviewed by Mark before code
4. **Layered haptic implementation** — purr + breathing + heartbeat simultaneously
5. **Audio loop verification** — check for click artifacts at loop points
6. **LEGO block refactor** — structural only, no behavior change
7. **App Store prep** — screenshots, metadata, privacy policy, submission

---

## Critical Context That Must Not Be Lost

- **The audio recordings are of the actual cats and are not to be altered.** They are imperfect. That is intentional. Do not suggest re-recording, normalizing, processing, or replacing them.

- **Haptics are the soul of the app.** The current haptic implementation (stop/restart player every 0.25s, single continuous buzz) is known-broken. Do not build on it — redesign it after the research phase.

- **The API is first-class.** It must be built before feature work. CC's ability to feel the haptics through telemetry and trigger patterns autonomously is core to the development loop.

- **Mark must feel every haptic change on his actual phone before it is committed.** The simulator cannot run haptics. There is no other verification.

- **CHHapticDynamicParameter** is likely the right approach for real-time intensity updates — it avoids stop/restart. Research this before implementing.

---

## Key Decisions Made

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-21 | API first, before feature work | Learned from Hal/Posey — retrofitting is always expensive |
| 2026-05-21 | Research before haptic code | Taptic engine has quirks; need to understand capabilities before designing |
| 2026-05-21 | Audio recordings preserved as-is | They are the real cats. Irreplaceable. |
| 2026-05-21 | Three layered haptic rhythms target | Purr + breathing + heartbeat = most realistic cat simulation |

---

## How to Resume

1. Read CLAUDE.md
2. Read this file
3. Read NEXT.md (Step 1 is API setup)
4. Check git log to see what's been committed since this file was last updated
5. Ask Mark what's changed or what he wants to work on
6. Do not write haptic code until the research phase (NEXT.md Step 2) is complete

---

**Update this file whenever the project state changes significantly.**
