#!/usr/bin/env bash
# ============================================================================
# enforce-skill-for-keywords.sh — UserPromptSubmit hook
#
# Detects third-party package keywords in the user's prompt.
# If a relevant skill exists but hasn't been invoked yet this session,
# injects a BLOCKING additionalContext message demanding skill invocation
# before Claude responds.
#
# Skill tracking: track-skill-invocations.sh (PostToolUse/Skill) writes to
# ${UNITY_HOOK_STATE_DIR}/skills-invoked.txt — one skill name per line.
#
# To add a new skill mapping: append a "keyword:skill_name" entry to
# KEYWORD_MAP below. keyword must be lowercase; skill_name must match the
# exact name used in the Skill tool (the skill's frontmatter `name:` field).
#
# To suppress for a session: DISABLE_HOOK_ENFORCE_SKILL_FOR_KEYWORDS=1
# ============================================================================
# Trigger: UserPromptSubmit
# Exit:    0 always — outputs additionalContext JSON when skills are missing
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="strict"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')

if [ -z "$PROMPT" ]; then
    exit 0
fi

# Pasted blocks are someone else's text (logs, other sessions' output) — a package
# named inside one says nothing about what the user is asking for now.
PROMPT=$(printf '%s' "$PROMPT" | perl -0pe 's{<pasted_content\b[^>]*>.*?</pasted_content\b[^>]*>}{}gs')
[ -z "${PROMPT//[[:space:]]/}" ] && exit 0

# ---------------------------------------------------------------------------
# Keyword → skill name mapping
# One entry per line: "keyword:skill_name"
# keyword  — lowercase phrase to match in the user's prompt
# skill_name — exact name to pass to the Skill tool
# ---------------------------------------------------------------------------
KEYWORD_MAP=(
    # Cinemachine
    "cinemachine:cinemachine"
    "vcam:cinemachine"
    "virtual camera:cinemachine"
    "cinemachinebrain:cinemachine"
    "camerarig:cinemachine"
    "camera shake:cinemachine"
    "camera blend:cinemachine"
    "freelook camera:cinemachine"
    "freelookcamera:cinemachine"
    "dolly track:cinemachine"
    "confiner2d:cinemachine"
    "cinemachineconfiner:cinemachine"
    "cinemachineimpulse:cinemachine"
    # UniTask
    "unitask:unitask"
    "unitaskvoid:unitask"
    "getcancellationtokenondestroy:unitask"
    "cancellationtokenondestroy:unitask"
    "playerlooptiming:unitask"
    # ShaderGraph
    "shadergraph:shader-graph"
    "shader graph:shader-graph"
    "shadersubgraph:shader-graph"
    "master stack:shader-graph"
    "blackboard property:shader-graph"
    # DOTween
    "dotween:dotween"
    "dotransform:dotween"
    "dofade:dotween"
    "dokill:dotween"
    "domove:dotween"
    "dosequence:dotween"
    # PrimeTween
    "primetween:primetween"
    # Dreamteck / Forever
    "dreamteck:dreamteck"
    "spline computer:dreamteck"
    "forever runner:dreamteck"
    "segment generator:dreamteck"
    # Feel / MMFeedbacks
    "mmfeedbacks:feel"
    "mmfeedback:feel"
    "nice vibrations:feel"
    # Odin Inspector
    "odin inspector:odin-inspector"
    "odin serializer:odin-inspector"
    "[showinif]:odin-inspector"
    "[listdrawersettings]:odin-inspector"
    # TextMeshPro
    "textmeshpro:textmeshpro"
    "tmpro:textmeshpro"
    # JMO Assets
    "jmo:jmo-assets"
    "war fx:jmo-assets"
    "particle image:particle-image"
    # Layer Lab GUI
    "layer lab:layer-lab-gui-pro-casual-game"
    "casualgui:layer-lab-gui-pro-casual-game"
    # Netcode for GameObjects
    "netcode:netcode"
    "networkbehaviour:netcode"
    "networkmanager:netcode"
    "networkobject:netcode"
    "networkvariable:netcode"
    "networklist:netcode"
    "serverrpc:netcode"
    "clientrpc:netcode"
    "onnetworkspawn:netcode"
    "onnetworkdespawn:netcode"
    "isowner:netcode"
    "isserver:netcode"
    "ishost:netcode"
    "multiplayer:netcode"
    "ngo:netcode"
    # URP Volume (MCP)
    "volume_create:urp-volume"
    "volume_add_effect:urp-volume"
    "volumeprofile:urp-volume"
    # ProBuilder
    "probuilder:probuilder"
    "shapegenerator:probuilder"
    "probuildermesh:probuilder"
    "polyshape:probuilder"
    "extrudemethod:probuilder"
    "combinemeshes:probuilder"
    "subdividefaces:probuilder"
    "greybox:probuilder"
    "whitebox:probuilder"
)

