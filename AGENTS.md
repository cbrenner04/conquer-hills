# AGENTS.md

Guidance for AI coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

Keep this file current: any PR that changes a convention, decision, or command documented here updates this file in the same PR.

## Project

Conquer Hills is a proof-of-concept iPhone app that simulates the elevation profile of a real running course on a treadmill. The app does not control the treadmill; it estimates the runner's position on the course from the speed they enter and prompts them to change the incline manually.

## Workflow

1. The product is described in `high-level-spec.md` (local only, gitignored).
2. Each piece of work gets a detailed spec in `specs/NN-name.md` (local only, gitignored). The owner reviews and approves the spec before any code is written.
3. Work is built on a feature branch off `main` and submitted as a pull request for review.
4. Uncommitted working files go in `.scratch/` (gitignored). Git worktrees go in `.scratch/worktrees/<branch-name>` (e.g. `git worktree add .scratch/worktrees/my-feature -b my-feature`).
5. Product and architecture decisions are made by the owner. Agents surface open decisions with a recommendation and wait; they do not decide silently.
6. This is a public repository. Do not commit personal information, signing team IDs, or other private configuration.

## Decisions log

| Area | Decision | Date |
| --- | --- | --- |
| Version control | Git, default branch `main`; public GitHub repo; spec files gitignored | 2026-10-06 |
| Local scratch | `.scratch/` is gitignored; worktrees live in `.scratch/worktrees/` | 2026-10-06 |
| Platform | Native Swift + SwiftUI; minimum iOS 26; iPhone only | 2026-10-06 |
| Architecture | Course model, incline processing, and workout engine live in a local Swift package with no UI dependency, testable with `swift test`; the app target is a thin SwiftUI layer | 2026-10-06 |
| Distribution | Paid Apple Developer account; run on a small number of personal devices | 2026-10-06 |
| Device usage | Screen kept awake while the app is in the foreground. Background/lock-screen operation is deferred | 2026-10-06 |
| Course data | Best effort from public data. Generated offline in this repo and bundled with the app; no backend. Keep the app light | 2026-10-06 |
| Delivery order | Thin end-to-end slice testable on a treadmill first, then broaden | 2026-10-06 |
| Initial courses | London Marathon, Boston Marathon, and a synthetic test course (development builds only) | 2026-10-06 |
| Progress tracking | Runner enters treadmill speed and updates it in the app when they change speed on the treadmill; distance accumulates per speed interval. Distance correction deferred | 2026-10-06 |
| Units | Imperial: miles and mph. Incline in percent | 2026-10-06 |
| Incline meaning | Smoothed approximation of course grade: 0.5% rounding, clamped to 0–15%, downhills clamp to 0%, minimum interval between changes. Generated offline and reviewed. Training-oriented transforms are a later idea | 2026-10-06 |
| Prompts | Advance warning ~10 s before a change (time-based at current speed), then a prompt at the change. Spoken + visual primary; haptics secondary | 2026-10-06 |
| Segment selection | Numeric steppers in 0.1 mi increments with the segment highlighted on the profile; predefined segments (auto halves/first & final 5K plus curated) | 2026-10-06 |
| Course metadata | Name, location, year, distance, elevation gain/loss, min/max elevation, source, accuracy disclaimer | 2026-10-06 |
| Run start/finish | 3-2-1 countdown to align with the treadmill. Completion summary shown; saving run data for later review is wanted (scope TBD) | 2026-10-06 |

## Tech stack, layout, and commands

To be filled in once the foundation spec is approved.
