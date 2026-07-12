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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-pure-csharp" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Validates that service/domain C# files don't import UnityEngine.
# Also blocks *Handler : MonoBehaviour and *Module : ScriptableObject violations.
# Checks: _Framework/, Games/Abstracts/, Games/Concretes/ (excluding providers)
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if ! echo "$FILE_PATH" | grep -qE "\.cs$"; then
    exit 0
fi

# Skip Editor / third-party / test paths
should_skip_path "$FILE_PATH" && exit 0

# --- Check 1: *Handler : MonoBehaviour is forbidden (blocking) ---
# Handler must be pure C# — never MonoBehaviour.
if [ -f "$FILE_PATH" ]; then
    HANDLER_MONO=$(grep -nE "class\s+\w+Handler\s*:\s*(MonoBehaviour|UnityEngine\.MonoBehaviour)" "$FILE_PATH" 2>/dev/null | head -5)
    if [ -n "$HANDLER_MONO" ]; then
        VIOLATION=$(echo "$HANDLER_MONO" | head -1 | sed 's/^[[:space:]]*//')
        unity_hook_block "Handler classes must be pure C# — not MonoBehaviour.
File: $FILE_PATH

Found: $VIOLATION

Rule (solid-oop.md Card 1): *Handler suffix is forbidden on MonoBehaviour. Handler must be pure C# sealed class."
    fi
fi

# --- Check 2: *Module : ScriptableObject is forbidden (blocking) ---
# Module classes must be static — not ScriptableObject.
if [ -f "$FILE_PATH" ]; then
    MODULE_SO=$(grep -nE "class\s+\w+Module\s*:\s*(ScriptableObject|UnityEngine\.ScriptableObject)" "$FILE_PATH" 2>/dev/null | head -5)
    if [ -n "$MODULE_SO" ]; then
        VIOLATION=$(echo "$MODULE_SO" | head -1 | sed 's/^[[:space:]]*//')
        unity_hook_block "*Module classes must be static — not ScriptableObject.
File: $FILE_PATH

Found: $VIOLATION

Rule (bootstrap-pattern.md): Modules are static classes. Use [Module]Module.Install(builder, config) pattern."
    fi
fi

# --- Check 3: UnityEngine imports in domain/service files (blocking) ---
if echo "$FILE_PATH" | grep -qiE "(_Framework|Games/Abstracts|Games/Concretes)/.*\.cs$"; then
    # Skip providers, MonoBehaviours, views, handlers, editors, installers — Unity API lives here.
    # Swappable-backend implementations (architecture.md Card 2.1) get the same exemption as
    # *Provider — *Loader (ISceneLoader), *Dal (ISaveLoadDal), *Client (external service calls)
    # are all Tier 4 backend implementations a Tier 3 Service depends on via interface.
    # *Extensions: static extension classes (csharp-unity.md Card 1.1) legitimately extend
    # UnityEngine types (Vector3Extensions, TransformExtensions) and are never pure-C# services.
    if echo "$FILE_PATH" | grep -qiE "(Provider|View|Root|Mono|Behaviour|Inspector|Editor|Drawer|Panel|Button|Controller|Installer|Scope|Loader|Dal|Client|Extensions)\.(cs)$"; then
        exit 0
    fi

    # Skip event files — IEvent structs are data containers that may use Unity math types (Vector3 etc.)
    if echo "$FILE_PATH" | grep -qiE "Events?\.(cs)$"; then
        exit 0
    fi

    # Skip ScriptableObject config classes — csharp-unity.md data taxonomy classifies these
    # as *Configuration/*Config/*Catalog/*Definition. They legitimately `using UnityEngine`
    # for [SerializeField]/ScriptableObject and are never treated as pure-C# services.
    if echo "$FILE_PATH" | grep -qiE "(Configuration|Config|Catalog|Definition)\.(cs)$"; then
        exit 0
    fi

    if [ -f "$FILE_PATH" ]; then
        UNITY_IMPORTS=$(grep -n "using UnityEngine" "$FILE_PATH" 2>/dev/null)
        if [ -n "$UNITY_IMPORTS" ]; then
            unity_hook_block "Domain/service file contains UnityEngine imports!
File: $FILE_PATH

Violations:
$UNITY_IMPORTS

Services and abstractions must be pure C#.
Move Unity-specific code to a Provider class in Games/Concretes/<Module>/."
        fi
    fi
fi

exit 0
