#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/agent-stop-log.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

_run_hook() {
    local agent_type="$1"
    echo "{\"tool_name\":\"Agent\",\"tool_input\":{\"subagent_type\":\"${agent_type}\",\"description\":\"test\"},\"session_id\":\"s1\"}" \
        | bash $HOOK
}

@test "committer stop deletes gate-cleared" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run _run_hook "committer"
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "non-committer stop does not delete gate-cleared" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run _run_hook "unity-coder"
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "committer stop is safe when gate-cleared is already absent" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run _run_hook "committer"
    [ "$status" -eq 0 ]
}

@test "committer stop writes subagent-log entry" {
    run _run_hook "committer"
    [ "$status" -eq 0 ]
    [ -f "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl" ]
    grep -q "SubagentStop" "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}
