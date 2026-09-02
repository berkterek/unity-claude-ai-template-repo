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

# --- TTL: what replaced the per-turn deletion --------------------------------
# session-save.sh used to delete sparc-approved on every turn-end, which was the
# only thing bounding it — and it forced re-approval once per turn on a multi-turn
# phase. The deletion is gone; these pin the bound that replaced it.

@test "a fresh approval passes" {
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "an approval older than the TTL blocks, and says it expired" {
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    python3 -c "import os,time;f='$UNITY_HOOK_STATE_DIR/sparc-approved';t=time.time()-2760;os.utime(f,(t,t))"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"expired"* ]]
}

@test "an approval just inside the TTL still passes" {
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    python3 -c "import os,time;f='$UNITY_HOOK_STATE_DIR/sparc-approved';t=time.time()-2600;os.utime(f,(t,t))"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "the block exit code is 2, never the helper's own return value" {
    # set -euo pipefail: without `|| true` on the helper call the script aborts with
    # ITS status (1 absent, 3 stale). A hook that exits 1 only warns, so that bug
    # would have silently disabled the gate rather than announcing itself.
    rm -f "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
