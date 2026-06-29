# Architecture Overview

## High-Level Architecture

NotchPomodoro is a **menu-bar agent application** (`LSUIElement = true`) that renders UI inside the MacBook hardware notch. It has two functional pillars:

1. **Pomodoro Timer** — a classic work/break countdown engine with session tracking and macOS notifications.
2. **Claude Code / Codex CLI Integration** — a Unix domain socket server that receives hook events from a Python hook script, drives an in-notch permission-approval UI, and returns allow/deny decisions back to the CLI.

The app runs entirely in the background with no Dock icon. A borderless `NSPanel` is positioned at the top-center of each selected display, growing downward from the screen's top edge so it visually fuses with the physical notch. All visual content is provided by SwiftUI hosted inside the panel via `NSHostingController`.

### Launch Sequence

The `AppDelegate.applicationDidFinishLaunching` method orchestrates startup in a strict order:

```
1. requestNotificationPermission()   — delayed 1s; skipped if not in a .app bundle
2. HookInstaller.installIfNeeded()   — writes hook script + ~/.claude/settings.json
3. HookInstaller.installCodexIfNeeded()  — writes ~/.codex/hooks.json
4. HookSocketServer.shared.start()  — binds Unix socket at /tmp/notch-pomodoro-claude.sock
5. ClaudeSessionManager()           — subscribes to socket events
6. PomodoroTimer()                  — loads config + today's stats from UserDefaults
7. NotchDisplayManager(timer:claudeManager:)  — creates one window per selected display
```

On termination (`applicationWillTerminate`), the socket server is stopped and the timer saves state.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         External Processes                              │
│                                                                         │
│   ┌──────────────────┐                    ┌──────────────────┐         │
│   │  Claude Code CLI │                    │   Codex CLI      │         │
│   │  (~/.claude/     │                    │  (~/.codex/      │         │
│   │   settings.json) │                    │   hooks.json)    │         │
│   └────────┬─────────┘                    └────────┬─────────┘         │
│            │ hooks (stdin → stdout)                 │ hooks             │
│            ▼                                          ▼                  │
│   ┌────────────────────────────────────────────────────────────┐       │
│   │            notch-pomodoro-hook.py (Python 3)               │       │
│   │  Reads stdin JSON, builds state, sends via Unix socket      │       │
│   │  For PermissionRequest: blocks & waits for response         │       │
│   └────────────────────────┬───────────────────────────────────┘       │
│                            │ AF_UNIX socket                              │
└────────────────────────────┼────────────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      NotchPomodoro App (Swift)                          │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐     │
│  │                    AppDelegate (entry point)                   │     │
│  │  Owns: PomodoroTimer, ClaudeSessionManager, NotchDisplayMgr  │     │
│  └──────┬──────────────────────┬────────────────────────┬────────┘     │
│         │                      │                        │              │
│         ▼                      ▼                        ▼              │
│  ┌──────────────┐    ┌───────────────────┐    ┌────────────────────┐   │
│  │ PomodoroTimer│    │ ClaudeSessionMgr  │    │ NotchDisplayManager│   │
│  │ (Observable  │    │ (ObservableObject)│    │  per-screen windows │   │
│  │  Object)     │    │                   │    └─────────┬──────────┘   │
│  │ - status     │    │ - currentPhase    │              │ creates     │
│  │ - config     │    │ - approvePermission│             ▼              │
│  │ - timeRemain │    │ - denyPermission   │    ┌────────────────────┐   │
│  └──────┬───────┘    └────────┬──────────┘    │ NotchWindowController│  │
│         │                     │ subscribes     │ (per display)        │  │
│         │                     │ to events      │ - NotchViewModel     │  │
│         │                     ▼                │ - NotchWindow(NSPanel)│  │
│         │          ┌──────────────────────┐     │ - NotchRootView      │  │
│         │          │  HookSocketServer   │     └──────────┬───────────┘  │
│         │          │  (singleton)         │                │ hosts        │
│         │          │ - eventSubject       │                ▼              │
│         │          │   (PassthroughSubject)│     ┌────────────────────┐   │
│         │          │ - pendingPermissions │     │   NSHostingController  │
│         │          │   (keeps socket open)│     │        + SwiftUI       │
│         │          └──────────────────────┘     └──────────┬───────────┘  │
│         │                                                 │ renders      │
│         └────────────────── Combine @Published ──────────►│             │
│                                                           ▼              │
│                                                ┌────────────────────┐   │
│                                                │     NotchView       │   │
│                                                │ (SwiftUI, 1159 LOC)│   │
│                                                │ idle/compact/expand │   │
│                                                │ settings/break/claude│   │
│                                                └────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
                  ┌────────────────────┐
                  │   UserDefaults     │
                  │ pomodoro_config    │
                  │ pomodoro_sessions  │
                  └────────────────────┘
