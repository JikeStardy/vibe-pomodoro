# Coding Conventions

> Derived from analysis of the NotchPomodoro codebase. All conventions below are observed patterns in the existing source code and should be followed for new contributions.

---

## A. Swift Style

### A.1 Class Finality

Use `final class` for all non-inheritable classes. The codebase contains no open or subclassable classes except where inheritance from AppKit/SwiftUI base classes is required.

```swift
// Correct
final class HookSocketServer: @unchecked Sendable { ... }
final class NotchWindowController: NSWindowController { ... }
final class NotchDisplayManager { ... }
final class NotchViewModel: ObservableObject { ... }
final class NotchWindow: NSPanel { ... }

// Exception: ObservableObject managers use plain class
class ClaudeSessionManager: ObservableObject { ... }
class PomodoroTimer: ObservableObject { ... }
class AppDelegate: NSObject, NSApplicationDelegate { ... }
```

> **Convention:** `final` is used for infrastructure classes (socket server, window controllers, display manager). ObservableObject managers that serve as injected dependencies use plain `class` to allow potential mocking in tests.

### A.2 Enum as Namespace

Use `enum` (not `struct` or `class`) as a namespace for static utility methods. An enum with no cases cannot be instantiated, which is the intended behavior.

```swift
enum HookInstaller {
    // MARK: - Claude Code Version Detection
    enum ClaudeCodeVersion: String { ... }

    // MARK: - Paths
    struct ClaudePaths { ... }
    struct CodexPaths { ... }

    static func installIfNeeded() { ... }
    static func isInstalled() -> Bool { ... }
    static func uninstall() { ... }
}
```

### A.3 Thread Safety Annotation

Use `@unchecked Sendable` for classes that manage their own thread safety:

```swift
final class HookSocketServer: @unchecked Sendable {
    private let lock = NSLock()
    private let socketQueue = DispatchQueue(label: "com.notchpomodoro.socket", qos: .userInitiated)
    // ...
}
```

Use `@unchecked Sendable` for type-erasing wrappers with known internal mutability:

```swift
struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any
}
```

### A.4 Combine ObservableObject Pattern

Combine `ObservableObject` with `@Published` for reactive state binding to SwiftUI:

```swift
class ClaudeSessionManager: ObservableObject {
    @Published var currentPhase: ClaudeSessionPhase = .idle
    @Published var activeSessionId: String? = nil
    @Published var projectName: String? = nil
    @Published var lastToolName: String? = nil
    @Published var isSubagentActive: Bool = false
}
```

Private `@Published` properties use `private(set)` to restrict external writes:

```swift
@Published private(set) var isTimerActive: Bool = false
@Published private(set) var isReady: Bool = false
@Published private(set) var displayState: NotchDisplayState = .idle
```

### A.5 Subscription Storage

Use `Set<AnyCancellable>` named `cancellables` for storing Combine subscriptions:

```swift
private var cancellables = Set<AnyCancellable>()

// Store subscriptions
server.eventSubject
    .receive(on: DispatchQueue.main)
    .sink { [weak self] event in
        self?.processEvent(event)
    }
    .store(in: &cancellables)
```

### A.6 Computed Properties for Derived State

Prefer computed properties over stored properties for derived state:

```swift
// PomodoroTimer
var totalTime: Int {
    switch status {
    case .working: return config.workDuration
    case .shortBreak: return config.shortBreakDuration
    case .longBreak: return config.longBreakDuration
    default: return config.workDuration
    }
}

var progress: Double {
    guard totalTime > 0 else { return 0 }
    return 1.0 - (Double(timeRemaining) / Double(totalTime))
}

var formattedTime: String {
    let minutes = timeRemaining / 60
    let seconds = timeRemaining % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

// PermissionContext
var formattedInput: String? {
    guard let input = toolInput else { return nil }
    if toolName == "Bash", let command = input["command"]?.value as? String { ... }
    // ...
}
```

### A.7 Custom Equatable for Enums with Associated Values

Enums with associated values implement custom `Equatable` to enable `removeDuplicates()` in Combine pipelines:

