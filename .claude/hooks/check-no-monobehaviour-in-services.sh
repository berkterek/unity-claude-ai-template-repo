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
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Validates that service/domain C# files don't leak real Unity engine/scene API.
# A `using UnityEngine` import is allowed when the file's only UnityEngine surface is the
# benign Tier 3 allow-list — math value types (Mathf, Vector3, Quaternion, Color...) and
# Debug logging (solid-oop.md Tier 3 "math types allowed"). It is BLOCKED when the file
# references engine/scene/asset/input/time API (SceneManager, Transform, AudioSource,
# Physics, Input, Time...) — that belongs in a Provider / *Loader / *Dal / *Client.
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

# --- Compute the EFFECTIVE post-tool-call content ---
# This hook runs PreToolUse: $FILE_PATH on disk is the file's state BEFORE the
# pending Edit/Write is applied. Every check below used to grep/strip "$FILE_PATH"
# directly, which means it validated the OLD file, not the one the agent is about
# to produce. Concretely: once a file has ANY blocked line on disk, an Edit whose
# whole purpose is to REMOVE that line still sees the unmodified disk content and
# gets blocked forever — the file becomes permanently unfixable via Edit/Write.
# Build the effective file here and run every check against it instead.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
EFFECTIVE_FILE=$(mktemp)

case "$TOOL_NAME" in
    Write)
        echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
        ;;
    Edit)
        if [ -f "$FILE_PATH" ]; then
            cp "$FILE_PATH" "$EFFECTIVE_FILE"
        fi
        OLD_STRING_FILE=$(mktemp)
        NEW_STRING_FILE=$(mktemp)
        echo "$INPUT" | jq -j '.tool_input.old_string // empty' > "$OLD_STRING_FILE"
        echo "$INPUT" | jq -j '.tool_input.new_string // empty' > "$NEW_STRING_FILE"
        REPLACE_ALL=$(echo "$INPUT" | jq -r '.tool_input.replace_all // false')
        if [ -s "$OLD_STRING_FILE" ]; then
            python3 - "$EFFECTIVE_FILE" "$OLD_STRING_FILE" "$NEW_STRING_FILE" "$REPLACE_ALL" <<'PYEOF' 2>/dev/null || true
import sys
target_path, old_path, new_path, replace_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "true"
with open(target_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    content = f.read()
with open(old_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    old = f.read()
with open(new_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    new = f.read()
content = content.replace(old, new) if replace_all else content.replace(old, new, 1)
with open(target_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(content)
PYEOF
        fi
        ;;
    *)
        # Unknown tool shape (shouldn't happen given the Edit|Write matcher) — fall
        # back to disk content rather than validating an empty file.
        if [ -f "$FILE_PATH" ]; then
            cp "$FILE_PATH" "$EFFECTIVE_FILE"
        fi
        ;;
esac

# --- Check 1: *Handler : MonoBehaviour is forbidden (blocking) ---
# Handler must be pure C# — never MonoBehaviour.
HANDLER_MONO=$(grep -nE "class\s+\w+Handler\s*:\s*(MonoBehaviour|UnityEngine\.MonoBehaviour)" "$EFFECTIVE_FILE" 2>/dev/null | head -5)
if [ -n "$HANDLER_MONO" ]; then
    VIOLATION=$(echo "$HANDLER_MONO" | head -1 | sed 's/^[[:space:]]*//')
    unity_hook_block "Handler classes must be pure C# — not MonoBehaviour.
File: $FILE_PATH

Found: $VIOLATION

Rule (solid-oop.md Card 1): *Handler suffix is forbidden on MonoBehaviour. Handler must be pure C# sealed class."
fi

# --- Check 2: *Module : ScriptableObject is forbidden (blocking) ---
# Module classes must be static — not ScriptableObject.
MODULE_SO=$(grep -nE "class\s+\w+Module\s*:\s*(ScriptableObject|UnityEngine\.ScriptableObject)" "$EFFECTIVE_FILE" 2>/dev/null | head -5)
if [ -n "$MODULE_SO" ]; then
    VIOLATION=$(echo "$MODULE_SO" | head -1 | sed 's/^[[:space:]]*//')
    unity_hook_block "*Module classes must be static — not ScriptableObject.
File: $FILE_PATH

Found: $VIOLATION

Rule (bootstrap-pattern.md): Modules are static classes. Use [Module]Module.Install(builder, config) pattern."
fi

# --- Check 3: UnityEngine imports in domain/service files (blocking) ---
if echo "$FILE_PATH" | grep -qiE "(_Framework|Games/Abstracts|Games/Concretes)/.*\.cs$"; then
    # Filename whitelist: ONLY structurally-undetectable pure-C# role categories.
    # *Handler (constructor-ref Unity access), *Loader/*Dal/*Client (Tier 4 swappable
    # backends, architecture.md Card 2.1), *Extensions (static extensions on Unity types),
    # *Installer/*Scope (VContainer wiring). Everything else — Provider/View/Controller/
    # Panel/Button/Inspector/Editor/Drawer — is now judged STRUCTURALLY (justified MB)
    # or excluded by should_skip_path (path-based Editor folders).
    if echo "$FILE_PATH" | grep -qiE "(Handler|Loader|Dal|Client|Extensions|Installer|Scope)\.(cs)$"; then
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

    if [ -s "$EFFECTIVE_FILE" ]; then
        STRIPPED=$(strip_cs_noise "$EFFECTIVE_FILE")
        # Structural justification: a real MonoBehaviour ([SerializeField] or lifecycle
        # callback) is allowed to touch UnityEngine even in a domain folder.
        if echo "$STRIPPED" | unity_monobehaviour_is_justified; then
            exit 0
        fi
        UNITY_IMPORTS=$(grep -n "using UnityEngine" "$EFFECTIVE_FILE" 2>/dev/null)
        if [ -n "$UNITY_IMPORTS" ]; then
            # `using UnityEngine` is present and this is NOT a justified MonoBehaviour.
            # It is a LEAK only if the file references real engine/scene/asset/input/time API.
            # The benign Tier 3 surface — math value types (Mathf, Vector3, Quaternion,
            # Color...) and Debug logging — is allowed (solid-oop.md Tier 3 "math types
            # allowed"; bootstrap-pattern.md Module null-guards use Debug.LogError).
            LEAK=$(echo "$STRIPPED" | grep -noE "$UNITY_ENGINE_LEAK_RE" | head -5)
            if [ -n "$LEAK" ]; then
                unity_hook_block "Domain/service file leaks real Unity engine/scene API!
File: $FILE_PATH

Offending Unity API usage (strippedLine:symbol):
$LEAK

Tier 3 services may use UnityEngine MATH value types (Mathf, Vector2/3/4, Quaternion,
Color, Rect, Bounds, Ray, Plane, Matrix4x4) and Debug logging ONLY. Move Scene/GameObject/
Physics/Audio/Input/Time/Resources API to a Provider (*Provider) or a swappable backend
(*Loader / *Dal / *Client). Rules: solid-oop.md Tier 3, architecture.md Card 2 / 2.1.
If this is genuinely a MonoBehaviour, it needs a [SerializeField] field or a Unity
lifecycle callback."
            fi
            # else: only math + Debug remain — benign; fall through to exit 0.
        fi
    fi
fi

exit 0