```

## MVVM Pattern

The app follows a lightweight **MVVM** pattern with the view-model as the central hub that merges multiple reactive sources into a single derived `displayState`:

| MVVM Role | Component | File |
|---|---|---|
| **Model** (business logic) | `PomodoroTimer` (`ObservableObject`) | `Models/PomodoroTimer.swift` |
| **Model** (session state machine) | `ClaudeSessionManager` (`ObservableObject`) | `Services/ClaudeSessionManager.swift` |
| **Model** (data types) | `PomodoroConfig`, `PomodoroStatus`, `PomodoroSession`, `HookEvent`, `ClaudeSessionPhase`, etc. | `Models/PomodoroModels.swift`, `Models/ClaudeModels.swift` |
| **ViewModel** | `NotchViewModel` (`ObservableObject`) | `Controllers/NotchWindowController.swift` |
| **View** | `NotchView` + `NotchRootView` (SwiftUI) | `Views/NotchView.swift`, `Controllers/NotchWindowController.swift` |
| **Controller** (window) | `NotchWindowController`, `NotchDisplayManager` | `Controllers/` |

### Why `PomodoroTimer` and `ClaudeSessionManager` are `ObservableObject`

Both are independently observable data sources. `PomodoroTimer` publishes `status`, `timeRemaining`, `config`, `currentRound`, `didCompleteWork`, and today's stats. `ClaudeSessionManager` publishes `currentPhase`, `activeSessionId`, `projectName`, etc. The `NotchViewModel` subscribes to both and merges their published values into a single `@Published var displayState`.

This means there is **one `NotchViewModel` per display window** (created by `NotchWindowController`), but they all share the same `PomodoroTimer` and `ClaudeSessionManager` instances from the `AppDelegate`. State is centralized; views are per-display.

## Combine Reactive Pipeline

The entire data flow is built on Combine. Events flow through the system in a one-directional pipeline:

### 1. Hook Event Ingestion → `HookSocketServer`

```
Python hook script
  ──► AF_UNIX socket (/tmp/notch-pomodoro-claude.sock)
        ──► HookSocketServer.acceptConnection()  [GCD DispatchSource on socketQueue]
              ──► handleClient(fd:)  reads + decodes JSON → HookEvent
                    ──► eventSubject.send(event)  [PassthroughSubject<HookEvent, Never>]
```

For `PermissionRequest` events, the server keeps the client socket open (`pendingPermissions` dictionary keyed by `toolUseId`) so it can later write the response back.

A FIFO cache (`toolUseCache`, max 50 entries) correlates `PreToolUse` events with subsequent `PermissionRequest` events by matching tool names when `tool_use_id` is missing.

### 2. `HookSocketServer` → `ClaudeSessionManager`

```
server.eventSubject
  .receive(on: DispatchQueue.main)
  .sink { event in self.processEvent(event) }
```

`ClaudeSessionManager.processEvent(_:)` maps the raw `HookEvent` to a `ClaudeSessionPhase`:

| Event status | Resulting phase | Auto-dismiss |
|---|---|---|
| `processing`, `running_tool` | `.processing` | no |
| `waiting_for_input` | `.waitingForInput` | after 5s |
| `waiting_for_response` | `.waitingForResponse(message)` | no (persists) |
| `waiting_for_approval` | `.waitingForApproval(PermissionContext)` | no (blocks) |
| `compacting` | `.compacting` | no |
| `ended` | `.idle` (reset) | — |
| `StopFailure` event | `.error(message)` | after 5s |

### 3. `ClaudeSessionManager` + `PomodoroTimer` → `NotchViewModel`

The `NotchViewModel.init` sets up the combined subscription:

```swift
// Timer status → isTimerActive
timer.$status.map { $0 != .idle }.removeDuplicates()
    .receive(on: RunLoop.main).assign(to: &$isTimerActive)

