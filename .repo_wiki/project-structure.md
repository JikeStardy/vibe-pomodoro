# Project Structure

## Directory Tree

```
NotchPomodoro/
├── .build/                          # SPM build output (gitignored)
├── .gitignore
├── Package.swift                    # SPM manifest (18 lines)
├── build.sh                         # App bundle packaging script (42 lines)
├── README.md                        # Project README (155 lines)
├── Sources/
│   ├── App/
│   │   ├── Info.plist               # Bundle metadata (35 lines)
│   │   ├── VibePomodoro.entitlements  # Entitlements (11 lines)
│   │   └── NotchPomodoroApp.swift   # @main entry + AppDelegate (92 lines)
│   ├── Controllers/
│   │   ├── NotchDisplayManager.swift   # Multi-display coordinator (106 lines)
│   │   └── NotchWindowController.swift # Display state, ViewModel, window, root view (328 lines)
│   ├── Models/
│   │   ├── ClaudeModels.swift        # Hook/permission/session models (188 lines)
│   │   ├── PomodoroModels.swift      # Config, status, session models (42 lines)
│   │   └── PomodoroTimer.swift       # Timer engine, ObservableObject (397 lines)
│   ├── Resources/
│   │   ├── AppIcon.icns             # App icon (binary)
│   │   └── vibe-pomodoro-hook.py    # Python hook script (121 lines)
│   ├── Services/
│   │   ├── ClaudeSessionManager.swift # Session state machine (137 lines)
│   │   └── Hooks/
│   │       ├── HookInstaller.swift    # Hook installer for Claude+Codex (603 lines)
│   │       └── HookSocketServer.swift # Unix socket server (317 lines)
│   ├── Utilities/                   # Empty directory (reserved)
│   │   └── (no files)
│   └── Views/
│       ├── NotchView.swift           # Main SwiftUI notch UI (1159 lines)
│       └── SettingsView.swift        # Legacy/unused standalone settings (245 lines)
└── .qoder/                          # Qoder-generated repo wiki (not part of source)
```

## File Inventory

### App (`Sources/App/`)

| File | Lines | Purpose |
|---|---|---|
| `NotchPomodoroApp.swift` | 92 | `@main` entry point. `VibePomodoroApp` (SwiftUI `App`) with `@NSApplicationDelegateAdaptor`. `AppDelegate` owns `PomodoroTimer`, `NotchDisplayManager`, and `ClaudeSessionManager`. Orchestrates the launch sequence: notification permission → hook installation → socket server → session manager → timer → display manager. Implements `UNUserNotificationCenterDelegate` for foreground notifications. |
| `Info.plist` | 35 | Bundle metadata. `LSUIElement = true` (agent app), `CFBundleDevelopmentRegion = zh_CN`, `CFBundleIdentifier = com.nothpomodoro.app` (typo), `CFBundleShortVersionString = 1.0.0`, `LSMinimumSystemVersion = 13.0`. |
| `VibePomodoro.entitlements` | 11 | Entitlements. `app-sandbox = false`, `notification = true`. |

### Models (`Sources/Models/`)

| File | Lines | Purpose |
|---|---|---|
| `PomodoroModels.swift` | 42 | Data types: `PomodoroStatus` enum (idle/working/shortBreak/longBreak/paused), `PomodoroConfig` struct (durations, rounds, auto-start flags, display selection, notch gap width), `PomodoroSession` struct (UUID, type, timestamps, completed). |
| `PomodoroTimer.swift` | 397 | Timer engine (`ObservableObject`). Manages work/break cycles, countdown via `Timer.scheduledTimer`, pause/resume, skip, session recording, today's stats, `UserDefaults` persistence (config + sessions), and `UNUserNotificationCenter` notifications on completion. |
| `ClaudeModels.swift` | 188 | Claude/hook data types: `AnyCodable` (type-erasing Codable wrapper), `HookEvent` (decoded from Python script JSON), `HookResponse` (allow/deny/ask), `PermissionContext` (tool details + formatted display), `ClaudeSessionPhase` (state machine enum with 7 cases), `PendingPermission` (internal socket tracking). |