```swift
enum ClaudeSessionPhase: Sendable, Equatable {
    case idle
    case processing
    case waitingForInput
    case waitingForResponse(String?)
    case waitingForApproval(PermissionContext)
    case compacting
    case error(String)

    static func == (lhs: ClaudeSessionPhase, rhs: ClaudeSessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.processing, .processing): return true
        case (.waitingForInput, .waitingForInput): return true
        case (.waitingForResponse(let a), .waitingForResponse(let b)): return a == b
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        case (.compacting, .compacting): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
```

### A.8 MARK Comments

Use `// MARK: -` comments to organize code sections within types:

```swift
class PomodoroTimer: ObservableObject {
    // MARK: - Published Properties
    @Published var status: PomodoroStatus = .idle

    // MARK: - Configuration
    @Published var config: PomodoroConfig { ... }

    // MARK: - Private Properties
    private var timer: Timer?

    // MARK: - Computed Properties
    var progress: Double { ... }

    // MARK: - Initialization
    init() { ... }

    // MARK: - Public Methods
    func startWork() { ... }

    // MARK: - Private Methods
    private func tick() { ... }

    // MARK: - Persistence
    private func saveConfig() { ... }
}
```

---

## B. Naming Conventions

### B.1 Types

Use **PascalCase** for all type names:

| Type | Example |
|---|---|
| Structs | `PomodoroConfig`, `HookEvent`, `HookResponse`, `PermissionContext`, `PendingPermission`, `AnyCodable` |
| Enums | `PomodoroStatus`, `ClaudeSessionPhase`, `NotchDisplayState`, `NotchShape` |
| Classes | `NotchViewModel`, `HookSocketServer`, `ClaudeSessionManager`, `PomodoroTimer`, `NotchWindowController` |
| Protocols | *(none currently — protocol-oriented patterns use structs)* |

### B.2 Properties and Methods

Use **camelCase** for all properties and methods:

| Category | Examples |
|---|---|
| Published properties | `currentPhase`, `activeSessionId`, `projectName`, `lastToolName`, `isSubagentActive` |
| Private state | `serverSocket`, `acceptSource`, `socketQueue`, `autoDismissWorkItem` |
| Public methods | `approvePermission()`, `denyPermission()`, `dismissNotification()`, `installIfNeeded()`, `startWork()`, `togglePause()` |
| Private methods | `processEvent()`, `resetSession()`, `scheduleAutoDismiss()`, `startServer()`, `handleClient()` |
| Computed properties | `formattedTime`, `progress`, `statusText`, `displayState`, `pendingCount`, `needsAttention` |

### B.3 Enum Cases

Use **camelCase** for enum cases:

```swift
enum PomodoroStatus: String, Codable {
    case idle = "idle"
    case working = "working"
    case shortBreak = "shortBreak"
    case longBreak = "longBreak"
    case paused = "paused"
}

enum ClaudeSessionPhase: Sendable, Equatable {
    case idle
    case processing
    case waitingForInput
    case waitingForResponse(String?)
    case waitingForApproval(PermissionContext)
    case compacting
    case error(String)
}

enum NotchDisplayState: Equatable {
    case idle
    case compact
    case expanded
    case settings
    case breakPrompt
    case claudeApproval
    case claudeNotification
}
```

### B.4 Private Properties

Private properties use **descriptive names** rather than abbreviated prefixes:

```swift
// Good: descriptive names
private var timer: Timer?
private var startDate: Date?
private var sessionStartTime: Date?
private var autoDismissWorkItem: DispatchWorkItem?
private var breakPromptDismissWork: DispatchWorkItem?

// Good: type-derived names
private let server: HookSocketServer
private let lock = NSLock()
private let socketQueue = DispatchQueue(...)
```

### B.5 Computed Property Naming

Computed properties use **descriptive names** that convey intent:

| Property | Type | Returns |
|---|---|---|
| `formattedTime` | `String` | Time as `"MM:SS"` |
| `progress` | `Double` | Progress as 0.0–1.0 |
| `statusText` | `String` | Human-readable status label |
| `totalTime` | `Int` | Total seconds for current phase |
| `needsAttention` | `Bool` | Whether user action is needed |
| `isWaitingForApproval` | `Bool` | Phase check |
| `isNotification` | `Bool` | Whether phase is a notification type |
| `isActive` | `Bool` | Whether phase represents active work |
| `formattedInput` | `String?` | Tool input formatted for display |
| `expectsResponse` | `Bool` | Whether event needs a permission response |
| `windowSize` | `NSSize` | Window dimensions for display state |

