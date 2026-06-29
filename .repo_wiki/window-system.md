# Window System & Display Management

> **Source files:**
> - `Sources/Controllers/NotchWindowController.swift` (328 lines)
> - `Sources/Controllers/NotchDisplayManager.swift` (106 lines)

This document describes how NotchPomodoro creates, positions, and manages the notch overlay windows across single and multi-display configurations.

---

## Table of Contents

- [NotchDisplayState](#notchdisplaystate)
- [NotchViewModel](#notchviewmodel)
- [NotchWindowController](#notchwindowcontroller)
- [NotchWindow](#notchwindow)
- [NotchRootView](#notchrootview)
- [NotchDisplayManager](#notchdisplaymanager)
- [State Priority Enforcement](#state-priority-enforcement)
- [Cold-Start Guard](#cold-start-guard)

---

## NotchDisplayState

| Attribute | Value |
|---|---|
| **Kind** | `enum` |
| **Conformance** | `Equatable` |
| **Source** | `NotchWindowController.swift:8` |

Defines all visual states the notch window can assume. Each case carries a corresponding window size via the `windowSize` computed property.

### Cases and Window Sizes

| Case | Width | Height | Description |
|---|---|---|---|
| `idle` | 400 | 38 | Timer idle, minimal indicator |
| `compact` | 400 | 38 | Timer running, compact info bar |
| `expanded` | 360 | 240 | Hover/click expanded, full control panel |
| `settings` | 380 | 420 | In-notch settings panel |
| `breakPrompt` | 360 | 180 | Break prompt popup (half-height) |
| `claudeApproval` | 400 | 260 | Claude Code permission request UI |
| `claudeNotification` | 360 | 140 | Claude Code task completion/error notification |

```swift
var windowSize: NSSize {
    switch self {
    case .idle:               return NSSize(width: 400, height: 38)
    case .compact:            return NSSize(width: 400, height: 38)
    case .expanded:           return NSSize(width: 360, height: 240)
    case .settings:           return NSSize(width: 380, height: 420)
    case .breakPrompt:        return NSSize(width: 360, height: 180)
    case .claudeApproval:     return NSSize(width: 400, height: 260)
    case .claudeNotification: return NSSize(width: 360, height: 140)
    }
}
```

### Window Size Diagram

```
  Width →  360    380    400
           │      │      │
           │      │    ┌──────────────────┐ 38pt   idle / compact
           │      │    └──────────────────┘
           │      │    ┌──────────────────┐ 260pt  claudeApproval
           │      │    └──────────────────┘
           ┌──────┼────┼──────────────────┐ 140pt  claudeNotification
           │      │    │                  │
           └──────┼────┼──────────────────┘
           ┌──────┼────┼──────────────────┐ 180pt  breakPrompt
           │      │    │                  │
           └──────┼────┼──────────────────┘
           ┌──────┼────┼──────────────────┐ 240pt  expanded
           │      │    │                  │
           │      │    │                  │
           └──────┼────┼──────────────────┘
                  ┌────┼──────────────────┐ 420pt  settings
                  │    │                  │
                  │    │                  │
                  │    │                  │
                  │    │                  │
                  └────┼──────────────────┘
```

---

## NotchViewModel

| Attribute | Value |
|---|---|
| **Kind** | `final class` |
| **Conformance** | `ObservableObject` |
| **Source** | `NotchWindowController.swift:41` |

The shared state object observed by both the SwiftUI views and the `NotchWindowController`. It derives the `displayState` from multiple input signals via a Combine pipeline.

### Published Properties

| Property | Type | Default | Access | Description |
|---|---|---|---|---|
| `connectedDisplays` | `[String]` | `[]` | read/write | List of connected display names (set by `NotchDisplayManager`) |
| `isPinnedExpanded` | `Bool` | `false` | read/write | User clicked to pin expanded state |
| `isHovering` | `Bool` | `false` | read/write | Mouse is hovering over the notch (debounced) |
| `showSettings` | `Bool` | `false` | read/write | Settings panel is open (highest priority) |
| `isTimerActive` | `Bool` | `false` | read-only | Timer is in a non-idle state |
| `isReady` | `Bool` | `false` | read-only | Cold-start guard flag (set after 0.5s delay) |
| `displayState` | `NotchDisplayState` | `.idle` | read-only | Derived display state (drives window size & layout) |
| `showBreakPrompt` | `Bool` | `false` | read/write | Break prompt is showing (auto-dismissed after 5s) |
| `claudePhase` | `ClaudeSessionPhase` | `.idle` | read/write | Current Claude session phase |

### Non-Published State

| Property | Type | Description |
|---|---|---|
| `claudeManager` | `ClaudeSessionManager` | Reference to Claude session manager (let) |
| `cancellables` | `Set<AnyCancellable>` | Combine subscription bag |
| `breakPromptDismissWork` | `DispatchWorkItem?` | DispatchWorkItem for 5-second auto-dismiss |

### Combine Subscriptions

The `init(timer:claudeManager:)` sets up four subscription pipelines:

#### 1. Timer Active State

```swift
timer.$status
    .map { $0 != .idle }
    .removeDuplicates()
    .receive(on: RunLoop.main)
    .assign(to: &$isTimerActive)
```

Maps timer status to a boolean — `true` when timer is running (any non-idle status).

#### 2. Work Completion → Break Prompt

```swift
timer.$didCompleteWork
    .filter { $0 == true }
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.triggerBreakPrompt()
    }
```

When `didCompleteWork` becomes `true`, triggers the break prompt UI.

#### 3. Claude Phase

```swift
claudeManager.$currentPhase
    .receive(on: RunLoop.main)
    .assign(to: &$claudePhase)
```

Mirrors the `ClaudeSessionManager.currentPhase` into the view model.

#### 4. Display State Derivation Pipeline

This is the core state machine that derives `displayState` from all input signals:

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

### State Derivation Priority

See [State Priority Enforcement](#state-priority-enforcement) below.

### Methods

#### `toggleExpansion()`

```swift
func toggleExpansion()
```

Toggles `isPinnedExpanded` between `true` and `false`. Called on tap gesture.

#### `openSettings()`

```swift
func openSettings()
```

Sets `showSettings = true`. Forces the window into `.settings` state (highest priority).

#### `closeSettings()`

```swift
func closeSettings()
```

Sets `showSettings = false`. Returns the window to the normal state derivation pipeline.

#### `collapse()`

```swift
func collapse()
```

Resets all expansion states to `false`:
- `isPinnedExpanded = false`
- `isHovering = false`
- `showSettings = false`

Used by control buttons (e.g., after pressing "Start" to collapse back to compact).

#### `triggerBreakPrompt()`

```swift
func triggerBreakPrompt()
```

Shows the break prompt and schedules auto-dismissal:
1. Sets `showBreakPrompt = true`
2. Cancels any existing `breakPromptDismissWork`
3. Creates a new `DispatchWorkItem` that sets `showBreakPrompt = false`
4. Schedules it via `DispatchQueue.main.asyncAfter(deadline: .now() + 5.0)`

The break prompt automatically disappears after 5 seconds unless manually dismissed.

#### `dismissBreakPrompt()`

```swift
func dismissBreakPrompt()
```

Manually dismisses the break prompt:
1. Cancels the `breakPromptDismissWork`
2. Sets `showBreakPrompt = false`

---

## NotchWindowController

| Attribute | Value |
|---|---|
| **Kind** | `final class` |
| **Conformance** | `NSWindowController` |
| **Source** | `NotchWindowController.swift:160` |

Manages a single notch window on a single display. Responsible for window creation, positioning, and responding to display state changes.

### Properties

| Property | Type | Access | Description |
|---|---|---|---|
| `timer` | `PomodoroTimer` | private | Timer reference |
| `claudeManager` | `ClaudeSessionManager` | private | Claude session manager reference |
| `viewModel` | `NotchViewModel` | internal (let) | The view model for this window |
| `assignedScreen` | `NSScreen` | private (var) | The display this window is attached to |
| `cancellables` | `Set<AnyCancellable>` | private | Combine subscription bag |

### Initialization

```swift
init(timer: PomodoroTimer, claudeManager: ClaudeSessionManager, screen: NSScreen)
```

Creates the window with the following configuration:

#### Window Configuration

```swift
let window = NotchWindow(
    contentRect: NSRect(origin: .zero, size: initialSize),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
```

| Configuration | Value | Reason |
|---|---|---|
| `styleMask` | `[.borderless, .nonactivatingPanel]` | No title bar; doesn't steal app focus |
| `isOpaque` | `false` | Transparent background for custom shape |
| `backgroundColor` | `.clear` | Transparent backing |
| `hasShadow` | `false` | Shadow provided by SwiftUI NotchShape |
| `level` | `statusBar.rawValue + 1` | Above menu bar, visually seamless with hardware notch |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` | Visible in all spaces & full-screen apps; doesn't participate in Cmd-Tab cycle |
| `isMovable` | `false` | Window is programmatically positioned only |
| `hidesOnDeactivate` | `false` | Persists when app loses focus |
| `acceptsMouseMovedEvents` | `true` | Required for hover detection |

#### Initialization Sequence

1. Create `NotchViewModel(timer:claudeManager:)`
2. Store `assignedScreen`
3. Create `NotchWindow` with initial size from `viewModel.displayState.windowSize`
4. Apply window configuration (above)
5. Call `super.init(window:)`
6. `setupHostingController()` — creates `NSHostingController` with `NotchRootView`
7. `bindViewModel()` — subscribes to `displayState` changes for repositioning
8. `repositionWindow(animated: false)` — initial placement
9. Register for `NSApplication.didChangeScreenParametersNotification`

### Setup: Hosting Controller

```swift
private func setupHostingController()
```

Creates an `NSHostingController` with `NotchRootView` as the root view:

- On macOS 13+: sets `hosting.sizingOptions = []` (lets the window drive SwiftUI sizing, not vice versa)
- Sets `hosting.view.wantsLayer = true`
- Sets `hosting.view.layer?.backgroundColor = NSColor.clear.cgColor`
- Sets `hosting.view.autoresizingMask = [.width, .height]`

### Setup: ViewModel Binding

```swift
private func bindViewModel()
```

Subscribes to `viewModel.$displayState`:

```swift
viewModel.$displayState
    .removeDuplicates()
    .dropFirst()  // Initial positioning already done in init
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        self?.repositionWindow(animated: true)
    }
```

Every display state change triggers an animated window reposition.

### Window Repositioning

```swift
private func repositionWindow(animated: Bool)
```

Positions the window so its **top edge** aligns with the **top of the screen** (where the hardware notch is):

```swift
let screenFrame = screen.frame
let originX = screenFrame.midX - size.width / 2
let originY = screenFrame.maxY - size.height
let newFrame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
```

#### Animation

When `animated == true`:

```swift
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.32
    ctx.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22, 0.88, 0.32, 1.0  // strong ease-out / natural spring
    )
    ctx.allowsImplicitAnimation = true
    window.animator().setFrame(newFrame, display: true)
}
```

| Parameter | Value | Description |
|---|---|---|
| Duration | 0.32s | Spring-like animation timing |
| Timing function | Cubic bezier `(0.22, 0.88, 0.32, 1.0)` | Strong ease-out with slight overshoot character |
| Implicit animation | `true` | Enables Core Animation implicit animations |

When `animated == false`: `window.setFrame(newFrame, display: true)` (no animation).

### Screen Parameter Observation

```swift
@objc private func screenParametersChanged()
```

Called when `NSApplication.didChangeScreenParametersNotification` fires (display connect/disconnect/resolution change):

1. Checks if `assignedScreen` is still in `NSScreen.screens`
2. If yes: calls `repositionWindow(animated: false)` to re-align
3. If no: window is orphaned (the `NotchDisplayManager` will clean it up)

### Screen Update

```swift
func updateScreen(_ screen: NSScreen)
```

Updates the `assignedScreen` reference and repositions without animation. Used by `NotchDisplayManager` when the screen object changes after a reconnect (same display name, different `NSScreen` instance).

### Visibility

```swift
func show()   // window?.orderFrontRegardless()
func hide()   // window?.orderOut(nil)
```

---

## NotchWindow

| Attribute | Value |
|---|---|
| **Kind** | `final class` |
| **Conformance** | `NSPanel` |
| **Source** | `NotchWindowController.swift:302` |

Custom `NSPanel` subclass enabling button click responses.

### Overrides

#### `canBecomeKey: Bool`

```swift
override var canBecomeKey: Bool { true }
```

**Critical:** This is `true` so that SwiftUI buttons inside the panel can receive clicks. Without this, a `.nonactivatingPanel` style mask would prevent the panel from becoming the key window, making all buttons unresponsive.

#### `canBecomeMain: Bool`

```swift
override var canBecomeMain: Bool { false }
```

The panel will never become the main window, preserving the app's non-intrusive behavior.

#### `mouseDown(with:)`

```swift
override func mouseDown(with event: NSEvent) {
    makeKey()
    super.mouseDown(with: event)
}
```

On any mouse-down event, the panel calls `makeKey()` to become the key window, ensuring subsequent button presses work. This is necessary because `.nonactivatingPanel` does not automatically make the window key on click.

---

## NotchRootView

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `View` |
| **Source** | `NotchWindowController.swift:317` |

The SwiftUI root container that wraps `NotchView` with proper environment setup.

```swift
struct NotchRootView: View {
    @ObservedObject var timer: PomodoroTimer
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var claudeManager: ClaudeSessionManager

    var body: some View {
        NotchView(timer: timer, viewModel: viewModel, claudeManager: claudeManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}
```

Key behaviors:
- `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` — fills the window, content aligned to top (notch grows downward)
- `.ignoresSafeArea()` — extends to the window edges, ignoring safe area insets (critical for full-bleed notch appearance)

---

## NotchDisplayManager

| Attribute | Value |
|---|---|
| **Kind** | `final class` |
| **Source** | `NotchDisplayManager.swift:5` |

Multi-display coordinator that creates and manages `NotchWindowController` instances for each selected display.

### Properties

| Property | Type | Description |
|---|---|---|
| `timer` | `PomodoroTimer` | Shared timer instance |
| `claudeManager` | `ClaudeSessionManager` | Shared Claude session manager |
| `controllers` | `[String: NotchWindowController]` | Active controllers, keyed by `screen.localizedName` |
| `cancellables` | `Set<AnyCancellable>` | Combine subscription bag |

### Initialization

```swift
init(timer: PomodoroTimer, claudeManager: ClaudeSessionManager)
```

Sets up two observation channels:

1. **Screen parameter changes:** `NSApplication.didChangeScreenParametersNotification` → `refreshWindows()`
2. **Config changes:** `timer.$config.map(\.selectedDisplayNames)` → `refreshWindows()`

Also calls `refreshWindows()` immediately for initial setup.

### `refreshWindows()`

```swift
func refreshWindows()
```

The core reconciliation method. Synchronizes the `controllers` dictionary with the current display configuration:

```
1. Get all connected screens: NSScreen.screens
2. Get their names: connectedNames = screens.map(\.localizedName)
3. Resolve target display names: selectedNames = resolvedSelectedNames()

4. Remove controllers for:
   a. Disconnected screens (name not in connectedNames)
   b. Deselected screens (name not in selectedNames)

5. For each connected screen in selectedNames:
   a. If controller exists → updateScreen(screen)  (screen object may have changed)
   b. If no controller → create new NotchWindowController + show()

6. Update all view models' connectedDisplays
```

### `resolvedSelectedNames()`

```swift
private func resolvedSelectedNames() -> [String]
```

Determines which display names to show the notch on:

| Condition | Result |
|---|---|
| `selectedDisplayNames` is **empty** | Default: built-in display only (or main screen fallback) |
| `selectedDisplayNames` is **non-empty** | The selected names as-is |

**Built-in detection:** `isBuiltInDisplay(_:)` checks if the screen name contains `"Built-in"`, `"内建"`, or `"内置"`.

```swift
private func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
    let name = screen.localizedName
    return name.contains("Built-in") || name.contains("内建") || name.contains("内置")
}
```

### `updateConnectedDisplays(_:)`

```swift
private func updateConnectedDisplays(_ names: [String])
```

Propagates the list of all connected display names to every active view model's `connectedDisplays` property. This is used by the settings UI to show display toggles.

---

## State Priority Enforcement

The display state is derived from multiple input signals with a strict priority chain:

```
┌─────────────────────────────────────────────────────────────┐
│                    Priority Chain                            │
│                                                             │
│  1. .settings          (showSettings == true)               │
│     ↓ no                                                   │
│  2. .claudeApproval    (claude.isWaitingForApproval)        │
│     ↓ no                                                   │
│  3. .breakPrompt       (showBreakPrompt == true)            │
│     ↓ no                                                   │
│  4. .claudeNotification(claude.isNotification)              │
│     ↓ no                                                   │
│  5. .expanded          (isPinnedExpanded || isHovering)     │
│     ↓ no                                                   │
│  6. .compact           (isTimerActive)                      │
│     ↓ no                                                   │
│  7. .idle              (default)                            │
└─────────────────────────────────────────────────────────────┘
```

### Priority Explanation

| Priority | State | Trigger Condition | User Impact |
|---|---|---|---|
| 1 (highest) | `.settings` | `showSettings == true` | Settings panel overrides everything |
| 2 | `.claudeApproval` | `claudePhase.isWaitingForApproval` | Permission request is urgent/interrupting |
| 3 | `.breakPrompt` | `showBreakPrompt == true` | Break suggestion takes priority over expanded view |
| 4 | `.claudeNotification` | `claudePhase.isNotification` | Claude notification shown as banner |
| 5 | `.expanded` | `isPinnedExpanded \|\| (isHovering && isReady)` | User expansion via click or hover |
| 6 | `.compact` | `isTimerActive` | Timer running shows compact info |
| 7 (lowest) | `.idle` | default | Nothing active |

### Design Rationale

- **Settings is highest priority** because it's a deliberate user action that shouldn't be interrupted
- **Claude approval is higher than break prompt** because permission requests are time-sensitive and blocking
- **Break prompt is higher than expanded** because it's a transient notification that should be seen even if the user is interacting
- **Claude notification is higher than expanded** for the same reason — transient alerts take priority
- **Expanded requires `isReady`** for hover (cold-start guard), but not for pin (explicit user action)

---

## Cold-Start Guard

The `isReady` flag prevents the notch from immediately expanding when the app launches with the mouse already over the notch area.

```swift
// In NotchViewModel.init():
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
    self?.isHovering = false  // Clear any accumulated hover state during cold start
    self?.isReady = true      // Enable hover response
}
```

### Timeline

```
App Launch
    │
    │  ──── 0.5 seconds ────►
    │
    │  During this window:
    │  • isReady = false
    │  • Hover is ignored (hovering && ready → false)
    │  • Pin (click) still works (isPinnedExpanded doesn't require isReady)
    │  • isHovering is cleared to false (in case OS sent hover events during init)
    │
    ▼
isReady = true
    │
    │  Hover is now active
    │  isHovering = false (clean slate)
    │
    ▼
Normal operation
```

### Why 0.5 seconds?

- Window positioning and initial layout takes a few frames
- The OS may send mouse-moved events during window creation if the cursor is in the notch zone
- 0.5s is long enough to ensure the window is fully positioned, but short enough to be imperceptible to the user
