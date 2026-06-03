#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/block-scene-edit.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks edits to .unity files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scenes/Game.unity\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks edits to .prefab files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Prefabs/Player.prefab\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows edits to .cs files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/PlayerService.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile still blocks scene edits" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scenes/Main.unity\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scenes/Game.unity\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
