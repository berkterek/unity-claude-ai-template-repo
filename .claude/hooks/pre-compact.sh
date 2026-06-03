#!/usr/bin/env bash
# ============================================================================
# pre-compact.sh — PRE-COMPACT HOOK
# Snapshots session state before /compact discards conversation history.
# session-save.sh and session-restore.sh both consume precompact-state.md.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

OUT="${UNITY_HOOK_STATE_DIR}/precompact-state.md"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
COMMITS=$(git log --oneline -5 2>/dev/null || echo "(no commits)")
MODIFIED="(none)"
if [ -f "$UNITY_EDITS_FILE" ]; then
    MODIFIED=$(sort -u "$UNITY_EDITS_FILE" | head -20)
fi

cat > "$OUT" <<EOF
# Pre-Compact Snapshot

> Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
> Branch: $BRANCH

## Recent commits
\`\`\`
$COMMITS
\`\`\`

## Files edited this session
\`\`\`
$MODIFIED
\`\`\`

## Workflow phase
$(unity_state_read workflow_phase 2>/dev/null || echo "unknown")

## Resume hint
Run /catch-up or read this file at the start of the next turn to restore context.
EOF

echo "Pre-compact snapshot written to $OUT" >&2
exit 0
