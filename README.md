# Conquer Hills

[![CI](https://github.com/cbrenner04/conquer-hills/actions/workflows/ci.yml/badge.svg)](https://github.com/cbrenner04/conquer-hills/actions/workflows/ci.yml)

An iPhone app for running a real race course's hills on a treadmill. Pick a course, enter your treadmill speed, and the app tracks where you are on the course and tells you when to change the incline.

The app doesn't connect to or control the treadmill: you change the incline yourself when prompted.

**Status:** early proof of concept, under active development.

## Requirements

- Xcode 27 (iOS 26 SDK or later)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

```sh
make bootstrap   # checks tools, creates Config/Local.xcconfig, generates the Xcode project
make check       # lint, package tests, and a simulator build
make open        # open in Xcode
```

To run on a physical iPhone, set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig` to your Apple Developer team ID. That file is gitignored.

The Xcode project is generated from `project.yml`. Edit that file rather than the project in Xcode, and run `make generate` after changing it.

## Contributing

Conventions, layout, and commands are documented in [AGENTS.md](AGENTS.md).
