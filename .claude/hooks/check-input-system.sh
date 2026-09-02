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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-input-system" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then local tmp="${log}.$$.tmp"; tail -n 500 "$log" > "$tmp" 2>/dev/null && mv "$tmp" "$log" 2>/dev/null; rm -f "$tmp"; fi
}
_cleanup_effective_file() { rm -f "${EFFECTIVE_FILE:-}" "${OLD_STRING_FILE:-}" "${NEW_STRING_FILE:-}"; }
trap '_exit_code=$?; _cleanup_effective_file; _hook_log $_exit_code' EXIT
# --- End Hook Audit Logging ---
# Hook: Validates Input System usage patterns
# Catches: legacy Input API, missing Enable/Disable, input in FixedUpdate
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
# pending Edit/Write is applied. Checking that stale content means a BLOCKING
# violation already on disk can never be cleared — even an edit that removes
# the offending line still sees the unmodified disk file. Build the effective
# post-edit file and run every check against it instead.
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
EFFECTIVE_FILE=$(mktemp)

case "$TOOL_NAME" in
    Write)
        echo "$INPUT" | jq -j '.tool_input.content // empty' > "$EFFECTIVE_FILE"
        ;;
    Edit)
        [ -f "$FILE_PATH" ] || exit 0
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
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
        [ -f "$FILE_PATH" ] || exit 0
        cp "$FILE_PATH" "$EFFECTIVE_FILE"
        ;;
esac

ISSUES=""

# Strip comments and string literals to avoid false positives
STRIPPED=$(strip_cs_noise "$EFFECTIVE_FILE")

# --- Check 1: Legacy Input API usage ---
LEGACY_INPUT=$(echo "$STRIPPED" | grep -nE "\bInput\.(GetKey|GetAxis|GetButton|GetMouseButton|mousePosition|touches|GetTouch|touchCount|anyKey|inputString)\b")
if [ -n "$LEGACY_INPUT" ]; then
    ISSUES="${ISSUES}\nBLOCKING — Legacy Input API detected (use New Input System):\n${LEGACY_INPUT}\n"
    ISSUES="${ISSUES}Fix: Use generated PlayerControls class with callbacks or polling via ReadValue/WasPressedThisFrame.\n"
fi

# --- Check 2: Missing Enable/Disable for input controls ---
# If file references PlayerControls, InputActionAsset, or InputAction, it must have Enable() in OnEnable and Disable() in OnDisable
HAS_INPUT_REF=$(echo "$STRIPPED" | grep -cE "(PlayerControls|InputActionAsset|InputAction\b|_controls\.|_inputActions\.)" 2>/dev/null)
if [ "$HAS_INPUT_REF" -gt 0 ]; then
    # Check for Enable() call in/near OnEnable
    HAS_ENABLE=$(echo "$STRIPPED" | grep -cE "\.(Enable|Player\.Enable|UI\.Enable)\(\)" 2>/dev/null)
    # Check for Disable() call in/near OnDisable
    HAS_DISABLE=$(echo "$STRIPPED" | grep -cE "\.(Disable|Player\.Disable|UI\.Disable)\(\)" 2>/dev/null)

    if [ "$HAS_ENABLE" -eq 0 ]; then
        ISSUES="${ISSUES}\nWARNING — Input controls referenced but no Enable() call found!\n"
        ISSUES="${ISSUES}Input actions MUST be enabled in OnEnable() to receive input.\n"
        ISSUES="${ISSUES}Example: _controls.Player.Enable(); in OnEnable()\n"
    fi

    if [ "$HAS_DISABLE" -eq 0 ]; then
        ISSUES="${ISSUES}\nWARNING — Input controls referenced but no Disable() call found!\n"
        ISSUES="${ISSUES}Input actions MUST be disabled in OnDisable() to prevent leaks.\n"
        ISSUES="${ISSUES}Example: _controls.Player.Disable(); in OnDisable()\n"
    fi

    # Check that callbacks are unsubscribed (if subscribed with +=, must have -=)
    SUBSCRIBES=$(echo "$STRIPPED" | grep -oE "\+= On[A-Z][[:alnum:]_]+" | sed 's/+= //' | sort -u)
    if [ -n "$SUBSCRIBES" ]; then
        for CALLBACK in $SUBSCRIBES; do
            UNSUB_COUNT=$(echo "$STRIPPED" | grep -cE "-= ${CALLBACK}\b" 2>/dev/null)
            if [ "$UNSUB_COUNT" -eq 0 ]; then
                ISSUES="${ISSUES}\nWARNING — Input callback '${CALLBACK}' subscribed (+= ) but never unsubscribed (-=)!\n"
                ISSUES="${ISSUES}Unsubscribe in OnDisable() to prevent memory leaks and ghost callbacks.\n"
            fi
        done
    fi
fi

# --- Check 3: Input reading inside FixedUpdate ---
# Extract FixedUpdate body (rough heuristic: lines between FixedUpdate and next method)
IN_FIXED_UPDATE=false
INPUT_IN_FIXED=""
while IFS= read -r line; do
    if echo "$line" | grep -qE "void[[:space:]]+FixedUpdate[[:space:]]*\("; then
        IN_FIXED_UPDATE=true
        continue
    fi
    if [ "$IN_FIXED_UPDATE" = true ]; then
        # Detect next method declaration = end of FixedUpdate
        if echo "$line" | grep -qE "^[[:space:]]*(private|public|protected|internal|void|static|async|override|virtual)[[:space:]]+[[:alnum:]_]+.*\("; then
            IN_FIXED_UPDATE=false
            continue
        fi
        # Check for input reads inside FixedUpdate
        INPUT_READ=$(echo "$line" | grep -E "(ReadValue|WasPressedThisFrame|WasReleasedThisFrame|IsPressed|_moveInput|_controls\.[[:alnum:]_]+\.[[:alnum:]_]+\.Read)")
        if [ -n "$INPUT_READ" ]; then
            INPUT_IN_FIXED="${INPUT_IN_FIXED}\n${INPUT_READ}"
        fi
    fi
done <<< "$STRIPPED"

if [ -n "$INPUT_IN_FIXED" ]; then
    ISSUES="${ISSUES}\nWARNING — Input reading detected inside FixedUpdate!\n"
    ISSUES="${ISSUES}${INPUT_IN_FIXED}\n"
    ISSUES="${ISSUES}Read input in Update() and cache the values. Apply physics forces in FixedUpdate using cached values.\n"
fi

# --- Check 4: InputActionAsset field without [SerializeField] ---
BARE_ASSET=$(echo "$STRIPPED" | grep -nE "^[[:space:]]*(private|protected)[[:space:]]+InputActionAsset[[:space:]]+[[:alnum:]_]+[[:space:]]*;" | grep -v "SerializeField")
if [ -n "$BARE_ASSET" ]; then
    ISSUES="${ISSUES}\nWARNING — InputActionAsset field without [SerializeField]:\n${BARE_ASSET}\n"
    ISSUES="${ISSUES}The asset reference must be serialized to be assigned in the Inspector.\n"
fi

if [ -n "$ISSUES" ]; then
    if echo "$ISSUES" | grep -q "BLOCKING"; then
        unity_hook_block "INPUT SYSTEM ERROR in: $FILE_PATH"$'\n'"$(echo -e "$ISSUES")"
    else
        echo "Input System issues in: $FILE_PATH" >&2
        echo -e "$ISSUES" >&2
        exit 0
    fi
fi

exit 0
