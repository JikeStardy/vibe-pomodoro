# Data Model Reference

> **Source files:** `Sources/Models/PomodoroModels.swift`, `Sources/Models/ClaudeModels.swift`

This document provides a complete reference for every data type used in NotchPomodoro's model layer. The models are divided into two domains:

1. **Pomodoro domain** — Timer status, configuration, and session history
2. **Claude integration domain** — Hook events, permission requests, and session phase tracking

---

## Table of Contents

- [Pomodoro Domain](#pomodoro-domain)
  - [PomodoroStatus](#pomodorostatus)
  - [PomodoroConfig](#pomodoroconfig)
  - [PomodoroSession](#pomodorosession)
- [Claude Integration Domain](#claude-integration-domain)
  - [AnyCodable](#anycodable)
  - [HookEvent](#hookevent)
  - [HookResponse](#hookresponse)
  - [PermissionContext](#permissioncontext)
  - [ClaudeSessionPhase](#claudesessionphase)
  - [PendingPermission](#pendingpermission)
- [Type Relationship Diagram](#type-relationship-diagram)

---

## Pomodoro Domain

### PomodoroStatus

| Attribute | Value |
|---|---|
| **Kind** | `enum` |
| **Conformance** | `String`, `Codable` |
| **Raw value type** | `String` |
| **Source** | `PomodoroModels.swift:4` |

Represents the finite set of states the Pomodoro timer can be in.

| Case | Raw value | Description |
|---|---|---|
| `idle` | `"idle"` | Timer is stopped / not running |
| `working` | `"working"` | Active focus work session |
| `shortBreak` | `"shortBreak"` | Short break between work rounds |
| `longBreak` | `"longBreak"` | Long break after N completed rounds |
| `paused` | `"paused"` | Timer is paused (transitional metadata flag) |

> **Note:** The `paused` case exists for enum completeness, but in practice the `isPaused` boolean flag on `PomodoroTimer` is used to indicate pause state while `status` remains `.working` or `.shortBreak` / `.longBreak`.

---

### PomodoroConfig

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Codable` |
| **Source** | `PomodoroModels.swift:13` |

User-configurable settings for the Pomodoro timer. Persisted to `UserDefaults` under the key `"pomodoro_config"`.

#### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `workDuration` | `Int` | `1500` (25 × 60) | Work session length in seconds |
| `shortBreakDuration` | `Int` | `300` (5 × 60) | Short break length in seconds |
| `longBreakDuration` | `Int` | `900` (15 × 60) | Long break length in seconds |
| `roundsBeforeLongBreak` | `Int` | `4` | Number of work rounds before a long break |
| `autoStartBreak` | `Bool` | `false` | Automatically start break after work completes |
| `autoStartWork` | `Bool` | `false` | Automatically start next work session after break |
| `selectedDisplayNames` | `[String]` | `[]` | Display names for notch window (empty = built-in display only) |
| `notchGapWidth` | `Int` | `240` | Physical notch occlusion zone width in points (pt) |

#### Static Members

| Member | Type | Description |
|---|---|---|
| `default` | `PomodoroConfig` | Shared default instance with all default values |

#### CodingKeys

No custom `CodingKeys` — uses synthesized encoding (property names match JSON keys directly).

#### Validation Ranges (enforced in UI)

| Property | Min | Max | Step |
|---|---|---|---|
| `workDuration` | 300 s (5 min) | 3600 s (60 min) | 300 s (5 min) |
| `shortBreakDuration` | 60 s (1 min) | 1800 s (30 min) | 60 s (1 min) |
| `longBreakDuration` | 300 s (5 min) | 3600 s (60 min) | 300 s (5 min) |
| `roundsBeforeLongBreak` | 2 | 8 | 1 |
| `notchGapWidth` | 200 pt | 300 pt | 10 pt |

---

### PomodoroSession

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Codable`, `Identifiable` |
| **Source** | `PomodoroModels.swift:27` |

A single recorded Pomodoro session (work or break), persisted for statistics.

#### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `id` | `UUID` | `UUID()` (generated in init) | Unique session identifier |
| `type` | `PomodoroStatus` | — | Session type (`.working`, `.shortBreak`, `.longBreak`) |
| `startTime` | `Date` | — | When the session started |
| `endTime` | `Date` | — | When the session ended |
| `completed` | `Bool` | — | Whether the session ran to completion (vs. stopped/skipped early) |

#### Initializer

```swift
init(type: PomodoroStatus, startTime: Date, endTime: Date, completed: Bool)
```

The `id` is auto-generated via `UUID()` inside the initializer — there is no external `id` parameter.

#### Persistence

Sessions are stored as `[PomodoroSession]` in `UserDefaults` under `"pomodoro_sessions"`, capped at **100 most recent** entries (older entries are dropped via `Array(sessions.suffix(100))`).

#### CodingKeys

No custom `CodingKeys` — uses synthesized encoding.

---

## Claude Integration Domain

### AnyCodable

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Codable`, `@unchecked Sendable` |
| **Source** | `ClaudeModels.swift:5` |

A type-erasing wrapper that allows encoding/decoding arbitrary JSON values through Swift's `Codable` system. Used to store `toolInput` dictionaries whose schema varies by tool type.

#### Properties

| Property | Type | Description |
|---|---|---|
| `value` | `Any` (stored as `nonisolated(unsafe)`) | The underlying untyped value |

#### Initializers

```swift
init(_ value: Any)
init(from decoder: Decoder) throws
```

#### Decode Priority

When decoding from JSON, the following order is attempted. The first successful decode wins:

| Priority | JSON Type | Swift Type |
|---|---|---|
| 1 | `null` | `NSNull()` |
| 2 | Boolean | `Bool` |
| 3 | Integer | `Int` |
| 4 | Floating point | `Double` |
| 5 | String | `String` |
| 6 | Array | `[Any]` (recursively decoded) |
| 7 | Object | `[String: Any]` (recursively decoded) |

If none match, `DecodingError.dataCorruptedError` is thrown.

#### Encode Logic

Uses a `switch` on the runtime type of `value`:

| Runtime type | Encoded as |
|---|---|
| `NSNull` | `nil` |
| `Bool` | Bool |
| `Int` | Int |
| `Double` | Double |
| `String` | String |
| `[Any]` | Array of `AnyCodable` (recursive) |
| `[String: Any]` | Dictionary of `AnyCodable` (recursive) |
| _other_ | `EncodingError.invalidValue` thrown |

> **Important:** `Bool` is checked before `Int` in both decode and encode paths. This is correct because in Swift's type system, a JSON `true`/`false` would otherwise be bridged to `Int` `1`/`0`.

---

### HookEvent

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Codable`, `Sendable` |
| **Source** | `ClaudeModels.swift:38` |

An event received from the Python hook script via a Unix domain socket. Represents a Claude Code / Codex CLI lifecycle event.

#### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `sessionId` | `String` | — | Claude session identifier |
| `cwd` | `String` | — | Current working directory of the session |
| `event` | `String` | — | Event type (e.g., `"PermissionRequest"`, `"Notification"`) |
| `status` | `String` | — | Event status (e.g., `"waiting_for_approval"`) |
| `pid` | `Int?` | `nil` | Process ID of the Claude CLI |
| `tty` | `String?` | `nil` | Terminal TTY path |
| `tool` | `String?` | `nil` | Tool name (e.g., `"Bash"`, `"Write"`, `"Read"`) |
| `toolInput` | `[String: AnyCodable]?` | `nil` | Tool input parameters |
| `toolUseId` | `String?` | `nil` | Unique tool use identifier |
| `notificationType` | `String?` | `nil` | Sub-type for notification events |
| `message` | `String?` | `nil` | Human-readable message |

#### Computed Properties

| Property | Type | Description |
|---|---|---|
| `expectsResponse` | `Bool` | `true` when `event == "PermissionRequest"` **and** `status == "waiting_for_approval"`. Events with this flag require the app to send a `HookResponse` back through the socket. |

#### CodingKeys

Custom `CodingKeys` mapping Swift camelCase to JSON snake_case:

| Swift property | JSON key |
|---|---|
| `sessionId` | `session_id` |
| `cwd` | `cwd` |
| `event` | `event` |
| `status` | `status` |
| `pid` | `pid` |
| `tty` | `tty` |
| `tool` | `tool` |
| `toolInput` | `tool_input` |
| `toolUseId` | `tool_use_id` |
| `notificationType` | `notification_type` |
| `message` | `message` |

#### Initializer

```swift
init(sessionId: String, cwd: String, event: String, status: String,
     pid: Int?, tty: String?, tool: String?,
     toolInput: [String: AnyCodable]?, toolUseId: String?,
     notificationType: String?, message: String?)
```

---

### HookResponse

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Codable` |
| **Source** | `ClaudeModels.swift:81` |

The response sent back to the Python hook script for permission requests.

#### Properties

| Property | Type | Description |
|---|---|---|
| `decision` | `String` | Decision: `"allow"`, `"deny"`, or `"ask"` |
| `reason` | `String?` | Optional reason for the decision |

#### CodingKeys

No custom `CodingKeys` — uses synthesized encoding.

---

### PermissionContext

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Sendable`, `Equatable` |
| **Source** | `ClaudeModels.swift:87` |

Context for a pending permission request, extracted from a `HookEvent`. Stored inside the `ClaudeSessionPhase.waitingForApproval` associated value.

#### Properties

| Property | Type | Description |
|---|---|---|
| `toolUseId` | `String` | Unique tool use identifier |
| `toolName` | `String` | Tool name (e.g., `"Bash"`, `"Write"`, `"Edit"`, `"Read"`) |
| `toolInput` | `[String: AnyCodable]?` | Tool input parameters |
| `receivedAt` | `Date` | When the permission request was received |

#### Computed Properties

##### `formattedInput: String?`

Formats the tool input into a human-readable string for UI display. Uses per-tool formatting logic:

| Tool name | Formatting logic |
|---|---|
| `"Bash"` | Extracts `input["command"]`, truncates to 120 chars with `"..."` suffix |
| `"Write"` / `"Edit"` | Extracts `input["file_path"]`, returns `lastPathComponent` |
| `"Read"` | Extracts `input["file_path"]`, returns `lastPathComponent` |
| _other_ | Priority key search → fallback to first non-`description` string |

**Priority key fallback** (for unrecognized tools):

```
["command", "file_path", "path", "query", "pattern", "url"]
```

Each key is checked in order; the first `String` value found is returned (truncated to 120 chars if needed).

If no priority key matches, the first key (excluding `"description"`) with a `String` value is used.

Returns `nil` if `toolInput` is `nil` or no suitable string value is found.

#### Equatable Implementation

Custom `==` implementation comparing only `toolUseId`, `toolName`, and `receivedAt` (does **not** compare `toolInput`):

```swift
static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
    lhs.toolUseId == rhs.toolUseId
        && lhs.toolName == rhs.toolName
        && lhs.receivedAt == rhs.receivedAt
}
```

> **Design note:** `toolInput` is excluded from equality because `AnyCodable` wrapping `Any` cannot be reliably compared. The triple `(toolUseId, toolName, receivedAt)` is sufficient to uniquely identify a permission request.

---

### ClaudeSessionPhase

| Attribute | Value |
|---|---|
| **Kind** | `enum` (indirect via associated values) |
| **Conformance** | `Sendable`, `Equatable` |
| **Source** | `ClaudeModels.swift:131` |

A state machine representing the current phase of a Claude Code / Codex CLI session. This is the primary type driving the Claude-related UI states in the notch.

#### Cases

| Case | Associated value | Description |
|---|---|---|
| `idle` | — | No active Claude session |
| `processing` | — | Claude is actively processing / generating |
| `waitingForInput` | — | Claude is waiting for user input in terminal |
| `waitingForResponse` | `String?` (question text) | Claude asked a question, awaiting user response |
| `waitingForApproval` | `PermissionContext` | Claude is requesting tool-use permission |
| `compacting` | — | Claude is compacting context |
| `error` | `String` (error message) | An error occurred |

#### Computed Properties

##### `needsAttention: Bool`

Returns `true` for states requiring user attention:

| State | `needsAttention` |
|---|---|
| `.waitingForApproval` | `true` |
| `.waitingForInput` | `true` |
| `.waitingForResponse` | `true` |
| all others | `false` |

##### `isWaitingForApproval: Bool`

Returns `true` only if the phase is `.waitingForApproval`. Uses `if case` pattern matching:

```swift
if case .waitingForApproval = self { return true }
return false
```

##### `isNotification: Bool`

Returns `true` for states that should be shown as a notification banner:

| State | `isNotification` |
|---|---|
| `.waitingForInput` | `true` |
| `.error` | `true` |
| `.waitingForResponse` | `true` |
| all others | `false` |

##### `isActive: Bool`

Returns `true` for states indicating active background processing:

| State | `isActive` |
|---|---|
| `.processing` | `true` |
| `.compacting` | `true` |
| all others | `false` |

#### Custom Equatable Implementation

Because associated values are involved (`.waitingForResponse(String?)`, `.waitingForApproval(PermissionContext)`, `.error(String)`), a custom `==` is provided:

```swift
static func == (lhs: ClaudeSessionPhase, rhs: ClaudeSessionPhase) -> Bool
```

| Comparison | Equality condition |
|---|---|
| `.idle` vs `.idle` | Always `true` |
| `.processing` vs `.processing` | Always `true` |
| `.waitingForInput` vs `.waitingForInput` | Always `true` |
| `.waitingForResponse(a)` vs `.waitingForResponse(b)` | `a == b` (String? comparison) |
| `.waitingForApproval(a)` vs `.waitingForApproval(b)` | `a == b` (PermissionContext equality) |
| `.compacting` vs `.compacting` | Always `true` |
| `.error(a)` vs `.error(b)` | `a == b` (String comparison) |
| any other pair | `false` |

---

### PendingPermission

| Attribute | Value |
|---|---|
| **Kind** | `struct` |
| **Conformance** | `Sendable` |
| **Source** | `ClaudeModels.swift:181` |

Internal tracking struct for a permission request that is awaiting a user decision. Maintains the socket file descriptor needed to send the response back.

#### Properties

| Property | Type | Description |
|---|---|---|
| `sessionId` | `String` | Claude session identifier |
| `toolUseId` | `String` | Unique tool use identifier |
| `clientSocket` | `Int32` | Unix domain socket file descriptor for response |
| `event` | `HookEvent` | The original hook event |
| `receivedAt` | `Date` | When the request was received |

> **Note:** `PendingPermission` does **not** conform to `Equatable`. It is compared by `toolUseId` in the `HookSocketServer` / `ClaudeSessionManager` logic.

---

## Type Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Pomodoro Domain                             │
│                                                                 │
│  PomodoroStatus ◄── rawValue ── String, Codable                │
│       │                                                         │
│       ├── used by ──► PomodoroConfig (via roundsBeforeLongBreak)│
│       ├── used by ──► PomodoroSession.type                      │
│       └── used by ──► PomodoroTimer.status                       │
│                                                                 │
│  PomodoroConfig ── persisted ──► UserDefaults["pomodoro_config"]│
│  PomodoroSession ── persisted ─► UserDefaults["pomodoro_sessions"]│
│       (capped at 100 entries)                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Claude Integration Domain                      │
│                                                                 │
│  AnyCodable ◄── wraps ── Any (type-erased Codable)             │
│     │                                                           │
│     ├── used by ──► HookEvent.toolInput: [String: AnyCodable]?  │
│     └── used by ──► PermissionContext.toolInput                  │
│                                                                 │
│  HookEvent ── socket ──► HookSocketServer                       │
│     │                                                           │
│     ├── expectsResponse ──► creates ──► PendingPermission       │
│     │                                │                           │
│     │                                ├── clientSocket: Int32     │
│     │                                └── event: HookEvent        │
│     │                                                           │
│     └── extracts ──► PermissionContext                          │
│          │                                                      │
│          ├── toolUseId, toolName, toolInput, receivedAt         │
│          └── formattedInput (computed)                          │
│                                                                 │
│  PermissionContext ── embedded in ──► ClaudeSessionPhase        │
│                                             .waitingForApproval  │
│                                                                 │
│  ClaudeSessionPhase (7 cases)                                   │
│     ├── .idle                                                   │
│     ├── .processing                                             │
│     ├── .waitingForInput                                        │
│     ├── .waitingForResponse(String?)                             │
│     ├── .waitingForApproval(PermissionContext)                   │
│     ├── .compacting                                             │
│     └── .error(String)                                          │
│          │                                                      │
│          ├── needsAttention (computed)                          │
│          ├── isWaitingForApproval (computed)                    │
│          ├── isNotification (computed)                          │
│          └── isActive (computed)                                │
│                                                                 │
│  HookResponse ── socket ──► Python hook script                  │
│     ├── decision: "allow" | "deny" | "ask"                      │
│     └── reason: String?                                         │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Summary

```
Python Hook Script
       │
       ▼ (Unix domain socket, JSON)
   HookEvent (Codable, snake_case → camelCase via CodingKeys)
       │
       ├── expectsResponse == true?
       │       │
       │       ▼ Yes
       │   PendingPermission (sessionId, toolUseId, clientSocket, event, receivedAt)
       │       │
       │       ▼ Extract context
       │   PermissionContext (toolUseId, toolName, toolInput, receivedAt)
       │       │
       │       ▼ Embed in phase
       │   ClaudeSessionPhase.waitingForApproval(PermissionContext)
       │       │
       │       ▼ User clicks Allow/Deny
       │   HookResponse(decision: "allow"/"deny", reason: nil?)
       │       │
       │       ▼ (write JSON back to clientSocket)
       │   Python Hook Script
       │
       └── expectsResponse == false?
               │
               ▼
           ClaudeSessionPhase (notification or active state)
```