### Controllers (`Sources/Controllers/`)

| File | Lines | Purpose |
|---|---|---|
| `NotchWindowController.swift` | 328 | Contains 5 types: `NotchDisplayState` enum (7 states with window sizes), `NotchViewModel` (`ObservableObject` — the central view-model that merges timer + Claude state via Combine into `displayState`), `NotchWindowController` (window lifecycle, positioning, resize animation), `NotchWindow` (`NSPanel` subclass — `canBecomeKey = true` for button clicks), `NotchRootView` (SwiftUI root that injects all three observable objects). |
| `NotchDisplayManager.swift` | 106 | Multi-display coordinator. Maintains a `[String: NotchWindowController]` dictionary keyed by screen name. Listens to screen connect/disconnect and config changes. Creates/destroys windows to match selected displays. Defaults to built-in display. |

### Services (`Sources/Services/`)

| File | Lines | Purpose |
|---|---|---|
| `ClaudeSessionManager.swift` | 137 | Session state machine (`ObservableObject`). Subscribes to `HookSocketServer.eventSubject`, maps `HookEvent` → `ClaudeSessionPhase`. Handles auto-dismiss (5s for notifications). Exposes `approvePermission()` / `denyPermission()` which call `HookSocketServer.respondToPermission()`. Tracks `activeSessionId`, `projectName`, `lastToolName`, `isSubagentActive`. |
| `Hooks/HookInstaller.swift` | 603 | Hook installation system. Writes the Python hook script to `~/.claude/hooks/notch-pomodoro-hook.py` (embedded as string literal with dynamic Python shebang). Registers hook entries in `~/.claude/settings.json` (13 events) and `~/.codex/hooks.json` (10 events). Supports detection, uninstall, and Codex-specific registration. Auto-detects Python 3 path. |
| `Hooks/HookSocketServer.swift` | 317 | Unix domain socket server (singleton). Binds `/tmp/notch-pomodoro-claude.sock`, uses GCD `DispatchSource` for non-blocking I/O. Decodes JSON to `HookEvent`, emits via `eventSubject`. Keeps client sockets open for `PermissionRequest` events. Maintains a FIFO `toolUseCache` (50 entries) for correlating `PreToolUse` → `PermissionRequest` by tool name. |

### Views (`Sources/Views/`)

| File | Lines | Purpose |
|---|---|---|
| `NotchView.swift` | 1159 | The main SwiftUI notch UI — the largest file in the project. Contains `NotchShape` (custom `Shape` with flat top, rounded bottom), `NotchView` (the main view that switches on `displayState`), and all sub-views for each state: compact countdown, expanded control panel, settings panel (the actual working settings UI), break prompt, Claude approval card, Claude notification, and supporting components (duration sliders, display picker, etc.). |
| `SettingsView.swift` | 245 | **Legacy / unused.** A standalone `SettingsView` SwiftUI view that was originally intended for a separate settings window. It is not referenced by any active code path. The actual settings UI is embedded directly inside `NotchView.swift` (rendered when `displayState == .settings`). |

### Resources (`Sources/Resources/`)

| File | Lines | Purpose |
|---|---|---|
| `notch-pomodoro-hook.py` | 121 | Python 3 hook script. Reads JSON from stdin (Claude Code/Codex hook payload), builds a state dict, sends it via Unix socket to the app. For `PermissionRequest`, blocks and waits for the app's allow/deny response, then prints the verdict JSON to stdout. Uses only standard library modules. |
| `AppIcon.icns` | — | macOS app icon (binary ICNS file). Copied to the bundle's `Contents/Resources/` by `build.sh`. |

### Root-level files