// Work completed → break prompt trigger
timer.$didCompleteWork.filter { $0 == true }
    .receive(on: RunLoop.main).sink { self.triggerBreakPrompt() }

// Claude phase passthrough
claudeManager.$currentPhase
    .receive(on: RunLoop.main).assign(to: &$claudePhase)
```

### 4. `NotchViewModel` → `NotchView` (display state)

```swift
Publishers.CombineLatest4(
    Publishers.CombineLatest4($isPinnedExpanded, $isHovering, $isTimerActive, $showSettings),
    $isReady,
    $showBreakPrompt,
    $claudePhase
)
.map { quad, ready, breakPrompt, claude -> NotchDisplayState in
    let (pinned, hovering, active, settings) = quad
    if settings { return .settings }
    if claude.isWaitingForApproval { return .claudeApproval }
    if breakPrompt { return .breakPrompt }
    if claude.isNotification { return .claudeNotification }
    if pinned || (hovering && ready) { return .expanded }
    if active { return .compact }
    return .idle
}
.removeDuplicates()
.receive(on: RunLoop.main)
.assign(to: &$displayState)
```

`NotchView` observes `viewModel.$displayState` via `@ObservedObject` and renders the appropriate content. `NotchWindowController` also subscribes to `$displayState` to animate window resizing.

### 5. Permission Decision (reverse flow)

```
User taps "Allow"/"Deny" in NotchView
  ──► claudeManager.approvePermission() / denyPermission(reason:)
        ──► server.respondToPermission(toolUseId:decision:reason:)
              ──► JSON-encodes HookResponse, writes to the held-open client socket
                    ──► Python script receives response, prints allow/deny JSON to stdout
                          ──► Claude Code / Codex CLI reads the hook's stdout verdict
