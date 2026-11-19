#!/usr/bin/env bats
# agent-stop-log.bats — PostToolUse:Agent is audit-only since 2026-11-19.
#
# It fires on the Agent tool's dispatch acknowledgement for background agents, not on
# completion. Using it as the decrement signal — immediately (2026-08-29), then at
# Start + 180s — read depth 0 while real subagents were still writing. The decrement
# now lives in subagent-stop-settle.sh (SubagentStop) with a fallback queued at Start.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
    HOOK="${CLAUDE_PROJECT_DIR}/.claude/hooks/agent-stop-log.sh"
    LIBSH="${CLAUDE_PROJECT_DIR}/.claude/hooks/_lib.sh"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

_read_depth() {
    bash -c "source '$LIBSH' >/dev/null 2>&1; unity_subagent_depth"
}

@test "Stop never decrements, even with a zero fallback window" {
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"T2.1"},"session_id":"s1"}' \
        | "$HOOK"
    [ "$(_read_depth)" = "1" ]
}

@test "Stop queues nothing on the pending queue" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"T2.1"},"session_id":"s1"}' \
        | "$HOOK"
    [ ! -s "$UNITY_HOOK_STATE_DIR/subagent-depth-pending.jsonl" ]
}

@test "Stop still writes its audit line" {
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"T2.1"},"session_id":"s1"}' \
        | "$HOOK"
    grep -q '"SubagentStop"' "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}

@test "non-Agent tool calls are ignored and touch no depth state" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Write","tool_input":{},"session_id":"s1"}' | "$HOOK"
    [ "$(_read_depth)" = "1" ]
    [ ! -f "$UNITY_HOOK_STATE_DIR/subagent-depth-pending.jsonl" ]
}
