# Hook System Reference

> **Source files covered in this document:**
> - `Sources/Services/Hooks/HookInstaller.swift` (603 lines)
> - `Sources/Services/Hooks/HookSocketServer.swift` (317 lines)
> - `Sources/Services/ClaudeSessionManager.swift` (137 lines)
> - `Sources/Resources/vibe-pomodoro-hook.py` (121 lines)
> - `Sources/Models/ClaudeModels.swift` (188 lines)

---

## A. Overview

The vibe-pomodoro hook system is a **five-component pipeline** that enables real-time integration between Claude Code / Codex CLI and the notch-based UI. When a Claude Code or Codex CLI session fires a hook event, the pipeline carries that event through a Python script, a Unix domain socket, a Swift socket server, a session manager, and ultimately into the SwiftUI notch view.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                         HOOK SYSTEM PIPELINE (5 components)                          │
├──────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Claude Code / Codex CLI                                                             │
│       │                                                                              │
│       │ fires hook event (JSON via stdin)                                            │
│       ▼                                                                              │
│  ① Python Hook Script (vibe-pomodoro-hook.py)                                       │
│       │  reads stdin JSON → builds state dict → sends via AF_UNIX socket             │
│       │  for PermissionRequest: BLOCKS on recv() for a decision                      │
│       ▼                                                                              │
│  ② Unix Domain Socket (/tmp/vibe-pomodoro-claude.sock)                              │
│       │                                                                              │
│       ▼                                                                              │
│  ③ HookSocketServer (Swift, singleton)                                              │
│       │  accepts connection → reads JSON → decodes HookEvent                          │
│       │  non-permission: emit immediately via Combine PassthroughSubject             │
│       │  permission: keep fd open, store PendingPermission, emit resolved event      │
│       ▼                                                                              │
│  ④ ClaudeSessionManager (Swift, ObservableObject)                                    │
│       │  subscribes to eventSubject → maps status to ClaudeSessionPhase              │
│       │  exposes @Published currentPhase for SwiftUI binding                          │
│       ▼                                                                              │
│  ⑤ NotchViewModel / NotchView (SwiftUI)                                              │
│       │  derives displayState from claudePhase → renders notch UI                    │
│       │  user actions (Allow/Deny) call back into ClaudeSessionManager               │
│       ▼                                                                              │
│  User sees notification in the notch                                                 │
│                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

The pipeline is **bidirectional** for permission requests: the Python script blocks on `recv()` while the user decides in the notch UI, and the decision flows back through the socket to unblock Claude Code.

---

## B. HookInstaller

**File:** `Sources/Services/Hooks/HookInstaller.swift`

`HookInstaller` is a **namespace enum** containing only static methods — it is never instantiated. It handles installing, checking, and uninstalling hook scripts for both Claude Code and Codex CLI.

### B.1 Path Constants

| Path Struct | Property | Resolved Path |
|---|---|---|
| `ClaudePaths` | `claudeDir` | `~/.claude` |
| `ClaudePaths` | `hooksDir` | `~/.claude/hooks` |
| `ClaudePaths` | `settingsFile` | `~/.claude/settings.json` |
| `ClaudePaths` | `hookScript` | `~/.claude/hooks/vibe-pomodoro-hook.py` |
| `CodexPaths` | `codexDir` | `~/.codex` |
| `CodexPaths` | `hooksFile` | `~/.codex/hooks.json` |
| `CodexPaths` | `hookScript` | Reuses `ClaudePaths.hookScript` (shared script) |

Both Claude Code and Codex CLI use the **same Python script** at `~/.claude/hooks/vibe-pomodoro-hook.py`.

### B.2 Supported Hook Events

#### Claude Code (13 events)

| # | Event Name | Has Matcher? | Timeout |
|---|---|---|---|
| 1 | `UserPromptSubmit` | No | — (default) |
| 2 | `PreToolUse` | Yes (`"*"`) | — |
| 3 | `PostToolUse` | Yes (`"*"`) | — |
| 4 | `PermissionRequest` | Yes (`"*"`) | 86400s (24h) |
| 5 | `Notification` | Yes (`"*"`) | — |
| 6 | `Stop` | No | — |
| 7 | `StopFailure` | Yes (`"*"`) | — |
| 8 | `SessionStart` | No | — |
| 9 | `SessionEnd` | No | — |
| 10 | `PreCompact` | Yes (`"*"`) | — |
| 11 | `PostCompact` | Yes (`"*"`) | — |
| 12 | `SubagentStart` | Yes (`"*"`) | — |
| 13 | `SubagentStop` | Yes (`"*"`) | — |

#### Codex CLI (10 events)

Same as Claude Code **minus** `Notification`, `StopFailure`, and `SessionEnd`.

