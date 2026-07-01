# UI / UX Design Reference

> **Source file:** `Sources/Views/NotchView.swift` (1159 lines)

This document describes the complete visual design system of vibe-pomodoro's notch interface — from the Dynamic Island silhouette shape through every content state, style token, animation, and gesture interaction.

---

## Table of Contents

- [NotchShape](#notchshape)
- [View Structure](#view-structure)
- [Content Switch by Display State](#content-switch-by-display-state)
- [Compact Content](#compact-content)
- [Expanded Content](#expanded-content)
- [Settings Content](#settings-content)
- [Claude Approval Content](#claude-approval-content)
- [Claude Notification Content](#claude-notification-content)
- [Break Prompt Content](#break-prompt-content)
- [Gesture Handling](#gesture-handling)
- [Animations](#animations)
- [Style Tokens](#style-tokens)
- [Physical Notch Occlusion Rule](#physical-notch-occlusion-rule)
- [Sub-Components](#sub-components)
- [Buttons](#buttons)

---

## NotchShape

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Shape` |
| **Source** | `NotchView.swift:7` |

A custom `Shape` that draws the Dynamic Island silhouette — a shape with a **completely flat top edge** (to seamlessly continue the hardware notch) and **large rounded bottom corners**.

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `bottomCornerRadius` | `CGFloat` | `22` | Radius of the bottom-left and bottom-right corners |
| `topCornerRadius` | `CGFloat` | `0` | Radius of the top corners (default: sharp/flat) |

### Path Construction

The shape is drawn as follows:

```
    ┌──────────────────────────────────────────┐  ← Flat top (topR=0 by default)
    │                                          │
    │              (content area)              │
    │                                          │
    └──────────────────────────────────────────┘  ← bottomR rounded corners
           ╲                              ╱
            ╲                            ╱
             ╲__________________________╱
```

1. **Top-left corner** (if `topR > 0`): Arc from 180° to 270°
2. **Top edge**: Straight line from left to right (at `rect.minY`)
3. **Top-right corner** (if `topR > 0`): Arc from 270° to 0°
4. **Right edge**: Straight line down to `rect.maxY - bottomR`
5. **Bottom-right corner**: Arc from 0° to 90° (radius = `bottomR`)
6. **Bottom edge**: Straight line left to `rect.minX + bottomR`
7. **Bottom-left corner**: Arc from 90° to 180° (radius = `bottomR`)
8. Close subpath

### Clamping

Both corner radii are clamped to `min(cornerRadius, min(rect.width, rect.height) / 2)` to prevent overflow on small views.

---

## View Structure

The main `NotchView` uses a `ZStack` with `.top` alignment:

```swift
ZStack(alignment: .top) {
    // Layer 1: Background fill
    NotchShape(bottomCornerRadius: bottomRadius)
        .fill(Color.black)

    // Layer 2: Content (padded and clipped)
    content
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.top, contentTopPadding)
        .padding(.bottom, contentBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.clipShape(NotchShape(bottomCornerRadius: bottomRadius))
.compositingGroup()
.contentShape(NotchShape(bottomCornerRadius: bottomRadius))
```

### Key Modifiers

| Modifier | Purpose |
|---|---|
| `.clipShape(NotchShape(...))` | Clips content to the Dynamic Island silhouette |
| `.compositingGroup()` | Groups all rendering into a single layer for compositing |
| `.contentShape(NotchShape(...))` | Defines the hit-testing area (only the shape, not the bounding rect) |

---

## Content Switch by Display State

The `content` computed property switches on `viewModel.displayState`:

```swift
@ViewBuilder
private var content: some View {
    switch viewModel.displayState {
    case .idle, .compact:
        compactContent
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    case .expanded:
        expandedContent
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
    case .settings:
        settingsContent
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    case .breakPrompt:
        breakPromptContent
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    case .claudeApproval:
        claudeApprovalContent
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    case .claudeNotification:
        claudeNotificationContent
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}
```

### Transition Summary

| State | Insertion transition | Removal transition |
|---|---|---|
| `.idle` / `.compact` | opacity + scale(0.94) | opacity + scale(0.94) |
| `.expanded` | opacity + move(top) | opacity |
| `.settings` | opacity + move(bottom) | opacity + move(bottom) |
| `.breakPrompt` | opacity + scale(0.94) | opacity + scale(0.94) |
| `.claudeApproval` | opacity + scale(0.94) | opacity + scale(0.94) |
| `.claudeNotification` | opacity + scale(0.94) | opacity + scale(0.94) |

---

## Compact Content

The compact content is a horizontal layout with three zones separated by the physical notch gap:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌──┐ 专注     ┌─────────────┐  09:03  AI                                │
│  │○ │         │             │  ────                                      │
│  └──┘         │  notch gap  │                                            │
│  progress     │  (240pt)    │                                            │
│  ring 12pt   │             │                                            │
│               │             │                                            │
│  LEFT WING    │  FORBIDDEN  │  RIGHT WING                               │
│               │  ZONE       │                                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Layout

```swift
HStack(spacing: 0) {
    // Left wing: progress ring + status label
    HStack(spacing: 6) {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 1.5)
            Circle().trim(from: 0, to: max(0.001, CGFloat(timer.progress)))
                .stroke(accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)

        Text(compactStatusLabel)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.7))
    }

    // Center: physical notch gap (forbidden zone)
    Spacer().frame(width: CGFloat(timer.config.notchGapWidth))

    // Right wing: countdown + Claude indicator
    HStack(spacing: 6) {
        Text(timer.formattedTime)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(.white)
            .kerning(0.5)

        compactClaudeIndicator
    }
}
```

### Compact Status Label

The `compactStatusLabel` computed property returns a short Chinese label:

| Status | isPaused | Label |
|---|---|---|
| `.idle` | — | `"准备"` |
| `.working` | `true` | `"暂停"` |
| `.working` | `false` | `"专注"` |
| `.shortBreak` | `true` | `"暂停"` |
| `.shortBreak` | `false` | `"短休"` |
| `.longBreak` | `true` | `"暂停"` |
| `.longBreak` | `false` | `"长休"` |
| `.paused` | — | `"暂停"` |

### Compact Claude Indicator

A small indicator shown at the right edge of the compact bar, reflecting the Claude session phase:

| Phase | Visual | Color | Animation |
|---|---|---|---|
| `processing` | `●` + `"AI"` | Amber (`0.95, 0.7, 0.2`) | Pulsing dot (opacity 0.3↔1.0, 1s repeat) |
| `waitingForInput` | `●` + `"✓"` | Green (`0.4, 0.86, 0.62`) | Static |
| `waitingForApproval` | `●` + `"!"` | Red (`0.85, 0.3, 0.3`) | Pulsing dot (opacity 0.3↔1.0, 1s repeat) |
| `waitingForResponse` | `●` + `"?"` | Amber (`0.95, 0.7, 0.2`) | Pulsing dot (opacity 0.3↔1.0, 1s repeat) |
| `compacting` | ⟳ (arrow.triangle.2.circlepath) | Amber (`0.95, 0.7, 0.2`) | Continuous rotation (360°, 1.5s linear repeat) |
| `idle` / `error` | _(empty)_ | — | — |

The pulsing animation uses `@State private var claudeDotPulsing: Bool` toggled on appear/disappear.

---

## Expanded Content

The expanded content is a vertical layout with four sections:

```
┌──────────────────────────────────────┐
│  ● 专注工作          [3/4]  ⚙       │  Header
│                                      │
│  42:30                    ◯          │  Main display
│  (42pt monospaced)      (52pt ring)  │
│                                      │
│  🔥 25 分钟    ✓ 3 个番茄             │  Today stats
│                                      │
│                                      │
│  [ ▶ 开始专注 ]  (or [⏸][⏭][⏹])    │  Control bar
└──────────────────────────────────────┘
```

### Header

```swift
HStack(spacing: 8) {
    statusDot.frame(width: 7, height: 7)

    Text(timer.statusText)
        .font(.system(size: 11, weight: .semibold, design: .rounded))

    Spacer(minLength: 8)

    if timer.status != .idle {
        Text("\(timer.currentRound)/\(timer.config.roundsBeforeLongBreak)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
    }

    Button(action: { viewModel.openSettings() }) {
        Image(systemName: "gearshape.fill").font(.system(size: 11))
    }
    .buttonStyle(.plain)
}
```

### Main Display

```swift
HStack(alignment: .center, spacing: 18) {
    Text(timer.formattedTime)
        .font(.system(size: 42, weight: .ultraLight, design: .monospaced))
        .monospacedDigit()
        .kerning(-1)
        .minimumScaleFactor(0.7)

    Spacer(minLength: 0)

    progressRing.frame(width: 52, height: 52)
}
```

### Today Stats

```swift
HStack(spacing: 12) {
    Label("\(timer.todayFocusMinutes) 分钟", systemImage: "flame.fill")
    Label("\(timer.todayCompletedSessions) 个番茄", systemImage: "checkmark.circle.fill")
}
```

### Control Bar

When `timer.status == .idle`: shows `startButton` (full-width capsule).

When active: shows three `circleButton`s:
- **Pause/Play**: `pause.fill` or `play.fill` → `timer.togglePause()`
- **Skip**: `forward.end.fill` → `timer.skip()`
- **Stop**: `stop.fill` (accent-colored) → `timer.stop()` + `timer.resetRounds()` + `viewModel.collapse()`

---

## Settings Content

The in-notch settings panel provides full configuration without opening a separate window.

### Layout Overview

```
┌──────────────────────────────────────┐
│  ‹ 返回       设置          ‹ 返回    │  Header (back button + centered title)
│                                      │
│  ┌──────────────────────────────────┐
│  │ TIME                             │
│  │  工作           - 25 分钟 +       │
│  │  短休息          - 5 分钟 +       │
│  │  长休息         - 15 分钟 +      │
│  │  长休息间隔      - 4 轮 +        │
│  └──────────────────────────────────┘
│  ┌──────────────────────────────────┐
│  │ BEHAVIOR                         │
│  │  自动开始休息            [ ◯ ]   │
│  │  自动开始工作            [ ◯ ]   │
│  └──────────────────────────────────┘
│  ┌──────────────────────────────────┐
│  │ DISPLAY                           │
│  │  Built-in Retina        [ ● ]    │
│  │  DELL U2723QE           [ ◯ ]    │
│  │  刘海宽度         - 240 pt +     │
│  └──────────────────────────────────┘
│  ┌──────────────────────────────────┐
│  │ AI HOOKS                         │
│  │  ✓ Hook 已安装    ~/.claude/...  │
│  │          [ 安装 Hook ]            │
│  │  ─────────────────────────────   │
│  │  ✓ Codex Hook 已安装              │
│  │  ~/.codex/hooks.json             │
│  │          [ 安装 Hook ]            │
│  │  ℹ 首次使用需在 Codex CLI 中...  │
│  └──────────────────────────────────┘
│  版本                    1.1.0      │
│  [        退出番茄钟         ]      │
└──────────────────────────────────────┘
```

### Sections

#### Time Section

| Setting | Range | Step | Unit |
|---|---|---|---|
| Work duration | 5–60 min | 5 min | minutes |
| Short break | 1–30 min | 1 min | minutes |
| Long break | 5–60 min | 5 min | minutes |
| Long break interval | 2–8 | 1 | rounds |

#### Behavior Section

| Toggle | Config property | Default |
|---|---|---|
| 自动开始休息 (Auto-start break) | `autoStartBreak` | `false` |
| 自动开始工作 (Auto-start work) | `autoStartWork` | `false` |

#### Display Section

- One toggle per connected display (from `viewModel.connectedDisplays`)
- Toggle logic: if `selectedDisplayNames` is empty, built-in display is treated as selected
- Prevents deselecting the last remaining display (`selected.count > 1` guard)
- Notch gap width stepper: 200–300 pt, step 10 pt

#### AI Hooks Section

| Element | Description |
|---|---|
| Claude Code status | `checkmark.circle.fill` (green) if installed, `xmark.circle.fill` (red) if not |
| Claude Code path | `"~/.claude/hooks/vibe-pomodoro-hook.py"` |
| Claude Code action button | "安装 Hook" or "重新安装" → `HookInstaller.installIfNeeded()` |
| Codex CLI status | Same checkmark/xmark pattern |
| Codex CLI path | `"~/.codex/hooks.json"` |
| Codex CLI action button | "安装 Hook" or "重新安装" → `HookInstaller.installCodexIfNeeded()` |
| Trust instruction | "首次使用需在 Codex CLI 中运行 /hooks 信任钩子" |

#### Version & Exit

- Version: `"1.1.0"` (monospaced)
- Exit button: `"退出番茄钟"` with power icon → `NSApplication.shared.terminate(nil)`
- Vibe-notch conflict warning (conditional): shows orange warning if `HookInstaller.isVibeNotchInstalled()` returns true

---

## Claude Approval Content

Displayed when `ClaudeSessionPhase == .waitingForApproval(PermissionContext)`.

### Layout

```
┌──────────────────────────────────────┐
│                                      │
│  ⚠ Claude Code 请求权限              │  Warning header (amber)
│                                      │
│  Tool: Bash                          │  Tool name (bold)
│                                      │
│  ┌──────────────────────────────────┐
│  │ npm run build                   │  Formatted input (monospaced)
│  └──────────────────────────────────┘
│                                      │
│                                      │
│     [ ✓ 允许 ]    [ ✕ 拒绝 ]        │  Action buttons
│                                      │
└──────────────────────────────────────┘
```

### Action Buttons

| Button | Label | Color (RGB) | Action |
|---|---|---|---|
| Allow | `"允许"` with checkmark | Green `(0.3, 0.75, 0.45)` | `claudeManager.approvePermission()` |
| Deny | `"拒绝"` with xmark | Red `(0.85, 0.3, 0.3)` | `claudeManager.denyPermission()` |

Both buttons use `Capsule()` background and `.buttonStyle(.plain)`.

---

## Claude Notification Content

Displayed when `ClaudeSessionPhase.isNotification == true` (phases: `.waitingForInput`, `.error`, `.waitingForResponse`).

### Header (phase-specific)

| Phase | Dot color | Title text | Title color |
|---|---|---|---|
| `.error` | Red | `"Claude 出错"` | Red |
| `.waitingForResponse` | Amber | `"Claude 需要你的回复"` | Amber |
| default (`.waitingForInput`) | Green | `"Claude 任务完成"` | Green |

### Body (phase-specific)

| Phase | Body content |
|---|---|
| `.error(let msg)` | Error message text (up to 2 lines) |
| `.waitingForResponse(let message)` | Question text (if non-nil, up to 2 lines) + `"请切换到终端回复"` |
| default | `"项目: \(projectName)"` + `"等待输入"` |

### Interaction

Tapping anywhere on the notification calls `claudeManager.dismissNotification()`.

---

## Break Prompt Content

Displayed when `showBreakPrompt == true` (auto-dismissed after 5 seconds).

### Layout

```
┌──────────────────────────────────────┐
│                                      │
│      太棒了！又完成了一个番茄钟 🎉    │  Motivational message (random)
│             休息一下吧                │  Subtitle
│                                      │
│         [ ☕ 开始休息 ]               │  Action button
│                                      │
└──────────────────────────────────────┘
```

### Motivational Messages

One of seven messages is randomly selected:

```
"太棒了！又完成了一个番茄钟 🎉"
"好好休息，让大脑放松一下 ☕"
"你的专注力真棒！该休息了 💪"
"做得很好！稍作休息效率更高 ✨"
"完美！休息是为了走更远的路 🌟"
"坚持就是胜利！先喝口水吧 💧"
"专注的你最有魅力！休息一下 🌈"
```

### Action Button

- Label: `"开始休息"` with `cup.and.saucer.fill` icon
- Background: `accentColor` capsule
- Foreground: black
- Action: `viewModel.dismissBreakPrompt()` + `timer.startBreak()`

---

## Gesture Handling

### Tap Gesture

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

**Guard:** Tap is ignored in `.settings`, `.claudeApproval`, and `.claudeNotification` states to prevent accidental dismissal of critical UI.

### Hover Gesture (with Debounce)

```swift
.onHover { hovering in
    scheduleHover(hovering)
}
```

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

### Debounce Timing

| Event | Delay | Reason |
|---|---|---|
| Mouse enters | 0.05s | Fast response — avoid sluggishness when user intentionally hovers |
| Mouse leaves | 0.30s | Delayed — gives user time to move cursor into expanded content without collapsing |

The `hoverDebounce` is a `@State private var` of type `DispatchWorkItem?`. Each new hover event cancels the previous pending work item, preventing rapid toggling.

---

## Animations

### Primary Animation: Display State

```swift
.animation(.spring(response: 0.32, dampingFraction: 0.72), value: viewModel.displayState)
```

Applied twice (once as `.animation(...)` modifier, once as explicit `withAnimation` in gesture handlers) to ensure smooth transitions between display states.

| Parameter | Value | Description |
|---|---|---|
| Response | 0.32s | Duration of the spring animation |
| Damping fraction | 0.72 | Slightly underdamped — subtle bounce |

### Secondary Animation: Status Change

```swift
.animation(.easeInOut(duration: 0.22), value: timer.status)
```

Smooth color transitions when the timer status changes (e.g., work → break).

### Scale Effect: Collapsed State

```swift
.scaleEffect(viewModel.displayState == .expanded ? 1.0 : 0.998)
```

When **not** expanded, the view is scaled down to 99.8% — a barely perceptible "settled" effect that makes the expanded state feel slightly larger/more prominent.

### Window Animation

Window frame changes use `NSAnimationContext`:

```swift
ctx.duration = 0.32
ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.88, 0.32, 1.0)
```

This cubic bezier curve `(0.22, 0.88, 0.32, 1.0)` is a strong ease-out with a natural spring-like character.

### Claude Indicator Animations

| Indicator | Animation | Duration |
|---|---|---|
| Pulsing dot (processing/approval/response) | `easeInOut.repeatForever(autoreverses: true)` | 1.0s |
| Compacting spinner | `linear.repeatForever(autoreverses: false)` | 1.5s |

---

## Style Tokens

### `bottomRadius`

The `NotchShape` bottom corner radius, varying by display state:

| State | bottomRadius |
|---|---|
| `.idle` / `.compact` | 18 |
| `.expanded` | 24 |
| `.settings` | 24 |
| `.breakPrompt` | 24 |
| `.claudeApproval` | 24 |
| `.claudeNotification` | 22 |

### Content Padding

#### `contentHorizontalPadding`

| State | Padding |
|---|---|
| `.idle` / `.compact` | 12 |
| `.expanded` | 18 |
| `.settings` | 18 |
| `.breakPrompt` | 18 |
| `.claudeApproval` | 18 |
| `.claudeNotification` | 16 |

#### `contentTopPadding`

| State | Padding | Reason |
|---|---|---|
| `.idle` / `.compact` | 12 | Content starts near the top |
| `.expanded` | 54 | Clears the hardware notch (content starts below the physical notch area) |
| `.settings` | 14 | Settings scrolls, less top clearance needed |
| `.breakPrompt` | 54 | Clears hardware notch |
| `.claudeApproval` | 54 | Clears hardware notch |
| `.claudeNotification` | 44 | Slightly less, notification is compact |

> **Critical:** The 54pt top padding for expanded states is essential to clear the hardware notch. macOS notch hardware occupies approximately 38–40pt of height at the top center of the screen. The 54pt ensures content starts below this zone.

#### `contentBottomPadding`

| State | Padding |
|---|---|
| `.idle` | 12 |
| `.compact` | 12 |
| `.expanded` | 16 |
| `.settings` | 16 |
| `.breakPrompt` | 16 |
| `.claudeApproval` | 16 |
| `.claudeNotification` | 14 |

### `accentColor` (per status)

The primary accent color changes based on the timer status:

| Status | RGB | Visual | Description |
|---|---|---|---|
| `working` | `(0.99, 0.55, 0.18)` | Warm orange | Tomato/saffron — energy, focus |
| `shortBreak` | `(0.40, 0.86, 0.62)` | Mint green | Refreshment, calm |
| `longBreak` | `(0.55, 0.70, 1.00)` | Cold blue | Deep rest, night |
| `paused` | `(0.80, 0.80, 0.85)` | Gray | Neutral, suspended |
| `idle` | `(0.92, 0.92, 0.94)` | Off-white | Neutral, ready |

### Claude Colors

| Token | RGB | Description |
|---|---|---|
| `claudeAmberColor` | `(0.95, 0.7, 0.2)` | Processing, waiting, warnings |
| `claudeGreenColor` | `(0.4, 0.86, 0.62)` | Success, input ready, completion |
| `claudeRedColor` | `(0.85, 0.3, 0.3)` | Error, denial, critical attention |

### `glyphName`

The SF Symbol displayed in the center of the progress ring:

| Status | isPaused | Glyph |
|---|---|---|
| `idle` | — | `timer` |
| `working` | `false` | `flame.fill` |
| `working` | `true` | `pause.fill` |
| `shortBreak` | `false` | `leaf.fill` |
| `shortBreak` | `true` | `pause.fill` |
| `longBreak` | `false` | `moon.stars.fill` |
| `longBreak` | `true` | `pause.fill` |
| `paused` | — | `pause.fill` |

---

## Physical Notch Occlusion Rule

The center zone of the notch window — directly above the hardware notch — is a **forbidden content area**. No UI content is ever rendered in this zone.

### Implementation

In the compact content layout:

```swift
// Center: physical notch gap (forbidden zone)
Spacer().frame(width: CGFloat(timer.config.notchGapWidth))
```

This `Spacer` with a fixed width of `timer.config.notchGapWidth` (default: 240pt) creates an impassable gap between the left wing and right wing of the compact content.

### Why It Matters

The hardware notch physically occupies the center-top of the display. Any content rendered there would be hidden behind the notch. The `notchGapWidth` spacer ensures:

1. The left wing content (progress ring, status label) is to the **left** of the notch
2. The right wing content (countdown, Claude indicator) is to the **right** of the notch
3. The center is always empty — the black `NotchShape` fill visually merges with the hardware notch

### Configurability

The `notchGapWidth` is user-configurable (200–300pt, step 10pt) in the settings panel to accommodate different MacBook models with varying notch widths.

### States Where It Applies

The notch gap is most critical in `.idle` and `.compact` states (38pt height), where content is at the same vertical level as the hardware notch. In expanded states, the 54pt top padding pushes content below the notch zone, making the gap less critical — but the layout still respects the left/right wing separation.

---

## Sub-Components

### `statusDot`

A small circle indicator showing the current status color with an animated outer ring:

```swift
private var statusDot: some View {
    Circle()
        .fill(accentColor)
        .overlay(
            Circle()
                .stroke(accentColor.opacity(0.35), lineWidth: 2)
                .scaleEffect(timer.isPaused ? 1.0 : 1.6)
                .opacity(timer.isPaused ? 0.0 : 0.0001)
        )
}
```

When the timer is **running** (not paused): the outer ring is scaled to 1.6× with near-zero opacity (0.0001) — this triggers the animation system without being visually distracting.

When **paused**: the ring collapses to 1.0× scale and becomes fully invisible.

### `progressRing`

A circular progress indicator with a glyph in the center:

```swift
private var progressRing: some View {
    ZStack {
        Circle()
            .stroke(Color.white.opacity(0.08), lineWidth: 2)  // Track

        Circle()
            .trim(from: 0, to: max(0.001, CGFloat(timer.progress)))
            .stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))  // Start from top

        Image(systemName: glyphName)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(accentColor)
    }
}
```

| Element | Purpose |
|---|---|
| Background circle | Unfilled track (8% white opacity) |
| Trimmed circle | Progress arc (rotated -90° to start from 12 o'clock) |
| SF Symbol | Status glyph in the center |

> **`max(0.001, ...)` guard:** The `trim` value is clamped to a minimum of 0.001 to prevent the `Circle` from disappearing entirely at 0% progress, which would cause a visual flash.

### `controlBar`

Switches between `startButton` (when idle) and three `circleButton`s (when active):

```swift
@ViewBuilder
private var controlBar: some View {
    if timer.status == .idle {
        startButton
    } else {
        HStack(spacing: 10) {
            circleButton(icon: timer.isPaused ? "play.fill" : "pause.fill", ...)
            circleButton(icon: "forward.end.fill", ...)
            circleButton(icon: "stop.fill", ...)
        }
    }
}
```

### `startButton`

Full-width capsule button:

```swift
private var startButton: some View {
    Button(action: {
        if timer.pendingBreak {
            timer.startBreak()
        } else {
            timer.startWork()
        }
        viewModel.collapse()
    }) {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
            Text(timer.pendingBreak ? "开始休息" : "开始专注")
        }
        .foregroundColor(.black)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(accentColor))
    }
    .buttonStyle(.plain)
}
```

The label adapts: `"开始休息"` (Start Break) when `pendingBreak` is true, `"开始专注"` (Start Focus) otherwise.

---

## Buttons

### Button Style Convention

All interactive buttons in vibe-pomodoro use `.buttonStyle(.plain)`:

```swift
Button(action: { ... }) {
    // Label content
}
.buttonStyle(.plain)
```

### Why `.plain`?

Using `.buttonStyle(.plain)` is **critical** for gesture priority. The `NotchView` has an `.onTapGesture` on the parent `ZStack`. Without `.plain` style, SwiftUI's default button rendering could intercept or conflict with the parent tap gesture.

With `.plain` style:
1. The button handles its own tap events directly
2. The parent `.onTapGesture` is not triggered when clicking a button
3. The button's visual appearance is fully controlled by the custom label

### `circleButton` Helper

A reusable circular button factory:

```swift
private func circleButton(
    icon: String,
    tint: Color,
    foreground: Color,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(foreground)
            .frame(width: 32, height: 32)
            .background(Circle().fill(tint))
            .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.6))
    }
    .buttonStyle(.plain)
}
```

| Parameter | Type | Description |
|---|---|---|
| `icon` | `String` | SF Symbol name |
| `tint` | `Color` | Background fill color |
| `foreground` | `Color` | Icon color |
| `action` | `() -> Void` | Tap action |

### Settings Helper Components

#### `settingsSection(title:content:)`

Creates a labeled section with a rounded background:

```swift
private func settingsSection<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
) -> some View
```

- Title: 10pt semibold, 40% white opacity, uppercase, 1pt letter spacing
- Content background: `RoundedRectangle(cornerRadius: 10)` with 6% white opacity fill
- Internal spacing: 1pt between rows

#### `settingsRow(title:value:unit:decrement:increment:)`

A stepper row with decrement/increment buttons:

```swift
private func settingsRow(
    title: String,
    value: Int,
    unit: String,
    decrement: @escaping () -> Void,
    increment: @escaping () -> Void
) -> some View
```

Layout: `[title] ---- [− icon] [value unit] [+ icon]`

- Title: 12pt, 80% white opacity
- Value: 12pt medium monospaced, minWidth 50pt
- Buttons: `minus.circle.fill` / `plus.circle.fill`, 14pt, 40% white opacity

#### `settingsToggle(title:isOn:)`

A toggle row:

```swift
private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View
```

Layout: `[title] ---- [Toggle switch]`

- Toggle scaled to 0.8× with `.toggleStyle(.switch)` and `.labelsHidden()`
- Title: 12pt, 80% white opacity

---

## State-Specific View Previews

The file includes SwiftUI previews for four states:

| Preview | Frame Size | Display Name |
|---|---|---|
| Idle | 350×38 | "Idle" |
| Compact | 350×36 | "Compact" |
| Expanded | 360×200 | "Expanded" |
| Settings | 380×420 | "Settings" |

All previews use a shared `PomodoroTimer`, `ClaudeSessionManager`, and `NotchViewModel` instance, with a 40pt padding and 25% gray background.
