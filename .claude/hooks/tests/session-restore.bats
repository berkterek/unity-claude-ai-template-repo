#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/session-restore.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    # Safety net: the self-heal test intentionally strips an exec bit. If an
    # assertion fails mid-test, restore it so the working tree is never left dirty.
    chmod +x .claude/hooks/check-time-scale.sh 2>/dev/null || true
}

@test "session-restore deletes gate-cleared on session start" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "session-restore is safe when gate-cleared is already absent" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
}

@test "session-restore writes session-start-time" {
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ -f "$UNITY_HOOK_STATE_DIR/session-start-time" ]
}

@test "session-restore self-heals a hook missing its exec bit" {
    local target=".claude/hooks/check-time-scale.sh"
    chmod 644 "$target"
    [ ! -x "$target" ]              # precondition: bit is gone
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ -x "$target" ]               # session-restore restored it
}
