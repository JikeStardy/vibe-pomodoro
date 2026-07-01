# vibe-pomodoro

vibe-pomodoro is a macOS menu-bar agent application (`LSUIElement = true`) that renders a Pomodoro timer directly inside the MacBook hardware notch. It uses a borderless `NSPanel` anchored to the top of each display and grows downward, visually fusing with the system notch. Beyond the timer, the app integrates with **Claude Code CLI** and **OpenAI Codex CLI** via shell hooks: a Python hook script sends session events over a Unix domain socket to the app, which surfaces permission-approval prompts and activity notifications inside the notch — so you can approve or deny Claude Code tool permissions without leaving your editor.

## Key Features

- **In-notch Pomodoro timer** — compact countdown, full expanded control panel, and break-prompt overlay rendered as a Dynamic-Island-style black pill.
- **Claude Code / Codex CLI hook integration** — auto-installs hook scripts on first launch; receives real-time session events (tool use, permission requests, compaction, subagents, etc.) via a Unix domain socket.
- **In-notch permission approval** — when Claude Code requests a tool-use permission, the notch expands an approval UI; your decision is sent back synchronously to the hook, which returns the allow/deny verdict to Claude Code.
- **Multi-display support** — creates one notch window per selected display; reacts to screen connect/disconnect dynamically.
- **State priority system** — a deterministic priority resolver merges timer state, Claude phase, settings, and hover into a single display state, preventing UI conflicts.
- **Zero external dependencies** — the entire app uses only Swift, SwiftUI, AppKit, Combine, and `UserNotifications`. No SPM third-party packages.
- **Session tracking & stats** — persists completed sessions to `UserDefaults` and surfaces today's focus minutes, break minutes, and completed sessions.
- **Configurable** — work/break durations, round counts, auto-start toggles, notch gap width, and per-display selection are all adjustable from the in-notch settings panel.

## Technology Summary

| Aspect | Detail |
|---|---|
| Language | Swift 5.9 (tools version); toolchain Apple Swift 6.3+ |
| UI | SwiftUI + AppKit interop (`NSPanel`, `NSHostingController`) |
| Reactive | Combine framework (`@Published`, `Publishers.CombineLatest4`) |
| Platform | macOS 13 Ventura+ |
| Dependencies | None (zero external packages) |
| Build | Swift Package Manager (single executable target) |
| Persistence | `UserDefaults` only (keys: `pomodoro_config`, `pomodoro_sessions`) |
| IPC | Unix domain socket at `/tmp/vibe-pomodoro-claude.sock` |
| Hook runtime | Python 3.x (auto-detected) |

## Table of Contents

| Document | Description |
|---|---|
| [index.md](index.md) | This file — project overview, features, tech summary, and quick start. |
| [architecture.md](architecture.md) | High-level architecture, component diagram, MVVM pattern, Combine reactive pipeline, state priority system, window strategy, persistence, and design decisions. |
| [tech-stack.md](tech-stack.md) | Detailed technology stack — language, frameworks, deployment target, dependencies, build system, resources, entitlements, Info.plist, Python, and socket. |
| [project-structure.md](project-structure.md) | Full directory tree, file inventory table with line counts and purposes, directory roles, and known issues. |
| [models.md](models.md) | Complete data model reference — all structs, enums, and classes in PomodoroModels.swift and ClaudeModels.swift with properties, defaults, and relationships. |
| [timer-engine.md](timer-engine.md) | PomodoroTimer state machine — all @Published properties, methods, timer mechanism, persistence, state transitions, and auto-start logic. |
| [window-system.md](window-system.md) | Window management — NotchDisplayState, NotchViewModel, NotchWindowController, NotchWindow, NotchDisplayManager, and multi-display coordination. |
| [ui-design.md](ui-design.md) | UI/UX design — NotchShape, all 7 display states, layouts, gestures, animations, style tokens, and the physical notch occlusion rule. |
| [hook-system.md](hook-system.md) | Complete hook system — HookInstaller, Python script, HookSocketServer, ClaudeSessionManager, event flow diagrams, data contracts, and known limitations. |
| [coding-conventions.md](coding-conventions.md) | Code conventions — Swift style, naming, architecture patterns, UI conventions, error handling, persistence, security, and file organization. |
| [build-deploy.md](build-deploy.md) | Build and deployment guide — prerequisites, debug/release builds, app bundling, installation, hook auto-installation, and verification steps. |

## Quick Start

### Prerequisites

- macOS 13 Ventura or later
- Xcode or a standalone Swift toolchain (`swift --version` should report 5.9+)
- Python 3.x available at `/usr/bin/python3`, `/usr/local/bin/python3`, or `/opt/homebrew/bin/python3`
- Claude Code CLI and/or OpenAI Codex CLI (optional, for hook integration)

### Debug build & run

```bash
swift build
swift run
```

> **Note:** Running via `swift run` executes outside a `.app` bundle, so macOS will **not** present the notification permission dialog. System notifications (work-complete alerts) won't fire. For full functionality including notifications, build the app bundle.

### Release build & app bundle

```bash
swift build -c release
./build.sh
open .build/release/VibePomodoro.app
```

### Install to /Applications

```bash
cp -r .build/release/VibePomodoro.app /Applications/
open /Applications/VibePomodoro.app
```

On first launch the app automatically:
1. Requests notification authorization.
2. Installs the Python hook script to `~/.claude/hooks/vibe-pomodoro-hook.py`.
3. Registers hook entries in `~/.claude/settings.json` and `~/.codex/hooks.json`.
4. Starts the Unix domain socket server at `/tmp/vibe-pomodoro-claude.sock`.

See [build-deploy.md](build-deploy.md) for details and verification steps.
