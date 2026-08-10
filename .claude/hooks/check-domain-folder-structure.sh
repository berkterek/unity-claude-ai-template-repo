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
    printf '{"ts":"%s","hook":"%s","status":"%s","file":"%s","project":"%s"}\n' "$ts" "check-domain-folder-structure" "$status" "$file" "$proj" >> "$log"
    local lines; lines=$(wc -l < "$log" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then tail -n 500 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"; fi
}
trap '_hook_log $?' EXIT
# --- End Hook Audit Logging ---
# Hook: Blocks layer names and catch-all names as the FIRST folder under
#       Games/Abstracts/ or Games/Concretes/, and .cs files with no domain
#       folder at all. Everything BELOW the domain folder is unconstrained.
# Event: PreToolUse (pure path check — needs no file content, so it can and
#        must stop the bad path before the file is ever created).
# Receives JSON on stdin with tool_input.file_path

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Non-.cs writes are never this hook's business. This is also what lets an
# ARCHITECTURE.md land in a brand-new domain folder without being flagged here.
case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac

should_skip_path "$FILE_PATH" && exit 0

# NO `sed -E` HERE — and do not "helpfully" reintroduce it. Both of these are
# broken on BSD sed and turn this hook into a SILENT NO-OP that never blocks
# and never errors:
#   sed -E 's|.*Games/(Abstracts|Concretes)/.*|\1|'    -> parentheses not balanced, empty output
#   sed -E 's|.*Games/\(Abstracts\|Concretes\)/.*|\1|' -> \1 not defined in the RE
# Empty SIDE would make the prefix strip fail, FIRST would be "", and both
# checks below would fall through. Use pure shell.
case "$FILE_PATH" in
    *Games/Abstracts/*) SIDE=Abstracts ;;
    *Games/Concretes/*) SIDE=Concretes ;;
    *) exit 0 ;;
esac

# Defensive guards: fail loud, never fall through into the silent-no-op mode.
[ -z "$SIDE" ] && exit 0

TAIL=${FILE_PATH#*Games/$SIDE/}
[ "$TAIL" = "$FILE_PATH" ] && exit 0    # prefix strip failed — refuse to guess

FIRST=${TAIL%%/*}

# --- Check 1: no domain folder at all ---
if [ "$FIRST" = "$TAIL" ]; then
    unity_hook_block "No domain folder: '$FILE_PATH'
.cs files may not sit directly under Games/$SIDE/.
Put it in a domain folder: Games/$SIDE/<Domain>/$FIRST
Plural for countable domains (Players/, Enemies/, Inputs/), singular for mass
nouns (Audio/, UI/, VFX/). DI and bootstrap wiring -> Concretes/Infrastructure/."
fi

# --- Check 2: banned first segment (17 forms, two families) ---
case "$(printf '%s' "$FIRST" | tr '[:upper:]' '[:lower:]')" in
    service|services|provider|providers|controller|controllers|view|views|\
manager|managers|interface|interfaces|config|configs)
        unity_hook_block "Layer name in the domain position: 'Games/$SIDE/$FIRST/'
The first folder under Games/$SIDE/ must be a DOMAIN — Players/, Enemies/,
Inputs/, Audio/, UI/, VFX/, Infrastructure/ — never a layer.
Layer names are free BELOW the domain: Games/$SIDE/<Domain>/$FIRST/ is legal.
Kill switch: DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1"
        ;;
    core|general|generals)
        unity_hook_block "Catch-all folder: 'Games/$SIDE/$FIRST/'
'$FIRST' is not a domain — it is a name that cannot refuse a file, so everything
drains into it. (In the voxel-blast project, Core/ reached 85 files and 7692
lines spanning five unrelated concerns.)
Pick a real domain instead. For code that genuinely has no domain:
  _Framework/                  -> domain-agnostic infrastructure
  Concretes/Infrastructure/    -> DI, bootstrap, scope and config wiring
Kill switch: DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1"
        ;;
esac

# Nothing below FIRST is ever inspected — by design.
exit 0
