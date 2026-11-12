#!/usr/bin/env bash
# Probe: the harness waits for EOF on a hook's stdout, not for the hook process to exit. A background
# child that inherits stdout (an in-script watchdog `( sleep 2; kill $$ ) &`) keeps the pipe open after
# the hook exits, so every tool call waits the full sleep — graph-nudge.sh did this on Read/Grep/Bash.
#
# Usage: run-probe.sh   (exit 0 = all pass, 1 = a hook holds stdout open)
set -u
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)"
FAIL=0

# 1. Static: no backgrounded sleep subshell in any hook.
HITS=$(grep -nE '\( *sleep [0-9.]+ *;[^)]*\) *&' "$HOOKS_DIR"/*.sh || true)
if [ -n "$HITS" ]; then
    echo "FAIL static: backgrounded sleep subshell (holds stdout open) in hooks"
    echo "$HITS" | cut -c1-160
    FAIL=1
else
    echo "PASS static: no backgrounded sleep subshell in hooks"
fi

# 2. Behavioural: graph-nudge.sh (the hook that had the watchdog) closes stdout fast, with the graph
#    feature on so it runs past the early exit.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/.claude/state"
echo '{"graph": true}' > "$SANDBOX/.claude/project-features.json"
INPUT='{"tool_name":"Read","session_id":"probe","tool_input":{"file_path":"/tmp/x.cs"}}'
START=$(python3 -c 'import time; print(time.time())')
printf '%s' "$INPUT" | CLAUDE_PROJECT_DIR="$SANDBOX" "$HOOKS_DIR/graph-nudge.sh" | cat >/dev/null
ELAPSED=$(python3 -c "import time; print(round(time.time() - $START, 2))")
if python3 -c "import sys; sys.exit(0 if $ELAPSED < 0.5 else 1)"; then
    echo "PASS behaviour: graph-nudge stdout EOF after ${ELAPSED}s"
else
    echo "FAIL behaviour: graph-nudge stdout EOF after ${ELAPSED}s (limit 0.5s)"
    FAIL=1
fi

exit $FAIL
