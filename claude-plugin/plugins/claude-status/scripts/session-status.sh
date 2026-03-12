#!/bin/bash
# Claude Status — Session status hook
#
# Writes a per-session status file to the Claude project directory
# so the Claude Status macOS menu bar app can read session state.
#
# No external dependencies — uses only bash builtins and standard macOS tools.
#
# Status file: ~/.claude/projects/<encoded-path>/<session_id>.cstatus
# Format:     {"session_id":"...","pid":N,"ppid":N,"state":"...","activity":"...","timestamp":"...","cwd":"...","event":"..."}
#
# States:
#   active     — Claude is processing a prompt or executing tools
#   waiting    — Claude is blocked waiting for user action (e.g. permission prompt)
#   idle       — Session just started or has no pending work
#   compacting — Session is compacting context

set -eo pipefail

# shellcheck source=lib/json-utils.sh
source "${BASH_SOURCE%/*}/lib/json-utils.sh"

# Read JSON input from stdin
INPUT=$(cat)

EVENT=$(extract_json_string "hook_event_name" "$INPUT")
SESSION_ID=$(extract_json_string "session_id" "$INPUT")
TRANSCRIPT=$(extract_json_string "transcript_path" "$INPUT")
CWD=$(extract_json_string "cwd" "$INPUT")

# CLAUDE_PID can be overridden for testing; defaults to PPID (the Claude process)
CLAUDE_PID="${CLAUDE_PID:-$PPID}"

# Get the parent of the Claude process (the shell/IDE that launched it)
CLAUDE_PPID=$(ps -o ppid= -p "$CLAUDE_PID" 2>/dev/null | tr -d ' ') || true
CLAUDE_PPID=${CLAUDE_PPID:-0}

# Derive the project directory from the transcript path
PROJECT_DIR=$(dirname "$TRANSCRIPT")

# Bail out if we can't determine the project directory
if [[ -z "$PROJECT_DIR" || "$PROJECT_DIR" == "." ]]; then
    exit 0
fi

STATUS_FILE="${PROJECT_DIR}/${SESSION_ID}.cstatus"

# On SessionEnd, remove the status file, notify, and exit
if [[ "$EVENT" == "SessionEnd" ]]; then
    rm -f "$STATUS_FILE"
    /usr/bin/notifyutil -p com.poisonpenllc.Claude-Status.session-changed 2>/dev/null || true
    exit 0
fi

# Extract tool_name for tool-related events
TOOL_NAME=$(extract_json_string "tool_name" "$INPUT")

# Read the previous state and session name from the existing .cstatus file (if any).
# During compaction, tool-use hooks fire but should not override the
# "compacting" state — only definitive end events (Stop, UserPromptSubmit,
# SessionStart, SessionEnd) clear it.
PREV_STATE=""
SESSION_NAME=""
if [[ -f "$STATUS_FILE" ]]; then
    PREV_CSTATUS=$(cat "$STATUS_FILE")
    PREV_STATE=$(extract_json_string "state" "$PREV_CSTATUS")
    SESSION_NAME=$(extract_json_string "session_name" "$PREV_CSTATUS")
fi

# Map hook event to session state and activity
ACTIVITY=""
case "$EVENT" in
    SessionStart)
        STATUS="idle"
        ;;
    UserPromptSubmit)
        STATUS="active"
        ACTIVITY="thinking"
        ;;
    PreToolUse)
        STATUS="active"
        ACTIVITY="$TOOL_NAME"
        ;;
    PostToolUse)
        STATUS="active"
        ;;
    PostToolUseFailure)
        STATUS="active"
        ;;
    PermissionRequest)
        STATUS="waiting"
        ACTIVITY="$TOOL_NAME"
        ;;
    PreCompact)
        STATUS="compacting"
        COMPACT_TRIGGER=$(extract_json_string "trigger" "$INPUT")
        ACTIVITY="${COMPACT_TRIGGER:-auto}"
        ;;
    SubagentStart)
        STATUS="active"
        AGENT_TYPE=$(extract_json_string "agent_type" "$INPUT")
        ACTIVITY="${AGENT_TYPE:-subagent}"
        ;;
    SubagentStop)
        STATUS="active"
        ;;
    Stop)
        STATUS="idle"
        ;;
    Notification)
        NTYPE=$(extract_json_string "notification_type" "$INPUT")
        case "$NTYPE" in
            permission_prompt|elicitation_dialog)
                STATUS="waiting"
                ;;
            idle_prompt)
                STATUS="idle"
                ;;
            *)
                STATUS="idle"
                ;;
        esac
        ;;
    ConfigChange)
        # Don't update status on config changes
        exit 0
        ;;
    *)
        STATUS="active"
        ;;
esac

# Sticky compacting: tool-use events during compaction should not override
# the "compacting" state. Only definitive end events clear it:
# UserPromptSubmit, SessionStart, Stop, SessionEnd, PermissionRequest.
STICKY_EVENTS="PreToolUse PostToolUse PostToolUseFailure SubagentStart SubagentStop"
if [[ "$PREV_STATE" == "compacting" && " $STICKY_EVENTS " == *" $EVENT "* ]]; then
    STATUS="compacting"
    ACTIVITY="${ACTIVITY:+compacting ($ACTIVITY)}"
    [[ -z "$ACTIVITY" ]] && ACTIVITY="compacting"
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escape values that may contain special characters for JSON safety
SAFE_SESSION_ID=$(json_escape "$SESSION_ID")
SAFE_ACTIVITY=$(json_escape "$ACTIVITY")
SAFE_CWD=$(json_escape "$CWD")
SAFE_EVENT=$(json_escape "$EVENT")
# Build optional session_name JSON fragment
SESSION_NAME_JSON=""
if [[ -n "$SESSION_NAME" ]]; then
    SESSION_NAME_JSON=",\"session_name\":\"$(json_escape "$SESSION_NAME")\""
fi

# Write atomically: temp file then move (prevents partial reads)
TMP_FILE="${STATUS_FILE}.tmp.$$"
trap 'rm -f "$TMP_FILE"' EXIT

cat > "$TMP_FILE" << EOF
{"session_id":"${SAFE_SESSION_ID}","pid":${CLAUDE_PID:-0},"ppid":${CLAUDE_PPID:-0},"state":"${STATUS}","activity":"${SAFE_ACTIVITY}","timestamp":"${TIMESTAMP}","cwd":"${SAFE_CWD}","event":"${SAFE_EVENT}"${SESSION_NAME_JSON}}
EOF

mv -f "$TMP_FILE" "$STATUS_FILE"

# Notify the Claude Status app to refresh immediately (Darwin notification)
/usr/bin/notifyutil -p com.poisonpenllc.Claude-Status.session-changed 2>/dev/null || true

exit 0
