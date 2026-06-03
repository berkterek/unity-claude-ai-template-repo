#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/block-projectsettings.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks edits to ProjectSettings/EditorSettings.asset" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
}

@test "allows edits to regular .cs files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Game/Foo.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks edits to Packages/manifest.json" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Packages/manifest.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks edits to Packages/packages-lock.json" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Packages/packages-lock.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (downgraded from BLOCKED)"* ]]
}

@test "minimal profile still runs (block-projectsettings is minimal level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"ProjectSettings/EditorSettings.asset\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
