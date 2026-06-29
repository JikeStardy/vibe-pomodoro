# Pomodoro Timer Engine

> **Source file:** `Sources/Models/PomodoroTimer.swift` (397 lines)

This document describes the `PomodoroTimer` class — the core state machine that manages work/break cycles, countdown timing, session persistence, and statistics tracking.

---

## Table of Contents

- [Class Declaration](#class-declaration)
- [Published Properties](#published-properties)
- [Private State](#private-state)
- [Callback Hooks](#callback-hooks)
- [Computed Properties](#computed-properties)
- [Public Methods](#public-methods)
- [Private Methods](#private-methods)
- [Timer Mechanism](#timer-mechanism)
- [Persistence](#persistence)
- [State Transitions](#state-transitions)
- [Break Selection Logic](#break-selection-logic)
- [Auto-Start Behavior](#auto-start-behavior)

---

## Class Declaration

```swift
class PomodoroTimer: ObservableObject
```

`PomodoroTimer` is the single source of truth for timer state in the app. It is injected as an `@ObservedObject` into SwiftUI views and observed by `NotchViewModel` via Combine subscriptions.

### Initialization

```swift
init()
```

The initializer:
1. Sets `config` to `PomodoroConfig.default`
2. Sets `timeRemaining` to `PomodoroConfig.default.workDuration` (1500)
3. Calls `loadConfig()` — overrides config & timeRemaining if persisted config exists
4. Calls `refreshTodayStats()` — loads today's focus/break/session counts from saved sessions

---

## Published Properties

All `@Published` properties trigger SwiftUI view updates when changed.

| Property | Type | Default | Description |
|---|---|---|---|
| `status` | `PomodoroStatus` | `.idle` | Current timer status |
| `timeRemaining` | `Int` | `1500` (set in init) | Seconds remaining in current phase |
| `currentRound` | `Int` | `1` | Current work round number (1-indexed) |
| `isPaused` | `Bool` | `false` | Whether timer is currently paused |
| `pendingBreak` | `Bool` | `false` | Flag: next action should be a break |
| `didCompleteWork` | `Bool` | `false` | Flag: work just completed (triggers break prompt UI) |
| `todayFocusMinutes` | `Int` | `0` | Total focus minutes today |
| `todayBreakMinutes` | `Int` | `0` | Total break minutes today |
| `todayCompletedSessions` | `Int` | `0` | Number of completed work sessions today |
| `config` | `PomodoroConfig` | `PomodoroConfig.default` | User configuration (auto-saves on change via `didSet`) |

### Config Auto-Save

The `config` property has a `didSet` observer that calls `saveConfig()` immediately:

```swift
@Published var config: PomodoroConfig {
    didSet {
        saveConfig()
    }
}
```

Any mutation to `config` (e.g., `timer.config.workDuration = 1800`) triggers automatic persistence.

---

## Private State

| Property | Type | Default | Description |
|---|---|---|---|
| `timer` | `Timer?` | `nil` | The active `Timer.scheduledTimer` instance |
| `startDate` | `Date?` | `nil` | When the current countdown segment started (for elapsed-time calculation) |
| `pausedTimeRemaining` | `Int?` | `nil` | Remaining time captured at pause (for resume calculation) |
| `sessionStartTime` | `Date?` | `nil` | When the current session started (for session record creation) |

---

## Callback Hooks

Optional closures that external code can set to react to timer events:

| Property | Type | Description |
|---|---|---|
| `onStatusChange` | `((PomodoroStatus) -> Void)?` | Called whenever `status` transitions |
| `onTick` | `((Int) -> Void)?` | Called on every tick with current `timeRemaining` |
| `onComplete` | `((PomodoroStatus) -> Void)?` | Called when a phase completes or is skipped |

---

## Computed Properties

### `totalTime: Int`

Returns the total duration of the current phase based on `status`:

| Status | Returns |
|---|---|
| `.working` | `config.workDuration` |
| `.shortBreak` | `config.shortBreakDuration` |
| `.longBreak` | `config.longBreakDuration` |
| `.idle` / `.paused` | `config.workDuration` (fallback) |

### `progress: Double`

Returns the elapsed progress as a value from `0.0` to `1.0`:

```swift
1.0 - (Double(timeRemaining) / Double(totalTime))
```

Returns `0.0` if `totalTime <= 0`.

### `formattedTime: String`

Returns `timeRemaining` formatted as `MM:SS`:

```swift
String(format: "%02d:%02d", minutes, seconds)
```

Example: `timeRemaining = 543` → `"09:03"`

### `statusText: String`

Returns a localized status label (Chinese):

| Status | isPaused | Returns |
|---|---|---|
| `.idle` | — | `"准备开始"` |
| `.working` | `true` | `"工作暂停"` |
| `.working` | `false` | `"专注工作"` |
| `.shortBreak` | `true` | `"休息暂停"` |
| `.shortBreak` | `false` | `"短休息"` |
| `.longBreak` | `true` | `"休息暂停"` |
| `.longBreak` | `false` | `"长休息"` |
| `.paused` | — | `"已暂停"` |

---

## Public Methods

### `startWork()`

```swift
func startWork()
```

Begins a new work session. Behavior:
1. Resets `didCompleteWork = false`, `pendingBreak = false`
2. Calls `stop()` to clean up any existing session
3. Sets `status = .working`, `timeRemaining = config.workDuration`
4. Sets `isPaused = false`, records `sessionStartTime = Date()`
5. Starts the timer via `startTimer()`
6. Fires `onStatusChange?(status)`

### `startBreak()`

```swift
func startBreak()
```

Begins a break session (short or long). Behavior:
1. Resets `didCompleteWork = false`, `pendingBreak = false`
2. Calls `stop()` to clean up any existing session
3. **Determines break type:** `isLongBreak = currentRound > config.roundsBeforeLongBreak`
4. Sets `status` to `.longBreak` or `.shortBreak` accordingly
5. Sets `timeRemaining` to the appropriate break duration
6. Sets `isPaused = false`, records `sessionStartTime = Date()`
7. Starts the timer via `startTimer()`
8. Fires `onStatusChange?(status)`

### `togglePause()`

```swift
func togglePause()
```

Toggles between paused and running states. Guard: only works when `status` is `.working`, `.shortBreak`, or `.longBreak`.

- If `isPaused == true` → calls `resume()`
- If `isPaused == false` → calls `pause()`

### `stop()`

```swift
func stop()
```

Stops the timer and records the session. Behavior:
1. Guard: returns early if `status == .idle`
2. Resets `pendingBreak = false`
3. Invalidates and nils the `timer`
4. Clears `startDate` and `pausedTimeRemaining`
5. If `sessionStartTime` exists:
   - Creates a `PomodoroSession` with `completed: (timeRemaining == 0)`
   - Saves the session via `saveSession()`
   - Calls `refreshTodayStats()`
   - Clears `sessionStartTime`
6. Resets to idle: `status = .idle`, `isPaused = false`, `timeRemaining = config.workDuration`
7. Fires `onStatusChange?(status)`

### `skip()`

```swift
func skip()
```

Skips the current phase and transitions to the next one. Behavior:
1. Guard: returns early if `status == .idle`
2. Saves the current `status` as `completedStatus`
3. Invalidates the timer
4. If `sessionStartTime` exists:
   - Creates a `PomodoroSession` with `completed: true`
   - Saves and refreshes stats
5. **Phase transition:**
   - If `completedStatus == .working`:
     - Increments `currentRound += 1`
     - If `config.autoStartBreak` → calls `startBreak()`
     - Else → sets `pendingBreak = true`, `status = .idle`, `timeRemaining = config.shortBreakDuration`, fires `onStatusChange`
   - Else (was a break):
     - If `completedStatus == .longBreak` → resets `currentRound = 1`
     - If `config.autoStartWork` → calls `startWork()`
     - Else → sets `status = .idle`, `timeRemaining = config.workDuration`, fires `onStatusChange`
6. Fires `onComplete?(completedStatus)`

### `resetRounds()`

```swift
func resetRounds()
```

Resets `currentRound` to `1`. Called when the user stops from the UI.

### `refreshTodayStats()`

```swift
func refreshTodayStats()
```

Recalculates today's statistics from persisted sessions:

1. Loads all sessions via `loadSessions()`
2. Filters to only sessions where `startTime` is today (using `Calendar.current.isDateInToday`)
3. `todayFocusMinutes`: sum of elapsed time for `.working` sessions, divided by 60
4. `todayBreakMinutes`: sum of elapsed time for `.shortBreak` + `.longBreak` sessions, divided by 60
5. `todayCompletedSessions`: count of `.working` sessions where `completed == true`

---

## Private Methods

### `startTimer()`

```swift
private func startTimer()
```

Creates and schedules the repeating timer:
1. Sets `startDate = Date()`
2. Creates `Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)` that calls `tick()`
3. Adds the timer to `RunLoop.main` for `.common` mode (ensures timer fires during UI interaction)

### `pause()`

```swift
private func pause()
```

Pauses the timer. Guard: `!isPaused && status != .idle`.
1. Invalidates and nils the timer
2. Sets `isPaused = true`
3. Captures `pausedTimeRemaining = timeRemaining`
4. Fires `onStatusChange?(status)`

### `resume()`

```swift
private func resume()
```

Resumes from pause. Guard: `isPaused && status != .idle`.
1. Invalidates any existing timer (prevents duplicate timers)
2. Sets `isPaused = false`
3. Resets `startDate = Date()`
4. Creates a new `Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)` calling `tick()`
5. Adds to `RunLoop.main` for `.common` mode
6. Fires `onStatusChange?(status)`

### `tick()`

```swift
private func tick()
```

Called every 1 second by the timer. Runs on `DispatchQueue.main.async`:

```swift
DispatchQueue.main.async { [weak self] in
    guard let self = self else { return }
    guard let startDate = self.startDate else { return }

    let elapsed = Int(Date().timeIntervalSince(startDate))
    let initialTime = self.pausedTimeRemaining ?? self.totalTime

    self.timeRemaining = max(0, initialTime - elapsed)
    self.onTick?(self.timeRemaining)

    if self.timeRemaining == 0 {
        self.complete()
    }
}
```

**Key detail:** The elapsed time is calculated from `startDate`, not by decrementing `timeRemaining` by 1 each tick. This approach is drift-resistant — if the app is backgrounded, the timer still correctly reflects elapsed wall-clock time upon the next tick. `pausedTimeRemaining` is used as `initialTime` when resuming from pause, so the countdown continues from where it left off.

### `complete()`

```swift
private func complete()
```

Called when `timeRemaining` reaches 0. Behavior:
1. Invalidates timer, clears `startDate` and `pausedTimeRemaining`
2. Saves `completedStatus = status`
3. If `sessionStartTime` exists:
   - Creates `PomodoroSession` with `completed: true`
   - Saves and refreshes stats
4. Calls `sendNotification(for: completedStatus)`
5. **Phase transition:**
   - If `completedStatus == .working`:
     - Increments `currentRound += 1`
     - Sets `didCompleteWork = true` (triggers break prompt UI)
     - If `config.autoStartBreak` → calls `startBreak()`
     - Else → sets `pendingBreak = true`, `status = .idle`, sets `timeRemaining` to the appropriate break duration based on round count, sets `isPaused = false`, fires `onStatusChange`
   - Else (was a break):
     - If `completedStatus == .longBreak` → resets `currentRound = 1`
     - If `config.autoStartWork` → calls `startWork()`
     - Else → sets `status = .idle`, `timeRemaining = config.workDuration`, `isPaused = false`, fires `onStatusChange`
6. Fires `onComplete?(completedStatus)`

### `sendNotification(for:)`

```swift
private func sendNotification(for status: PomodoroStatus)
```

Sends a local notification via `UNUserNotificationCenter`:

| Status | Title | Body | Sound |
|---|---|---|---|
| `.working` | `"工作完成！"` | `"休息一下吧 🎉"` | `.default` |
| `.shortBreak` / `.longBreak` | `"休息结束"` | `"准备开始新的番茄钟 💪"` | `.default` |
| `.idle` / `.paused` | _(no notification)_ | — | — |

The notification is delivered immediately (`trigger: nil`) with a random UUID identifier.

---

## Timer Mechanism

### Timer Creation

```swift
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.tick()
}
RunLoop.main.add(timer!, forMode: .common)
```

### Key Characteristics

| Aspect | Value | Reason |
|---|---|---|
| Interval | `1.0` second | Per-second countdown granularity |
| Mode | `RunLoop.main` + `.common` | Ensures timer fires during scroll/drag interactions |
| Repeating | `true` | Continuous countdown |
| Weak self | `[weak self]` | Prevents retain cycles |
| Dispatch | `DispatchQueue.main.async` inside `tick()` | Ensures UI updates happen on main thread even if timer fires from non-main context |

### Why `.common` Mode?

By default, `Timer.scheduledTimer` is added to `.default` mode, which pauses during modal interactions (scrolling, dragging). Adding to `.common` mode ensures the timer continues firing during these interactions, preventing the countdown from stalling.

---

## Persistence

### Config Persistence

| Method | Key | Description |
|---|---|---|
| `saveConfig()` | `"pomodoro_config"` | Encodes `config` to `Data` via `JSONEncoder`, stores in `UserDefaults.standard` |
| `loadConfig()` | `"pomodoro_config"` | Reads `Data` from `UserDefaults`, decodes via `JSONDecoder`. On success, updates `config` and `timeRemaining` |

**Auto-save:** `saveConfig()` is called automatically via the `didSet` observer on the `config` @Published property.

### Session Persistence

| Method | Key | Description |
|---|---|---|
| `saveSession(_:)` | `"pomodoro_sessions"` | Appends a new session to the existing array, caps at 100 entries, encodes and stores |
| `loadSessions()` | `"pomodoro_sessions"` | Reads and decodes `[PomodoroSession]`. Returns `[]` on failure |

**100-entry cap:** When `sessions.count > 100`, only the most recent 100 are kept:

```swift
sessions = Array(sessions.suffix(100))
```

---

## State Transitions

### ASCII State Diagram

```
                         ┌──────────────────────────────────────────────┐
                         │                                              │
                         ▼                                              │
                    ┌─────────┐                                        │
        ────────────►│  idle   │◄─────────────────────────────────────  │
                    └────┬─────┘                                        │
                         │                                              │
              startWork()│            startBreak()                      │
                         │                                              │
              ┌──────────┴───────────────────────┐                     │
              ▼                                  ▼                     │
      ┌──────────────┐                   ┌──────────────┐             │
      │   working    │                   │ shortBreak /  │             │
      │              │                   │  longBreak    │             │
      └──────┬───┬───┘                   └───────┬──────┘             │
             │   │                               │                    │
     togglePause│ │complete()            togglePause│                  │
             │   │                               │                    │
             ▼   │                               ▼                    │
      ┌──────────┴──┐                   ┌──────────┴──┐               │
      │  paused     │                   │  paused     │               │
      │ (isPaused   │                   │ (isPaused   │               │
      │  = true)    │                   │  = true)    │               │
      └──────┬──────┘                   └──────┬──────┘               │
             │                                   │                    │
     togglePause│                       togglePause│                   │
      (resume)  │                        (resume)  │                    │
             │   │                               │                    │
             ▼   │                               ▼                    │
      ┌──────────────┐                   ┌──────────────┐             │
      │   working    │                   │ shortBreak /  │             │
      │ (running)    │                   │  longBreak    │             │
      └──────┬───────┘                   └──────┬───────┘             │
             │                                  │                     │
     complete()│                       complete()│                     │
      or skip()│                        or skip()│                     │
             │                                  │                     │
             ▼                                  ▼                     │
      ┌──────────────────────────────────────────────┐                │
      │              Phase Transition                │                │
      │                                              │                │
      │  working → complete:                         │                │
      │    currentRound += 1                         │                │
      │    didCompleteWork = true                    │                │
      │    autoStartBreak? → startBreak()            │                │
      │    else? → pendingBreak=true, idle           │                │
      │                                              │                │
      │  break → complete:                          │                │
      │    if longBreak: currentRound = 1            │                │
      │    autoStartWork? → startWork()              │                │
      │    else? → idle                             │                │
      └──────────────────────────────────────────────┘                │
                         │                                              │
                         ▼                                              │
                    ┌─────────┐                                        │
                    │  idle   │────────────────────────────────────────┘
                    └─────────┘  (via stop() / auto-transition)

  Legend:
    ────────────►  Initial entry
    ──►           State transition
    ◄──           Return to idle
```

### Transition Summary Table

| From | To | Trigger | Method | Side Effects |
|---|---|---|---|---|
| `idle` | `working` | User starts work | `startWork()` | `sessionStartTime` recorded |
| `idle` | `shortBreak` / `longBreak` | User starts break / auto-start | `startBreak()` | Break type determined by `currentRound` vs `roundsBeforeLongBreak` |
| `working` | paused | User pauses | `togglePause()` → `pause()` | `pausedTimeRemaining` captured |
| `shortBreak`/`longBreak` | paused | User pauses | `togglePause()` → `pause()` | `pausedTimeRemaining` captured |
| paused | `working` | User resumes | `togglePause()` → `resume()` | New timer created |
| `working` | `idle` | User stops | `stop()` | Session saved, `completed = (timeRemaining == 0)` |
| `working` | `idle` | Timer hits 0 | `complete()` | Session saved (`completed: true`), `currentRound += 1`, `didCompleteWork = true`, `pendingBreak = true` (if no auto-start) |
| `working` | next phase | User skips | `skip()` | Session saved (`completed: true`), `currentRound += 1`, transition to break or idle |
| `shortBreak`/`longBreak` | `idle` | Timer hits 0 | `complete()` | Session saved, `currentRound = 1` if longBreak, auto-start work if enabled |
| `shortBreak`/`longBreak` | `idle`/`working` | User skips | `skip()` | Session saved, `currentRound = 1` if longBreak, auto-start work if enabled |
| any active | `idle` | User stops | `stop()` | Session saved with `completed = (timeRemaining == 0)` |

---

## Break Selection Logic

The decision between short break and long break is made in `startBreak()` and `complete()`:

```swift
let isLongBreak = currentRound > config.roundsBeforeLongBreak
```

### Decision Table

| Condition | Break Type | Duration |
|---|---|---|
| `currentRound <= roundsBeforeLongBreak` | Short break | `config.shortBreakDuration` |
| `currentRound > roundsBeforeLongBreak` | Long break | `config.longBreakDuration` |

### Round Progression Example

With `roundsBeforeLongBreak = 4` (default):

| Round | After work completes | Break type |
|---|---|---|
| 1 → 2 | `currentRound` becomes 2 | Short (2 ≤ 4) |
| 2 → 3 | `currentRound` becomes 3 | Short (3 ≤ 4) |
| 3 → 4 | `currentRound` becomes 4 | Short (4 ≤ 4) |
| 4 → 5 | `currentRound` becomes 5 | Long (5 > 4) |
| After long break | `currentRound` resets to 1 | Cycle restarts |

> **Important:** `currentRound` is incremented **after** work completes but **before** the break type is determined. This means the 5th round triggers a long break. After a long break completes (or is skipped), `currentRound` resets to 1.

---

## Auto-Start Behavior

Two independent configuration flags control automatic transitions:

### `autoStartBreak` (default: `false`)

When work completes (via `complete()` or `skip()`):
- **`true`:** Automatically calls `startBreak()` — the break begins immediately
- **`false:** Sets `pendingBreak = true`, transitions to `.idle`, and waits for user to manually start the break

### `autoStartWork` (default: `false`)

When a break completes (via `complete()` or `skip()`):
- **`true`:** Automatically calls `startWork()` — the next work session begins immediately
- **`false`:** Transitions to `.idle` and waits for user to manually start work

### Interaction with `didCompleteWork`

When `autoStartBreak` is `false`, the `complete()` method sets `didCompleteWork = true`. This flag is observed by `NotchViewModel` via a Combine subscription:

```swift
timer.$didCompleteWork
    .filter { $0 == true }
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.triggerBreakPrompt()
    }
```

This triggers the break prompt UI (shown for 5 seconds, auto-dismissed). The `pendingBreak` flag causes the expanded view's start button to show "开始休息" (Start Break) instead of "开始专注" (Start Focus).
