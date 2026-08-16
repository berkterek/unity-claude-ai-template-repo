#!/usr/bin/env bats
#
# track-codex-review.sh writes the marker guard-reviewer-order.sh reads.
# The two must agree on WHERE, and the only way they can is the absolute
# $UNITY_HOOK_STATE_DIR — a hook's cwd is whatever the tool call ran in, which
# for a subagent is not the repo root.
#
# NOTE on bats 1.13: a `[[ ]]` assertion that is not the LAST statement of an
# @test body does not fail the test. Every assertion here is `[ ]`/`test`,
# a simple command, which propagates failure from any position.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPCWD="$(mktemp -d)"
    HOOK="$BATS_TEST_DIRNAME/../track-codex-review.sh"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPCWD"
}

codex_payload() {
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"codex:codex-rescue"}}'
}

@test "marker lands in UNITY_HOOK_STATE_DIR, not in the hook's cwd" {
    cd "$TMPCWD" || return 1
    run bash -c "$(declare -f codex_payload); codex_payload | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash '$HOOK'"
    [ "$status" -eq 0 ]
    # The reader (guard-reviewer-order.sh) looks exactly here.
    [ -f "$UNITY_HOOK_STATE_DIR/codex-reviewed" ]
    # A relative write would have created this instead — nothing may appear here.
    [ ! -e "$TMPCWD/.claude" ]
}

@test "guard-reviewer-order.sh sees the marker this hook just wrote" {
    cd "$TMPCWD" || return 1
    run bash -c "$(declare -f codex_payload); codex_payload | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash '$HOOK'"
    [ "$status" -eq 0 ]

    # End-to-end: writer then reader, same state dir, unity-reviewer must pass.
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash '$BATS_TEST_DIRNAME/../guard-reviewer-order.sh' 2>&1"
    [ "$status" -eq 0 ]
}

@test "non-codex agents write no marker" {
    cd "$TMPCWD" || return 1
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-coder\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -f "$UNITY_HOOK_STATE_DIR/codex-reviewed" ]
}

@test "non-Agent tools write no marker" {
    cd "$TMPCWD" || return 1
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"x.cs\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -f "$UNITY_HOOK_STATE_DIR/codex-reviewed" ]
}
