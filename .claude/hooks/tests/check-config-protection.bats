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

@test "blocks edits to EXISTING .asmdef files outside test folders" {
    EXISTING="${UNITY_HOOK_STATE_DIR}/GameAssembly.asmdef"
    echo '{}' > "$EXISTING"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows CREATING a new .asmdef — no existing boundary to break" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"${UNITY_HOOK_STATE_DIR}/Brand.New.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
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
