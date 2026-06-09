#!/usr/bin/env bash
# check-ls-grep.sh — PreToolUse/Bash hook
# Blocks ls|grep patterns used for directory listing. Use tree instead.
# Exit: 2 (blocking)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip git commands entirely (commit messages may contain ls|grep as text)
if echo "$CMD" | grep -qE '^\s*git\b'; then
    exit 0
fi

# Block: ls piped to grep/awk/sed (directory listing via regex)
if echo "$CMD" | grep -qE 'ls[^|]*\|[[:space:]]*(grep|awk|sed)'; then
    echo "[check-ls-grep] BLOCKED: ls|grep detected. Use 'tree' for directory listings." >&2
    echo "[check-ls-grep] Examples: tree -L 2 | tree --gitignore | tree src/" >&2
    exit 2
fi

exit 0