### B.6 Constant Naming

Static constants use **camelCase** (Swift convention, not SCREAMING_SNAKE_CASE):

```swift
struct ClaudePaths {
    static let claudeDir = ...
    static let hooksDir = ...
    static let settingsFile = ...
    static let hookScript = ...
}

// Within a class
private static let socketPath = "/tmp/notch-pomodoro-claude.sock"
private static let bufferSize = 131_072
private static let pollTimeout: TimeInterval = 0.5
private let maxCacheSize = 50
```

Use numeric literals with **underscore separators** for readability: `131_072`, `0o755`, `0o600`.

---

## C. Architecture Patterns

### C.1 MVVM

`NotchViewModel` bridges `PomodoroTimer` and `ClaudeSessionManager` to SwiftUI views:

```
┌─────────────────────────────────────────────────────────────┐
│                        MVVM Pattern                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐     ┌─────────────────┐               │
│  │  PomodoroTimer   │     │ ClaudeSession   │               │
│  │  (ObservableObj) │     │ Manager         │               │
│  │                  │     │ (ObservableObj) │               │
│  └────────┬────────┘     └────────┬────────┘               │
│           │                       │                         │
│           │    Combine pipelines  │                         │
│           ▼                       ▼                         │
│  ┌──────────────────────────────────────────┐               │
│  │            NotchViewModel                │               │
│  │            (ObservableObject)            │               │
│  │                                          │               │
│  │  - merges timer + claude state           │               │
│  │  - derives displayState (priority FSM)  │               │
│  │  - manages hover/pin/settings state      │               │
│  └──────────────────┬───────────────────────┘               │
│                     │                                       │
│                     │ @Published displayState              │
│                     ▼                                       │
│  ┌──────────────────────────────────────────┐               │
│  │              NotchView                   │               │
│  │              (SwiftUI View)              │               │
│  └──────────────────────────────────────────┘               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

The ViewModel uses `Publishers.CombineLatest4` to merge 8 input signals into a single `displayState`:

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

### C.2 Observer / Reactive Pattern

| Component | Pattern | Implementation |
|---|---|---|
| `HookSocketServer` | Event Bus | `PassthroughSubject<HookEvent, Never>` |
| `ClaudeSessionManager` | Subscriber | `.sink { event in processEvent(event) }` |
| `NotchViewModel` | Subscriber + Merger | `Publishers.CombineLatest4(...)` |
| `PomodoroTimer` | Publisher | `@Published` properties observed by ViewModel |
| `NotchWindowController` | Subscriber | `viewModel.$displayState.sink { repositionWindow }` |

### C.3 Singleton

```swift
final class HookSocketServer: @unchecked Sendable {
    static let shared = HookSocketServer()
    private init() {}
}
```

**Justification:** There is exactly one Unix socket endpoint. A singleton ensures:
- Only one server listens on `/tmp/notch-pomodoro-claude.sock`.
- `ClaudeSessionManager` can call `respondToPermission` without dependency injection.
- The Python script always connects to the same endpoint.

### C.4 State Machine

`ClaudeSessionPhase` is a state machine with associated values:

```swift
enum ClaudeSessionPhase: Sendable, Equatable {
    case idle                           // No active session
    case processing                     // Claude is working
    case waitingForInput                // Claude finished, awaiting user
    case waitingForResponse(String?)    // AskUserQuestion, awaiting terminal reply
    case waitingForApproval(PermissionContext)  // Permission request, awaiting user decision
    case compacting                     // Context compaction in progress
    case error(String)                 // StopFailure or other error
}
```

Computed properties (`needsAttention`, `isNotification`, `isActive`, `isWaitingForApproval`) provide phase queries for the ViewModel and views.

### C.5 Repository Pattern (Self-Persisting)

`PomodoroTimer` handles its own `UserDefaults` persistence — there is no separate repository layer:

```swift
private func saveConfig() {
    if let data = try? JSONEncoder().encode(config) {
        UserDefaults.standard.set(data, forKey: "pomodoro_config")
    }
}