| # | Event Name | Has Matcher? | Timeout |
|---|---|---|---|
| 1 | `UserPromptSubmit` | No | 30s |
| 2 | `PreToolUse` | Yes (`".*"`) | 30s |
| 3 | `PostToolUse` | Yes (`".*"`) | 30s |
| 4 | `PermissionRequest` | Yes (`".*"`) | 86400s (24h) |
| 5 | `Stop` | No | 30s |
| 6 | `SessionStart` | No | 30s |
| 7 | `SubagentStart` | Yes (`".*"`) | 30s |
| 8 | `SubagentStop` | Yes (`".*"`) | 30s |
| 9 | `PreCompact` | Yes (`".*"`) | 30s |
| 10 | `PostCompact` | Yes (`".*"`) | 30s |

> **Matcher difference:** Claude Code uses glob `"*"`; Codex CLI uses regex `".*"`.

### B.3 Python Detection

The installer searches for `python3` at known paths in priority order:

| Priority | Path | Notes |
|---|---|---|
| 1 | `/usr/bin/python3` | macOS system Python (usually present) |
| 2 | `/usr/local/bin/python3` | Homebrew Intel path |
| 3 | `/opt/homebrew/bin/python3` | Homebrew Apple Silicon path |
| 4 | `"python3"` | Fallback: rely on `$PATH` |

The detected path is used both as the shebang line (`#!`) in the installed script and as the command prefix in settings.

### B.4 Public API

| Method | Description |
|---|---|
| `installIfNeeded()` | Writes the Python script to disk (chmod 755) and registers hooks in `~/.claude/settings.json`. Called on app launch. |
| `isInstalled() -> Bool` | Checks both the script file and settings JSON for the hook identifier. Supports nested and legacy flat formats. |
| `uninstall()` | Removes the script file and strips all vibe-pomodoro entries from settings. |
| `installCodexIfNeeded()` | Writes the shared script and registers hooks in `~/.codex/hooks.json`. |
| `isCodexInstalled() -> Bool` | Checks the script file and `~/.codex/hooks.json` for the hook identifier. |
| `uninstallCodex()` | Strips all vibe-pomodoro entries from Codex hooks.json. |
| `isVibeNotchInstalled() -> Bool` | Checks if `claude-island-state.py` appears in any Claude hook command (conflict detection). |
| `detectClaudeCodeVersion() -> ClaudeCodeVersion?` | Detects Claude Code installation and version (`.v1` or `.v2`). |

### B.5 Registration Format

Hooks are registered in the **nested format**:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 /Users/<user>/.claude/hooks/vibe-pomodoro-hook.py",
            "timeout": 86400
          }
        ]
      }
    ]
  }
}
```

- Each event maps to an **array of hook groups**.
- Each hook group has an optional `"matcher"` field and a `"hooks"` array.
- Each hook in the `"hooks"` array has `"type"`, `"command"`, and optionally `"timeout"`.

The installer supports both this nested format and a **legacy flat format** (where `command` and `timeout` are directly on the entry object). The flat format is supported for backward compatibility during detection and uninstall, but new registrations always use the nested format.

### B.6 Timeout Configuration

| CLI | Event | Timeout |
|---|---|---|
| Claude Code | `PermissionRequest` | 86400s (24 hours) |
| Claude Code | All other events | Not set (uses Claude's default) |
| Codex CLI | `PermissionRequest` | 86400s (24 hours) |
| Codex CLI | All other events | 30s |

### B.7 vibe-notch Conflict Detection

`isVibeNotchInstalled()` scans all hook entries in `~/.claude/settings.json` for the string `"claude-island-state.py"`. If found, the settings UI displays a warning. This prevents double-prompting and conflicting notch rendering when both tools are installed.

### B.8 Embedded Hook Script

The Python script is stored as a **string literal** inside `hookScriptContent(pythonPath:)`. When writing the script to disk, the detected Python path is interpolated into the shebang line:

```swift
private static func hookScriptContent(pythonPath: String) -> String {
    return """
    #!\(pythonPath)
    \"\"\"VibePomodoro Hook - Sends session state via Unix socket\"\"\"
    ...
    """
}
```

A standalone copy also exists at `Sources/Resources/vibe-pomodoro-hook.py` for reference and version control, but the **runtime copy** is always generated from the embedded string literal to ensure the shebang matches the detected Python path.

---

## C. Python Hook Script

**File:** `Sources/Resources/vibe-pomodoro-hook.py` (121 lines)

This is a stateless script invoked by Claude Code / Codex CLI on every hook event. Each invocation is a **fresh process** — no state persists between calls.

### C.1 Constants

| Constant | Value | Purpose |
|---|---|---|
| `SOCKET_PATH` | `"/tmp/vibe-pomodoro-claude.sock"` | Unix domain socket path |
| `TIMEOUT_SECONDS` | `300` | Socket timeout (5 minutes) |

### C.2 `send_event(state)` Function

```python
def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()
        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None
