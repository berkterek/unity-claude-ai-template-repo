#!/usr/bin/env bash
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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "block-graph-direct-read" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# ============================================================================
# block-graph-direct-read.sh — BLOCKING HOOK
#
# When hybrid_graph is enabled in project-features.json, Claude must NEVER
# read graph partition files directly (graph.json, scenes.json, prefabs.json).
# All queries must go through /knowledge-graph commands or mcp__graph_mcp__*
# MCP tools — which return only the relevant slice, not the full file.
#
# Direct reads dump thousands of lines into context, wasting tokens and
# defeating the purpose of the hybrid backend.
#
# Portable: uses git rev-parse for project root — works in any repo layout,
# including nested Unity project folders (unity_project_folder setting).
#
# Trigger: PreToolUse on Read
# Exit: 2 = block, 0 = allow
# ============================================================================

set -euo pipefail

INPUT=$(cat)

# matcher: "Read" in settings.json already filters this hook to Read tool only.

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Resolve project root (portable across any repo layout)
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$PROJECT_ROOT" ]; then
    exit 0
fi

FEATURES_FILE="${PROJECT_ROOT}/.claude/project-features.json"
GRAPH_DIR="${PROJECT_ROOT}/.claude/graph"

# Only block files inside the graph directory
REAL_FILE="$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")"
REAL_GRAPH_DIR="$(realpath "$GRAPH_DIR" 2>/dev/null || echo "$GRAPH_DIR")"

BASENAME=$(basename "$REAL_FILE")
case "$BASENAME" in
    graph.json|scenes.json|prefabs.json)
        ;;
    *)
        exit 0
        ;;
esac

# Confirm the file is actually inside .claude/graph/ (not some other graph.json)
if [[ "$REAL_FILE" != "$REAL_GRAPH_DIR"/* ]]; then
    exit 0
fi

# Check hybrid_graph flag — only block when explicitly true
if [ ! -f "$FEATURES_FILE" ]; then
    exit 0
fi

HYBRID=$(jq -r '.hybrid_graph // false' "$FEATURES_FILE" 2>/dev/null)
if [ "$HYBRID" != "true" ]; then
    exit 0
fi

MSG="BLOCKED: Direct read of $BASENAME is forbidden when hybrid_graph is enabled."$'\n'
MSG+="  Reading this file dumps the entire graph into context, wasting tokens."$'\n'
MSG+="  Use /knowledge-graph <subcommand> to query only what you need:"$'\n'
MSG+="    /knowledge-graph summary"$'\n'
MSG+="    /knowledge-graph callers <Class.Method>"$'\n'
MSG+="    /knowledge-graph impact <ClassName>"$'\n'
MSG+="    /knowledge-graph prefab <PrefabName>"$'\n'
MSG+="    /knowledge-graph violations"$'\n'
MSG+="  Or use mcp__graph_mcp__* tools directly for call-graph queries."
unity_hook_block "$MSG"
