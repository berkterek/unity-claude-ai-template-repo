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

# --- TTL. Added with the 2026-10-04 fix that stopped session-save.sh deleting the
# marker at every turn-end. Removing that deletion without an expiry would have
# swapped a marker that lived <1 turn for one that lived forever — the exact pair
# of failure modes sparc-approved went through. These two pin both ends.

@test "blocks unity-reviewer when the marker is older than the TTL" {
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    # Backdate well past the default 2700s TTL.
    python3 -c "import os; os.utime('$UNITY_HOOK_STATE_DIR/codex-reviewed', (1, 1))"
    PATH="$FAKEBIN:$PATH" run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"expired"* ]]
}

# Backdated INSIDE the window rather than by overriding the TTL: _lib.sh:438 sets
# `UNITY_GATE_TTL=2700` unconditionally, not `${UNITY_GATE_TTL:-2700}`, so no env
# value reaches it. A first draft of this test passed UNITY_GATE_TTL=99999999999
# and failed — correctly, because the variable is not an input. Do not "fix" that
# by making _lib.sh honour an override: the TTL is shared by every deny-then-allow
# gate, and a per-run override is a bypass for all of them at once.
#
# A second trap this avoids: the env assignment must go INSIDE the bash -c string.
# `run` is a bats shell function, and a `VAR=x` prefix on a function call sets the
# variable without exporting it, so the `bash $HOOK` child never sees it.
@test "allows unity-reviewer when the marker is recent but not brand new" {
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    python3 -c "
import os, time
t = time.time() - 600          # 10 minutes old — well inside the 2700s TTL
os.utime('$UNITY_HOOK_STATE_DIR/codex-reviewed', (t, t))
"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | PATH=\"$FAKEBIN:\$PATH\" bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- Pipeline-pass bound. Independent of the TTL: a second pipeline can start
# well inside the TTL window, and a marker from the previous one must not release
# its reviewer.

@test "blocks unity-reviewer when gate-cleared is newer than the marker" {
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    sleep 1
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    PATH="$FAKEBIN:$PATH" run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"stale"* ]]
}

@test "allows unity-reviewer when the marker is newer than gate-cleared" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    sleep 1
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    PATH="$FAKEBIN:$PATH" run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- The hook is only an ordering guard. With no Codex CLI on PATH, unity-reviewer
# is the primary reviewer and nothing about the marker applies.
#
# This needs a PATH with no `codex` on it, which the default PATH on a developer
# machine does not give you — codex ships to /opt/homebrew/bin here. So the PATH is
# rebuilt from the two directories the hook actually needs (jq, python3) and nothing
# else. Writing this test with the inherited PATH would have exercised the enforced
# branch and quietly asserted the opposite of its own name.
@test "allows unity-reviewer with no marker when Codex is not installed" {
    rm -f "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    local minimal_path="/usr/bin:/bin:$(dirname "$(command -v python3)")"
    PATH="$minimal_path" command -v codex >/dev/null && skip "codex is reachable from the minimal PATH"
    run bash -c "echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\"}}' | PATH=\"$minimal_path\" bash $HOOK"
    [ "$status" -eq 0 ]
}
