#!/usr/bin/env bash
# ============================================================================
# inject-rule-pointers.sh — UserPromptSubmit hook (awareness net 2)
#
# Path-scoped rules (.claude/rules/*.md with `paths:`) load only when a matching
# file is Read/Written/Edited. A planning prompt touches no file, so the rule that
# should shape the plan is absent and the model does not know it exists. This hook
# matches prompt keywords and injects a short POINTER — never the rule body —
# naming the rule files to Read before planning.
#
# Prior art: diet103/claude-code-infrastructure-showcase skill-rules.json. Regex
# only on purpose: its optional LLM classifier over-triggers on ~1/3 of off-topic
# prompts (its own benchmark comment).
#
# Deliberately NOT folded into enforce-skill-for-keywords.sh: that hook declares
# HOOK_PROFILE_LEVEL="strict", so under the default `standard` profile _lib.sh
# exits it before any matching runs.
#
# Spec: docs/superpowers/specs/2026-10-08-instruction-loading-design.md
#
# To add a mapping: append "stem|rule-basename[ rule-basename…]|feature" to RULE_MAP.
#   stem    — lowercase; matched at a word start ("save" hits "saves", not "unsaved")
#   feature — optional project-features.json key; skipped when that key is false
# ============================================================================
# Trigger: UserPromptSubmit
# Exit:    0 always — prints additionalContext JSON when a stem matches
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
# Lowercase and fold Turkish letters to ASCII: prompts are often typed without them
# ("kalici", "plani"), and `tr` lowercases "I" to "i" and leaves "İ" alone. Stems in
# RULE_MAP are therefore written in ASCII.
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null \
    | perl -CSD -Mutf8 -pe '$_ = lc; s/\x{307}//g; tr/ışçğüö/iscguo/')
[ -z "$PROMPT" ] && exit 0

# Pasted blocks are someone else's text (logs, other sessions' output) — their
# keywords say nothing about what the user is asking for now.
PROMPT=$(printf '%s' "$PROMPT" | perl -0pe 's{<pasted_content\b[^>]*>.*?</pasted_content\b[^>]*>}{}gs')
[ -z "${PROMPT//[[:space:]]/}" ] && exit 0

FEATURES_FILE="${UNITY_PROJECT_FEATURES_FILE:-${SCRIPT_DIR}/../project-features.json}"
RULES_DIR="${SCRIPT_DIR}/../rules"

RULE_MAP=(
    # Persistence
    "save|save-load|"
    "persist|save-load|"
    "playerprefs|save-load|"
    "kayd|save-load|"
    "kayit|save-load|"
    "kalici|save-load|"
    # UI — ui-toolkit-runtime Card 1 decides UGUI vs UI Toolkit before any file exists
    "screen|ui-toolkit-runtime|"
    "menu|ui-toolkit-runtime|"
    "popup|ui-toolkit-runtime|"
    "hud|ui-toolkit-runtime unity-prefabs|"
    "uxml|ui-toolkit-runtime|"
    "ui toolkit|ui-toolkit-runtime|"
    "ekran|ui-toolkit-runtime|"
    "arayuz|ui-toolkit-runtime|"
    # Async — unity-async loads on any .cs Read, but a planning prompt reads none
    "async|unity-async|"
    "unitask|unity-async|"
    "await|unity-async|"
    "coroutine|unity-async|"
    "asenkron|unity-async|"
    # Testing — unambiguous stems only; "test" itself is handled by TEST_ACTION below
    "nsubstitute|testing|testing"
    "tdd|testing|testing"
    # Milestones
    "milestone|roadmap-milestones|"
    "roadmap|roadmap-milestones|"
    "plan-module|roadmap-milestones|"
    # Prefabs and scenes
    "prefab|unity-prefabs|"
    "scene|scene-hierarchy|"
    "sahne|scene-hierarchy|"
    # Optional features
    "ecs|ecs-dots|ecs"
    "dots|ecs-dots|ecs"
    "addressable|addressables|addressables"
    # Browser authoring tools
    "web tool|web-tool-architecture web-tool-data-contract web-tool-design-system|"
    "level editor|web-tool-architecture web-tool-data-contract web-tool-design-system|"
)

# "test" alone fires on "did the tests pass"; a fixed phrase ("write test") misses
# "write a test" and "testleri yaz". So testing needs a test word AND an action word,
# anywhere in the prompt, in either order.
# English verbs end at a word boundary ("add" must not hit "addressables", "plan" not
# "plane"); Turkish stems stay open because suffixes carry the meaning ("yazalım").
TEST_ACTION_EN="(write|writes|writing|wrote|written|add|adds|added|adding|create|creates|created|creating|generate|generates|generated|generating|plan|plans|planned|planning)([^[:alnum:]]|$)"
TEST_ACTION_TR="yaz|ekle|olustur|planla|plani|planin"

_feature_enabled() {
    local feature="$1"
    [ -z "$feature" ] && return 0
    [ -f "$FEATURES_FILE" ] || return 0
    # `.[$f] // true` would turn an explicit false into true — test with has().
    [ "$(jq -r --arg f "$feature" 'if has($f) then .[$f] else true end' "$FEATURES_FILE" 2>/dev/null)" != "false" ]
}

_word() { printf '%s' "$PROMPT" | grep -qE "(^|[[:space:][:punct:]])($1)"; }

MATCHED=()
_test_request() {
    { _word test || printf '%s' "$PROMPT" | grep -qE 'tests?\.cs'; } || return 1
    _word "$TEST_ACTION_EN" || _word "$TEST_ACTION_TR"
}

if _test_request && _feature_enabled testing && [ -f "${RULES_DIR}/testing.md" ]; then
    MATCHED+=("testing")
fi
for entry in "${RULE_MAP[@]}"; do
    IFS='|' read -r stem rules feature <<< "$entry"
    printf '%s' "$PROMPT" | grep -qE "(^|[[:space:][:punct:]])${stem}" || continue
    _feature_enabled "$feature" || continue
    for rule in $rules; do
        [ -f "${RULES_DIR}/${rule}.md" ] || continue
        case " ${MATCHED[*]:-} " in *" ${rule} "*) continue ;; esac
        MATCHED+=("$rule")
    done
done

[ ${#MATCHED[@]} -eq 0 ] && exit 0

LIST=$(printf '  .claude/rules/%s.md\n' "${MATCHED[@]}")

jq -n --arg list "$LIST" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: ("RULE CHECK — this request touches areas governed by path-scoped rules that are NOT in your context yet. Before planning, answering or writing code, Read each file below and state which of its Cards apply (or that none do):\n\n" + $list + "\n\nThis is a pointer, not the rule — do not plan from memory of it.")
    }
}'

exit 0
