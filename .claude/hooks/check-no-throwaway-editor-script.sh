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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-no-throwaway-editor-script" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks one-shot / throwaway Editor scripts written to do work MCP should do.
#
# Pattern this exists to stop: instead of assigning a prefab field, a sprite
# reference, or a component value through MCP (manage_gameobject / manage_components
# / manage_asset), a temporary C# Editor script is written, invoked once, then
# deleted. That leaves file + .meta churn behind and hides an MCP call that was
# never attempted — the real cause is not knowing the MCP parameter shape and
# retreating to C# rather than reading the tool schema.
#
# Legitimate bulk AssetImporter work (audio-clip-agent, graphics-setup) belongs in a
# PERMANENT tool under Assets/Editor/ — not a Temp/ file marked for deletion.
# Escape valve: write a one-line reason to $UNITY_HOOK_STATE_DIR/editor-script-override

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac

CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // empty')

REASON=""

# Signal 1 — path lives in a scratch/temp Editor location
if echo "$FILE_PATH" | grep -qiE '/Editor/(Temp|Tmp|Scratch|OneShot|Throwaway)/'; then
    REASON="scratch Editor location: $FILE_PATH"
fi

# Signal 2 — content declares itself disposable
if [ -z "$REASON" ] && [ -n "$CONTENT" ]; then
    if echo "$CONTENT" | grep -qiE 'delete (this|the) file (once|after|when)|throwaway|one-shot (wiring|helper)|temporary wiring helper|geçici (editor )?script|EditorTemp'; then
        REASON="disposable content marker (throwaway / delete-after-use) in $FILE_PATH"
    fi
fi

[ -z "$REASON" ] && exit 0

# Escape valve — a non-empty override file with a stated reason
OVERRIDE_FILE="${UNITY_HOOK_STATE_DIR}/editor-script-override"
if [ -s "$OVERRIDE_FILE" ]; then
    echo "NOTE: throwaway Editor script allowed by override: $(head -n1 "$OVERRIDE_FILE")" >&2
    exit 0
fi

unity_hook_block "One-shot Editor script — $REASON

Do the work through MCP instead:
  prefab / component field assignment -> manage_gameobject, manage_components
  scene objects and wiring            -> manage_scene, manage_gameobject
  asset creation / lookup             -> manage_asset

Unknown parameter shape is NOT a reason to write C#: load the unity-mcp-skill
skill and read the tool schema, or inspect the live API with unity_reflect.
Do not guess, and do not fall back to C# after one failed call.

If this genuinely needs C# (bulk AssetImporter work MCP does not cover):
  -> write it as a PERMANENT tool under Assets/Editor/, not a Temp/ file to delete
  -> or state the reason: echo 'why' > \"\$(git rev-parse --show-toplevel)/.claude/state/editor-script-override\"
Kill switch: DISABLE_HOOK_CHECK_NO_THROWAWAY_EDITOR_SCRIPT=1"
