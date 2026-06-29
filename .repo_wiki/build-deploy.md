# Build and Deployment Guide

## Prerequisites

| Requirement | Details |
|---|---|
| **macOS** | 13 Ventura or later (`LSMinimumSystemVersion = 13.0`) |
| **Swift toolchain** | Swift 5.9+ (tools version). Verify with `swift --version`. The project compiles on Apple Swift 6.3+ toolchains. Xcode includes Swift; alternatively install via swift.org or `xcode-select --install`. |
| **Python 3** | Required for the hook script. Auto-detected at one of: `/usr/bin/python3`, `/usr/local/bin/python3`, `/opt/homebrew/bin/python3`. Verify with `python3 --version`. |
| **Claude Code CLI** (optional) | Needed for Claude Code hook integration. Install from Anthropic. |
| **OpenAI Codex CLI** (optional) | Needed for Codex CLI hook integration. |

No additional package managers (CocoaPods, Carthage, etc.) are needed — the project has zero external dependencies.

---

## Debug Build

### Build

```bash
swift build
```

This compiles the `NotchPomodoro` executable target in debug mode. The binary is placed at `.build/debug/NotchPomodoro`.

### Run

```bash
swift run
```

This builds (if needed) and runs the app directly from the `.build/debug/` directory.

> **Important limitation:** When running via `swift run`, the executable is **not inside a `.app` bundle**. The app checks `Bundle.main.bundleURL.pathExtension == "app"` before requesting notification authorization. Since this check fails when running via `swift run`, the notification permission dialog is **skipped**, and system notifications (work-complete alerts, break reminders) will **not fire**. The timer, notch UI, and hook integration will still work. For full functionality including notifications, use the app bundle approach below.

---

## Release Build

### Compile in release mode

```bash
swift build -c release
```

This produces an optimized binary at `.build/release/NotchPomodoro`.

### Create the app bundle

```bash
./build.sh
```

