#!/usr/bin/env bats
# subagent-stop-settle.bats — the depth counter's real completion signal (2026-11-19).
#
# agent-start-log.sh increments and queues a fallback decrement at Start + grace;
# SubagentStop consumes that fallback and decrements at once. The bug this replaces:
# the decrement fired at Start + 180s whatever the subagent was doing, so every coder
# running longer than 3 minutes had its writes blocked (word-soda module 04).

setup() {
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$PWD"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

_start() {   # $1 description, $2 agent type
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"${2:-coder}\",\"description\":\"$1\"},\"session_id\":\"S1\"}" \
        | bash .claude/hooks/agent-start-log.sh >/dev/null 2>&1
}
_dispatch_ack() {   # PostToolUse:Agent — fires right after Start for a background agent
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"coder\",\"description\":\"$1\"},\"session_id\":\"S1\"}" \
        | bash .claude/hooks/agent-stop-log.sh >/dev/null 2>&1
}
_finish() {   # SubagentStop — $1 agent type, or omitted
    if [ -n "${1:-}" ]; then
        echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"S1\",\"agent_type\":\"$1\"}"
    else
        echo '{"hook_event_name":"SubagentStop","session_id":"S1"}'
    fi | bash .claude/hooks/subagent-stop-settle.sh >/dev/null 2>&1
}
_depth() { bash -c 'source .claude/hooks/_lib.sh; unity_subagent_depth'; }

@test "a running background agent keeps depth 1 after its dispatch ack" {
    _start "T053 coder"
    _dispatch_ack "T053 coder"
    [ "$(_depth)" -eq 1 ]
}

@test "SubagentStop brings depth back to 0 at once, long before the fallback" {
    _start "T053 coder"
    _dispatch_ack "T053 coder"
    _finish coder
    [ "$(_depth)" -eq 0 ]
}

@test "the fallback decrements on its own when SubagentStop never arrives" {
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    _start "T053 coder"
    [ "$(_depth)" -eq 0 ]
}

@test "a SubagentStop after its own fallback matured does not decrement twice" {
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    _start "a"                       # +1, fallback already due
    _finish coder                    # the due entry is not consumable here
    [ "$(_depth)" -eq 0 ]            # one decrement in total, from the fallback
    grep -q '"settled":false' "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}

@test "two parallel agents: one finishing leaves the other counted" {
    _start "T053 coder"
    _start "T054 coder"
    _finish coder
    [ "$(_depth)" -eq 1 ]
    _finish coder
    [ "$(_depth)" -eq 0 ]
}

@test "the matching agent type is settled first" {
    _start "T053 coder" coder
    _start "T064 tester" tester
    _finish tester
    # the coder's fallback must still be open
    run jq -s '[.[] | select(.agent_type == "coder")] | length' "$UNITY_HOOK_STATE_DIR/subagent-depth-pending.jsonl"
    [ "$output" -eq 1 ]
}

@test "a SubagentStop with nothing counted (SendMessage resume) changes nothing" {
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    _finish coder
    [ "$(_depth)" -eq 0 ]
    grep -q '"settled":false' "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}

@test "every SubagentStop is logged with its payload keys for the measurement" {
    _start "T053 coder"
    _finish coder
    grep -q '"SubagentFinished"' "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
    grep -q '"payload_keys"' "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}
