#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-no-runtime-instantiate.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks new GameObject() in runtime code" {
    local f="$TMPDIR_TEST/Spawner.cs"
    echo 'void S(){ var go = new GameObject("Enemy"); }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Instantiate(prefab)" {
    local f="$TMPDIR_TEST/Spawner.cs"
    echo 'void S(){ var go = Instantiate(_prefab, transform); }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skips Editor tooling that uses new GameObject()" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Editor"
    local f="$TMPDIR_TEST/Assets/Scripts/Editor/LevelEditorWindow.cs"
    echo 'void S(){ var go = new GameObject("Preview"); }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skips third-party Plugins code" {
    mkdir -p "$TMPDIR_TEST/Assets/Plugins/UniRx/Scripts"
    local f="$TMPDIR_TEST/Assets/Plugins/UniRx/Scripts/MainThreadDispatcher.cs"
    echo 'void S(){ var go = new GameObject("Dispatcher"); }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
