#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-sparc-approved.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks coder spawn when sparc-approved is missing" {
    rm -f "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks unity-coder spawn when sparc-approved is missing" {
    rm -f "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows coder spawn when sparc-approved exists" {
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows a non-gated agent (reviewer) without sparc-approved" {
    rm -f "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-Agent tool calls" {
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"Foo.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
