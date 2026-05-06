#!/usr/bin/env bash
# Loads active session state on session start.

STATE_FILE="production/session-state/active.md"

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

TASK=$(grep -m1 "^\- \*\*Task:\*\*" "$STATE_FILE" | sed 's/.*\*\*Task:\*\* //')
STATUS=$(grep -m1 "^\- \*\*Status:\*\*" "$STATE_FILE" | sed 's/.*\*\*Status:\*\* //')
LAST=$(grep -m1 "^\## Last Updated" -A1 "$STATE_FILE" | tail -1)

if [ "$TASK" = "—" ] || [ -z "$TASK" ]; then
  exit 0
fi

echo "📋 Session resumed — active task: $TASK ($STATUS)" >&2
echo "   Last updated: $LAST" >&2
echo "   Read production/session-state/active.md for full context." >&2

exit 0
