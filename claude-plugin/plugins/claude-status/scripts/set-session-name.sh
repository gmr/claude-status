#!/bin/bash
# Claude Status — Set session name
#
# Updates the session's .cstatus file to include a session_name field.
# The hook script (session-status.sh) carries this name forward on
# subsequent updates by reading it from the previous .cstatus content.
#
# Usage: set-session-name.sh "<session name>"

set -eo pipefail

# shellcheck source=lib/json-utils.sh
source "${BASH_SOURCE%/*}/lib/json-utils.sh"

SESSION_NAME="$1"

if [[ -z "$SESSION_NAME" ]]; then
    echo "Usage: set-session-name.sh <session-name>" >&2
    exit 1
fi

# Find the .cstatus file by walking the ancestor PID chain.
# The script runs as: Claude -> bash -> this script, so we check
# each ancestor PID against .cstatus files to find the Claude process.
PROJECTS_DIR="${HOME}/.claude/projects"

find_cstatus_for_pid() {
    local pid="$1"
    for cstatus_file in "${PROJECTS_DIR}"/*/*.cstatus; do
        [[ -f "$cstatus_file" ]] || continue
        if grep -Eq "\"pid\":[[:space:]]*${pid}([[:space:]]*[,}])" "$cstatus_file" 2>/dev/null; then
            echo "$cstatus_file"
            return 0
        fi
    done
    return 1
}

CSTATUS_FILE=""
CURRENT_PID="${CLAUDE_PID:-$PPID}"
for _ in $(seq 1 8); do
    [[ "$CURRENT_PID" -gt 1 ]] || break
    CSTATUS_FILE=$(find_cstatus_for_pid "$CURRENT_PID") && break
    CURRENT_PID=$(ps -o ppid= -p "$CURRENT_PID" 2>/dev/null | tr -d ' ') || break
done

if [[ -z "$CSTATUS_FILE" ]]; then
    echo "Error: Could not find .cstatus file for any ancestor PID" >&2
    exit 1
fi

# Lock the .cstatus file to prevent concurrent writes from session-status.sh.
LOCK_FILE="${CSTATUS_FILE}.lock"
exec 9>"$LOCK_FILE"
flock -x 9

# Read the current .cstatus content and inject/replace the session_name field.
CURRENT=$(cat "$CSTATUS_FILE")
SAFE_NAME=$(json_escape "$SESSION_NAME")

# Use awk to safely remove any existing session_name field (handling escaped
# quotes in its value) and append the new one before the closing brace.
# Pass SAFE_NAME via ENVIRON to avoid awk -v interpreting backslash escapes.
export SAFE_NAME
UPDATED=$(printf '%s' "$CURRENT" | awk '
{
    name = ENVIRON["SAFE_NAME"]
    key = "\"session_name\""
    idx = index($0, key)
    if (idx > 0) {
        pre_start = idx
        if (pre_start > 1 && substr($0, pre_start - 1, 1) == ",") pre_start--
        rest = substr($0, idx + length(key))
        gsub(/^[[:space:]]*:[[:space:]]*/, "", rest)
        if (substr(rest, 1, 1) == "\"") {
            rest = substr(rest, 2)
            while (length(rest) > 0) {
                c = substr(rest, 1, 1)
                if (c == "\\") { rest = substr(rest, 3) }
                else if (c == "\"") { rest = substr(rest, 2); break }
                else { rest = substr(rest, 2) }
            }
        }
        line = substr($0, 1, pre_start - 1) rest
    } else {
        line = $0
    }
    if (sub(/[[:space:]]*}$/, "", line)) {
        printf "%s,\"session_name\":\"%s\"}", line, name
    } else {
        print line
    }
}')

# Write atomically
TMP_FILE="${CSTATUS_FILE}.tmp.$$"
trap 'rm -f "$TMP_FILE" "$LOCK_FILE"' EXIT
printf '%s\n' "$UPDATED" > "$TMP_FILE"
mv -f "$TMP_FILE" "$CSTATUS_FILE"

# Release lock
exec 9>&-

echo "Session name set to: ${SESSION_NAME}"

# Notify the Claude Status app to refresh
/usr/bin/notifyutil -p com.poisonpenllc.Claude-Status.session-changed 2>/dev/null || true
