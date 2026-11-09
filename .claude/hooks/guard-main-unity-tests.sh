#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"
# ============================================================================
# guard-main-unity-tests.sh — BLOCKING HOOK
#
# While a Director Gate is open (a pipeline is running), the main session may
# not run or poll Unity tests itself — that is unity-verifier's job.
#
# Why: measured on a downstream project (Nov 2026, 17 /orchestrate runs) the
# main session averaged 214 turns at ~440k context each; 84 of them were Unity
# MCP calls (run_tests 8, get_test_job polling 13, refresh 12, read_console 12,
# execute_code 27) while unity-verifier was spawned ONCE in the project's whole
# history. Every poll re-reads the full Director context; inside a verifier the
# same poll costs a ~60k context. The written rule ("spawn a unity-verifier")
# existed and was skipped, so this hook makes it mechanical.
#
# Scope is deliberately narrow — run_tests and get_test_job only. Those are the
# calls that are always delegable; refresh / read_console / Play Mode stay
# allowed (a quick compile check or a user-requested manual run is legitimate).
#
# Subagent detection: a subagent's tool call carries `agent_id` in the hook
# payload. As a fallback for older runtimes, a fresh non-zero subagent-depth
# also allows — this hook fails toward ALLOW for subagents, because blocking a
# real verifier would stall the pipeline it exists to protect.
#
# Escape valve: `.claude/state/pipeline-override` (user-approved, one line) —
# read, not consumed (guard-pipeline-direct-work.sh consumes it).
# No gate open → /ralph, /validate, ad-hoc test runs are untouched.
# ============================================================================
# Trigger: PreToolUse on mcp__UnityMCP__run_tests|mcp__UnityMCP__get_test_job
# Exit:    2 = block, 0 = allow
# ============================================================================
set -uo pipefail

INPUT=$(cat)

# Subagent → allow
[ -n "$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)" ] && exit 0

# No open, fresh gate → no pipeline running → allow
unity_gate_cleared_valid >/dev/null 2>&1 || exit 0

[ -f "${UNITY_HOOK_STATE_DIR}/pipeline-override" ] && exit 0

# Fallback: a subagent is running and the counter moved in the last 15 min
DEPTH_FILE="${UNITY_HOOK_STATE_DIR}/subagent-depth"
DEPTH=$(unity_subagent_depth 2>/dev/null || echo 0)
if [ "${DEPTH:-0}" -gt 0 ] 2>/dev/null && [ -f "$DEPTH_FILE" ]; then
    _m=$(stat -c %Y "$DEPTH_FILE" 2>/dev/null || stat -f %m "$DEPTH_FILE" 2>/dev/null || echo 0)
    case "$_m" in ''|*[!0-9]*) _m=0 ;; esac
    [ $(( $(date +%s) - _m )) -le 900 ] && exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
unity_hook_block "$TOOL from the main session while a pipeline gate is open.
  Running or polling tests here re-reads the whole Director context on every call.
  Spawn unity-verifier (orchestrate Step 3.5 / Phase Gate Step 1, implement/fix
  validator step) and read its one-line verdict instead.
  User explicitly asked you to run them here? Write the reason to
  .claude/state/pipeline-override and retry."
