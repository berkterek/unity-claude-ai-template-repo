#!/usr/bin/env bash
# ============================================================================
# block-projectsettings.sh — PRE-TOOL-USE HOOK
# Blocks edits to Unity project configuration files that must be changed
# through the Unity Editor (Project Settings, Package Manager) rather than
# raw text edits. Wrong-format edits here can corrupt the project.
# ============================================================================
# Trigger: PreToolUse (Edit|Write)
# Exit: 0 if not a protected file, 2 if blocked
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # critical safety — runs in all profiles
source "${SCRIPT_DIR}/_lib.sh"

TOOL_INPUT=$(cat)
FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', d).get('file_path', ''))
except Exception:
    print('')
")

[ -z "$FILE_PATH" ] && exit 0

case "$FILE_PATH" in
    */ProjectSettings/*.asset|ProjectSettings/*.asset)
        unity_hook_block "Direct edits to ProjectSettings/*.asset are forbidden. Use the Unity Editor (Edit > Project Settings) or MCP 'manage_editor' / 'manage_build' tools. File: $FILE_PATH" ;;
    */Packages/manifest.json|Packages/manifest.json)
        unity_hook_block "Direct edits to Packages/manifest.json are forbidden. Use the Unity Package Manager UI or MCP 'manage_shell' (openupm add ...) instead. File: $FILE_PATH" ;;
    */Packages/packages-lock.json|Packages/packages-lock.json)
        unity_hook_block "Packages/packages-lock.json is generated — never edit by hand. Let Unity regenerate it. File: $FILE_PATH" ;;
esac

exit 0
