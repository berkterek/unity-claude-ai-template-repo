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

# unity_monobehaviour_is_justified — reads ALREADY-STRIPPED C# content on stdin
# (caller runs strip_cs_noise once). Returns 0 if the class has a legitimate reason
# to be a MonoBehaviour / touch UnityEngine: a [SerializeField] field OR any Unity
# lifecycle callback. Returns 1 otherwise (Card 0 candidate — should be pure C#).
# NOTE: callback match intentionally broadens check-mono-justification.sh's historical
# exact list to OnTrigger*/OnCollision* prefixes (Enter/Stay/Exit all count) — superset,
# by design.
#
# The list must cover EVERY Unity message that justifies a MonoBehaviour, not just the
# common lifecycle six, because check-no-monobehaviour-in-services.sh uses this function
# as its early-exit escape hatch: a class this function fails to recognise falls through
# to the UnityEngine-leak check and is BLOCKED with exit 2. A missing callback name is
# therefore not stderr noise — it is a legal Controller that cannot be written. Measured
# gap before this list was extended: a Controller whose only callback was OnMouseDown,
# OnValidate, OnDrawGizmos or OnApplicationPause was blocked outright.
#
# Only Unity-OWNED prefixes are broadened (OnMouse*, OnApplication*, OnDrawGizmos*,
# OnParticle*, OnAnimator*, OnTransform*Changed, OnJointBreak*). Deliberately NOT matched:
# - bare `Reset(` — an ordinary method name (pool reset), and matching it would hand the
#   blocking hook's escape hatch to any pure-C# class with a Reset method.
# - a generic `On[A-Z]\w*(` wildcard — that would match `OnScoreChanged`/`OnPointerClick`,
#   silently exempting exactly the Card 0 candidates this function exists to catch.
unity_monobehaviour_is_justified() {
    local stripped; stripped=$(cat)
    if echo "$stripped" | grep -qE "\[SerializeField\]"; then
        return 0
    fi
    if echo "$stripped" | grep -qE "\b(Awake|Start|OnEnable|OnDisable|OnDestroy|Update|FixedUpdate|LateUpdate|OnGUI|OnValidate|OnTrigger[A-Za-z]*|OnCollision[A-Za-z]*|OnMouse[A-Za-z]*|OnApplication[A-Za-z]*|OnDrawGizmos[A-Za-z]*|OnParticle[A-Za-z]*|OnAnimator[A-Za-z]*|OnTransform[A-Za-z]*Changed|OnJointBreak[A-Za-z0-9]*|OnBecame(Visible|Invisible)|OnControllerColliderHit|OnAudioFilterRead|OnPreCull|OnPreRender|OnPostRender|OnRenderObject|OnRenderImage|OnWillRenderObject|OnLevelWasLoaded)\s*\("; then
        return 0
    fi
    return 1
}

# UNITY_ENGINE_LEAK_RE — word-boundary regex of real Unity engine/scene/asset/input/time API
# symbols that must NOT appear in a pure-C# Tier 3 service/domain file. Presence of ANY one
# means a `using UnityEngine` import is a genuine leak (move to a Provider / *Loader / *Dal /
# *Client). Its ABSENCE means the only UnityEngine surface left is the benign allow-list that
# Tier 3 permits: math value types (Mathf, Vector2/3/4, Quaternion, Color, Rect, Bounds, Ray,
# Plane, Matrix4x4 ...) and Debug logging (solid-oop.md Tier 3 "math types allowed";
# bootstrap-pattern.md Module null-guards legitimately call Debug.LogError).
# Implemented as a forbidden block-list (not a positive allow-list) because bash cannot resolve
# whether a bare identifier belongs to UnityEngine without a compiler — absence of every
# forbidden symbol is the tractable proxy for "only math + Debug remain".
# NOTE: '\bSceneManager\b' does NOT match the namespace 'SceneManagement' (no substring), so a
# service importing 'using UnityEngine.SceneManagement;' purely for the 'Scene' handle type
# (bootstrap-pattern.md Card 6 SceneService) passes; an actual 'SceneManager.LoadScene' call
# is caught. Case-sensitive: type 'Input'/'Camera' matches, local vars 'input'/'_camera' do not.
UNITY_ENGINE_LEAK_RE='\b(SceneManager|Addressables|GameObject|MonoBehaviour|Transform|GetComponent|AddComponent|Instantiate|Destroy|DontDestroyOnLoad|FindObjectOfType|FindFirstObjectByType|FindAnyObjectByType|FindObjectsByType|Physics|Physics2D|Rigidbody|Rigidbody2D|Collider|CharacterController|Raycast|MeshRenderer|SkinnedMeshRenderer|SpriteRenderer|Renderer|Animator|Camera|Material|Shader|ParticleSystem|AudioSource|AudioClip|AudioListener|InputSystem)\b|\b(Time|Application|Screen|Input|Resources|Gizmos)\.'