This script (42 lines) automates the creation of a proper macOS `.app` bundle. See [What build.sh Does](#what-buildsh-does-step-by-step) for details.

### Run the app bundle

```bash
open .build/release/NotchPomodoro.app
```

When launched from a `.app` bundle, the app will:
- Request notification authorization (after a 1-second delay).
- Install hooks to `~/.claude/` and `~/.codex/`.
- Start the Unix domain socket server.
- Display the notch UI.

---

## What `build.sh` Does Step by Step

The `build.sh` script performs the following steps:

```
1. set -e                          # Exit on any error
2. APP_NAME="NotchPomodoro"
   BUILD_DIR=".build/release"
   APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
3. echo "🔨 Compiling Release..."  # (Chinese: "Compile Release version")
4. swift build -c release           # Compile the optimized binary
5. echo "📦 Creating .app bundle..." # (Chinese: "Create .app bundle")
6. rm -rf "${APP_BUNDLE}"          # Remove any previous bundle
7. mkdir -p "${MACOS_DIR}"          # Create Contents/MacOS/
8. mkdir -p "${RESOURCES_DIR}"     # Create Contents/Resources/
9. cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/"          # Copy executable
10. cp "Sources/App/Info.plist" "${CONTENTS_DIR}/"         # Copy Info.plist
11. cp "Sources/App/NotchPomodoro.entitlements" "${CONTENTS_DIR}/"  # Copy entitlements
12. cp "Sources/Resources/AppIcon.icns" "${RESOURCES_DIR}/"         # Copy icon
13. echo "✅ Build complete: ${APP_BUNDLE}"
```

The resulting bundle structure:

```
.build/release/NotchPomodoro.app/
└── Contents/
    ├── Info.plist                      # Bundle metadata
    ├── MacOS/
    │   └── NotchPomodoro               # Compiled executable
    ├── NotchPomodoro.entitlements      # Entitlements (for signing reference)
    └── Resources/
        └── AppIcon.icns                # App icon
```

> **Note:** The script does **not** code-sign the bundle. For local development and personal use, this is fine — macOS will allow running unsigned apps after a right-click → Open confirmation (or after `xattr -cr` to clear the quarantine flag). For distribution, you would need to add `codesign` steps.

---

## Installation

### Install to /Applications

```bash
cp -r .build/release/NotchPomodoro.app /Applications/
open /Applications/NotchPomodoro.app
```

### Clear quarantine (if needed)

If macOS blocks the app because it was downloaded or built outside Xcode:

```bash
xattr -cr /Applications/NotchPomodoro.app
open /Applications/NotchPomodoro.app
```

### Launch at login

To add the app to your login items:
1. Open **System Settings → General → Login Items**.
2. Add `NotchPomodoro.app` under "Open at Login".

Alternatively, right-click the app in Finder → **Options** → **Open at Login**.

---

## Hook Auto-Installation

On first launch (and every launch — installation is idempotent), the app automatically installs hooks for both Claude Code and Codex CLI.

### Claude Code hooks

`HookInstaller.installIfNeeded()` performs:

1. **Creates the hooks directory**: `~/.claude/hooks/` (if it doesn't exist).
2. **Writes the hook script**: `~/.claude/hooks/notch-pomodoro-hook.py` — the script content is embedded as a Swift string literal in `HookInstaller.hookScriptContent(pythonPath:)`, with the shebang dynamically set to the detected Python 3 path. File permissions set to `0o755` (executable).
3. **Registers in settings.json**: Reads or creates `~/.claude/settings.json`, strips any existing `notch-pomodoro-hook.py` entries (handles both nested and legacy flat formats), then registers the hook for **13 events**:
   - `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionStart`, `SessionEnd`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`
4. Uses the **nested hooks format** (Claude Code v2 schema): each event maps to an array of `{ "hooks": [{ "type": "command", "command": "<python3> <script>", "timeout": <N> }] }` objects. Tool-specific events include a `"matcher": "*"` field.
5. `PermissionRequest` events get a timeout of `86400` seconds (24 hours) to allow ample time for user interaction.

### Codex CLI hooks

`HookInstaller.installCodexIfNeeded()` performs:

1. **Ensures the hook script exists** (same script as Claude, shared at `~/.claude/hooks/notch-pomodoro-hook.py`).
2. **Creates `~/.codex/` directory** if needed.
3. **Registers in hooks.json**: Reads or creates `~/.codex/hooks.json`, strips existing entries, then registers the hook for **10 events**:
   - `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `SessionStart`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`
4. Uses a regex matcher (`"matcher": ".*"`) for tool-specific events (Codex uses regex, not glob).
5. `PermissionRequest` events get a timeout of `86400` seconds; all others get `30` seconds.

---

## Verifying Hook Installation

After launching the app at least once, verify that hooks were installed correctly:

### Check Claude Code hooks

```bash
# Verify the hook script exists and is executable
ls -la ~/.claude/hooks/notch-pomodoro-hook.py

# Verify settings.json contains notch-pomodoro hook entries
cat ~/.claude/settings.json | python3 -m json.tool | grep -A5 "notch-pomodoro-hook"
```

You should see entries like:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 /Users/<user>/.claude/hooks/notch-pomodoro-hook.py"
          }
        ]
      }
    ],
    ...
  }
}
```

### Check Codex CLI hooks

```bash
# Verify hooks.json exists
ls -la ~/.codex/hooks.json

# Verify it contains notch-pomodoro hook entries
cat ~/.codex/hooks.json | python3 -m json.tool | grep -A5 "notch-pomodoro-hook"
```

### Check the socket server

```bash
# Verify the Unix domain socket exists
ls -la /tmp/notch-pomodoro-claude.sock
```

The socket file should exist with permissions `srw-------` (owner read/write only, `0o600`).

### End-to-end test

1. Launch the app: `open .build/release/NotchPomodoro.app`
2. Run a Claude Code session in a terminal: `claude`
3. Send a prompt. The notch should expand to show a "processing" indicator.
4. If Claude requests a tool permission, the notch should expand an approval card with "Allow" / "Deny" buttons.

---

## Testing

**No tests are currently defined.** The `Package.swift` declares no test targets. There is no `Tests/` directory.

To add tests in the future, you would:
1. Add a `.testTarget` to `Package.swift`.
2. Create a `Tests/NotchPomodoroTests/` directory.
3. Restructure the code if needed (executable targets' types aren't importable by test targets unless split into a library target).

For now, testing is manual: build the app, launch it, interact with the notch UI, and run Claude Code sessions to verify hook integration.

---

## Troubleshooting

### App doesn't appear in the notch

- Ensure you're on a Mac with a notch (MacBook Pro 14"+/16"+, or MacBook Air M2+).
- Check that the built-in display is selected (or the correct display name in settings).
- Verify the app is running: `pgrep -fl NotchPomodoro`.

### Notifications don't fire

- This happens when running via `swift run` (not in a `.app` bundle). Build the app bundle with `./build.sh` and `open .build/release/NotchPomodoro.app`.
- Check **System Settings → Notifications → NotchPomodoro** — ensure notifications are allowed.

### Hook events not received

- Verify the socket exists: `ls -la /tmp/notch-pomodoro-claude.sock`.
- Verify hooks are installed: `cat ~/.claude/settings.json | grep notch-pomodoro`.
- Check the hook script is executable: `ls -la ~/.claude/hooks/notch-pomodoro-hook.py` (should show `rwxr-xr-x`).
- Verify Python 3 is available: `python3 --version`.
- Restart the app to re-create the socket server.

### Permission approval doesn't work

- The `PermissionRequest` event has a 300-second timeout on the Python side. If you don't respond within 5 minutes, the hook exits and Claude Code proceeds with its default behavior.
- Ensure only one instance of the app is running (multiple instances would conflict on the socket path).
