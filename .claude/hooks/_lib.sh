#!/usr/bin/env bash
# ============================================================================
# _lib.sh — Shared hook library (sourced, not executed)
# Provides kill switches, hook profiles, and shared utilities for all hooks.
#
# Environment variables:
#   DISABLE_UNITY_HOOKS=1          — bypass ALL hooks (exit 0 immediately)
#   DISABLE_HOOK_<NAME>=1          — bypass a specific hook (name uppercased, hyphens→underscores)
#   UNITY_HOOK_MODE=warn           — downgrade blocking hooks to warnings (exit 0 instead of 2)
#   UNITY_HOOK_PROFILE=standard    — hook profile: minimal|standard|strict (default: standard)
#
# Hook profiles control which hooks are active:
#   minimal  — only critical safety hooks (block scene/meta corruption)
#   standard — safety + quality warnings (default)
#   strict   — everything, including gateguard, learning, cost tracking
#
# Usage in hook scripts (add after set -euo pipefail):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   HOOK_PROFILE_LEVEL="standard"   # minimal|standard|strict
#   source "${SCRIPT_DIR}/_lib.sh"
# ============================================================================

# --- Profile levels (numeric for comparison) ---
_profile_to_num() {
    case "$1" in
        minimal)  echo 1 ;;
        standard) echo 2 ;;
        strict)   echo 3 ;;
        *)        echo 2 ;; # default to standard
    esac
}

_ACTIVE_PROFILE="${UNITY_HOOK_PROFILE:-standard}"
_ACTIVE_PROFILE_NUM=$(_profile_to_num "$_ACTIVE_PROFILE")

# If the hook declared a required profile level, check it
if [ -n "${HOOK_PROFILE_LEVEL:-}" ]; then
    _REQUIRED_NUM=$(_profile_to_num "$HOOK_PROFILE_LEVEL")
    if [ "$_REQUIRED_NUM" -gt "$_ACTIVE_PROFILE_NUM" ]; then
        exit 0  # hook's profile level exceeds active profile — skip silently
    fi
fi

# Global kill switch — disable all hooks
if [ "${DISABLE_UNITY_HOOKS:-}" = "1" ]; then
    exit 0
fi

# Per-hook kill switch — derive hook name from caller's filename
_HOOK_BASENAME="$(basename "${BASH_SOURCE[1]}" .sh)"
_HOOK_ENV_NAME="DISABLE_HOOK_$(echo "$_HOOK_BASENAME" | tr '[:lower:]-' '[:upper:]_')"

if [ "${!_HOOK_ENV_NAME:-}" = "1" ]; then
    exit 0
fi

# --- Shared paths ---
# Resolve project-local state directory, falling back to /tmp
_resolve_state_dir() {
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
    if [ -n "$git_root" ] && [ -d "$git_root/.claude/state" ]; then
        echo "$git_root/.claude/state"
    else
        echo "/tmp/unity-claude-hooks"
    fi
}
# Honor pre-set UNITY_HOOK_STATE_DIR (for tests and explicit overrides)
if [ -z "${UNITY_HOOK_STATE_DIR:-}" ]; then
    UNITY_HOOK_STATE_DIR="$(_resolve_state_dir)"
fi
mkdir -p "$UNITY_HOOK_STATE_DIR"

UNITY_SESSION_FILE="${UNITY_HOOK_STATE_DIR}/session.json"
UNITY_READS_FILE="${UNITY_HOOK_STATE_DIR}/gateguard-reads.txt"
UNITY_EDITS_FILE="${UNITY_HOOK_STATE_DIR}/session-edits.txt"
UNITY_COST_FILE="${UNITY_HOOK_STATE_DIR}/session-cost.jsonl"
UNITY_LEARNING_FILE="${UNITY_HOOK_STATE_DIR}/learnings.jsonl"
UNITY_WARNINGS_FILE="${UNITY_HOOK_STATE_DIR}/session-warnings.txt"
UNITY_NOTIFY_EVENT_FILE="${UNITY_HOOK_STATE_DIR}/notify-event.json"

# Instinct system paths (project-scoped, with global layer for promoted instincts)
UNITY_INSTINCTS_DIR="${UNITY_HOOK_STATE_DIR}/instincts"
UNITY_OBSERVATIONS_FILE="${UNITY_INSTINCTS_DIR}/observations.jsonl"

# unity_project_hash — stable identifier for the current project
# Prefers git remote URL (shared across clones); falls back to repo root path.
unity_project_hash() {
    local src
    src="$(git config --get remote.origin.url 2>/dev/null)" || true
    if [ -z "$src" ]; then
        src="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    fi
    echo "$src" | shasum | awk '{print $1}' | cut -c1-12
}

# --- Shared utilities ---

# unity_hook_block — use instead of exit 2 in blocking hooks
# If UNITY_HOOK_MODE=warn, prints the message as a warning and exits 0
# Otherwise, prints the message and exits 2 (blocking)
unity_hook_block() {
    local message="$1"
    if [ "${UNITY_HOOK_MODE:-}" = "warn" ]; then
        echo "WARNING (downgraded from BLOCKED): $message" >&2
        exit 0
    else
        echo "BLOCKED: $message" >&2
        exit 2
    fi
}

