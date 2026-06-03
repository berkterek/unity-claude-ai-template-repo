#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-unity-event.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks UnityEvent field declaration" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/UI/ButtonView.cs\",\"content\":\"[SerializeField] private UnityEvent _onClick;\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks using UnityEngine.Events" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/UI/ButtonView.cs\",\"content\":\"using UnityEngine.Events;\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Button.onClick in code (approved exception)" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/UI/ButtonView.cs\",\"content\":\"_button.onClick.AddListener(OnClicked);\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips unity-event check (standard level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/UI/ButtonView.cs\",\"content\":\"[SerializeField] private UnityEvent _onClick;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/UI/ButtonView.cs\",\"content\":\"[SerializeField] private UnityEvent _onClick;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