| File | Lines | Purpose |
|---|---|---|
| `Package.swift` | 18 | SPM manifest. Swift tools 5.9, `.macOS(.v13)`, single `.executableTarget` "NotchPomodoro" with `path: "Sources"`, excludes Info.plist and entitlements, processes Resources. Zero dependencies. |
| `build.sh` | 42 | Bash script that builds the release binary, creates a `.app` bundle structure (`Contents/MacOS/`, `Contents/Resources/`), copies the executable, Info.plist, entitlements, and icon into it. |
| `README.md` | 155 | Project README with feature overview, build instructions, and hook integration notes. |
| `.gitignore` | 14 | Ignores `.build/`, `Package.resolved`, Xcode user data, and `.DS_Store`. |

## Directory Roles

### `Sources/App/`
Application entry point and bundle metadata. Contains the `@main` struct, `AppDelegate`, `Info.plist`, and entitlements. These are the files that define the app as a macOS agent (`LSUIElement`) and configure its runtime capabilities. The `Info.plist` and `.entitlements` are excluded from SPM compilation (they're bundle metadata only) but are copied into the `.app` bundle by `build.sh`.

### `Sources/Models/`
Data models and business logic. Pure data types (`PomodoroModels`, `ClaudeModels`) plus the timer engine (`PomodoroTimer`). These have no UI dependencies — `PomodoroTimer` does import `UserNotifications` for sending alerts, but it doesn't reference any views.

### `Sources/Controllers/`
Window management and the view-model layer. `NotchWindowController.swift` is the most architecturally significant file — it defines the display state enum, the `NotchViewModel` (the Combine hub), and the window infrastructure. `NotchDisplayManager` coordinates across multiple displays.

### `Sources/Services/`
Background services for Claude Code/Codex CLI integration. Split into the session state machine (`ClaudeSessionManager`) and the hooks subsystem (`Hooks/HookInstaller` + `Hooks/HookSocketServer`). These handle all communication with external CLI tools.

### `Sources/Views/`
SwiftUI view layer. `NotchView.swift` is the monolithic view file containing all notch UI states and supporting components. `SettingsView.swift` is legacy/unused.

### `Sources/Resources/`
Static resources processed by SPM. The Python hook script (source-of-truth) and app icon.

### `Sources/Utilities/`
**Empty directory.** This directory exists but contains no files. It appears to be reserved for future utility code (e.g., formatters, helpers, extensions) but is currently unused. SPM includes it in the build path, so any `.swift` file added here would be automatically compiled.

## Notes

### `SettingsView.swift` — Legacy / Unused
`Sources/Views/SettingsView.swift` (245 lines) defines a standalone `SettingsView` SwiftUI struct that is **not referenced by any active code path**. It was likely created during early development when settings were planned as a separate window (via the SwiftUI `Settings` scene, which `NotchPomodoroApp.body` defines as `EmptyView()`). The actual, working settings UI is embedded directly inside `NotchView.swift` and rendered when `displayState == .settings`. This file can be safely removed without affecting functionality.

### `Sources/Utilities/` — Empty
The `Utilities/` directory is empty. It contains no Swift files and serves no current purpose. It is included in the SPM target's `path: "Sources"` so any files added here would be compiled automatically.

## Known Issues

### 1. CFBundleIdentifier Typo
`Info.plist` declares `CFBundleIdentifier` as `com.vibepomodoro.app`. The previous typo ("noth") has been fixed during the rename to vibe-pomodoro.

### 2. Version Mismatch
`Info.plist` declares `CFBundleShortVersionString` as `1.0.0`, but the in-app UI (rendered in `NotchView.swift`) displays version `1.1.0`. The `Info.plist` value is what macOS sees for the bundle version in Finder, About panels, and System Settings. The UI version string is hardcoded in the SwiftUI view. These should be kept in sync.

### 3. No Test Targets
The project defines no test targets in `Package.swift`. There are no unit tests, integration tests, or UI tests. Adding a `testTarget` would require restructuring the code to allow importing the app's types from a test module.