# unity_hook_warn — use for warn-only hooks. Prints to stderr (the channel the
# model sees), then exits 0 (non-blocking). Mirrors unity_hook_block.
unity_hook_warn() {
    echo "WARNING: $1" >&2
    exit 0
}

# should_skip_path — returns 0 (skip the hook) when the path is non-runtime
# project code: Editor tooling, third-party packages, or test code. This is the
# single source of truth for path exclusion — hooks call it instead of
# duplicating ad-hoc `grep -qE "/Editor/"` guards.
should_skip_path() {
    case "$1" in
        */Editor/*|*/editor/*|*/Editors/*|*/editors/*) return 0 ;;
        */Plugins/*|*/ThirdParty/*|*_AssetFolders/*|*PackageCache/*) return 0 ;;
        *EditModeTest/*|*PlayModeTest/*|*Tests/*|*Test/*|*Spec/*) return 0 ;;
    esac
    return 1
}

# unity_track_edit — record a file edit for session tracking
unity_track_edit() {
    local file_path="$1"
    if [ -n "$file_path" ]; then
        echo "$file_path" >> "$UNITY_EDITS_FILE"
    fi
}

# unity_track_read — record a file read for gateguard tracking
unity_track_read() {
    local file_path="$1"
    if [ -n "$file_path" ]; then
        echo "$file_path" >> "$UNITY_READS_FILE"
    fi
}

# unity_was_read — check if a file was previously read
unity_was_read() {
    local file_path="$1"
    [ -f "$UNITY_READS_FILE" ] && grep -qxF "$file_path" "$UNITY_READS_FILE" 2>/dev/null
}

# unity_state_read — read a top-level key from session.json
# Usage: unity_state_read "branch" -> prints the value
unity_state_read() {
    local key="$1"
    if [ -f "$UNITY_SESSION_FILE" ]; then
        jq -r ".$key // empty" "$UNITY_SESSION_FILE" 2>/dev/null
    fi
}

# unity_state_write — write a top-level key to session.json
# Usage: unity_state_write "workflow_phase" '"Execute"'
unity_state_write() {
    local key="$1"
    local value="$2"
    if [ -f "$UNITY_SESSION_FILE" ]; then
        local tmp="${UNITY_SESSION_FILE}.tmp"
        jq --argjson val "$value" ".$key = \$val" "$UNITY_SESSION_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$UNITY_SESSION_FILE"
    fi
}

# unity_state_plan_update — update a plan step status in session.json
# Usage: unity_state_plan_update "Write DamageSystem" "done"
unity_state_plan_update() {
    local step_name="$1"
    local new_status="$2"
    if [ -f "$UNITY_SESSION_FILE" ]; then
        local tmp="${UNITY_SESSION_FILE}.tmp"
        jq --arg name "$step_name" --arg status "$new_status" \
            '(.plan.steps // [])[] | select(.name == $name) |= (.status = $status)' \
            "$UNITY_SESSION_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$UNITY_SESSION_FILE"
    fi
}

# unity_track_warning — record a hook warning for session analytics
unity_track_warning() {
    local hook_name="$1"
    local message="$2"
    if [ -n "$hook_name" ]; then
        echo "${hook_name}: ${message}" >> "$UNITY_WARNINGS_FILE"
    fi
}

# strip_cs_noise <file_path> — strip C# string literals, // line comments, and /* */ block comments.
# Uses python3 (required hook dependency). Replaces BSD-incompatible GNU sed ':a;N;$!ba' pipelines.
# The Python helper is cached in /tmp on first call to avoid per-invocation overhead.
strip_cs_noise() {
    local src="$1"
    local _helper="/tmp/_unity_strip_cs_noise.py"
    if [ ! -f "$_helper" ]; then
        cat > "$_helper" << 'PYEOF'
import sys

def strip_noise(text):
    result = []; i = 0; n = len(text)
    in_str = in_lc = in_bc = False
    while i < n:
        c = text[i]
        if in_bc:
            if c == '*' and i + 1 < n and text[i + 1] == '/':
                in_bc = False; i += 2; continue
            if c == '\n': result.append('\n')
            i += 1; continue
        if in_lc:
            if c == '\n': in_lc = False; result.append('\n')
            i += 1; continue
        if in_str:
            if c == '\\' and i + 1 < n: i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if c == '"': in_str = True; i += 1; continue
        if c == '/' and i + 1 < n:
            if text[i + 1] == '/': in_lc = True; i += 2; continue
            if text[i + 1] == '*': in_bc = True; i += 2; continue
        result.append(c); i += 1
    return ''.join(result)

src = sys.argv[1] if len(sys.argv) > 1 else '-'
text = sys.stdin.read() if src == '-' else open(src, errors='replace').read()
sys.stdout.write(strip_noise(text))
PYEOF
    fi
    python3 "$_helper" "$src"
}