# unity_subagent_depth — how many subagents are currently on the stack.
#
# Echoes a sanitized integer: 0 when the file is missing, empty, or non-numeric.
# The counter is written by agent-start-log.sh / agent-stop-log.sh and it LEAKS
# (see agent-start-log.sh for the measurement) — treat the value as a hint, never
# as fact.
#
# Deliberately does NOT apply a staleness rule, because the safe direction is not
# the same for every caller:
#   * A caller that ALLOWS on depth > 0 (guard-pipeline-direct-work.sh) must
#     downgrade a stale count to 0 — that makes it enforce.
#   * A caller that BLOCKS on depth > 0 (gateguard.sh, check-config-protection.sh)
#     must NOT downgrade — doing so would hand a long-running subagent the exact
#     retry-bypass those gates exist to prevent. Nothing touches the depth file
#     while an agent merely runs, so any agent outliving the timeout would look
#     like the Director.
# Each caller layers its own direction on top of this value.
unity_subagent_depth() {
    local depth
    depth=$(cat "${UNITY_HOOK_STATE_DIR}/subagent-depth" 2>/dev/null || echo 0)
    case "$depth" in
        ''|*[!0-9]*) depth=0 ;;
    esac
    echo "$depth"
}

# unity_subagent_depth_lock / _unlock — mutual exclusion around the
# read-modify-write on subagent-depth.
#
# Root cause fixed here: agent-start-log.sh and agent-stop-log.sh each did
# `read current -> add/subtract 1 -> write` with no atomicity. Two PreToolUse
# hooks firing for a parallel Agent dispatch (or a Start racing a Stop) could
# both read the same value before either write landed — a classic lost-update.
# Measured 2026-08-29: 4 parallel Agent spawns left the counter at 1 instead
# of 4, and guard-pipeline-direct-work.sh subsequently treated a genuinely
# running subagent's first Write as if no subagent existed.
#
# mkdir is atomic on every POSIX filesystem this project targets (single
# syscall, exactly one caller wins) — used here as a lock, not a marker-per-
# agent scheme, to keep the on-disk shape (one scalar file) and every existing
# reader/remediation string ("echo 0 > .../subagent-depth") unchanged.
# Bounded to ~5s (50 * 0.1s) so a crashed holder can't wedge every future
# Agent spawn — on timeout the caller proceeds unlocked, which reintroduces
# the race only in that pathological case instead of hanging the pipeline.
unity_subagent_depth_lock() {
    local lockdir="${UNITY_HOOK_STATE_DIR}/subagent-depth.lock"
    local tries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -ge 50 ] && break
        sleep 0.1
    done
}

unity_subagent_depth_unlock() {
    rmdir "${UNITY_HOOK_STATE_DIR}/subagent-depth.lock" 2>/dev/null || true
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

# unity_gate_cleared_valid — is a Director Gate open and still within its TTL?
#
# Echoes the gate's age in seconds (empty when indeterminate) and returns:
#   0 = present and fresh    1 = absent
#   2 = age indeterminate    3 = stale
#
# Four states, not two, because callers need OPPOSITE directions on state 2 —
# the same split unity_subagent_depth documents. guard-gate-cleared.sh treats 2
# as valid (its historical behaviour: a failed age computation defaulted to 0).
# unity_plan_covers treats 2 as not-covered, because there a pass would release
# a gate on a stale approval.
UNITY_GATE_TTL=2700

unity_gate_cleared_valid() {
    local gate_file="${UNITY_HOOK_STATE_DIR}/gate-cleared"
    [ -f "$gate_file" ] || return 1

    local age
    age=$(python3 -c "import os,time; print(int(time.time() - os.path.getmtime('$gate_file')))" 2>/dev/null) || return 2
    case "$age" in
        ''|*[!0-9]*) return 2 ;;
    esac

    echo "$age"
    [ "$age" -le "$UNITY_GATE_TTL" ] || return 3
    return 0
}

# unity_plan_covers <script-path>
#
# 0 = a human-approved plan declares this path. Non-zero = it does not.
#
# Two conditions, both required:
#   1. a Director Gate is open and fresh  (unity_gate_cleared_valid == 0)
#   2. some docs/**/tasks.md declares this path
#
# gateguard.sh layers a third check (the facts block must validate) on top.
# guard-critical-files.sh and check-config-protection.sh consult coverage only:
# their demand is "investigate and confirm the change is intentional", which a
# task declared in the plan and approved at SCOPE_GATE already satisfies.
#
# Runs in a subshell with `set +e` so that ANY failure inside — an unreadable
# plan root, a missing library, a broken awk — surfaces as non-zero rather than
# killing the calling hook with status 1, which the harness does NOT treat as
# blocking. No uncertainty may ever produce a pass.
#
# Fail-closed only in a condition context (`if unity_plan_covers "$f"`,
# `unity_plan_covers "$f" && ...`, `unity_plan_covers "$f" || ...`). A bare
# `unity_plan_covers "$f"` under `set -e` propagates the non-zero return and
# terminates the calling hook with status 1 — which is NOT blocking in this
# harness, i.e. a fail-open. Every caller (Tasks 6, 7, 8) must invoke this in
# a condition context, never bare.
unity_plan_covers() {
    local target="${1:-}"
    (
        set +e
        # shellcheck source=lib-gateguard-facts.sh
        . "${UNITY_HOOK_DIR:-$(dirname "${BASH_SOURCE[0]}")}/lib-gateguard-facts.sh" 2>/dev/null || exit 1
        unity_gate_cleared_valid >/dev/null || exit 1
        [ -n "$(unity_find_task_line "$target")" ] || exit 1
        exit 0
    )
}