INVOKED_FILE="${UNITY_HOOK_STATE_DIR}/skills-invoked.txt"
touch "$INVOKED_FILE" 2>/dev/null || true

# auto-loaded-skills.md is a plain index since 2026-10-08, not an @-import, so a
# skill listed there is NOT in context. This hook used to skip enforcement for
# listed skills; keeping that skip would now silently disable it. (The old
# @.claude/... imports never loaded either — imports resolve relative to the
# importing file — so the skip was already wrong before the change.)

MISSING_SKILLS=()
REFERENCE_SKILLS=()

SKILLS_ROOT="${CLAUDE_PROJECT_DIR:-.}/.claude/skills"

for entry in "${KEYWORD_MAP[@]}"; do
    keyword="${entry%%:*}"
    skill="${entry##*:}"

    if echo "$PROMPT" | grep -qF "$keyword"; then
        # Skip if already invoked via Skill tool this session
        if grep -qxF "$skill" "$INVOKED_FILE" 2>/dev/null; then
            continue
        fi
        # Skip if no skill file backs this mapping. Demanding a skill that cannot be
        # invoked is a block with no exit: the injected message says "invoke it before
        # writing any code", the Skill tool answers "Unknown skill", and there is no
        # third move. Measured 2026-09-02: 5 of 75 mappings pointed at absent files
        # (dreamteck, feel, jmo-assets, layer-lab-gui-pro-casual-game, particle-image).
        #
        # These are template-level mappings for packages a given project may not have
        # installed, so absence is NORMAL, not a defect to repair by writing 5 stub
        # skills. The mapping simply has nothing to enforce — say so on stderr for the
        # maintainer and move on, rather than blocking the turn.
        #
        # Only .claude/skills/<name>/SKILL.md is invocable through the Skill tool. A nested
        # reference skill (third-party/<name>/SKILL.md, plugins/<name>.md) is not — demanding
        # a Skill call for it is the same no-exit block described above, and it re-fired on
        # every matching prompt because skills-invoked.txt is only written by a Skill call
        # that fails (found in review 2026-10-08). Point at the file instead.
        if [ ! -f "$SKILLS_ROOT/$skill/SKILL.md" ]; then
            ref=$(find "$SKILLS_ROOT" -maxdepth 3 \( -path "*/$skill/SKILL.md" -o -type f -name "${skill}.md" \) -print -quit 2>/dev/null)
            if [ -z "$ref" ]; then
                echo "[enforce-skill-for-keywords] '$keyword' maps to skill '$skill', which has no file under $SKILLS_ROOT — mapping skipped." >&2
                continue
            fi
            ref=".claude/skills/${ref#"$SKILLS_ROOT"/}"
            case " ${REFERENCE_SKILLS[*]:-} " in *" $ref "*) ;; *) REFERENCE_SKILLS+=("$ref") ;; esac
            continue
        fi
        # Deduplicate
        already_added=false
        for s in "${MISSING_SKILLS[@]:-}"; do
            [ "$s" = "$skill" ] && already_added=true && break
        done
        $already_added || MISSING_SKILLS+=("$skill")
    fi
done

if [ ${#MISSING_SKILLS[@]} -eq 0 ] && [ ${#REFERENCE_SKILLS[@]} -eq 0 ]; then
    exit 0
fi

MESSAGE=""
if [ ${#MISSING_SKILLS[@]} -gt 0 ]; then
    SKILLS_CSV=$(printf '%s, ' "${MISSING_SKILLS[@]}")
    SKILLS_CSV="${SKILLS_CSV%, }"
    MESSAGE="⛔ SKILL ENFORCEMENT — ACTION REQUIRED BEFORE RESPONDING ⛔

This request involves a third-party package that has a dedicated skill. The following skill(s) have NOT been invoked yet this session:

  ${SKILLS_CSV}

You MUST call the Skill tool for each skill above BEFORE:
- Writing any code
- Giving implementation advice
- Calling any MCP tools
- Answering questions about the package

Invoke the skill now. Do not proceed without it."
fi
if [ ${#REFERENCE_SKILLS[@]} -gt 0 ]; then
    REF_LIST=$(printf '  %s\n' "${REFERENCE_SKILLS[@]}")
    MESSAGE="${MESSAGE:+${MESSAGE}

}REFERENCE SKILL — this request names a package with a project reference skill. It is not invocable through the Skill tool; Read it before writing code or giving implementation advice for that package:

${REF_LIST}"
fi

# Output additionalContext — injected into Claude's system context before responding
jq -n --arg msg "$MESSAGE" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'

exit 0
