#!/usr/bin/env python3
"""Claude Status — Set session name.

Updates the session's .cstatus file to include a session_name field.
The hook script (session-status.py) carries this name forward on
subsequent updates by reading it from the previous .cstatus content.

Usage: set-session-name.py "<session name>"
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile


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


def find_cstatus_for_pid(projects_dir: pathlib.Path, pid: int):
    """Find a .cstatus file that references the given PID."""
    for cstatus_file in projects_dir.glob("*/*.cstatus"):
        try:
            data = json.loads(cstatus_file.read_text())
            if data.get("pid") == pid:
                return cstatus_file
        except (json.JSONDecodeError, OSError):
            continue
    return None


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
    if len(sys.argv) < 2 or not sys.argv[1]:
        print("Usage: set-session-name.py <session-name>", file=sys.stderr)
        sys.exit(1)

    session_name = sys.argv[1]
    projects_dir = pathlib.Path.home() / ".claude" / "projects"

    # Walk the ancestor PID chain to find the .cstatus file
    current_pid = int(os.environ.get("CLAUDE_PID", os.getppid()))
    cstatus_file = None
    for _ in range(8):
        if current_pid <= 1:
            break
        cstatus_file = find_cstatus_for_pid(projects_dir, current_pid)
        if cstatus_file:
            break
        current_pid = get_ppid(current_pid)
        if current_pid <= 0:
            break

    if not cstatus_file:
        print("Error: Could not find .cstatus file for any ancestor PID",
              file=sys.stderr)
        sys.exit(1)

    # Read current .cstatus and update the session_name field
    try:
        data = json.loads(cstatus_file.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        print(f"Error: Could not read {cstatus_file}: {exc}", file=sys.stderr)
        sys.exit(1)

    data["session_name"] = session_name
    write_atomic(cstatus_file, json.dumps(data, separators=(",", ":")) + "\n")

    print(f"Session name set to: {session_name}")

    # Notify the Claude Status app to refresh
    try:
        subprocess.run(
            ["/usr/bin/notifyutil", "-p",
             "com.poisonpenllc.Claude-Status.session-changed"],
            capture_output=True, timeout=2,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


if __name__ == "__main__":
    main()
