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

# agent-stop-log.sh was named here as a gate-lifecycle owner. It no longer touches gate
# state at all (see agent-stop-log.bats), so the owners are the pipeline step that opened
# the gate, the 45-minute TTL, and session-restore.sh at SessionStart.
@test "session-save preserves gate-cleared (lifecycle owned by the opening pipeline and session-restore)" {
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

# Reversed 2026-09-02, deliberately. This test asserted the bug: Stop fires after
# every Claude turn, so expiring a HUMAN-approval gate here forced a multi-turn phase
# to re-open SPARC_GATE once per turn — measured in a real project. sparc-approved is
# the same class as gate-cleared, which was excluded from this list from the start.
# The bound that replaced the deletion is a TTL in guard-sparc-approved.sh plus a
# SessionStart clear in session-restore.sh; both are asserted in their own suites.
@test "session-save does NOT expire sparc-approved — it is a human-approval gate" {
    touch "$UNITY_HOOK_STATE_DIR/sparc-approved"
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/sparc-approved" ]
}

@test "session-save does NOT expire gate-cleared either — same class, same reason" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash .claude/hooks/session-save.sh < /dev/null
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
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
