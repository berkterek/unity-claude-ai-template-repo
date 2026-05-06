#!/usr/bin/env bash
# Runs before context compaction. Reminds Claude to save state.

STATE_FILE="production/session-state/active.md"

echo "⚠️  Context compaction starting." >&2
echo "   Before compacting: update $STATE_FILE with current task, progress, and decisions." >&2
echo "   After compacting: read $STATE_FILE to restore context." >&2

exit 0
