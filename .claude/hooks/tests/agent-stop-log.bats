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

# This used to assert the opposite — that a committer stop DELETES gate-cleared.
# That behaviour was removed: it assumed committer is always the final pipeline step,
# and /orchestrate commits after every phase and then continues, so the deletion tore
# the gate down mid-pipeline. The assertion is inverted rather than deleted, so the rm
# cannot come back unnoticed. Rationale: CLAUDE.md → Subagent Lifecycle Hooks.
@test "committer stop does NOT delete gate-cleared (gate lifecycle is not this hook's)" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run _run_hook "committer"
    [ "$status" -eq 0 ]
    [ -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
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
    [ ! -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "committer stop writes subagent-log entry" {
    run _run_hook "committer"
    [ "$status" -eq 0 ]
    [ -f "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl" ]
    grep -q "SubagentStop" "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
}
