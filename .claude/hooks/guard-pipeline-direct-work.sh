#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"
# ============================================================================
# guard-pipeline-direct-work.sh — BLOCKING HOOK
#
# Problem this closes: a Director Gate being "cleared" only proves the gate was
# SHOWN — it does not prove the coder/tester/reviewer/committer pipeline was
# actually spawned afterward. Nothing previously stopped the main session from
# clearing the gate and then doing the Coder's/Committer's job itself via
# direct Edit/Write/Bash — a written-instruction rule with no enforcement.
#
# This hook closes that gap mechanically: while a Director Gate is open
# (.claude/state/gate-cleared exists) and no subagent is currently running
# (subagent-depth == 0, maintained by agent-start-log.sh / agent-stop-log.sh),
# direct Edit/Write/MultiEdit to game script files, and direct `git commit`,
# are blocked. The main session must spawn the corresponding pipeline agent
# instead of doing the work itself.
#
# Escape valve: if the user has explicitly approved skipping the pipeline for
# THIS task, write .claude/state/pipeline-override with a one-line reason
# before retrying. The override file is a discrete, visible tool call the
# user can see and challenge — it is not a silent bypass.
# ============================================================================
# Trigger: PreToolUse on Edit|MultiEdit|Write|Bash
# Exit:    2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

case "$TOOL_NAME" in
    Edit|MultiEdit|Write|Bash) ;;
    *) exit 0 ;;
esac

GATE_FILE="${UNITY_HOOK_STATE_DIR}/gate-cleared"
DEPTH_FILE="${UNITY_HOOK_STATE_DIR}/subagent-depth"
OVERRIDE_FILE="${UNITY_HOOK_STATE_DIR}/pipeline-override"

# No open gate → no pipeline in flight → nothing to guard
[ -f "$GATE_FILE" ] || exit 0

# Explicit, visible override for this task — consumed once, then cleared
if [ -f "$OVERRIDE_FILE" ]; then
    rm -f "$OVERRIDE_FILE"
    exit 0
fi

# unity_subagent_depth() (not a raw `cat`) — it applies any scheduled decrement
# whose grace window has elapsed first (see agent-stop-log.sh / _lib.sh's
# unity_subagent_schedule_decrement: Stop fires on async dispatch ack, not on
# actual subagent completion, so decrements are deferred rather than immediate).
CURRENT_DEPTH=$(unity_subagent_depth)

# Staleness guard. The depth counter leaks (see agent-start-log.sh): any spawn
# whose PostToolUse Stop never fires leaves the count permanently high, and a high
# count makes the check below exit 0 forever — this blocking hook silently
# downgraded to a no-op. session-restore.sh bounds the leak to one session; this
# bounds it further, within a session.
#
# The file's mtime is rewritten on every increment AND decrement, so it tracks the
# last agent lifecycle event. Nothing touches it while an agent merely runs, so a
# long-running agent eventually looks stale here — and that is the SAFE direction
# for this hook specifically: reading a stale count as 0 makes it enforce, and the
# worst case is a direct edit blocked while a genuine subagent is mid-run, which
# the pipeline-override valve already covers.
#
# gateguard.sh and check-config-protection.sh deliberately do NOT copy this: there
# a 0 means "Director", which lets a retry PASS, so downgrading on staleness would
# hand a long-running subagent the exact bypass those hooks exist to prevent. Same
# counter, opposite resolution, because each must fail toward enforcing ITS rule.
STALE_AFTER=900   # 15 min without any spawn/stop event

if [ "$CURRENT_DEPTH" -gt 0 ] 2>/dev/null && [ -f "$DEPTH_FILE" ]; then
    # GNU stat: -c %Y. BSD/macOS stat: -f %m. GNU must be tried FIRST — GNU's -f
    # means "filesystem info", so `stat -f %m` there does not fail, it prints "?"
    # with exit 0, and the arithmetic below then dies under `set -e` (CI-only
    # failure, invisible on macOS). The numeric guard is the second belt: any
    # non-integer becomes 0, which reads as "very old" → enforce.
    _mtime=$(stat -c %Y "$DEPTH_FILE" 2>/dev/null || stat -f %m "$DEPTH_FILE" 2>/dev/null || echo 0)
    case "$_mtime" in
        ''|*[!0-9]*) _mtime=0 ;;
    esac
    _age=$(( $(date +%s) - _mtime ))
    if [ "$_age" -gt "$STALE_AFTER" ]; then
        CURRENT_DEPTH=0
    fi
