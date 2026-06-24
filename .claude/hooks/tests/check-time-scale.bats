#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-time-scale.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks Time.timeScale assignment in runtime code" {
    local f="$TMPDIR_TEST/PauseController.cs"
    echo "void Pause(){ Time.timeScale = 0f; }" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows code that reads Time.timeScale" {
    local f="$TMPDIR_TEST/Reader.cs"
    echo "float t = Time.timeScale;" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skips Editor-only files" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Editor"
    local f="$TMPDIR_TEST/Assets/Scripts/Editor/PreviewTool.cs"
    echo "void Pause(){ Time.timeScale = 0f; }" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
