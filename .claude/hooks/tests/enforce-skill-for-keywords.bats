#!/usr/bin/env bats
# The Skill tool can only invoke a skill at .claude/skills/<name>/SKILL.md (or a plugin/user
# skill). Nested reference skills (third-party/<name>/SKILL.md, plugins/<name>.md) are NOT
# invocable, so demanding a Skill call for them is a demand that can never be met — it
# re-fires on every matching prompt because skills-invoked.txt is only written by a Skill
# call that fails. Those get a Read pointer instead.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export UNITY_HOOK_PROFILE=strict   # this hook is strict-level
    HOOK="$BATS_TEST_DIRNAME/../enforce-skill-for-keywords.sh"
    export CLAUDE_PROJECT_DIR="$UNITY_HOOK_STATE_DIR/project"
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude/skills"
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

@test "a discoverable skill (.claude/skills/<name>/SKILL.md) is demanded via the Skill tool" {
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude/skills/unitask"
    echo '# UniTask' > "$CLAUDE_PROJECT_DIR/.claude/skills/unitask/SKILL.md"
    run bash "$HOOK" <<< '{"prompt":"use unitask for the loader"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"MUST call the Skill tool"* ]]
    [[ "$output" == *"unitask"* ]]
}

@test "a nested reference skill gets a Read pointer, never an unsatisfiable Skill demand" {
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude/skills/third-party/unitask"
    echo '# UniTask' > "$CLAUDE_PROJECT_DIR/.claude/skills/third-party/unitask/SKILL.md"
    output=$(bash "$HOOK" 2>/dev/null <<< '{"prompt":"use unitask for the loader"}')
    echo "$output" | jq -e .
    [[ "$output" != *"MUST call the Skill tool"* ]]
    [[ "$output" == *"Read"* ]]
    [[ "$output" == *".claude/skills/third-party/unitask/SKILL.md"* ]]
}

@test "a flat plugin reference file (plugins/<name>.md) gets a Read pointer" {
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude/skills/plugins"
    echo '# PrimeTween' > "$CLAUDE_PROJECT_DIR/.claude/skills/plugins/primetween.md"
    output=$(bash "$HOOK" 2>/dev/null <<< '{"prompt":"animate with primetween"}')
    [[ "$output" != *"MUST call the Skill tool"* ]]
    [[ "$output" == *".claude/skills/plugins/primetween.md"* ]]
}

@test "an invoked skill is not demanded again" {
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude/skills/unitask"
    echo '# UniTask' > "$CLAUDE_PROJECT_DIR/.claude/skills/unitask/SKILL.md"
    echo unitask > "$UNITY_HOOK_STATE_DIR/skills-invoked.txt"
    run bash "$HOOK" <<< '{"prompt":"use unitask for the loader"}'
    [ -z "$output" ]
}

@test "a mapping with no skill file anywhere is skipped silently on stdout" {
    output=$(bash "$HOOK" 2>/dev/null <<< '{"prompt":"use unitask for the loader"}')
    [ -z "$output" ]   # stdout only — the skip note goes to stderr by design
}