fi

# A subagent is actively running — this call belongs to it, not the Director
[ "$CURRENT_DEPTH" -gt 0 ] 2>/dev/null && exit 0

_blocked() {
    local reason="$1"
    echo "" >&2
    echo "  PIPELINE BYPASS BLOCKED ────────────────────────────────────" >&2
    echo "  $reason" >&2
    echo "" >&2
    echo "  A Director Gate is open and the subagent depth counter reads 0." >&2
    echo "  Doing this directly instead of spawning coder/tester/reviewer/" >&2
    echo "  committer defeats the point of the gate — it was cleared for a" >&2
    echo "  pipeline, not for you to do the work yourself." >&2
    echo "" >&2
    echo "  Fix: spawn the correct pipeline agent for this step instead." >&2
    echo "" >&2
    echo "  IF YOU *ARE* A SPAWNED SUBAGENT and are seeing this, the counter" >&2
    echo "  is wrong, not you. TWO known causes, both measured in real" >&2
    echo "  projects. First: you were resumed via SendMessage, which fires no" >&2
    echo "  PreToolUse/Agent, so nothing ever incremented for you. Second:" >&2
    echo "  agent-start-log.sh treats a second Agent call with the SAME" >&2
    echo "  session_id + description as the tool's own internal retry and" >&2
    echo "  skips the increment. A Director that respawns an agent with an" >&2
    echo "  identical description inside the retry window is indistinguishable" >&2
    echo "  from that, so depth stays 0 while you really are running." >&2
    echo "" >&2
    echo "  Remedy, in order:" >&2
    echo "    1. If this was a retry-dedupe collision, respawn with a" >&2
    echo "       DIFFERENT description. That is the fix and it costs one word." >&2
    echo "    1b. If you were resumed via SendMessage there is no description" >&2
    echo "       to change. Correcting the counter is legitimate — the guard's" >&2
    echo "       question is 'is a subagent running', and the true answer is" >&2
    echo "       yes. Do NOT write pipeline-override instead: that file claims" >&2
    echo "       the user approved SKIPPING the pipeline, which is false when" >&2
    echo "       the pipeline is what is doing the work. Clear the companion" >&2
    echo "       queue in the same breath or the correction evaporates on the" >&2
    echo "       next read, and put the counter back when you finish." >&2
    echo "    2. Do NOT hand-reset the counter — it was tried twice and was" >&2
    echo "       the wrong fix both times; the counter has a companion queue" >&2
    echo "       (subagent-depth-pending.jsonl) that must be cleared with it." >&2
    echo "       If you must, clear BOTH or start a new session." >&2
    echo "    3. Never switch to Bash (cat >, tee, sed -i) to get past this." >&2
    echo "       That skips every content hook at once, which is a worse" >&2
    echo "       outcome than the block you are trying to clear." >&2
    echo "" >&2
    echo "  Or, if the user explicitly approved skipping the pipeline for" >&2
    echo "  this specific task in this response, run:" >&2
    echo "    echo '<one-line reason + what user said>' > \"\$(git rev-parse --show-toplevel)/.claude/state/pipeline-override\"" >&2
    echo "  then retry. This is logged and visible to the user — do not" >&2
    echo "  write it speculatively or to work around this hook silently." >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    exit 2
}

if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    if echo "$COMMAND" | grep -qE '(^|[;&|]|\s)git\s+commit(\s|$)'; then
        _blocked "Direct 'git commit' while a gate is open — that is the committer agent's job."
    fi
    exit 0
fi

# Edit/MultiEdit/Write — only guard actual game code, not docs/plans/state files
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if echo "$FILE_PATH" | grep -qE '_GameFolders/Scripts/.*\.cs$'; then
    _blocked "Direct edit to '$FILE_PATH' while a gate is open — that is the coder/tester agent's job."
fi

exit 0
