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
)

INVOKED_FILE="${UNITY_HOOK_STATE_DIR}/skills-invoked.txt"
touch "$INVOKED_FILE" 2>/dev/null || true

MISSING_SKILLS=()

for entry in "${KEYWORD_MAP[@]}"; do
    keyword="${entry%%:*}"
    skill="${entry##*:}"

    if echo "$PROMPT" | grep -qF "$keyword"; then
        if ! grep -qxF "$skill" "$INVOKED_FILE" 2>/dev/null; then
            # Deduplicate
            already_added=false
            for s in "${MISSING_SKILLS[@]:-}"; do
                [ "$s" = "$skill" ] && already_added=true && break
            done
            $already_added || MISSING_SKILLS+=("$skill")
        fi
    fi
done

if [ ${#MISSING_SKILLS[@]} -eq 0 ]; then
    exit 0
fi

# Build comma-separated skill list
SKILLS_CSV=$(printf '%s, ' "${MISSING_SKILLS[@]}")
SKILLS_CSV="${SKILLS_CSV%, }"

# Output additionalContext — injected into Claude's system context before responding
jq -n \
    --arg skills "$SKILLS_CSV" \
    '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: ("⛔ SKILL ENFORCEMENT — ACTION REQUIRED BEFORE RESPONDING ⛔\n\nThis request involves a third-party package that has a dedicated skill. The following skill(s) have NOT been invoked yet this session:\n\n  " + $skills + "\n\nYou MUST call the Skill tool for each skill above BEFORE:\n- Writing any code\n- Giving implementation advice\n- Calling any MCP tools\n- Answering questions about the package\n\nInvoke the skill now. Do not proceed without it.")
        }
    }'

exit 0
