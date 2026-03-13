#!/bin/bash
# Shared JSON utilities for Claude Status plugin scripts.
# No external dependencies — uses only bash builtins and awk.

# Escape a string for safe interpolation into JSON string values.
# Handles backslash, double quote, tab, newline, carriage return, backspace, and form feed.
json_escape() {
    printf '%s' "$1" | awk -v RS='' '
    BEGIN {
        bs = sprintf("%c", 8)
        ff = sprintf("%c", 12)
    }
    {
        result = ""
        for (i = 1; i <= length($0); i++) {
            c = substr($0, i, 1)
            if (c == "\\") result = result "\\\\"
            else if (c == "\"") result = result "\\\""
            else if (c == "\t") result = result "\\t"
            else if (c == "\n") result = result "\\n"
            else if (c == "\r") result = result "\\r"
            else if (c == bs) result = result "\\b"
            else if (c == ff) result = result "\\f"
            else result = result c
        }
        printf "%s", result
    }'
}

# Extract a string value from JSON using awk.
# Handles escaped quotes within values and unescapes the result so that
# json_escape(extract_json_string(...)) round-trips correctly.
# Returns empty string when key is absent.
extract_json_string() {
    local key="$1"
    local json="$2"
    local result
    result=$(printf '%s' "$json" | awk -v key="\"${key}\"" '
    BEGIN {
        bs = sprintf("%c", 8)
        ff = sprintf("%c", 12)
    }
    {
        idx = index($0, key)
        if (idx == 0) next
        rest = substr($0, idx + length(key))
        gsub(/^[[:space:]]*:[[:space:]]*/, "", rest)
        if (substr(rest, 1, 1) != "\"") next
        rest = substr(rest, 2)
        val = ""
        while (length(rest) > 0) {
            c = substr(rest, 1, 1)
            if (c == "\\") {
                nc = substr(rest, 2, 1)
                if (nc == "n") val = val "\n"
                else if (nc == "t") val = val "\t"
                else if (nc == "r") val = val "\r"
                else if (nc == "b") val = val bs
                else if (nc == "f") val = val ff
                else val = val nc
                rest = substr(rest, 3)
            } else if (c == "\"") {
                print val
                exit
            } else {
                val = val c
                rest = substr(rest, 2)
            }
        }
    }') || true
    echo "$result"
}

# Check if the last assistant message in a JSONL transcript ends with a question.
# Reads only the tail of the file for efficiency.
# Returns 0 if question detected, 1 otherwise.
ends_with_question() {
    local transcript="$1"
    [[ -f "$transcript" ]] || return 1

    # Read last 8KB — enough to capture the final assistant message
    local last_assistant
    last_assistant=$(tail -c 8192 "$transcript" | grep '"type":"assistant"' | tail -1) || return 1
    [[ -n "$last_assistant" ]] || return 1

    # Extract the last "text":"..." value from the assistant message.
    # This finds the final text content block, which is what the user sees.
    local last_text
    last_text=$(printf '%s' "$last_assistant" | awk '{
        result = ""
        rest = $0
        while (1) {
            # Find next "text":" occurrence
            idx = index(rest, "\"text\":\"")
            if (idx == 0) break
            rest = substr(rest, idx + 8)
            # Extract the string value (handle escaped quotes)
            val = ""
            while (length(rest) > 0) {
                c = substr(rest, 1, 1)
                if (c == "\\") {
                    val = val substr(rest, 1, 2)
                    rest = substr(rest, 3)
                } else if (c == "\"") {
                    rest = substr(rest, 2)
                    break
                } else {
                    val = val c
                    rest = substr(rest, 2)
                }
            }
            result = val
        }
        print result
    }') || return 1

    [[ -n "$last_text" ]] || return 1

    # Strip trailing whitespace and check for question mark
    last_text="${last_text%"${last_text##*[! ]}"}"
    [[ "$last_text" == *'?' ]]
}
