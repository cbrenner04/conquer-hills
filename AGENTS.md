# AGENTS.md

Guidance for AI coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

Keep this file current: any PR that changes a convention, decision, or command documented here updates this file in the same PR.

## Project

Conquer Hills is a proof-of-concept iPhone app that simulates the elevation profile of a real running course on a treadmill. The app does not control the treadmill; it estimates the runner's position on the course from the speed they enter and prompts them to change the incline manually.

## Workflow

1. The product is described in `specs/high-level-spec.md` (local only, gitignored).
2. Each piece of work gets a detailed spec in `specs/NN-name.md` (local only, gitignored). Decisions are logged in `specs/decisions.md`. The owner reviews and approves the spec before any code is written.
3. Work is built on a feature branch off `main` and submitted as a pull request for review.
4. Uncommitted working files go in `.scratch/` (gitignored). Git worktrees go in `.scratch/worktrees/<branch-name>` (e.g. `git worktree add .scratch/worktrees/my-feature -b my-feature`).
5. Product and architecture decisions are made by the owner. Agents surface open decisions with a recommendation and wait; they do not decide silently.
6. This is a public repository. Do not commit personal information, signing team IDs, or other private configuration.

## Decisions

Decisions are recorded in the local decision ledger, `specs/decisions.md` (gitignored). Durable conventions that follow from them are documented in this file.

## Tech stack, layout, and commands

To be filled in once the foundation spec is approved.
