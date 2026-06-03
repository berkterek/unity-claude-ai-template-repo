#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/block-git-push.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks git push" {
    run bash -c "echo '{\"tool_input\":{\"command\":\"git push origin main\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "blocks git push with options" {
    run bash -c "echo '{\"tool_input\":{\"command\":\"git push --force-with-lease\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows regular git commands" {
    run bash -c "echo '{\"tool_input\":{\"command\":\"git commit -m test\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile still blocks git push" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"command\":\"git push\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "DISABLE_UNITY_HOOKS=1 skips the hook" {
    DISABLE_UNITY_HOOKS=1 run bash -c "echo '{\"tool_input\":{\"command\":\"git push\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
