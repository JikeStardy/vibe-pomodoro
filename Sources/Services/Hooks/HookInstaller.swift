import Foundation

/// Installs and manages the NotchPomodoro hook script for Claude Code.
enum HookInstaller {
    // MARK: - Claude Code Version Detection
    enum ClaudeCodeVersion: String {
        case v1 = "1.x"
        case v2 = "2.x"
    }

    // MARK: - Paths
    struct ClaudePaths {
        static let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        static let hooksDir = claudeDir.appendingPathComponent("hooks")
        static let settingsFile = claudeDir.appendingPathComponent("settings.json")
        static let hookScript = hooksDir.appendingPathComponent("notch-pomodoro-hook.py")
    }

    struct CodexPaths {
        static let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        static let hooksFile = codexDir.appendingPathComponent("hooks.json")
        static let hookScript = ClaudePaths.hookScript  // Reuse same script
    }

    // MARK: - Supported Hook Events
    private static let supportedEvents: [String] = [
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Notification",
        "Stop",
        "StopFailure",
        "SessionStart",
        "SessionEnd",
        "PreCompact",
        "PostCompact",
        "SubagentStart",
        "SubagentStop"
    ]

    // MARK: - Codex Supported Events
    private static let codexSupportedEvents: [String] = [
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop",
        "SessionStart",
        "SubagentStart",
        "SubagentStop",
        "PreCompact",
        "PostCompact"
    ]

    private static let codexEventsWithMatcher: Set<String> = [
        "PreToolUse", "PostToolUse", "PermissionRequest",
        "SubagentStart", "SubagentStop", "PreCompact", "PostCompact"
    ]

    private static let hookIdentifier = "notch-pomodoro-hook.py"

    // MARK: - Public API

    /// Install hook if not already installed. Called on app launch.
    /// Always attempts installation regardless of Claude Code detection —
    /// the hook and settings can be pre-installed for when Claude Code runs.
    static func installIfNeeded() {
        do {
            try installHookScript()
            try registerInSettings()
            print("[HookInstaller] Hook installed successfully at \(ClaudePaths.hookScript.path)")
        } catch {
            print("[HookInstaller] Installation failed: \(error.localizedDescription)")
        }
    }

