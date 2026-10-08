#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/auto-load-skills.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_AUTO_LOADED_SKILLS_FILE="$UNITY_HOOK_STATE_DIR/auto-loaded-skills.md"
    printf '# Auto-Loaded Skills\n\n<!-- managed by auto-load-skills.sh — do not edit manually -->\n\n' > "$UNITY_AUTO_LOADED_SKILLS_FILE"
    REPO="$(pwd)"
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

_payload() { jq -n --arg f "$REPO/$1" '{tool_input: {file_path: $f}}'; }

@test "adds a plain described entry, never an @-import" {
    run bash $HOOK <<< "$(_payload .claude/skills/plugins/r3.md)"
    [ "$status" -eq 0 ]
    grep -qF -- '- `.claude/skills/plugins/r3.md` — R3' "$UNITY_AUTO_LOADED_SKILLS_FILE"
    ! grep -q '^@' "$UNITY_AUTO_LOADED_SKILLS_FILE"
}

@test "folded description (description: >) reads the next line" {
    run bash $HOOK <<< "$(_payload .claude/skills/third-party/netcode/SKILL.md)"
    line=$(grep -F 'netcode/SKILL.md' "$UNITY_AUTO_LOADED_SKILLS_FILE")
    [[ "$line" != *"— >"* ]]
    [[ "$line" =~ —\ [A-Za-z] ]]
}

@test "does not duplicate a skill already listed in the old @ format" {
    printf '@.claude/skills/plugins/r3.md\n' >> "$UNITY_AUTO_LOADED_SKILLS_FILE"
    run bash $HOOK <<< "$(_payload .claude/skills/plugins/r3.md)"
    [ "$(grep -c 'plugins/r3.md' "$UNITY_AUTO_LOADED_SKILLS_FILE")" -eq 1 ]
}

@test "ignores files outside the managed skill folders" {
    run bash $HOOK <<< "$(_payload .claude/rules/logging.md)"
    ! grep -q 'logging.md' "$UNITY_AUTO_LOADED_SKILLS_FILE"
}