private func loadConfig() {
    if let data = UserDefaults.standard.data(forKey: "pomodoro_config"),
       let loaded = try? JSONDecoder().decode(PomodoroConfig.self, from: data) {
        config = loaded
    }
}
```

### C.6 Strategy Pattern

Break duration selection is a strategy based on round count:

```swift
func startBreak() {
    let isLongBreak = currentRound > config.roundsBeforeLongBreak
    status = isLongBreak ? .longBreak : .shortBreak
    timeRemaining = isLongBreak ? config.longBreakDuration : config.shortBreakDuration
}
```

---

## D. UI Conventions

### D.1 Localization

The development region is **zh_CN** (Chinese Simplified), as specified in `Info.plist`:

```xml
<key>CFBundleDevelopmentRegion</key>
<string>zh_CN</string>
```

All user-facing strings are in Chinese:

```swift
Text("专注工作")              // "Focus work"
Text("短休息")                // "Short break"
Text("开始休息")              // "Start break"
Text("允许")                  // "Allow"
Text("拒绝")                  // "Deny"
Text("Claude Code 请求权限")   // "Claude Code requests permission"
Text("休息一下吧")             // "Take a break"
```

Comments in model and controller files are also in Chinese.

### D.2 Buttons in Non-Activating Panels

The notch window uses `.nonactivatingPanel` style mask. To ensure buttons receive clicks, use `Button(action:).buttonStyle(.plain)`:

```swift
Button(action: { claudeManager.approvePermission() }) {
    HStack(spacing: 5) {
        Image(systemName: "checkmark")
        Text("允许")
    }
    .foregroundColor(.white)
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
    .background(Capsule().fill(Color(red: 0.3, green: 0.75, blue: 0.45)))
}
.buttonStyle(.plain)
```

The custom `NotchWindow` (subclass of `NSPanel`) overrides `canBecomeKey` to `true`:

```swift
final class NotchWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }
}
```

### D.3 Tap Gesture Guards

Parent `.onTapGesture` handlers guard against interactive child states:

```swift
.onTapGesture {
    guard viewModel.displayState != .settings,
          viewModel.displayState != .claudeApproval,
          viewModel.displayState != .claudeNotification else { return }
    withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
        viewModel.toggleExpansion()
    }
}
```

### D.4 Physical Notch Zone

The physical notch area is a **forbidden content spacer** — no UI content is ever rendered in the center zone. The spacer width is configurable:

```swift
// Default: 240pt (configurable 200–300pt)
var notchGapWidth: Int = 240

// In compact content:
Spacer()
    .frame(width: CGFloat(timer.config.notchGapWidth))
```

Settings UI allows adjustment in 10pt increments:

```swift
settingsRow(title: "刘海宽度", value: timer.config.notchGapWidth, unit: "pt") {
    timer.config.notchGapWidth = max(200, timer.config.notchGapWidth - 10)
} increment: {
    timer.config.notchGapWidth = min(300, timer.config.notchGapWidth + 10)
}
```

### D.5 Window Sizing Per Display State

Each `NotchDisplayState` has a corresponding `windowSize`:

```swift
var windowSize: NSSize {
    switch self {
    case .idle:                 return NSSize(width: 400, height: 38)
    case .compact:              return NSSize(width: 400, height: 38)
    case .expanded:             return NSSize(width: 360, height: 240)
    case .settings:             return NSSize(width: 380, height: 420)
    case .breakPrompt:          return NSSize(width: 360, height: 180)
    case .claudeApproval:       return NSSize(width: 400, height: 260)
    case .claudeNotification:   return NSSize(width: 360, height: 140)
    }
}
```

Windows are positioned at the top of the screen, centered horizontally, growing downward:

```swift
let originX = screenFrame.midX - size.width / 2
let originY = screenFrame.maxY - size.height
```

### D.6 Spring Animations

Consistent spring animation parameters throughout the UI:

```swift
.animation(.spring(response: 0.32, dampingFraction: 0.72), value: viewModel.displayState)
```

| Parameter | Value | Effect |
|---|---|---|
| `response` | 0.32 | Quick settle time |
| `dampingFraction` | 0.72 | Slight bounce, not underdamped |

Window resizing uses a custom timing function:

```swift
ctx.duration = 0.32
ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.32, 1.0)
```

### D.7 Hover Debounce

Hover state is debounced with asymmetric timing:

```swift
private func scheduleHover(_ hovering: Bool) {
    hoverDebounce?.cancel()
    let delay: Double = hovering ? 0.05 : 0.30
    let work = DispatchWorkItem { [viewModel] in
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            viewModel.isHovering = hovering
        }
    }
    hoverDebounce = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
}
```

| Direction | Delay | Rationale |
|---|---|---|
| Enter | 0.05s | Fast response — avoid feeling sluggish |
| Leave | 0.30s | Slow — let user move mouse within the expanded panel without collapsing |

### D.8 Cold Start Protection

A 0.5-second delay prevents accidental expansion during cold start:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    self?.isHovering = false
    self?.isReady = true
}
```

