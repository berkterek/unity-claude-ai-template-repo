#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-config-protection.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks edits to settings.json" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks edits to .asmdef files outside test folders" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/GameAssembly.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows edits to test assembly .asmdef files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Tests/EditModeTest/MyProject.EditModeTest.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows edits to regular .cs files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile still blocks settings.json (minimal level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
