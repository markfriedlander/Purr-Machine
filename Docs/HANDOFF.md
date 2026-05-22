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

**Device:** To be filled in once API is set up  
**API host:** TBD  
**API port:** TBD  
**API token:** TBD  

---

## What Is Done

- v0 code: working audio playback, basic haptics, sleep timer, kitten selection
- App icon: complete (meditating cat in lotus position)
- GitHub repo: created
- Document system: established (this session)
- Strategy: agreed (see HISTORY.md 2026-05-21)

## What Is Not Done (in priority order)

1. **API** — build first, before anything else
2. **Haptic research** — cat physiology + CoreHaptics capabilities
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
