#!/usr/bin/env python3
"""VibePomodoro Hook - Sends session state via Unix socket"""
import argparse
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/vibe-pomodoro-claude.sock"
TIMEOUT_SECONDS = 300

def send_event(state):
    """Send event to app, return response if any"""
    sock = None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())
        if state.get("status") in ("waiting_for_approval", "asking_question"):
            response = sock.recv(4096)
            if response:
                return json.loads(response.decode())
        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None
    finally:
        if sock is not None:
            sock.close()

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
    permission_suggestions = data.get("permission_suggestions", None)
    claude_pid = os.getppid()

    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "source": args.source,
    }

    if event == "PreToolUse" and data.get("tool_name") == "AskUserQuestion":
        # AskUserQuestion: blocking flow — send to app, wait for answer
        tool_use_id = data.get("tool_use_id", "")
        state["status"] = "asking_question"
        state["tool"] = "AskUserQuestion"
        state["tool_input"] = tool_input
        state["tool_use_id"] = tool_use_id
        response = send_event(state)
        if response and "answers" in response:
            output = {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "allow",
                    "updatedInput": {
                        **tool_input,
                        "answers": response["answers"]
                    }
                }
            }
            print(json.dumps(output))
            sys.exit(0)
        # No response — let default behavior proceed
        print("{}")
        sys.exit(0)
    elif event == "UserPromptSubmit":
        state["status"] = "processing"
    elif event == "PreToolUse":
        tool_name = data.get("tool_name")
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
        if permission_suggestions is not None:
            state["permission_suggestions"] = permission_suggestions
        response = send_event(state)
        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")
            updated_permissions = response.get("updatedPermissions", None)
            if decision == "allow":
                output = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}
                if updated_permissions:
                    output["hookSpecificOutput"]["decision"]["updatedPermissions"] = updated_permissions
                print(json.dumps(output))
                sys.exit(0)
            elif decision == "deny":
                output = {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": reason or "Denied via vibe-pomodoro"}}}
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
