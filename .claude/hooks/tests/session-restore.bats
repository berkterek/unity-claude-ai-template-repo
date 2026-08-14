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

@test "session-restore resets a leaked subagent-depth counter to 0" {
    # The counter is monotonic, not self-healing: any spawn whose PostToolUse Stop
    # never fires leaves it high forever, and a high count makes
    # guard-pipeline-direct-work.sh exit 0 — a blocking hook silently no-op'd.
    echo 12 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNITY_HOOK_STATE_DIR/subagent-depth")" -eq 0 ]
}

@test "session-restore expires every deny-then-allow grant" {
    # Without this a file waved through once was waved through forever: the gates
    # became one-per-file-per-lifetime instead of one-per-session.
    for f in gateguard-facts-passed gateguard-facts-denied \
             guard-critical-passed guard-critical-denied \
             config-asmdef-passed config-asmdef-denied; do
        echo "/some/File.cs" > "$UNITY_HOOK_STATE_DIR/${f}.txt"
    done
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    for f in gateguard-facts-passed gateguard-facts-denied \
             guard-critical-passed guard-critical-denied \
             config-asmdef-passed config-asmdef-denied; do
        [ ! -e "$UNITY_HOOK_STATE_DIR/${f}.txt" ]
    done
}

@test "session-restore self-heals a hook missing its exec bit" {
    local target=".claude/hooks/check-time-scale.sh"
    chmod 644 "$target"
    [ ! -x "$target" ]              # precondition: bit is gone
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ -x "$target" ]               # session-restore restored it
}
