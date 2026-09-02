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
