#!/usr/bin/env bats
# The hook only enforces ordering when the Codex CLI is on PATH. Tests that need
# the enforced path prepend a fake `codex` executable to PATH (keeping the rest
# of PATH so jq/git still resolve). The codex-reviewed marker lives in
# UNITY_HOOK_STATE_DIR (set per-test).

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-reviewer-order.sh"
    FAKEBIN="$(mktemp -d)"
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/codex"
    chmod +x "$FAKEBIN/codex"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$FAKEBIN"
}

@test "allows non-Agent tool calls" {
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows a non-reviewer agent (coder)" {
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks unity-reviewer when Codex is available but has not reviewed" {
    rm -f "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    PATH="$FAKEBIN:$PATH" run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows unity-reviewer when Codex has already reviewed (marker present)" {
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    PATH="$FAKEBIN:$PATH" run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
