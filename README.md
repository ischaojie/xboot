# xboot

[![CI](https://github.com/ischaojie/xboot/actions/workflows/ci.yml/badge.svg)](https://github.com/ischaojie/xboot/actions/workflows/ci.yml)

A Dock app with one row per target, that builds and runs it without opening Xcode.

## Why

Xcode is a 3.8 GB IDE whose GUI costs seconds of launch time and gigabytes of memory
just to press Run. xboot replaces that with a single window: pick a project, pick a
device next to the target you want, click Run. The build itself still goes through `xcodebuild` — that is unavoidable —
but the editor, the indexer, and the IDE chrome are not started.

## How

xboot is a thin GUI over [`mobilebuildmcp`](https://www.mobilebuildmcp.com/):

```
xboot  ──  mobilebuildmcp simulator build-and-run --output jsonl  ──  xcodebuild + simctl
  ▲                │
  └──  structured JSONL events (build stages, compiler diagnostics, summary)
```

The CLI is the only backend. All build/simulator logic, derived data management,
and error parsing live there; xboot renders the event stream as a progress state
and a readable error list.

## Hard constraints

- **Never write to the project being run.** All state lives in
  `~/Library/Developer/MobileBuildMCP/` (owned by the CLI) and in
  `~/Library/Preferences/com.shanxiao.xboot.plist` (owned by xboot).
- **Never call `mobilebuildmcp setup`.** It writes `.mobilebuildmcp/config.yaml`
  into the project directory, which violates the previous rule. Every parameter
  is passed as a command-line flag instead.
- **No Xcode project for xboot itself.** Built with a `Makefile` + `clang`; the
  whole app is 140 KB and takes under a second to compile.

## Install

Download `xboot-*.zip` from [Releases](../../releases), unzip, and move `xboot.app`
to `/Applications`. Releases are signed with a Developer ID certificate and notarized
by Apple, so they launch with no Gatekeeper prompt.

Builds from source are ad-hoc signed; run them locally or clear the quarantine
attribute yourself.

Requires [`mobilebuildmcp`](https://www.mobilebuildmcp.com/):

```sh
brew install getsentry/xcodebuildmcp/mobilebuildmcp
```

## Build

```sh
make          # clang + manual .app assembly + ad-hoc codesign
make run      # build and launch
make test     # unit tests (no XCTest dependency)
make icon     # regenerate Resources/xboot.icns from tools/IconGen.m
```

The icon is drawn in Core Graphics (`tools/IconGen.m`): a blue tile with a hammer
whose head tapers into a play arrow. Regenerating it is a build step, not a binary
asset in the repo.

Requires `mobilebuildmcp` on `$PATH` (`brew install getsentry/xcodebuildmcp/mobilebuildmcp`).

## What it does

- Lists every scheme of a project as a row, with per-target device selection and a Run
  button.
- Probes each scheme's `PLATFORM_NAME` / `WRAPPER_EXTENSION` in the background and
  labels non-runnable ones (`aggregate`, `extension`, `framework`) instead of pretending
  they can run.
- Routes runnable schemes to `simulator build-and-run`, `device build-and-run` or
  `macos build-and-run` automatically; macOS targets hide the device picker.
- Lists connected iPhones / iPads under a 真机 section at the top of the device picker,
  re-listed each time the app is brought forward. Signing is whatever the project has
  configured; xboot passes no signing flags.
- Remembers a simulator per target, stream stage / phase / compiler errors into the row
  and the error pane below.
- One build at a time across the app; other rows are disabled while a build runs.
- Streams `build-stage` / `phase` / `compiler-diagnostic` / `build-summary` events
  into a stage label and an error list.
- Cancels and restarts the current build when Run is pressed twice.
- Builds at most one project at a time across the app.

## Not in this version

Runtime log streaming, breakpoints, hot reload, UI automation,
notifications, global hotkeys. Each was considered and deferred; see the
discussion in the commit history.

Multi-platform projects whose schemes differ per platform work, but a scheme that
is an aggregate (builds no app) will fail at build time — pick a concrete scheme.

## Layout

```
tools/  IconGen.m              icon generator (Core Graphics -> .iconset -> .icns)
Sources/
  main.m
  MBTAppDelegate.m           app lifecycle, main menu
  MBTMainWindowController.m  window, one row per target
  MBTBuildRunner.m           NSTask + streaming JSONL
  MBTBuildEvent.m            event parsing
  MBTLineBuffer.m            newline framing across pipe chunks
  MBTCLI.m                   list-schemes / list simulators and devices
  MBTProject{,Store}.m       recent projects, persisted in NSUserDefaults
  MBTTarget.m                one runnable scheme per project + its device
Tests/
  MBTTests.m                 parser, line buffer, store
```
