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

@test "gate-cleared file path is absolute (UNITY_HOOK_STATE_DIR, not relative .claude/state)" {
    # If guard uses a relative path, it fails when CWD != project root.
    # Run from /tmp to prove the hook resolves state dir via absolute UNITY_HOOK_STATE_DIR.
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    local abs_hook
    abs_hook="$(pwd)/${HOOK}"
    local state_dir="$UNITY_HOOK_STATE_DIR"
    run bash -c "cd /tmp && echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | UNITY_HOOK_STATE_DIR=${state_dir} bash ${abs_hook}"
    [ "$status" -eq 0 ]
}

@test "blocks agent spawn when gate-cleared is older than TTL (46 min)" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    # Back-date the file by 2761 seconds (46 min) using python
    python3 -c "import os,time; p='$UNITY_HOOK_STATE_DIR/gate-cleared'; os.utime(p,(time.time()-2761,time.time()-2761))"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows agent spawn when gate-cleared is within TTL (5 min old)" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    # Back-date by 300 seconds (5 min) — well within the 2700s TTL
    python3 -c "import os,time; p='$UNITY_HOOK_STATE_DIR/gate-cleared'; os.utime(p,(time.time()-300,time.time()-300))"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
