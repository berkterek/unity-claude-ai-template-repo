#!/usr/bin/env bats
# gateguard runs only at the 'strict' profile, so block-path tests set
# UNITY_HOOK_PROFILE=strict; the default-profile test confirms it is skipped.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/gateguard.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "fact-gate: first Write of a new C# file is denied" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "fact-gate: second attempt on the same file is allowed" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "non-C# files are not gated" {
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPDIR_TEST/data.json\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skipped at standard profile (strict-level hook)" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=standard run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