Before `isReady` becomes `true`, hover does not trigger expansion:

```swift
if pinned || (hovering && ready) { return .expanded }
```

### D.9 Color Tokens

Claude-related colors are defined as computed properties:

```swift
private var claudeAmberColor: Color  { Color(red: 0.95, green: 0.7, blue: 0.2) }
private var claudeGreenColor: Color   { Color(red: 0.4, green: 0.86, blue: 0.62) }
private var claudeRedColor: Color     { Color(red: 0.85, green: 0.3, blue: 0.3) }
```

Pomodoro status colors are context-dependent:

```swift
private var accentColor: Color {
    switch timer.status {
    case .working:    return Color(red: 0.99, green: 0.55, blue: 0.18)  // tomato/saffron
    case .shortBreak: return Color(red: 0.40, green: 0.86, blue: 0.62)  // mint
    case .longBreak:  return Color(red: 0.55, green: 0.70, blue: 1.00)  // cool blue
    case .paused:     return Color(red: 0.80, green: 0.80, blue: 0.85)
    case .idle:       return Color(red: 0.92, green: 0.92, blue: 0.94)
    }
}
```

### D.10 NotchShape

The custom `Shape` draws a top-flat, bottom-rounded rectangle that visually continues the hardware notch:

```swift
struct NotchShape: Shape {
    var bottomCornerRadius: CGFloat = 22
    var topCornerRadius: CGFloat = 0  // Always flat top (seamless with hardware)
}
```

`bottomCornerRadius` varies by display state (18 for compact, 24 for expanded).

---

## E. Error Handling

### E.1 Python Script — Silent Failure

All errors in the Python hook script are caught and swallowed:

```python
def send_event(state):
    try:
        # socket operations
        ...
    except (socket.error, OSError, json.JSONDecodeError):
        return None  # Silent failure — never crash Claude Code
```

| Error Scenario | Handling |
|---|---|
| Socket connection refused (app not running) | `send_event` returns `None`, script exits 0 |
| Socket timeout (300s, no permission response) | `send_event` returns `None`, script exits 0 |
| JSON decode failure on response | `send_event` returns `None`, script exits 0 |
| stdin JSON decode failure | `sys.exit(1)` |

### E.2 Swift Socket Server — Graceful Degradation

```swift
// Non-blocking reads with retry on EAGAIN
while Date() < deadline {
    let bytesRead = read(fd, &buffer, Self.bufferSize)
    if bytesRead > 0 {
        data.append(contentsOf: buffer[0..<bytesRead])
        if let lastByte = data.last, lastByte == UInt8(ascii: "}") { break }
    } else if bytesRead == 0 {
        break  // Connection closed
    } else if errno == EAGAIN || errno == EWOULDBLOCK {
        usleep(10_000)  // 10ms sleep before retry
        continue
    } else {
        break  // Error
    }
}

// Decode failure
guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
    print("[HookSocketServer] Failed to decode event from \(data.count) bytes")
    return
}
```

### E.3 Permission Response — Default Behavior

If no response is received (app crashed, socket timeout):

```python
# No response → exit 0 (Claude uses default behavior)
sys.exit(0)
```

Claude Code then proceeds with its built-in permission prompt. This ensures the system is **fail-safe** — the worst case is falling back to Claude's native UI.

### E.4 Swift Installation Errors

Hook installation failures are logged but do not crash the app:

```swift
static func installIfNeeded() {
    do {
        try installHookScript()
        try registerInSettings()
        print("[HookInstaller] Hook installed successfully at \(...)")
    } catch {
        print("[HookInstaller] Installation failed: \(error.localizedDescription)")
    }
}
```

### E.5 File Operations

File operations use `try?` to silently ignore failures:

