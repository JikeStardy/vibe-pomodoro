# Technology Stack

## Language

| Property | Value |
|---|---|
| Swift tools version | **5.9** (declared in `Package.swift` line 1: `// swift-tools-version:5.9`) |
| Actual toolchain | Apple Swift 6.3+ (the project compiles on modern toolchains while maintaining 5.9 compatibility) |
| Concurrency | Uses `@unchecked Sendable`, `nonisolated(unsafe)`, and `Sendable` conformances for thread-safe model types |

## UI Framework

The app uses **SwiftUI + AppKit interop**:

- **SwiftUI** — declarative UI for all notch content (`NotchView`, `NotchRootView`, shapes, animations, settings controls). This is the primary rendering layer.
- **AppKit** — provides the windowing substrate:
  - `NSPanel` (subclass `NotchWindow`) — borderless, non-activating panel positioned at the notch.
  - `NSWindowController` (subclass `NotchWindowController`) — manages window lifecycle, positioning, and resizing.
  - `NSHostingController` — bridges SwiftUI views into the AppKit panel.
  - `NSScreen` — multi-display detection and frame calculations.
  - `NSAnimationContext` — window resize animations with custom timing curves.

The interop boundary is `NotchRootView` (SwiftUI `View`) hosted inside `NSHostingController`, which is set as the panel's `contentViewController`. The `NSHostingController.sizingOptions` is set to `[]` so the panel's manually-set frame drives the SwiftUI layout (not the other way around).

## Reactive Framework

**Combine** is the sole reactive framework, used for all inter-component communication:

| Combine Feature | Usage |
|---|---|
| `ObservableObject` protocol | `PomodoroTimer`, `ClaudeSessionManager`, `NotchViewModel` |
| `@Published` property wrapper | All observable state across the three view-models |
| `PassthroughSubject` | `HookSocketServer.eventSubject` — emits `HookEvent` values |
| `Publishers.CombineLatest4` | Merges 7 published inputs into the single `displayState` in `NotchViewModel` |
| `assign(to:)` | One-way binding of derived state to `@Published` properties |
| `sink` subscriptions | Event processing in `ClaudeSessionManager`, window resizing in `NotchWindowController` |
| `Set<AnyCancellable>` | Subscription lifecycle management |

No third-party reactive libraries (RxSwift, etc.) are used.

## Deployment Target

| Property | Value | Source |
|---|---|---|
| Minimum macOS | **macOS 13 Ventura** | `Package.swift`: `.macOS(.v13)` |
| `LSMinimumSystemVersion` | `13.0` | `Info.plist` |

macOS 13 is the minimum because the project relies on:
- `NSHostingController.sizingOptions` (available macOS 13+).
- Modern SwiftUI APIs and `ContentShape`/`clipShape` behavior.

## Dependencies

**None.** The project has zero external package dependencies. `Package.swift` defines no `dependencies:` array and no product requirements. Everything is built on first-party Apple frameworks:

- `SwiftUI`
- `AppKit`
- `Combine`
- `Foundation`
- `UserNotifications`

This is a deliberate choice — the app is self-contained and can be built with just the Swift toolchain, no package resolution step required.

## Build System

**Swift Package Manager (SPM)** — the project is a single SPM package with one executable target.

### `Package.swift` (full contents)

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibePomodoro",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VibePomodoro",
            path: "Sources",
            exclude: ["App/Info.plist", "App/VibePomodoro.entitlements"],
            resources: [.process("Resources")]
        )
    ]
)
```

| Configuration | Value |
|---|---|
| Package name | `VibePomodoro` |
| Target type | `.executableTarget` (command-line executable) |
| Source path | `Sources` (all subdirectories compiled into one target) |
| Excluded | `App/Info.plist`, `App/VibePomodoro.entitlements` (bundle metadata, not compiled) |
| Resources | `.process("Resources")` — processes `AppIcon.icns` and `vibe-pomodoro-hook.py` into the bundle |
| Dependencies | `[]` (none) |

There is no Xcode project (`.xcodeproj`). The app is built entirely via `swift build` and packaged into a `.app` bundle by `build.sh`.

## Resources

SPM processes the `Sources/Resources/` directory via `.process("Resources")`:

| Resource | Purpose |
|---|---|
| `AppIcon.icns` | Application icon (copied into the `.app` bundle's `Contents/Resources/` by `build.sh`) |
| `vibe-pomodoro-hook.py` | Python hook script (also embedded as a string literal in `HookInstaller.swift` and written to disk at runtime) |

> **Note:** The hook script exists in two forms. The copy in `Resources/` is the source-of-truth for reference, but at runtime `HookInstaller` embeds the script content as a Swift string literal (with a dynamically-detected Python shebang) and writes it to `~/.claude/hooks/vibe-pomodoro-hook.py`. This avoids `Bundle.main` resource path issues when running via `swift run` (which doesn't produce a standard `.app` bundle structure).

## Entitlements

File: `Sources/App/VibePomodoro.entitlements`

```xml
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.notification</key>
    <true/>
