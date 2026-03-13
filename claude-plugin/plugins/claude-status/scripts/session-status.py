#!/usr/bin/env python3
"""Claude Status — Session status hook.

Writes a per-session status file to the Claude project directory
so the Claude Status macOS menu bar app can read session state.

Status file: ~/.claude/projects/<encoded-path>/<session_id>.cstatus
States: active, waiting, idle, compacting
"""
import datetime
import json
import os
import pathlib
import subprocess
import sys
import tempfile


def ends_with_question(transcript_path: str) -> bool:
    """Check if the last assistant message ends with a question mark."""
    path = pathlib.Path(transcript_path)
    if not path.is_file():
        return False
    try:
        # Read last 200 lines — JSONL lines can be very large in long conversations
        lines = subprocess.run(
            ["tail", "-200", str(path)],
            capture_output=True, text=True, timeout=3,
        ).stdout.splitlines()
    except (subprocess.TimeoutExpired, OSError):
        return False
    # Find the last end_turn assistant message
    last_text = ""
    for line in lines:
        try:
            entry = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        msg = entry.get("message", {})
        if msg.get("stop_reason") != "end_turn":
            continue
        for block in msg.get("content", []):
            if block.get("type") == "text" and block.get("text"):
                last_text = block["text"]
    return last_text.rstrip().endswith("?")


def notify():
    """Post a Darwin notification to refresh the Claude Status app."""
    try:
        subprocess.run(
            ["/usr/bin/notifyutil", "-p",
             "com.poisonpenllc.Claude-Status.session-changed"],
            capture_output=True, timeout=2,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def get_ppid(pid: int) -> int:
    """Get the parent PID of a process."""
    try:
        result = subprocess.run(
            ["ps", "-o", "ppid=", "-p", str(pid)],
            capture_output=True, text=True, timeout=2,
        )
        return int(result.stdout.strip())
    except (subprocess.TimeoutExpired, OSError, ValueError):
        return 0


def write_atomic(path: pathlib.Path, data: str):
    """Write data to a file atomically via tmp + rename."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".tmp.")
    try:
        os.write(fd, data.encode())
        os.close(fd)
        os.rename(tmp, path)
    except Exception:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main():
    hook_input = json.load(sys.stdin)

    event = hook_input.get("hook_event_name", "")
    session_id = hook_input.get("session_id", "")
    transcript = hook_input.get("transcript_path", "")
    cwd = hook_input.get("cwd", "")

    claude_pid = int(os.environ.get("CLAUDE_PID", os.getppid()))
    claude_ppid = get_ppid(claude_pid)

    project_dir = pathlib.Path(transcript).parent if transcript else None
    if not project_dir or str(project_dir) == ".":
        return

    status_file = project_dir / f"{session_id}.cstatus"

    # SessionEnd: remove status file and notify
    if event == "SessionEnd":
        status_file.unlink(missing_ok=True)
        notify()
        return

    tool_name = hook_input.get("tool_name", "")

    # Read previous state and session name
    prev_state = ""
    session_name = ""
    if status_file.is_file():
        try:
            prev = json.loads(status_file.read_text())
            prev_state = prev.get("state", "")
            session_name = prev.get("session_name", "")
        except (json.JSONDecodeError, OSError):
            pass

    # Map event to state and activity
    activity = ""
    if event == "SessionStart":
        state = "idle"
    elif event == "UserPromptSubmit":
        state = "active"
        activity = "thinking"
    elif event == "PreToolUse":
        state = "active"
        activity = tool_name
    elif event in ("PostToolUse", "PostToolUseFailure"):
        state = "active"
    elif event == "PermissionRequest":
        state = "waiting"
        activity = tool_name
    elif event == "PreCompact":
        state = "compacting"
        activity = hook_input.get("trigger", "auto")
    elif event == "SubagentStart":
        state = "active"
        activity = hook_input.get("agent_type", "subagent")
    elif event == "SubagentStop":
        state = "active"
    elif event == "Stop":
        if ends_with_question(transcript):
            state = "waiting"
            activity = "question"
        else:
            state = "idle"
    elif event == "Notification":
        ntype = hook_input.get("notification_type", "")
        if ntype in ("permission_prompt", "elicitation_dialog"):
            state = "waiting"
        elif ntype == "idle_prompt":
            if ends_with_question(transcript):
                state = "waiting"
                activity = "question"
            else:
                state = "idle"
        else:
            state = "idle"
    elif event == "ConfigChange":
        return
    else:
        state = "active"

    # Sticky compacting: tool-use events during compaction keep compacting state
    sticky_events = {
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "SubagentStart", "SubagentStop",
    }
    if prev_state == "compacting" and event in sticky_events:
        state = "compacting"
        activity = f"compacting ({activity})" if activity else "compacting"

    now = datetime.datetime.now(datetime.timezone.utc)
    timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")

    record = {
        "session_id": session_id,
        "pid": claude_pid,
        "ppid": claude_ppid,
        "state": state,
        "activity": activity,
        "timestamp": timestamp,
        "cwd": cwd,
        "event": event,
    }
    if session_name:
        record["session_name"] = session_name

    write_atomic(status_file, json.dumps(record, separators=(",", ":")) + "\n")
    notify()


if __name__ == "__main__":
    main()
