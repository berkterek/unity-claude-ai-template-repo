#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "minimal profile skips a strict-level hook body" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=minimal run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="strict"
        source "$SCRIPT_DIR/_lib.sh"
        echo "should not reach here"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"should not reach here"* ]]
}

@test "minimal profile skips a standard-level hook body" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=minimal run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="standard"
        source "$SCRIPT_DIR/_lib.sh"
        echo "should not reach here"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"should not reach here"* ]]
}

@test "standard profile runs a standard-level hook body" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=standard run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="standard"
        source "$SCRIPT_DIR/_lib.sh"
        echo "reached"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached"* ]]
}

@test "strict profile runs a standard-level hook body" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_PROFILE=strict run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="standard"
        source "$SCRIPT_DIR/_lib.sh"
        echo "reached"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached"* ]]
}

@test "DISABLE_UNITY_HOOKS=1 short-circuits the lib" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    DISABLE_UNITY_HOOKS=1 run bash -c '
        SCRIPT_DIR=".claude/hooks"
        HOOK_PROFILE_LEVEL="standard"
        source "$SCRIPT_DIR/_lib.sh"
        echo "should not reach"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"should not reach"* ]]
}

@test "UNITY_HOOK_MODE=warn allows check of downgrade behavior" {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | bash .claude/hooks/block-projectsettings.sh"
    [ "$status" -eq 0 ]
}
