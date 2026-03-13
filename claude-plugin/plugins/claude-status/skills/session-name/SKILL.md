---
name: session-name
description: >-
  Set a custom name for the current Claude Code session that appears in the
  Claude Status menu bar app. Use when the user says "/name-session",
  "name this session", "set session name", or "rename session".
allowed-tools: Bash(bash:*)
---

# Set Session Name

Sets a custom display name for the current Claude Code session in the Claude Status macOS menu bar app.

## Usage

```text
/name-session <name>
```

## Steps

1. Extract the desired session name from the user's arguments. If no name was provided, ask the user what they'd like to name this session.

2. Run the set-session-name.py script from the plugin:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/set-session-name.py" "<session-name>"
```

The script updates the session's `.cstatus` file with a `session_name` field. The hook script carries this name forward on subsequent status updates.

3. Confirm to the user that the session name was set.

## Examples

- `/name-session API Refactor` — names the session "API Refactor"
- `/name-session Bug Hunt` — names the session "Bug Hunt"
