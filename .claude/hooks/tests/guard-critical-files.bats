#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-critical-files.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks editing AppScope" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/AppScope.cs\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks editing an .asmdef" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Game.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks editing EventBus" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/EventBus.cs\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks editing an EXISTING Installer" {
    local f="$TMPDIR_TEST/AudioInstaller.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows creating a NEW Installer (file does not exist yet)" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$TMPDIR_TEST/NewModuleInstaller.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows a normal non-critical file" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/EnemyModel.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
