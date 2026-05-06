#!/usr/bin/env bash
# Runs after context compaction. Reminds Claude to restore state.

STATE_FILE="production/session-state/active.md"

if [ -f "$STATE_FILE" ]; then
  echo "🔄 Context compacted. Restore working context from: $STATE_FILE" >&2
fi

exit 0
