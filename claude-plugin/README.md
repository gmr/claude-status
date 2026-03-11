# Claude Status Plugin

A Claude Code plugin that reports session status for the
[Claude Status](https://github.com/gmr/claude-status) macOS menu bar app.

## What it does

This plugin hooks into Claude Code session lifecycle events and writes a small
JSON status file per session to `~/.claude/projects/<project>/.session-status.<session_id>`.
The Claude Status macOS app reads these files to show real-time session state
in your menu bar — no JSONL parsing heuristics needed.

Multiple sessions in the same project each get their own status file.

## Status states

| State | Meaning |
|---|---|
| `active` | Claude is processing a prompt or executing tools |
| `waiting` | Claude is blocked waiting for user action (e.g. permission prompt) |
| `idle` | Session just started or has no pending work |

## Hook events

| Event | Writes state |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `active` |
| `PreToolUse` | `active` |
| `Stop` | `idle` |
| `Notification` | `waiting` (permission/elicitation) or `idle` |
| `SessionEnd` | *(deletes status file)* |

## Status file format

`~/.claude/projects/<encoded-path>/.session-status.<session_id>`:

```json
{
  "session_id": "abc123",
  "pid": 12345,
  "state": "active",
  "timestamp": "2026-03-10T20:00:00Z",
  "cwd": "/path/to/project",
  "event": "PreToolUse"
}
```

The `pid` field is the Claude process PID, allowing the macOS app to
cross-reference with its process scanner.

## Requirements

- macOS (uses only bash builtins, `sed`, `date`, and `mv` — no extra dependencies)
- Claude Code with plugin support

## Installation

Install via the Claude Code CLI:

```
/plugin install claude-status
```

Or add to your marketplace configuration if hosting privately.

## License

BSD-3-Clause
