#!/usr/bin/env bats

setup() {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$PWD"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

# --- Retry window ------------------------------------------------------------
# Retry detection keys on session_id + description, which cannot distinguish the
# Agent tool's internal retry from a Director legitimately respawning with the same
# description. That false positive was measured in a real project: depth stayed 0,
# the subagent's own Write was blocked as "no pipeline subagent is running", and it
# cost two misdiagnoses. Time is what separates the two cases.

_start() {
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\",\"description\":\"$1\"},\"session_id\":\"S1\"}" \
        | bash .claude/hooks/agent-start-log.sh >/dev/null 2>&1
}
_depth() { cat "$UNITY_HOOK_STATE_DIR/subagent-depth" 2>/dev/null || echo 0; }
_age_log() {
    python3 -c "
import json,time,sys
p='$UNITY_HOOK_STATE_DIR/subagent-log.jsonl'
old=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-int(sys.argv[1])))
rows=[json.loads(l) for l in open(p)]
for r in rows: r['started_at']=old
open(p,'w').write('\n'.join(json.dumps(r) for r in rows)+'\n')" "$1"
}

@test "an immediate same-description Start is a retry and does not increment depth" {
    _start "build the thing"
    [ "$(_depth)" -eq 1 ]
    _start "build the thing"
    [ "$(_depth)" -eq 1 ]
}

@test "a same-description Start beyond the window is a respawn and DOES increment" {
    _start "build the thing"
    _age_log 1200
    _start "build the thing"
    [ "$(_depth)" -eq 2 ]
}

@test "a different description always increments" {
    _start "build the thing"
    _start "something else"
    [ "$(_depth)" -eq 2 ]
}

@test "the retry window is overridable for tests and tuning" {
    _start "x"
    _age_log 30
    UNITY_RETRY_WINDOW_SECONDS=10 _start "x"
    [ "$(_depth)" -eq 2 ]
}

# --- Denied spawns -----------------------------------------------------------
# This harness runs EVERY hook in a PreToolUse group even after one exits 2, so a
# blocked spawn still reaches agent-start-log.sh and still increments. Measured
# 2026-10-04: a unity-reviewer spawn blocked by guard-reviewer-order.sh took the
# counter 2 -> 3 with no agent running, and no PostToolUse Stop can ever match it
# because the Agent tool never ran. The guard therefore retracts its own increment
# through the pending queue (unity_subagent_note_spawn_denied).
#
# These tests drive the guard directly rather than mocking it: the whole point is
# that the retraction survives whatever order the two hooks actually run in.

_deny() {
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\",\"description\":\"$1\"},\"session_id\":\"S1\"}" \
        | PATH="$FAKEBIN:$PATH" bash .claude/hooks/guard-reviewer-order.sh >/dev/null 2>&1 || true
}
_start_reviewer() {
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"unity-reviewer\",\"description\":\"$1\"},\"session_id\":\"S1\"}" \
        | bash .claude/hooks/agent-start-log.sh >/dev/null 2>&1
}
# Reading the depth is what applies matured pending entries — there is no timer.
_depth_settled() { bash -c 'source .claude/hooks/_lib.sh; unity_subagent_depth' ; }

_fakebin() {
    FAKEBIN="$(mktemp -d)"
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/codex"
    chmod +x "$FAKEBIN/codex"
    export FAKEBIN
}

@test "a denied spawn nets to zero whichever order the two hooks run in" {
    _fakebin
    _deny "blocked work"
    _start_reviewer "blocked work"
    [ "$(_depth_settled)" -eq 0 ]

    # ...and the reverse order, which is the one registration order suggests.
    _start_reviewer "other blocked work"
    _deny "other blocked work"
    [ "$(_depth_settled)" -eq 0 ]
}

@test "two guards denying ONE spawn retract exactly one increment" {
    _fakebin
    _start_reviewer "doubly blocked"
    _deny "doubly blocked"
    _deny "doubly blocked"          # same session_id + description = same spawn
    [ "$(_depth_settled)" -eq 0 ]
}

@test "a denied spawn does not cancel a different agent that is really running" {
    _fakebin
    _start "real work"              # a coder that genuinely spawned
    _start_reviewer "blocked work"
    _deny "blocked work"
    [ "$(_depth_settled)" -eq 1 ]
}

@test "an allowed spawn is untouched — no retraction is queued" {
    _fakebin
    touch "$UNITY_HOOK_STATE_DIR/codex-reviewed"
    _deny "permitted work"          # guard exits 0 here, so nothing is queued
    _start_reviewer "permitted work"
    [ "$(_depth_settled)" -eq 1 ]
}

@test "the pending queue reads as empty once every decrement has applied" {
    _fakebin
    _start_reviewer "transient"
    _deny "transient"
    [ "$(_depth_settled)" -eq 0 ]
    # A lone newline left behind here would report one pending decrement forever.
    [ ! -s "$UNITY_HOOK_STATE_DIR/subagent-depth-pending.jsonl" ]
}
