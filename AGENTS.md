# AGENTS.md

Guidance for AI coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

Keep this file current: any PR that changes a convention, decision, or command documented here updates this file in the same PR.

## Project

Conquer Hills is a proof-of-concept iPhone app that simulates the elevation profile of a real running course on a treadmill. The app does not control the treadmill; it estimates the runner's position on the course from the speed they enter and prompts them to change the incline manually.

## Workflow

1. The product is described in `specs/high-level-spec.md` (local only, gitignored).
2. Each piece of work gets a detailed spec in `specs/NN-name.md` (local only, gitignored). Decisions are logged in `specs/decisions.md`. The owner reviews and approves the spec before any code is written. `specs/` exists only in the main checkout, not in worktrees.
3. **Never work in the main checkout.** It stays on `main` and may be in use concurrently. Do all branch work in a git worktree under `.scratch/worktrees/<branch-name>`:
   ```sh
   git worktree add .scratch/worktrees/01-foundation -b 01-foundation
   cd .scratch/worktrees/01-foundation && make bootstrap
   ```
4. Branches are named `NN-short-name` after their spec (follow-ups: `NN-short-name-topic`). `main` is protected: all changes go through a pull request, and merging requires the CI `check` job to pass with the branch up to date.
5. Run `make check` before opening a PR. A PR isn't ready for review until CI is green. PR descriptions cover: summary, what changed, decisions made, how it was tested, anything deferred.
6. Merge only when the owner says so, and in this order:
   1. Move anything untracked you need to keep out of the worktree first.
   2. `gh pr merge <n> --squash`. **Do not pass `--delete-branch`**: it also deletes the local worktree directory, including untracked files. GitHub deletes the remote branch automatically.
   3. In the main checkout: `git pull --ff-only`.
   4. `git worktree remove .scratch/worktrees/<branch-name>` (add `--force` for generated files) and `git branch -D <branch-name>`.
7. Uncommitted working files go in `.scratch/` (gitignored).
8. Product and architecture decisions are made by the owner. Agents surface open decisions with a recommendation and wait; they do not decide silently.
9. This is a public repository. Do not commit personal information, signing team IDs, or other private configuration.

## Decisions

Decisions are recorded in the local decision ledger, `specs/decisions.md` (gitignored). Durable conventions that follow from them are documented in this file.

## Tech stack

- Swift 6 (language mode 6, complete concurrency checking), SwiftUI, iOS 26+, iPhone only, portrait only.
- The app target defaults to `MainActor` isolation. Package code is nonisolated; model types are `Sendable` value types.
- Tests use Swift Testing (`import Testing`), not XCTest.
- No third-party dependencies. Tooling: Xcode 27, XcodeGen, `swift format` (in the Xcode toolchain).
- Units: miles and mph for display; incline in percent.

## Layout

```
project.yml                  XcodeGen definition of the Xcode project (source of truth)
Makefile                     all commands
.swift-format                formatter/linter config (line length 120)
Config/Shared.xcconfig       committed; optionally includes Local.xcconfig
Config/Local.xcconfig        gitignored; DEVELOPMENT_TEAM for device builds
App/Sources/                 SwiftUI app target: thin UI layer only
App/Resources/               asset catalog
App/Resources/Courses/       bundled course files (<id>.course.json); see docs/course-format.md
docs/                        reference docs (course-format.md: the course file schema)
.github/workflows/ci.yml     CI: runs `make check` on PRs and pushes to main
Tools/                       developer scripts (e.g. make-app-icon.swift regenerates the app icon)
Packages/ConquerHillsKit/    all non-UI logic, as a local Swift package
  Sources/CourseKit/         course model, bundled data loading, validation
  Sources/WorkoutKit/        workout engine: progress, prompts, pause/resume, run record (depends on CourseKit)
  Tests/                     one test target per module
```

Logic goes in the package, not the app target, so it can be tested with `swift test` without a simulator. `CourseKit` must not depend on `WorkoutKit`.

## Course data

- Course files follow [docs/course-format.md](docs/course-format.md). Change the schema only with a `schemaVersion` bump and a doc update in the same PR.
- Distances are meters everywhere in data and logic; convert to miles only for display.
- Files store the signed *course incline*. `TreadmillSettings` (baseline, limits, step) turns it into *treadmill incline* on the phone; `TreadmillProfile` applies that to a segment and is what the workout engine consumes. Defaults match the owner's Peloton Tread: 0–12.5% in 0.5% steps, 0% baseline.
- `CourseLoaderTests` validates every file in `App/Resources/Courses/`, so an invalid course fails `make check`.
- `App/Resources/Courses/` is bundled as a folder: the app finds courses at `Bundle.main` `Courses/`.

## Workout engine

- `Workout` (WorkoutKit) is a value type that **never reads a clock**. Every call passes the current time as a `Duration` on the app's clock (read from `ContinuousClock`, which keeps counting while the phone sleeps). Each call first catches up to that time, then applies the command, and returns the events due since the last call, in order, each with its due time and an `isLate` flag.
- Distance is speed × running time, summed per stretch at one speed; pauses and the countdown add nothing. Speeds are `Speed.mph(_:)`: 0.5–12.5 mph in 0.1 steps (Peloton Tread). Stopping is Pause, not 0 mph.
- Event rules: each incline change gets at most one warning (`upcomingChange`, 10 s ahead at the current speed, skipped if under 3 s remain) and exactly one `inclineChange`; a final change held under 15 s before the finish is skipped; `resumed` repeats the current incline. Calls that don't fit the current state are ignored, never crash.
- All timings live in `WorkoutConfiguration` (`.standard`), so treadmill testing can tune them in one place.
- `Workout` and `WorkoutRecord` are `Codable`: the record is what the completion summary shows and run history will store; the whole workout can be saved and restored mid-run.
- The app owns the tick (e.g. every 0.25 s) and the clock; it calls `advance(to:)` and renders `snapshot(at:)`. Engine tests use explicit times, never a real clock.

## Xcode project

`ConquerHills.xcodeproj` is generated by XcodeGen and gitignored. Change targets, build settings, or Info.plist keys (`INFOPLIST_KEY_*` settings; there is no Info.plist file) in `project.yml`, never in Xcode's project editor; run `make generate` after editing `project.yml` or pulling changes to it. New source files under `App/Sources` and `App/Resources` are picked up on regeneration.

## Commands

| Command | Does |
| --- | --- |
| `make bootstrap` | Checks Xcode and XcodeGen; creates `Config/Local.xcconfig` (in a worktree, links the main checkout's copy); generates the project |
| `make generate` | Regenerates the Xcode project from `project.yml` |
| `make open` | Opens the project in Xcode, regenerating if `project.yml` changed |
| `make test` | `swift test` for the package (fast, runs on macOS) |
| `make build` | Builds the app for the iOS Simulator without signing |
| `make format` | Formats Swift sources in place |
| `make lint` | Fails on any formatting violation |
| `make check` | `lint` + `test` + `build`; required before a PR, and exactly what CI runs |

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs one job, `check`: install XcodeGen, `make bootstrap`, `make check`. It runs on every pull request to `main` and every push to `main`, on the `xcode-27` runner image (a GitHub public preview; move to the GA label when one exists). CI has no signing team, so builds are unsigned simulator builds.

If CI fails but `make check` passes locally, suspect a toolchain difference first: the job prints `xcodebuild -version` and `swift --version`.
