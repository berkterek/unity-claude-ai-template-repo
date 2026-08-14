#!/usr/bin/env bats
# The depth counter this hook reads LEAKS (see agent-start-log.sh). These tests
# pin the resolution direction: for THIS hook a doubtful count must resolve toward
# ENFORCING, i.e. be read as 0. gateguard.sh and check-config-protection.sh pin the
# opposite direction, because there 0 is the permissive value.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-pipeline-direct-work.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"   # a gate is open in every test
    EDIT_PAYLOAD='{"tool_name":"Write","tool_input":{"file_path":"_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs"}}'
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks a direct script edit while a gate is open and no agent runs" {
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows the edit while a subagent is genuinely running" {
    echo 1 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "a STALE depth count is read as 0, so the hook enforces again" {
    # A leaked count made this hook exit 0 forever — blocking downgraded to a no-op
    # with nothing on screen to say so. Measured in a derived project: the counter
    # sat at 12 while no agent ran.
    local depth="$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo 12 > "$depth"
    touch -t 200001010000 "$depth"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "a FRESH non-zero depth is still trusted — staleness must not block real agents" {
    local depth="$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo 2 > "$depth"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "no open gate means nothing to guard, whatever the depth is" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks a direct git commit while a gate is open" {
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m wip\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "the pipeline-override valve is consumed once and then allows through" {
    echo 0 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    echo "user approved skipping the pipeline for this one-line fix" > "$UNITY_HOOK_STATE_DIR/pipeline-override"
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/pipeline-override" ]   # consumed, not reusable
    run bash -c "echo '$EDIT_PAYLOAD' | bash $HOOK"
    [ "$status" -eq 2 ]
}
