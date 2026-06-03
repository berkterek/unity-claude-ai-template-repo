#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-unity-event.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks UnityEvent field declaration" {
    local f="$TMPDIR_TEST/ButtonView.cs"
    echo '[SerializeField] private UnityEvent _onClick;' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks using UnityEngine.Events" {
    local f="$TMPDIR_TEST/ButtonView.cs"
    echo 'using UnityEngine.Events;' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Button.onClick in code (approved exception)" {
    local f="$TMPDIR_TEST/ButtonView.cs"
    echo '_button.onClick.AddListener(OnClicked);' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips unity-event check (standard level)" {
    local f="$TMPDIR_TEST/ButtonView.cs"
    echo '[SerializeField] private UnityEvent _onClick;' > "$f"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    local f="$TMPDIR_TEST/ButtonView.cs"
    echo '[SerializeField] private UnityEvent _onClick;' > "$f"
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
