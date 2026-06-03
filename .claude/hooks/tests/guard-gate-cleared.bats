#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-gate-cleared.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks agent spawn when gate-cleared is missing" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows agent spawn when gate-cleared exists" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-agent tool calls without gate-cleared" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash -c "echo '{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips gate check (standard level)" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks committer agent when gate-cleared is missing" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"committer\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