```swift
try? fm.removeItem(at: ClaudePaths.hookScript)
try? updatedData.write(to: ClaudePaths.settingsFile)
if let data = try? Data(contentsOf: ClaudePaths.settingsFile) { ... }
```

---

## F. Persistence

### F.1 UserDefaults Only

The app uses **only `UserDefaults`** for persistence — no Core Data, no SQLite, no file-based storage:

```swift
private func saveConfig() {
    if let data = try? JSONEncoder().encode(config) {
        UserDefaults.standard.set(data, forKey: "pomodoro_config")
    }
}

private func saveSession(_ session: PomodoroSession) {
    var sessions = loadSessions()
    sessions.append(session)
    if sessions.count > 100 {
        sessions = Array(sessions.suffix(100))
    }
    if let data = try? JSONEncoder().encode(sessions) {
        UserDefaults.standard.set(data, forKey: "pomodoro_sessions")
    }
}
```

| Key | Type | Content |
|---|---|---|
| `"pomodoro_config"` | `Data` (JSON) | `PomodoroConfig` struct |
| `"pomodoro_sessions"` | `Data` (JSON) | `[PomodoroSession]` array |

### F.2 JSON Encoding

All persisted data uses `Codable` with `JSONEncoder` / `JSONDecoder`:

```swift
// Encode
if let data = try? JSONEncoder().encode(config) { ... }

// Decode
if let data = UserDefaults.standard.data(forKey: "pomodoro_config"),
   let loaded = try? JSONDecoder().decode(PomodoroConfig.self, from: data) { ... }
```

### F.3 Session History Cap

Session history is capped at **100 entries** to prevent unbounded growth:

```swift
private func saveSession(_ session: PomodoroSession) {
    var sessions = loadSessions()
    sessions.append(session)
    if sessions.count > 100 {
        sessions = Array(sessions.suffix(100))
    }
    // ...
}
```

### F.4 Config Auto-Save

Configuration changes trigger automatic persistence via `didSet`:

```swift
@Published var config: PomodoroConfig {
    didSet {
        saveConfig()
    }
}
```

Any mutation to `config` (e.g., `timer.config.workDuration = 1500`) triggers a save.

### F.5 Settings File (External)

Claude Code and Codex CLI settings are managed as external JSON files:

| File | Format | Library |
|---|---|---|
| `~/.claude/settings.json` | JSON (pretty-printed, sorted keys) | `JSONSerialization` |
| `~/.codex/hooks.json` | JSON (pretty-printed, sorted keys) | `JSONSerialization` |

Written with `.atomic` option and `[.prettyPrinted, .sortedKeys]` formatting:

```swift
let updatedData = try JSONSerialization.data(
    withJSONObject: json,
    options: [.prettyPrinted, .sortedKeys]
)
try updatedData.write(to: ClaudePaths.settingsFile, options: .atomic)
```

---

## G. Security

### G.1 No App Sandbox

The app is explicitly **not sandboxed**, as required for:

- Writing to `~/.claude/` and `~/.codex/` directories
- Creating a Unix domain socket in `/tmp/`
- Running Python scripts from arbitrary paths

```xml
<!-- NotchPomodoro.entitlements -->
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.notification</key>
<true/>
```

### G.2 Socket File Permissions

The Unix domain socket is created with `chmod 600` (owner read/write only):

```swift
chmod(Self.socketPath, 0o600)
```

This prevents other users on the system from connecting to the socket and injecting events.

### G.3 Hook Script Permissions

The installed Python script is made executable with `chmod 755`:

```swift
try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ClaudePaths.hookScript.path)
```

### G.4 No Hardcoded Secrets

The codebase contains **no hardcoded secrets, API keys, or credentials**. All configuration is user-supplied through the settings UI.

### G.5 SO_NOSIGPIPE

Client sockets are configured with `SO_NOSIGPIPE` to prevent signal-based crashes when writing to a closed socket:

```swift
var nosigpipe: Int32 = 1
setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
```

### G.6 Atomic File Writes

External settings files are written atomically to prevent corruption:

```swift
try updatedData.write(to: ClaudePaths.settingsFile, options: .atomic)
try updatedData.write(to: CodexPaths.hooksFile, options: .atomic)
```

---

## H. File Organization

### H.1 Directory Structure