```

**Behavior:**

1. Creates an `AF_UNIX` `SOCK_STREAM` socket.
2. Sets a 300-second timeout.
3. Connects to the socket path.
4. Sends the JSON-encoded `state` dict.
5. **For `waiting_for_approval` status:** blocks on `recv(4096)`, parses the response JSON, and returns it as a dict. This is the blocking call that keeps Claude Code waiting for the user's permission decision.
6. **For all other statuses:** closes the socket immediately and returns `None`.
7. **Error handling:** all `socket.error`, `OSError`, and `json.JSONDecodeError` exceptions are caught and swallowed — returns `None`. **The script never crashes Claude Code.**

### C.3 `main()` Function

Reads JSON from `stdin`, extracts event metadata, builds a `state` dict, and dispatches based on the event name.

#### Input Parsing

```python
data = json.load(sys.stdin)          # JSON decode failure → exit(1)
session_id = data.get("session_id", "unknown")
event = data.get("hook_event_name", "")
cwd = data.get("cwd", "")
tool_input = data.get("tool_input", {})
claude_pid = os.getppid()
```

The base `state` dict always includes: `session_id`, `cwd`, `event`, `pid`.

#### Event-Specific Mapping Table

| Event | Status | Extra Fields | Behavior |
|---|---|---|---|
| `UserPromptSubmit` | `processing` | — | `send_event(state)` |
| `PreToolUse` (tool=`AskUserQuestion`) | `waiting_for_response` | `tool`, `message` (first question) | `send_event(state)` |
| `PreToolUse` (other) | `running_tool` | `tool`, `tool_input`, `tool_use_id` | `send_event(state)` |
| `PostToolUse` | `processing` | `tool`, `tool_use_id` | `send_event(state)` |
| `PermissionRequest` | `waiting_for_approval` | `tool`, `tool_input` | **BLOCKS** on `send_event(state)` for response |
| `Notification` (`permission_prompt`) | — | — | **Exit 0 immediately** (suppressed) |
| `Notification` (`idle_prompt`) | `waiting_for_input` | — | `send_event(state)` |
| `Notification` (other) | `notification` | `notification_type`, `message` | `send_event(state)` |
| `Stop` | `waiting_for_input` | — | `send_event(state)` |
| `StopFailure` | `waiting_for_input` | `message` (from `error` or `message` field) | `send_event(state)` |
| `SubagentStart` | `processing` | — | `send_event(state)` |
| `SubagentStop` | `processing` | — | `send_event(state)` |
| `SessionStart` | `waiting_for_input` | — | `send_event(state)` |
| `SessionEnd` | `ended` | — | `send_event(state)` |
| `PreCompact` | `compacting` | — | `send_event(state)` |
| `PostCompact` | `processing` | — | `send_event(state)` |
| *(unknown)* | `unknown` | — | `send_event(state)` |

#### PermissionRequest Response Handling

When `send_event(state)` returns a response dict (user has made a decision):

```python
decision = response.get("decision", "ask")
reason = response.get("reason", "")

if decision == "allow":
    output = {"hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {"behavior": "allow"}
    }}
    print(json.dumps(output))
    sys.exit(0)

elif decision == "deny":
    output = {"hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {
            "behavior": "deny",
            "message": reason or "Denied via vibe-pomodoro"
        }
    }}
    print(json.dumps(output))
    sys.exit(0)

