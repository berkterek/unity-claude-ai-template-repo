#!/usr/bin/env bats
# agent-stop-log.bats — covers the deferred-decrement fix (2026-08-29).
#
# Root cause: in this harness PostToolUse:Agent fires on the Agent tool's async
# dispatch acknowledgement, not on the subagent's actual completion (measured:
# duration_approx_s of 1-3s vs a real usage.duration_ms of 45-54s for the same
# calls). Decrementing subagent-depth immediately at Stop time therefore read
# depth back to 0 while the subagent was still genuinely running, which is what
# let guard-pipeline-direct-work.sh block real coder/tester subagents mid-Write.
# The fix defers the decrement by UNITY_SUBAGENT_STOP_GRACE_SECONDS, anchored on
# the matched Start timestamp, applied lazily by unity_subagent_depth().

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

@test "Stop does NOT decrement immediately under the default grace window" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"T2.1"},"session_id":"s1"}' \
        | "$HOOK"
    [ "$(_read_depth)" = "1" ]
}

@test "Stop schedules a decrement that applies once the grace window elapses" {
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"T2.1"},"session_id":"s1"}' \
        | "$HOOK"
    [ "$(_read_depth)" = "0" ]
}

@test "an unmatched Stop (no prior Start logged) still schedules a decrement, anchored on stop time" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"never-started"},"session_id":"s1"}' \
        | "$HOOK"
    [ "$(_read_depth)" = "0" ]
}

@test "depth never goes negative even with multiple matured pending decrements" {
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    export UNITY_SUBAGENT_STOP_GRACE_SECONDS=0
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"a"},"session_id":"s1"}' | "$HOOK"
    echo '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","description":"b"},"session_id":"s1"}' | "$HOOK"
    [ "$(_read_depth)" = "0" ]
}

@test "non-Agent tool calls are ignored and touch no depth state" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo '{"tool_name":"Write","tool_input":{},"session_id":"s1"}' | "$HOOK"
    [ "$(_read_depth)" = "1" ]
    [ ! -f "$UNITY_HOOK_STATE_DIR/subagent-depth-pending.jsonl" ]
}
