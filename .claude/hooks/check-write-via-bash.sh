#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="minimal"   # minimal | standard | strict
source "${SCRIPT_DIR}/_lib.sh"

# ============================================================================
# check-write-via-bash.sh — BLOCKING HOOK
#
# Closes the hole every other content hook depends on.
#
# Every file-content hook in settings.json (block-scene-edit,
# check-config-protection, guard-critical-files, check-domain-folder-structure,
# check-vcontainer-singleton, …) is registered with matcher `Edit|Write`.
# None of them see a Bash command. So `cat > Foo.asmdef` writes the exact file
# those 20+ hooks exist to govern, and not one of them runs.
#
# That is not a theoretical gap: an agent that hit a legitimate .asmdef block
# switched from Write to `cat >` and landed the file anyway — cancelling, on its
# own, a check whose entire job was to hand the decision to a human.
#
# This hook makes Write/Edit the only route to project files, so the other hooks
# get to do their job. It deliberately does NOT judge the content — it only
# refuses the channel.
#
# Escape valve: none by design. If a block is wrong, the fix is to fix the
# blocking hook or raise it at the gate — never to route around it.
# (DISABLE_UNITY_HOOKS=1 / UNITY_HOOK_MODE=warn still apply, via _lib.sh.)
# ============================================================================
# Trigger: PreToolUse on Bash
# Exit: 2 = block, 0 = allow
# ============================================================================

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && exit 0

# Project file types the content hooks govern. A write to any of these must go
# through Write/Edit so the matcher-`Edit|Write` hooks actually fire.
EXT_RE='cs|asmdef|asmref|unity|prefab|asset|meta|inputactions|shader|shadergraph|mat|controller|uxml|uss'

# Scratch/temp locations are not project files — a helper script in /tmp is not
# what the content hooks protect, and blocking it is pure friction.
TMP_RE='(^|[ =])(/tmp/|/private/tmp/|/var/folders/)'

VIOLATION=""

# --- 1. Shell redirection:  > path   >> path   (heredocs land here too) ---
# Three target shapes, because a quoted path may legally contain spaces:
#   bare        > Assets/Foo.cs
#   "quoted"    > "Assets/My Folder/Foo.cs"
#   'quoted'    > 'Assets/My Folder/Foo.cs'
REDIR_RE=">>?[[:space:]]*(\"[^\"]*\.($EXT_RE)\"|'[^']*\.($EXT_RE)'|[^[:space:]'\"|;&]*\.($EXT_RE)([[:space:]]|\$))"
if echo "$CMD" | grep -qE "$REDIR_RE"; then
    TARGET=$(echo "$CMD" | grep -oE "$REDIR_RE" | head -1)
    echo "$TARGET" | grep -qE "$TMP_RE" || VIOLATION="shell redirection ($TARGET)"
fi

# --- 2. tee ---
if [ -z "$VIOLATION" ] && echo "$CMD" | grep -qE "\btee\b([[:space:]]+-[a-zA-Z]+)*[[:space:]]+['\"]?[^[:space:]'\"|;&]*\.($EXT_RE)"; then
    TARGET=$(echo "$CMD" | grep -oE "\btee\b([[:space:]]+-[a-zA-Z]+)*[[:space:]]+['\"]?[^[:space:]'\"|;&]*\.($EXT_RE)" | head -1)
    echo "$TARGET" | grep -qE "$TMP_RE" || VIOLATION="tee ($TARGET)"
fi

# --- 3. In-place edit:  sed -i   perl -i ---
if [ -z "$VIOLATION" ] && echo "$CMD" | grep -qE "\b(sed|perl)\b[^|;&]*[[:space:]]-i([[:space:]]|')" \
   && echo "$CMD" | grep -qE "\.($EXT_RE)([[:space:]]|['\"]|$)"; then
    VIOLATION="in-place edit (sed -i / perl -i)"
fi

# --- 4. cp / mv INTO a project file (last argument is the destination) ---
if [ -z "$VIOLATION" ] && echo "$CMD" | grep -qE "\b(cp|mv|install)\b[^|;&]*[[:space:]][^[:space:]'\"|;&]*\.($EXT_RE)([[:space:]]|['\"]|$)"; then
    DEST=$(echo "$CMD" | sed -E 's/[|;&].*$//' | awk '{print $NF}' | tr -d "'\"")
    case "$DEST" in
        *.cs|*.asmdef|*.asmref|*.unity|*.prefab|*.asset|*.meta|*.inputactions|*.shader|*.shadergraph|*.mat|*.controller|*.uxml|*.uss)
            echo "$DEST" | grep -qE '^(/tmp/|/private/tmp/|/var/folders/)' || VIOLATION="cp/mv into a project file ($DEST)"
            ;;
    esac
fi

if [ -n "$VIOLATION" ]; then
    unity_hook_block "$(cat <<EOF
writing a project file through Bash — $VIOLATION

Use the Write or Edit tool instead.

Every content hook in this project (asmdef protection, scene-edit block,
domain-folder rules, singleton/DI checks) is registered on Edit|Write and does
not see a Bash command. Writing the file this way skips all of them.

If you came here because Write/Edit was BLOCKED:
  → That block is the point. Do not route around it.
  → Read the block message, fix the underlying issue, or surface the conflict
    at the gate and let the human decide.
  → A hook you silenced yourself is not a hook.
EOF
)"
fi

exit 0