# No response received → exit 0 (Claude uses default behavior)
sys.exit(0)
```

| Decision | stdout Output | Effect |
|---|---|---|
| `allow` | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` | Claude proceeds with the tool |
| `deny` | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"..."}}}` | Claude aborts the tool |
| No response | *(nothing)* | Claude uses its default behavior |

### C.4 Notification Suppression

When a `Notification` event with `notification_type == "permission_prompt"` arrives, the script calls `sys.exit(0)` **before** building any state or calling `send_event()`. This prevents double-prompting — the `PermissionRequest` hook already fires for the same tool, so the notification is redundant.

### C.5 Error Handling Philosophy

All errors are **swallowed silently**:

| Error Source | Handling |
|---|---|
| `json.JSONDecodeError` on stdin | `sys.exit(1)` |
| Socket connection failure | `send_event` returns `None` |
| Socket timeout | `send_event` returns `None` |
| JSON decode failure on response | `send_event` returns `None` |
| No response (app crashed / not running) | `send_event` returns `None` → exit 0 |

**The script must never crash or block Claude Code indefinitely.** If the app is not running, `send_event` fails silently and the script exits normally, allowing Claude to continue with default behavior.

---

## D. HookSocketServer

**File:** `Sources/Services/Hooks/HookSocketServer.swift` (317 lines)

### D.1 Class Declaration

```swift
final class HookSocketServer: @unchecked Sendable {
    static let shared = HookSocketServer()
```

- `final class` — not inheritable.
- `@unchecked Sendable` — manual thread safety via `NSLock` and a serial `DispatchQueue`.
- **Singleton** via `static let shared` — justified because there is exactly one Unix socket endpoint.

### D.2 Constants

| Constant | Value | Purpose |
|---|---|---|
| `socketPath` | `"/tmp/vibe-pomodoro-claude.sock"` | Unix domain socket file path |
| `bufferSize` | `131_072` (128 KB) | Read buffer for incoming JSON |
| `pollTimeout` | `0.5` seconds | Maximum time to wait for a complete message |

### D.3 Combine Publisher

```swift
let eventSubject = PassthroughSubject<HookEvent, Never>()
```

A `PassthroughSubject` that broadcasts decoded `HookEvent` values to subscribers (typically `ClaudeSessionManager`). Events are emitted on the `socketQueue`.

### D.4 State

| Property | Type | Purpose |
|---|---|---|
| `serverSocket` | `Int32` | File descriptor for the listening socket (-1 when stopped) |
| `acceptSource` | `DispatchSourceRead?` | GCD source that fires when a new connection arrives |
| `socketQueue` | `DispatchQueue` | Serial queue (`.userInitiated`) for all socket operations |
| `lock` | `NSLock` | Protects `pendingPermissions` and `toolUseCache` |
| `pendingPermissions` | `[String: PendingPermission]` | Keyed by `toolUseId`; stores client fd for blocking responses |
| `isRunning` | `Bool` | Prevents double-start |
| `toolUseCache` | `[ToolUseEntry]` | FIFO cache for tool_use_id correlation |
| `maxCacheSize` | `Int` (50) | Maximum entries in the FIFO cache |

### D.5 ToolUseEntry (FIFO Cache)

```swift
private struct ToolUseEntry {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let timestamp: Date
}
```

This struct correlates `PreToolUse` events with subsequent `PermissionRequest` events. The `PermissionRequest` payload from Claude Code may not include a `tool_use_id`, so the server uses the cache to look up the most recent `PreToolUse` with the same tool name.

| Method | Behavior |
|---|---|
| `cacheToolUse(toolUseId:toolName:toolInput:)` | Appends a new entry; trims cache to `maxCacheSize` (50) by removing the oldest entry. |
| `resolveToolUseId(for:)` | Returns the `toolUseId` of the **last** cached entry whose `toolName` matches the event's tool. |

### D.6 `start()` Method

```swift
func start() {
    socketQueue.async { [weak self] in
        self?.startServer()
    }
}
```

`startServer()` performs the following steps:

1. **Guard** against double-start (`isRunning`).
2. **Unlink** any stale socket file at `socketPath`.
3. **Create** an `AF_UNIX` `SOCK_STREAM` socket.
4. **Set non-blocking** via `fcntl(F_SETFL, flags | O_NONBLOCK)`.
5. **Bind** to `sockaddr_un` with the socket path.
6. **Set permissions** `chmod(socketPath, 0o600)` — owner read/write only.
7. **Listen** with a backlog of 16.
8. **Create** a `DispatchSource.makeReadSource` on `socketQueue` that calls `acceptConnection()` when data is available.
9. **Set cancel handler** to close the socket and unlink the file.
10. **Resume** the source and set `isRunning = true`.

### D.7 `handleClient(fd:)` Method

This is the core per-connection handler, dispatched on `socketQueue`:

```
┌─────────────────────────────────────────────────────────────┐
│                    handleClient(fd:)                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Read loop (deadline = now + 0.5s)                       │
│     ├── read(fd, buffer, 128KB)                             │
│     ├── if bytesRead > 0 → append to data                   │
│     │   └── if last byte == '}' → break (complete JSON)     │
│     ├── if bytesRead == 0 → break (connection closed)       │
│     └── if EAGAIN/EWOULDBLOCK → usleep(10ms), retry        │
│                                                             │
│  2. Decode: JSONDecoder().decode(HookEvent.self, from:data) │
│     └── failure → print error, return                        │
│                                                             │
│  3. Cache: if PreToolUse + toolUseId → cacheToolUse()       │
│                                                             │
│  4. Branch:                                                 │
│     ├── expectsResponse (PermissionRequest):                │
│     │   ├── Resolve toolUseId:                               │
│     │   │   event.toolUseId ?? resolveToolUseId() ?? UUID   │
│     │   ├── Create PendingPermission (keeps fd OPEN)        │
│     │   ├── Store in pendingPermissions[toolUseId]         │
│     │   └── Emit RESOLVED event (not original) via          │
│     │       eventSubject.send(resolvedEvent)                │
│     │                                                        │
│     └── Non-permission:                                     │
│         └── eventSubject.send(event) directly               │
│                                                             │
│  defer: close(fd) ONLY if not in pendingPermissions        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### The "resolved event" critical fix

When a `PermissionRequest` arrives without a `tool_use_id`, the server resolves one via the FIFO cache (by tool name) or generates a UUID. It then constructs a **new `HookEvent`** with this resolved `toolUseId` and emits **that** instead of the original. This ensures `ClaudeSessionManager` stores the same `toolUseId` key that the server will use when `respondToPermission` is called later.

### D.8 `respondToPermission(toolUseId:decision:reason:)`

```swift
func respondToPermission(toolUseId: String, decision: String, reason: String?) {
    lock.lock()
    guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
        lock.unlock()
        return
    }
    lock.unlock()

    let response = HookResponse(decision: decision, reason: reason)
    socketQueue.async {
        self.sendResponse(response, to: pending.clientSocket)
    }
}
```

1. Removes the `PendingPermission` from the dictionary (thread-safe via lock).
2. Creates a `HookResponse` with the decision and optional reason.
3. Dispatches `sendResponse` on `socketQueue` to write the response JSON to the client socket and close the fd.

This unblocks the Python script's `recv()` call, which then prints the `hookSpecificOutput` JSON and exits.

### D.9 `pendingCount` Property

```swift
var pendingCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return pendingPermissions.count
}
```

Returns the number of currently pending permission requests. Thread-safe.

---

## E. ClaudeSessionManager

**File:** `Sources/Services/ClaudeSessionManager.swift` (137 lines)

### E.1 Class Declaration

```swift
class ClaudeSessionManager: ObservableObject {
```

An `ObservableObject` that subscribes to `HookSocketServer.shared.eventSubject` and maps hook events into observable session phases for SwiftUI binding.

### E.2 Published Properties

| Property | Type | Description |
|---|---|---|
| `currentPhase` | `ClaudeSessionPhase` | Current state machine phase |
| `activeSessionId` | `String?` | Claude Code session ID |
| `projectName` | `String?` | Derived from `cwd` (last path component) |
| `lastToolName` | `String?` | Most recent tool name |
| `isSubagentActive` | `Bool` | Whether a subagent is running |

### E.3 Event Processing State Machine

`processEvent(_ event: HookEvent)` is called for every event received via Combine:

| `event.status` | `currentPhase` | Auto-Dismiss |
|---|---|---|
| `"processing"` | `.processing` | No |
| `"running_tool"` | `.processing` | No |
| `"waiting_for_input"` | `.waitingForInput` | 5 seconds |
| `"waiting_for_response"` | `.waitingForResponse(message)` | No (persists until next event) |
| `"waiting_for_approval"` | `.waitingForApproval(PermissionContext)` | No |
| `"compacting"` | `.compacting` | No |
| `"ended"` | `.idle` (via `resetSession()`) | No |
| *(default)* — `event.event == "StopFailure"` | `.error(message)` | 5 seconds |

When `currentPhase` is set to `.waitingForApproval`, a `PermissionContext` is constructed:

```swift
let context = PermissionContext(
    toolUseId: event.toolUseId ?? "",
    toolName: event.tool ?? "unknown",
    toolInput: event.toolInput,
    receivedAt: Date()
)
currentPhase = .waitingForApproval(context)
```

### E.4 Subagent Tracking

```swift
if event.event == "SubagentStart" {
    isSubagentActive = true
} else if event.event == "SubagentStop" {
    isSubagentActive = false
}
```

This is independent of phase — `isSubagentActive` is updated regardless of what `currentPhase` becomes.

### E.5 Permission Actions

| Method | Guard | Action | Phase After |
|---|---|---|---|
| `approvePermission()` | `case .waitingForApproval(let context)` | `server.respondToPermission(toolUseId:context.toolUseId, decision:"allow", reason:nil)` | `.processing` |
| `denyPermission(reason:)` | `case .waitingForApproval(let context)` | `server.respondToPermission(toolUseId:context.toolUseId, decision:"deny", reason:reason)` | `.idle` |
| `dismissNotification()` | (none) | `cancelAutoDismiss()` | `.idle` |

### E.6 Auto-Dismiss

```swift
private func scheduleAutoDismiss(after seconds: TimeInterval) {
    cancelAutoDismiss()
    let workItem = DispatchWorkItem { [weak self] in
        self?.currentPhase = .idle
    }
    autoDismissWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
}
```

- Uses a `DispatchWorkItem` on the main queue.
- Each new event **cancels** any pending auto-dismiss via `cancelAutoDismiss()` (called at the top of `processEvent`).
- Only `.waitingForInput` and `.error` (StopFailure) phases trigger auto-dismiss.

### E.7 Session Reset

When `event.status == "ended"` (SessionEnd), `resetSession()` is called:

```swift
private func resetSession() {
    currentPhase = .idle
    activeSessionId = nil
    isSubagentActive = false
}
```

---

## F. Complete Event Flow Diagrams

### F.1 Non-Permission Event Flow

Example: `UserPromptSubmit`, `PreToolUse`, `Stop`, `Notification(idle_prompt)`

```
Claude Code          Python Script           Socket Server          Session Manager          ViewModel          NotchView
     │                     │                       │                       │                     │                   │
     │── stdin JSON ──────▶│                       │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │── connect + send ───▶│                       │                     │                   │
     │                     │   (JSON state dict)   │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │                       │── recv 128KB ─────────│                     │                   │
     │                     │                       │── JSONDecoder ────────│                     │                   │
     │                     │                       │── cacheToolUse ───────│                     │                   │
     │                     │                       │   (if PreToolUse)     │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │                       │── eventSubject.send ▶│                     │                   │
     │                     │                       │                       │── processEvent ────▶│                   │
     │                     │                       │                       │── map to phase ─────▶│                   │
     │                     │                       │                       │                     │── displayState ──▶│
     │                     │                       │                       │                     │                   │── render UI
     │                     │◀── socket closed ────│                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │◀── exit(0) ─────────│                       │                       │                     │                   │
     │                     │                       │                       │                     │                   │
```

**Key point:** The socket is closed immediately after the event is emitted. No response is expected or sent.

### F.2 Permission Request Flow (Full Round-Trip)

```
Claude Code          Python Script           Socket Server          Session Manager          ViewModel          NotchView
     │                     │                       │                       │                     │                   │
     │── PermissionRequest │                       │                       │                     │                   │
     │   (stdin JSON) ───▶│                       │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │── connect + send ───▶│                       │                     │                   │
     │                     │   status=            │                       │                     │                   │
     │                     │   "waiting_for_      │                       │                     │                   │
     │                     │    approval"         │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │                       │── recv + decode ───────│                     │                   │
     │                     │                       │── resolve toolUseId ──│                     │                   │
     │                     │                       │   (cache or UUID)     │                     │                   │
     │                     │                       │── store PendingPerm ──│                     │                   │
     │                     │                       │   (fd stays OPEN)     │                     │                   │
     │                     │                       │── emit RESOLVED ─────▶│                     │                   │
     │                     │                       │   event                │                     │                   │
     │                     │                       │                       │── processEvent ────▶│                   │
     │                     │                       │                       │── .waitingForApproval                  │
     │                     │                       │                       │   (PermissionContext)                  │
     │                     │                       │                       │                     │── displayState ──▶│
     │                     │                       │                       │                     │   .claudeApproval│
     │                     │                       │                       │                     │                   │── show Allow/Deny
     │                     │                       │                       │                     │                   │   buttons
     │                     │                       │                       │                     │                   │
     │                     │   ⏳ BLOCKING          │                       │                     │                   │
     │                     │   recv(4096) ...      │                       │                     │                   │
     │                     │   (waits up to 300s)  │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │                       │                       │                     │   ┌───────────────┤
     │                     │                       │                       │                     │   │ User clicks   │
     │                     │                       │                       │                     │   │ "Allow"       │
     │                     │                       │                       │                     │   └──────┬────────┘
     │                     │                       │                       │                     │          │
     │                     │                       │                       │◀── approvePermission│          │
     │                     │                       │                       │                     │          │
     │                     │                       │◀── respondToPermission                     │          │
     │                     │                       │    (toolUseId,         │                     │          │
     │                     │                       │     decision:"allow", │                     │          │
     │                     │                       │     reason:nil)        │                     │          │
     │                     │                       │                       │                     │          │
     │                     │                       │── remove PendingPerm   │                     │          │
     │                     │                       │── encode HookResponse │                     │          │
     │                     │                       │── write to client fd ─▶│                    │          │
     │                     │                       │── close(fd)           │                     │          │
     │                     │                       │                       │── currentPhase =    │          │
     │                     │                       │                       │   .processing ─────▶│          │
     │                     │                       │                       │                     │── UI updates     │
     │                     │                       │                       │                     │   to processing  │
     │                     │◀── recv returns ──────│                       │                     │                   │
     │                     │   response JSON      │                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │                     │── parse decision ─    │                       │                     │                   │
     │                     │   "allow"            │                       │                     │                   │
     │                     │── print hookSpecificOutput                  │                     │                   │
     │                     │   {"hookSpecificOutput":                   │                     │                   │
     │                     │    {"hookEventName":                     │                     │                   │
     │                     │     "PermissionRequest",                │                     │                   │
     │                     │     "decision":{"behavior":             │                     │                   │
     │                     │      "allow"}}}                        │                     │                   │
     │                     │── exit(0) ──────────│                       │                     │                   │
     │                     │                       │                       │                     │                   │
     │◀── stdout consumed ─│                       │                       │                     │                   │
     │   Claude proceeds   │                       │                       │                     │                   │
     │   with the tool     │                       │                       │                     │                   │
     │                     │                       │                       │                     │                   │
```

**Key point:** The client socket fd is kept open in `pendingPermissions` until the user responds (or the server is stopped). This is what allows the blocking `recv()` in the Python script to eventually return.

### F.3 Notification Suppression Flow

When Claude Code fires a `Notification` event with `notification_type == "permission_prompt"`:

```
Claude Code          Python Script           Socket Server          Session Manager
     │                     │                       │                       │
     │── Notification      │                       │                       │
     │   (stdin JSON,      │                       │                       │
     │    notification_type│                       │                       │
     │    = "permission_   │                       │                       │
     │     prompt") ──────▶│                       │                       │
     │                     │                       │                       │
     │                     │── if notification_type│                       │
     │                     │   == "permission_     │                       │
     │                     │   prompt":            │                       │
     │                     │── sys.exit(0) ────────▶│ (never reached)       │
     │                     │   (NO send_event)     │                       │
     │                     │                       │                       │
     │◀── exit(0) ─────────│                       │                       │
     │                     │                       │                       │
     │   Claude continues  │                       │                       │
     │   with default      │                       │                       │
     │   behavior          │                       │                       │
```

**Key point:** No socket connection is made. The event is entirely suppressed. This prevents double-prompting since `PermissionRequest` fires separately for the same tool.

---

## G. Data Contracts

### G.1 HookEvent (Python → Swift via socket)

**JSON format** (snake_case keys):

```json
{
  "session_id": "abc-123-def",
  "cwd": "/Users/user/project",
  "event": "PermissionRequest",
  "status": "waiting_for_approval",
  "pid": 12345,
  "tty": null,
  "tool": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/test"
  },
  "tool_use_id": "toolu_01ABC",
  "notification_type": null,
  "message": null
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `session_id` | String | Yes | Claude Code session identifier |
| `cwd` | String | Yes | Current working directory |
| `event` | String | Yes | Hook event name (e.g. `"PreToolUse"`) |
| `status` | String | Yes | Derived status (see mapping table in C.3) |
| `pid` | Int? | Yes | Parent process PID (`os.getppid()`) |
| `tty` | String? | No | Declared in Swift struct; not currently sent by Python |
| `tool` | String? | No | Tool name (for tool-related events) |
| `tool_input` | `{String: AnyCodable}`? | No | Tool input parameters |
| `tool_use_id` | String? | No | Unique tool use identifier |
| `notification_type` | String? | No | Notification type (for Notification events) |
| `message` | String? | No | Human-readable message or question text |

**Swift type:** `HookEvent: Codable, Sendable` with explicit `CodingKeys` mapping snake_case to camelCase.

### G.2 HookResponse (Swift → Python via socket)

**JSON format:**

```json
{
  "decision": "allow",
  "reason": null
}
```

| Field | Type | Values |
|---|---|---|
| `decision` | String | `"allow"`, `"deny"`, or `"ask"` |
| `reason` | String? | Denial reason (used as message for deny) |

**Swift type:** `HookResponse: Codable`

### G.3 hookSpecificOutput (Python stdout → Claude Code)

Printed to stdout by the Python script for `PermissionRequest` events:

**Allow:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

**Deny:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "Denied via vibe-pomodoro"
    }
  }
}
```

| Field | Type | Values |
|---|---|---|
| `hookSpecificOutput.hookEventName` | String | Always `"PermissionRequest"` |
| `hookSpecificOutput.decision.behavior` | String | `"allow"` or `"deny"` |
| `hookSpecificOutput.decision.message` | String? | Only present for `"deny"`; defaults to `"Denied via vibe-pomodoro"` |

### G.4 Claude Code Settings JSON

**File:** `~/.claude/settings.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/.claude/hooks/vibe-pomodoro-hook.py",
            "timeout": null
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/.claude/hooks/vibe-pomodoro-hook.py",
            "timeout": 86400
          }
        ]
      }
    ]
  }
}
```

- **Matcher:** glob `"*"` (wildcard matching all tools).
- **Timeout:** only `PermissionRequest` gets `86400` (24h); all other events omit the timeout key.
- **Format:** nested `{"hooks": [{"type": "command", "command": "...", "timeout": N, "matcher": "*"}]}`.

### G.5 Codex CLI Settings JSON

**File:** `~/.codex/hooks.json`

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/.claude/hooks/vibe-pomodoro-hook.py",
            "timeout": 86400
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 ~/.claude/hooks/vibe-pomodoro-hook.py",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

- **Matcher:** regex `".*"` (matches all tools).
- **Timeout:** `PermissionRequest` gets `86400`; all other events get `30`.
- **Script:** reuses `ClaudePaths.hookScript` (same Python file as Claude Code).

### G.6 Swift Data Models

#### `ClaudeSessionPhase` (State Machine)

```swift
enum ClaudeSessionPhase: Sendable, Equatable {
    case idle
    case processing
    case waitingForInput
    case waitingForResponse(String?)  // question text
    case waitingForApproval(PermissionContext)
    case compacting
    case error(String)
}
```

**Computed properties:**

| Property | Returns `true` when |
|---|---|
| `needsAttention` | `.waitingForApproval`, `.waitingForInput`, `.waitingForResponse` |
| `isWaitingForApproval` | `.waitingForApproval` |
| `isNotification` | `.waitingForInput`, `.error`, `.waitingForResponse` |
| `isActive` | `.processing`, `.compacting` |

Custom `Equatable` implementation compares associated values.

#### `PermissionContext`

```swift
struct PermissionContext: Sendable, Equatable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date
}
```

`formattedInput` computed property intelligently formats tool input for display:
- `Bash` → shows `command` (truncated to 120 chars)
- `Write`/`Edit` → shows file name from `file_path`
- `Read` → shows file name from `file_path`
- Fallback: checks priority keys `["command", "file_path", "path", "query", "pattern", "url"]`
- Last resort: first non-`description` string value

#### `PendingPermission`

```swift
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}
```

Internal tracking struct used by `HookSocketServer` to keep the client socket fd open while waiting for the user's permission decision.

#### `AnyCodable`

A type-erasing `Codable` wrapper that handles arbitrary JSON values:

```swift
struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any
}
```

Decodes: `NSNull`, `Bool`, `Int`, `Double`, `String`, `[AnyCodable]`, `[String: AnyCodable]`.

---

## H. Known Limitations

### H.1 Heuristic tool_use_id Correlation

The `resolveToolUseId(for:)` method finds the **last** `PreToolUse` entry in the FIFO cache whose `toolName` matches. If Claude Code makes rapid successive calls to the **same tool** (e.g., two `Bash` calls in quick succession), the correlation may match the wrong `PreToolUse` entry, causing the permission response to be sent to the wrong client socket.

**Mitigation:** The FIFO cache is capped at 50 entries, reducing stale match probability. If Claude Code includes `tool_use_id` in the `PermissionRequest` payload (newer versions do), the cache lookup is bypassed entirely.

### H.2 Timeout Mismatch

| Layer | Timeout | Effect |
|---|---|---|
| Python script (`TIMEOUT_SECONDS`) | 300s (5 minutes) | Socket recv() blocks for at most 5 min |
| Claude Code hook timeout | 86400s (24 hours) | Claude waits up to 24 hours for the hook to exit |

If the user does not respond within 5 minutes, the Python socket times out, `send_event` returns `None`, and the script exits with code 0 (no decision). Claude Code then proceeds with its **default behavior** for the permission request.

### H.3 App Crash During Pending Permission

If the vibe-pomodoro app crashes or is killed while a permission request is pending:

1. The `pendingPermissions` dictionary is lost.
2. The client socket fd is never written to.
3. The Python script's `recv(4096)` blocks until the 300-second timeout.
4. After timeout, `send_event` returns `None`, the script exits with code 0.
5. Claude Code proceeds with default behavior (typically prompting the user in the terminal).

**No data corruption or deadlock occurs**, but the Claude Code session is delayed by up to 5 minutes.

### H.4 Single Socket Endpoint

The server uses a singleton (`HookSocketServer.shared`) with a single Unix socket. If multiple instances of vibe-pomodoro were to run simultaneously, the second instance would fail to bind the socket (the first instance holds it). The `unlink` call in `start()` would remove the first instance's socket, breaking its event reception.

### H.5 JSON Completeness Heuristic

The server detects complete JSON by checking if the last byte is `}` (closing brace). This works for all current event payloads but would fail for JSON containing trailing whitespace or newlines after the closing brace. In practice, the Python script sends clean JSON without trailing characters.

### H.6 No Codex Notification/StopFailure/SessionEnd Support

Codex CLI does not support `Notification`, `StopFailure`, or `SessionEnd` events. The hook system cannot detect idle prompts, stop failures, or session termination for Codex sessions. The UI will remain in the last known phase until another supported event arrives.