```
Sources/
├── App/
│   ├── Info.plist                      # Bundle configuration (zh_CN, LSUIElement)
│   ├── NotchPomodoro.entitlements      # App sandbox disabled, notifications enabled
│   └── NotchPomodoroApp.swift          # @main entry point, AppDelegate
├── Models/
│   ├── ClaudeModels.swift              # HookEvent, HookResponse, ClaudeSessionPhase, PermissionContext, AnyCodable
│   ├── PomodoroModels.swift            # PomodoroStatus, PomodoroConfig, PomodoroSession
│   └── PomodoroTimer.swift             # PomodoroTimer (ObservableObject, timer logic + persistence)
├── Controllers/
│   ├── NotchDisplayManager.swift       # Multi-display notch window management
│   └── NotchWindowController.swift      # NotchViewModel, NotchWindowController, NotchWindow, NotchRootView
├── Views/
│   ├── NotchView.swift                 # Main notch UI (1159 lines, all display states)
│   └── SettingsView.swift              # Standalone settings view (legacy, mostly superseded by inline settings)
├── Services/
│   ├── ClaudeSessionManager.swift       # Claude session state manager (ObservableObject)
│   └── Hooks/
│       ├── HookInstaller.swift          # Hook installation/uninstallation (namespace enum)
│       └── HookSocketServer.swift       # Unix socket server (singleton)
└── Resources/
    ├── AppIcon.icns                    # Application icon
    └── notch-pomodoro-hook.py          # Standalone Python hook script (also embedded in HookInstaller)
```

### H.2 Layer Responsibilities

| Layer | Directory | Responsibility |
|---|---|---|
| App Entry | `Sources/App/` | `@main` struct, `AppDelegate`, lifecycle, launch sequence |
| Models | `Sources/Models/` | Data structures, state enums, timer logic, persistence |
| Controllers | `Sources/Controllers/` | Window management, view model, display state coordination |
| Views | `Sources/Views/` | SwiftUI views, shapes, UI components |
| Services | `Sources/Services/` | Business logic (hook system, session management) |
| Resources | `Sources/Resources/` | Bundled resources (Python script, app icon) |

### H.3 App Launch Sequence

The launch sequence in `AppDelegate.applicationDidFinishLaunching` follows a strict order:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // 1. Request notification permission (delayed 1s for bundle readiness)
    requestNotificationPermission()

    // 2. Install Claude Code hook
    HookInstaller.installIfNeeded()

    // 3. Install Codex CLI hook
    HookInstaller.installCodexIfNeeded()

    // 4. Start socket server
    HookSocketServer.shared.start()

    // 5. Initialize Claude session manager (subscribes to socket server)
    claudeManager = ClaudeSessionManager()

    // 6. Initialize pomodoro timer
    timer = PomodoroTimer()

    // 7. Initialize display manager (creates notch windows)
    displayManager = NotchDisplayManager(timer: timer, claudeManager: claudeManager!)
}
```

| Step | Component | Why This Order |
|---|---|---|
| 1 | Notification permission | Must be ready before timer completes |
| 2 | Hook installation | Must be in place before Claude Code runs |
| 3 | Codex installation | Same — pre-installs for when Codex runs |
| 4 | Socket server | Must be listening before any hook fires |
| 5 | Session manager | Must subscribe before events arrive |
| 6 | Timer | Loads persisted config |
| 7 | Display manager | Creates windows, requires timer + manager |

### H.4 Termination Sequence

```swift
func applicationWillTerminate(_ notification: Notification) {
    HookSocketServer.shared.stop()  // Close socket, cleanup pending permissions
    timer.stop()                     // Save current session, invalidate timer
}
```

### H.5 Package Configuration

```swift
// Package.swift
let package = Package(
    name: "NotchPomodoro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NotchPomodoro",
            path: "Sources",
            exclude: ["App/Info.plist", "App/NotchPomodoro.entitlements"],
            resources: [.process("Resources")]
        )
    ]
)
```

- **Minimum deployment:** macOS 13.0 (Ventura) — required for `NSHostingController.sizingOptions` and modern SwiftUI APIs.
- **Single executable target:** all sources are in one target; no separate library/test modules.
- **Resources:** the `Resources/` directory is processed by SPM (`.process`), making `notch-pomodoro-hook.py` and `AppIcon.icns` available as bundle resources. However, the runtime hook script is generated from the embedded string literal in `HookInstaller`, not loaded from the bundle.