    /// Check if the hook is currently installed
    static func isInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: ClaudePaths.hookScript.path) else { return false }
        guard fm.fileExists(atPath: ClaudePaths.settingsFile.path) else { return false }

        // Check settings contain our hook
        guard let data = try? Data(contentsOf: ClaudePaths.settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check at least one event has our hook registered
        for event in supportedEvents {
            if let entries = hooks[event] as? [[String: Any]] {
                for entry in entries {
                    // Check nested format (correct)
                    if let hooksList = entry["hooks"] as? [[String: Any]] {
                        for hook in hooksList {
                            if let cmd = hook["command"] as? String, cmd.contains(hookIdentifier) {
                                return true
                            }
                        }
                    }
                    // Check flat format (legacy)
                    if let cmd = entry["command"] as? String, cmd.contains(hookIdentifier) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Remove all NotchPomodoro hooks
    static func uninstall() {
        let fm = FileManager.default

        // Remove hook script
        try? fm.removeItem(at: ClaudePaths.hookScript)

        // Remove from settings
        guard fm.fileExists(atPath: ClaudePaths.settingsFile.path),
              let data = try? Data(contentsOf: ClaudePaths.settingsFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { entry -> [String: Any]? in
                    // Handle nested format
                    if var hooksList = entry["hooks"] as? [[String: Any]] {
                        hooksList.removeAll { (($0["command"] as? String)?.contains(hookIdentifier)) == true }
                        if hooksList.isEmpty { return nil }
                        var updated = entry
                        updated["hooks"] = hooksList
                        return updated
                    }
                    // Handle flat format (legacy)
                    if let cmd = entry["command"] as? String, cmd.contains(hookIdentifier) { return nil }
                    return entry
                }
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        json["hooks"] = hooks.isEmpty ? nil : hooks
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: ClaudePaths.settingsFile)
        }
        print("[HookInstaller] Uninstalled")
    }

    // MARK: - Codex CLI Public API

    /// Install Codex hooks if ~/.codex directory exists
    static func installCodexIfNeeded() {
        do {
            // Ensure the hook script exists first (shared with Claude)
            try installHookScript()
            try registerCodexHooks()
            print("[HookInstaller] Codex hooks installed successfully")
        } catch {
            print("[HookInstaller] Codex installation failed: \(error.localizedDescription)")
        }
    }

    /// Check if Codex hooks are installed
    static func isCodexInstalled() -> Bool {
        let fm = FileManager.default
        // Script must exist
        guard fm.fileExists(atPath: ClaudePaths.hookScript.path) else { return false }
        // hooks.json must exist
        guard fm.fileExists(atPath: CodexPaths.hooksFile.path) else { return false }

        guard let data = try? Data(contentsOf: CodexPaths.hooksFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check for our hook in any event
        for event in codexSupportedEvents {
            if let entries = hooks[event] as? [[String: Any]] {
                for entry in entries {
                    if let hooksList = entry["hooks"] as? [[String: Any]] {
                        for hook in hooksList {
                            if let cmd = hook["command"] as? String, cmd.contains(hookIdentifier) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        return false
    }

    /// Uninstall Codex hooks
    static func uninstallCodex() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: CodexPaths.hooksFile.path),
              let data = try? Data(contentsOf: CodexPaths.hooksFile),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { entry -> [String: Any]? in
                    if var hooksList = entry["hooks"] as? [[String: Any]] {
                        hooksList.removeAll { ($0["command"] as? String)?.contains(hookIdentifier) == true }
                        if hooksList.isEmpty { return nil }
                        var updated = entry
                        updated["hooks"] = hooksList
                        return updated
                    }
                    return entry
                }
                if entries.isEmpty { hooks.removeValue(forKey: event) }
                else { hooks[event] = entries }
            }
        }

        json["hooks"] = hooks.isEmpty ? nil : hooks
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: CodexPaths.hooksFile)
        }
    }

    /// Detect if vibe-notch is installed (to avoid conflicts)
    static func isVibeNotchInstalled() -> Bool {
        guard let data = try? Data(contentsOf: ClaudePaths.settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    // Check nested format
                    if let hooksList = entry["hooks"] as? [[String: Any]] {
                        for hook in hooksList {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("claude-island-state.py") {
                                return true
                            }
                        }
                    }
                    // Check flat format (legacy)
                    if let command = entry["command"] as? String,
                       command.contains("claude-island-state.py") {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Detect Claude Code installation and version
    static func detectClaudeCodeVersion() -> ClaudeCodeVersion? {
        let fm = FileManager.default
        // Check if ~/.claude directory exists (indicates Claude Code is installed)
        guard fm.fileExists(atPath: ClaudePaths.claudeDir.path) else { return nil }

        // Check for claude CLI
        let result = detectCLI("claude")
        if result {
            // If hooks directory concept exists, it's v2+
            if fm.fileExists(atPath: ClaudePaths.hooksDir.path) ||
               fm.fileExists(atPath: ClaudePaths.settingsFile.path) {
                return .v2
            }
            return .v1
        }
        // If ~/.claude exists but no CLI, may still be v2 with hooks support
        return .v2
    }

    // MARK: - Private Implementation

    private static func registerCodexHooks() throws {
        let fm = FileManager.default

        var json: [String: Any]
        if fm.fileExists(atPath: CodexPaths.hooksFile.path),
           let data = try? Data(contentsOf: CodexPaths.hooksFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        } else {
            try fm.createDirectory(at: CodexPaths.codexDir, withIntermediateDirectories: true)
            json = [:]
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Strip existing notch-pomodoro entries
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { entry -> [String: Any]? in
                    if var hooksList = entry["hooks"] as? [[String: Any]] {
                        hooksList.removeAll { ($0["command"] as? String)?.contains(hookIdentifier) == true }
                        if hooksList.isEmpty { return nil }
                        var updated = entry
                        updated["hooks"] = hooksList
                        return updated
                    }
                    return entry
                }
                hooks[event] = entries.isEmpty ? nil : entries
            }
        }

        // Build hook command (same script as Claude, with codex source attribution)
        let pythonPath = detectPython()
        let command = "\(pythonPath) \(CodexPaths.hookScript.path) --source codex"

        // Register for each Codex event
        for event in codexSupportedEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []

            var hookCommand: [String: Any] = ["type": "command", "command": command]
            if event == "PermissionRequest" {
                hookCommand["timeout"] = 86400
            } else {
                hookCommand["timeout"] = 30
            }

            var hookGroup: [String: Any] = ["hooks": [hookCommand]]
            if codexEventsWithMatcher.contains(event) {
                hookGroup["matcher"] = ".*"  // Codex uses regex, not glob
            }

            entries.append(hookGroup)
            hooks[event] = entries
        }

        json["hooks"] = hooks
        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: CodexPaths.hooksFile, options: .atomic)
    }

    private static func installHookScript() throws {
        let fm = FileManager.default

        // Ensure hooks directory exists
        try fm.createDirectory(at: ClaudePaths.hooksDir, withIntermediateDirectories: true)

        // Get Python path
        let pythonPath = detectPython()

        // Write hook script from embedded content
        let scriptContent = hookScriptContent(pythonPath: pythonPath)
        try scriptContent.write(to: ClaudePaths.hookScript, atomically: true, encoding: .utf8)

        // Make executable
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ClaudePaths.hookScript.path)
    }

    private static func registerInSettings() throws {
        let fm = FileManager.default

        // Read or create settings
        var json: [String: Any]
        if fm.fileExists(atPath: ClaudePaths.settingsFile.path),
           let data = try? Data(contentsOf: ClaudePaths.settingsFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        } else {
            // Ensure .claude directory exists
            try fm.createDirectory(at: ClaudePaths.claudeDir, withIntermediateDirectories: true)
            json = [:]
        }

        // Get or create hooks section
        var hooks = json["hooks"] as? [String: Any] ?? [:]

        // Strip existing notch-pomodoro entries from all events (handles both formats)
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries = entries.compactMap { entry -> [String: Any]? in
                    // Check in nested hooks array
                    if var hooksList = entry["hooks"] as? [[String: Any]] {
                        hooksList.removeAll { hook in
                            (hook["command"] as? String)?.contains(hookIdentifier) == true
                        }
                        if hooksList.isEmpty { return nil }
                        var updated = entry
                        updated["hooks"] = hooksList
                        return updated
                    }
                    // Check flat format (legacy cleanup)
                    if let cmd = entry["command"] as? String, cmd.contains(hookIdentifier) {
                        return nil
                    }
                    return entry
                }
                hooks[event] = entries.isEmpty ? nil : entries
            }
        }

        // Build hook command
        let pythonPath = detectPython()
        let command = "\(pythonPath) \(ClaudePaths.hookScript.path)"

        // Events that use matcher (tool-specific events)
        let eventsWithMatcher: Set<String> = [
            "PreToolUse", "PostToolUse", "PermissionRequest", "Notification",
            "StopFailure", "PreCompact", "PostCompact", "SubagentStart", "SubagentStop"
        ]

        // Register for each event in correct nested format
        for event in supportedEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []

            var hookCommand: [String: Any] = ["type": "command", "command": command]
            if event == "PermissionRequest" {
                hookCommand["timeout"] = 86400
            }

            var hookGroup: [String: Any] = ["hooks": [hookCommand]]
            if eventsWithMatcher.contains(event) {
                hookGroup["matcher"] = "*"
            }

            entries.append(hookGroup)
            hooks[event] = entries
        }

        json["hooks"] = hooks

        // Write back
        let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try updatedData.write(to: ClaudePaths.settingsFile, options: .atomic)
    }

    /// Detect python3 path
    private static func detectPython() -> String {
        let candidates = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ]
        let fm = FileManager.default
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return "python3"
    }

    /// Check if a CLI tool is available
    private static func detectCLI(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Embedded Hook Script

    private static func hookScriptContent(pythonPath: String) -> String {
        return """
        #!\(pythonPath)
        \"\"\"NotchPomodoro Hook - Sends session state via Unix socket\"\"\"
        import argparse
        import json
        import os
        import socket
        import sys

        SOCKET_PATH = "/tmp/notch-pomodoro-claude.sock"
        TIMEOUT_SECONDS = 300

        def send_event(state):
            \"\"\"Send event to app, return response if any\"\"\"
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

        def main():
            parser = argparse.ArgumentParser()
            parser.add_argument("--source", default="claude", choices=["claude", "codex"])
            args = parser.parse_args()

            try:
                data = json.load(sys.stdin)
            except json.JSONDecodeError:
                sys.exit(1)

            session_id = data.get("session_id", "unknown")
            event = data.get("hook_event_name", "")
            cwd = data.get("cwd", "")
            tool_input = data.get("tool_input", {})
            claude_pid = os.getppid()

            state = {
                "session_id": session_id,
                "cwd": cwd,
                "event": event,
                "pid": claude_pid,
                "source": args.source,
            }

            if event == "UserPromptSubmit":
                state["status"] = "processing"
            elif event == "PreToolUse":
                tool_name = data.get("tool_name")
                if tool_name == "AskUserQuestion":
                    state["status"] = "waiting_for_response"
                    state["tool"] = tool_name
                    # Extract first question for display
                    questions = tool_input.get("questions", [])
                    if questions:
                        state["message"] = questions[0].get("question", "")
                else:
                    state["status"] = "running_tool"
                    state["tool"] = tool_name
                    state["tool_input"] = tool_input
                    tool_use_id = data.get("tool_use_id")
                    if tool_use_id:
                        state["tool_use_id"] = tool_use_id
            elif event == "PostToolUse":
                state["status"] = "processing"
                state["tool"] = data.get("tool_name")
                tool_use_id = data.get("tool_use_id")
                if tool_use_id:
                    state["tool_use_id"] = tool_use_id
            elif event == "PermissionRequest":
                state["status"] = "waiting_for_approval"
                state["tool"] = data.get("tool_name")
                state["tool_input"] = tool_input
                response = send_event(state)
                if response:
                    decision = response.get("decision", "ask")
                    reason = response.get("reason", "")
                    if decision == "allow":
                        output = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
                        print(json.dumps(output))
                        sys.exit(0)
                    elif decision == "deny":
                        output = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": reason or "Denied via NotchPomodoro"}}}
                        print(json.dumps(output))
                        sys.exit(0)
                sys.exit(0)
            elif event == "Notification":
                notification_type = data.get("notification_type")
                if notification_type == "permission_prompt":
                    sys.exit(0)
                elif notification_type == "idle_prompt":
                    state["status"] = "waiting_for_input"
                else:
                    state["status"] = "notification"
                    state["notification_type"] = notification_type
                    state["message"] = data.get("message")
            elif event == "Stop":
                state["status"] = "waiting_for_input"
            elif event == "StopFailure":
                state["status"] = "waiting_for_input"
                state["message"] = data.get("error") or data.get("message")
            elif event == "SubagentStart" or event == "SubagentStop":
                state["status"] = "processing"
            elif event == "SessionStart":
                state["status"] = "waiting_for_input"
            elif event == "SessionEnd":
                state["status"] = "ended"
            elif event == "PreCompact":
                state["status"] = "compacting"
            elif event == "PostCompact":
                state["status"] = "processing"
            else:
                state["status"] = "unknown"

            send_event(state)

        if __name__ == "__main__":
            main()
        """
    }
}
