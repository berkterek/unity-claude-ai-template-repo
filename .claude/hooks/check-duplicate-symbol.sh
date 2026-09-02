#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# --- Hook Audit Logging ---
_hook_log() {
    local code=$1
    local log="${HOME}/.claude/hook-audit.log"
    mkdir -p "$(dirname "$log")"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local proj; proj=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    local file="${FILE_PATH:-}"
    local status
    if [ "$code" -eq 2 ]; then status="BLOCKED"
    elif [ "$code" -eq 0 ]; then status="OK"
    else status="WARN"; fi
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-duplicate-symbol" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks creation of a NEW .cs file under Games/Abstracts/ or
#       Games/Concretes/ when a class or interface of the same name already
#       exists in the knowledge graph. Reuse-first enforcement — the mechanical
#       half of csharp-unity.md Card 6 and the agents' Step 0 duplicate check.
# Event: PreToolUse, matcher "Write" (new-file creation only — NOT Edit).
# Receives JSON on stdin with tool_input.file_path
#
# DEGRADES SILENTLY (exit 0) whenever it cannot be sure: graph feature off,
# graph file missing, empty symbol arrays, or a graph older than 24h. This repo
# ships as a TEMPLATE with an empty, month-old graph — a hook that fired wrongly
# on a fresh clone would be strictly worse than no hook.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac

should_skip_path "$FILE_PATH" && exit 0

# Only the two domain trees carry the one-type-per-file convention this check
# relies on. Everything else (Ecs/, Editors/, Tests/) is out of scope.
case "$FILE_PATH" in
    */Games/Abstracts/*|*/Games/Concretes/*|Games/Abstracts/*|Games/Concretes/*) ;;
    *) exit 0 ;;
esac

# NEW-FILE GATE — inverted vs check-new-service.sh ON PURPOSE. Do not "fix" this.
# PreToolUse fires BEFORE the Write lands, so a genuinely NEW file is absent from
# disk. A file that already exists means this Write is an overwrite of a file
# whose symbol is legitimately in the graph already — not our business.
[ ! -f "$FILE_PATH" ] || exit 0

# --- Degrade gate 1: graph feature disabled ---
# CLAUDE_PROJECT_DIR first, git rev-parse fallback (2026-08-29): a bare git rev-parse
# here is cwd-dependent, and a subagent's cwd is not guaranteed to be the repo root —
# an empty result silently mis-resolves both files below and this check no-ops inside
# a subagent even when the graph feature and graph.json genuinely exist.
UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/project-features.json}"
[ "$(jq -r '.graph // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0

# --- Degrade gate 2: graph file missing ---
UNITY_GRAPH_FILE="${UNITY_GRAPH_FILE:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/graph/graph.json}"
[ -f "$UNITY_GRAPH_FILE" ] || exit 0

# --- Degrade gate 3: no symbols extracted yet (the shipped-template case) ---
SYMBOL_COUNT=$(jq -r '((.codebase.classes // []) | length) + ((.codebase.interfaces // []) | length)' "$UNITY_GRAPH_FILE" 2>/dev/null || echo 0)
case "$SYMBOL_COUNT" in ''|*[!0-9]*) exit 0 ;; esac
[ "$SYMBOL_COUNT" -gt 0 ] || exit 0

# --- Degrade gate 4: graph older than 24h (second shipped-template guard) ---
# Field is TOP-LEVEL .generated_at (ISO-8601 UTC). There is no `metadata` object.
GENERATED_AT=$(jq -r '.generated_at // empty' "$UNITY_GRAPH_FILE" 2>/dev/null)
[ -n "$GENERATED_AT" ] || exit 0
# BSD date (macOS) and GNU date (Linux) disagree on flags — try both, bail if neither parses.
GRAPH_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$GENERATED_AT" +%s 2>/dev/null \
           || date -u -d "$GENERATED_AT" +%s 2>/dev/null)
case "$GRAPH_EPOCH" in ''|*[!0-9]*) exit 0 ;; esac
NOW_EPOCH=$(date -u +%s)
[ $(( NOW_EPOCH - GRAPH_EPOCH )) -lt 86400 ] || exit 0

# --- The actual check ---
# Symbol name comes from the basename. The repo's "one type per file, filename
# matches class name" rule guarantees filename<->type agreement, but NOT global
# uniqueness across domains: Enemies/SpawnConfig.cs and Waves/SpawnConfig.cs are
# both legal. Blocking the second is an ACCEPTED false positive — the escape is
# named in the block message. Namespace-aware matching is a deliberate non-goal
# for v1 (it would require parsing tool_input.content, which no hook does).
SYMBOL="$(basename "$FILE_PATH" .cs)"

# .codebase.classes / .codebase.interfaces are INLINE arrays. Only scenes and
# prefabs use {"$partition": ...} refs, so no partition resolution is needed.
EXISTING=$(jq -r --arg n "$SYMBOL" \
    '[(.codebase.classes // [])[], (.codebase.interfaces // [])[]]
     | map(select(.name == $n)) | .[0].file // empty' "$UNITY_GRAPH_FILE" 2>/dev/null)

if [ -n "$EXISTING" ]; then
    unity_hook_block "Duplicate symbol '$SYMBOL' already exists at $EXISTING.

Extend the existing type instead of creating a second file with the same name.
Query it first:  /knowledge-graph implementers $SYMBOL

If this is a legitimate different-domain type that happens to share the name,
re-run with:  DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1"
fi

exit 0
