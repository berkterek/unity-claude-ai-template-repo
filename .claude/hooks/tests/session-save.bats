#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    touch "$UNITY_HOOK_STATE_DIR/graph-empty-warned"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "session-save preserves gate-cleared (lifecycle managed by agent-stop-log and session-restore)" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "session-save auto-expires sparc-approved" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/sparc-approved" ]
}

@test "session-save auto-expires codex-reviewed" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/codex-reviewed" ]
}

@test "session-save auto-expires graph-empty-warned" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/graph-empty-warned" ]
}

@test "session-save exits 0 when no gate files exist" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared" \
          "$UNITY_HOOK_STATE_DIR/sparc-approved" \
          "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
}