</dict>
```

| Entitlement | Value | Reason |
|---|---|---|
| `app-sandbox` | `false` | App needs to create Unix sockets in `/tmp`, write to `~/.claude/` and `~/.codex/`, and position windows above the menu bar — all restricted under sandbox |
| `notification` | `true` | Required for `UNUserNotificationCenter` to deliver banner notifications |

The app is **not sandboxed**. This is intentional and required for the hook installation and socket IPC functionality.

## Info.plist

File: `Sources/App/Info.plist` (35 lines)

| Key | Value | Purpose |
|---|---|---|
| `CFBundleDevelopmentRegion` | `zh_CN` | Default locale is Chinese (Simplified). UI strings are primarily in Chinese. |
| `CFBundleExecutable` | `VibePomodoro` | Executable name inside the bundle |
| `CFBundleIconFile` | `AppIcon` | Icon file name (without extension) |
| `CFBundleIdentifier` | `com.vibepomodoro.app` | Bundle identifier |
| `CFBundleInfoDictionaryVersion` | `6.0` | Info.plist version |
| `CFBundleName` | `vibe-pomodoro` | Display name |
| `CFBundlePackageType` | `APPL` | Application bundle type |
| `CFBundleShortVersionString` | `1.0.0` | Version (**note:** the in-app UI displays 1.1.0 — a version mismatch) |
| `CFBundleVersion` | `1` | Build number |
| `LSMinimumSystemVersion` | `13.0` | Minimum macOS version |
| `LSUIElement` | `true` | **Agent app** — no Dock icon, no main menu bar; runs in background |
| `NSHumanReadableCopyright` | `Copyright © 2024. All rights reserved.` | Copyright string |
| `NSPrincipalClass` | `NSApplication` | Principal class |
| `NSUserNotificationAlertStyle` | `banner` | Notification alert style |

### Known Issues

1. **Bundle identifier typo**: `com.vibepomodoro.app` — previously contained a typo that has been fixed.
2. **Version mismatch**: `Info.plist` declares `1.0.0` but the UI shows `1.1.0`.

## Python (Hook Script Runtime)

The hook script (`vibe-pomodoro-hook.py`) requires Python 3.x. The app auto-detects the Python path at install time by checking candidates in order:

| Detection order | Path |
|---|---|
| 1 | `/usr/bin/python3` (system Python, macOS default) |
| 2 | `/usr/local/bin/python3` (Intel Homebrew / manual install) |
| 3 | `/opt/homebrew/bin/python3` (Apple Silicon Homebrew) |
| Fallback | `python3` (relies on PATH) |

The detected path is written as the shebang line (`#!`) in the installed hook script. The script uses only Python standard library modules (`json`, `os`, `socket`, `sys`) — no pip packages required.

### Hook script behavior

- Reads JSON from stdin (provided by Claude Code / Codex CLI hook system).
- Builds a `state` dict with `session_id`, `cwd`, `event`, `pid`, and event-specific fields.
- Sends the state as JSON over a Unix domain socket to `/tmp/vibe-pomodoro-claude.sock`.
- For `PermissionRequest` events: blocks and waits (up to 300s) for a response from the app, then prints the allow/deny JSON to stdout for the CLI to read.
- For all other events: fire-and-forget (sends and closes the socket immediately).

## Socket (IPC)

| Property | Value |
|---|---|
| Type | Unix domain socket (`AF_UNIX`, `SOCK_STREAM`) |
| Path | `/tmp/vibe-pomodoro-claude.sock` |
| Permissions | `0o600` (owner read/write only) |
| Read buffer | 128 KB (`131_072` bytes) |
| Poll timeout | 0.5s (per connection read loop) |
| Permission request timeout | 300s (Python side) / 86400s (hook config timeout for Claude) |
| Concurrency | GCD `DispatchSource` (non-blocking accept) on a dedicated `socketQueue` |

The socket server (`HookSocketServer`) is a singleton (`static let shared`). It:
- Cleans up any existing socket file on `start()`.
- Uses non-blocking I/O with `DispatchSource.makeReadSource` for accept.
- Keeps client sockets open for `PermissionRequest` events in a `pendingPermissions` dictionary (keyed by `toolUseId`), allowing the app to write responses back later.
- Uses an `NSLock` to protect shared state (`pendingPermissions`, `toolUseCache`).