```

## State Priority System

The notch can only be in **one display state** at a time. A strict priority resolver ensures deterministic behavior when multiple conditions overlap. The priority order, from highest to lowest:

```
settings  >  claudeApproval  >  breakPrompt  >  claudeNotification  >  expanded  >  compact  >  idle
```

| Priority | State | Trigger | Window Size (W×H) |
|---|---|---|---|
| 1 (highest) | `.settings` | `showSettings == true` | 380 × 420 |
| 2 | `.claudeApproval` | `claudePhase.isWaitingForApproval` | 400 × 260 |
| 3 | `.breakPrompt` | `showBreakPrompt == true` (auto-dismiss after 5s) | 360 × 180 |
| 4 | `.claudeNotification` | `claudePhase.isNotification` (waitingForInput / error / waitingForResponse) | 360 × 140 |
| 5 | `.expanded` | `isPinnedExpanded` OR (`isHovering && isReady`) | 360 × 240 |
| 6 | `.compact` | `isTimerActive == true` (timer running) | 400 × 38 |
| 7 (lowest) | `.idle` | none of the above | 400 × 38 |

**Design rationale:** Settings always wins because the user explicitly opened it. Permission approval takes precedence over everything else because it blocks the CLI. Break prompts are transient (5s). Claude notifications override expanded/compact because they convey time-sensitive session info. A 0.5s cold-start delay (`isReady`) prevents the notch from immediately expanding if the mouse happens to be over the notch area at launch.

## Window Strategy

### One `NSPanel` per display

`NotchDisplayManager` maintains a dictionary `controllers: [String: NotchWindowController]` keyed by `screen.localizedName`. It:

- Listens to `NSApplication.didChangeScreenParametersNotification` for connect/disconnect.
- Listens to `timer.$config.selectedDisplayNames` for user display selection changes.
- Defaults to the built-in display only (detected by name containing "Built-in", "内建", or "内置").
- Creates or tears down windows in `refreshWindows()` to match the current configuration.
- Updates the `connectedDisplays` list on all view-models for the settings UI.

### Window positioning — grows downward from top edge

```swift
let screenFrame = screen.frame
let originX = screenFrame.midX - size.width / 2
let originY = screenFrame.maxY - size.height   // top edge aligned to screen top
```

The window's top edge is clamped to `screenFrame.maxY` (the screen's top in the bottom-left coordinate system). As `displayState` changes, the window's height changes, and the window grows **downward** from the fixed top edge. This keeps the notch pill visually anchored to the hardware notch.

### Window level — above the menu bar

```swift
window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
```

This places the panel above the system menu bar and notch, allowing the black `NotchShape` to visually merge with the hardware notch.

### Window properties

| Property | Value | Reason |
|---|---|---|
| `styleMask` | `[.borderless, .nonactivatingPanel]` | No title bar; doesn't steal focus |
| `isOpaque` | `false` | Transparent background |
| `backgroundColor` | `.clear` | Visual shape drawn by SwiftUI |
| `hasShadow` | `false` | Shape provides its own visual |
| `isMovable` | `false` | Position is computed |
| `hidesOnDeactivate` | `false` | Persistent across app switches |
| `collectionBehavior` | `.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle` | Visible in all spaces incl. fullscreen |
| `acceptsMouseMovedEvents` | `true` | Needed for hover detection |

`NotchWindow` (a subclass of `NSPanel`) overrides `canBecomeKey` to return `true` so that SwiftUI buttons inside the panel can receive clicks — critical for permission approval and settings interactions. `canBecomeMain` returns `false` so it never becomes the main window.

### Animations

Window resizing uses `NSAnimationContext` with a 0.32s duration and a custom ease-out timing function (`0.22, 0.88, 0.32, 1.0`). SwiftUI content transitions use spring animations (`response: 0.32, dampingFraction: 0.72`).

## Persistence

The app uses **`UserDefaults` exclusively** — no Core Data, no SQLite, no file-based storage.

| Key | Type | Contents |
|---|---|---|
| `pomodoro_config` | JSON-encoded `PomodoroConfig` | Work duration, break durations, rounds, auto-start flags, selected display names, notch gap width |
| `pomodoro_sessions` | JSON-encoded `[PomodoroSession]` | Session history (max 100 entries, FIFO trim); each entry has UUID, type, start/end time, completed flag |

`PomodoroTimer` loads config and sessions on init. Config is saved on every change (via `didSet` on the `@Published var config`). Sessions are appended on completion/skip/stop and trimmed to the most recent 100. Today's stats (focus minutes, break minutes, completed sessions) are recomputed from the session array.

## Key Design Decisions & Trade-offs

### 1. Embedded Python hook script (not a separate file)
The Python hook script content is embedded as a Swift string literal in `HookInstaller.hookScriptContent(pythonPath:)` and written to disk at install time. This keeps the SPM resource bundle self-contained and avoids runtime `Bundle.main` resource path issues (which don't work reliably with `swift run`). The Python shebang is dynamically set to the detected `python3` path.

### 2. Synchronous permission flow via held-open socket
When a `PermissionRequest` arrives, the Python script blocks waiting for a response (`sock.recv(4096)`, 300s timeout). The Swift server keeps the client file descriptor alive in `pendingPermissions`. This synchronous request/response over a single connection avoids needing a second socket or polling mechanism — at the cost of holding a thread per pending permission.

### 3. One ViewModel per display, shared model instances
Each `NotchWindowController` creates its own `NotchViewModel`, but they all reference the same `PomodoroTimer` and `ClaudeSessionManager` from `AppDelegate`. This means every display shows the same timer and Claude state, but each can independently handle hover/expansion. Permission approval is handled through the shared `ClaudeSessionManager`, so only one display needs the user's decision.

### 4. Not sandboxed
The entitlements file sets `com.apple.security.app-sandbox = false`. This is required because the app needs to: create a Unix domain socket in `/tmp`, write to `~/.claude/` and `~/.codex/`, and run above the menu bar. The `notification` entitlement is enabled.

### 5. `LSUIElement = true` (agent app)
The app has no Dock icon and no main menu bar. It lives entirely in the notch. This is set via `LSUIElement = true` in `Info.plist`.

### 6. No test suite
The project currently defines no test targets. The Combine pipeline and window logic are straightforward enough that manual testing via the running app has been sufficient. Adding tests would require mocking the socket server and timer engine.

### 7. Single executable target
`Package.swift` defines one `.executableTarget` with `path: "Sources"`, excluding `Info.plist` and `.entitlements` (those are bundle metadata, not compiled). The `Resources` directory is processed by SPM for `AppIcon.icns` and `notch-pomodoro-hook.py`, though the hook script is embedded as a string literal at runtime rather than loaded from the bundle.
