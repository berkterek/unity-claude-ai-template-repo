#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-input-system.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks Input.GetKey usage" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Player/PlayerInputView.cs\",\"content\":\"if (Input.GetKey(KeyCode.Space)) Jump();\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks Input.GetAxis usage" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Player/PlayerInputView.cs\",\"content\":\"float h = Input.GetAxis(Horizontal);\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows new Input System usage" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Player/PlayerInputView.cs\",\"content\":\"_controls.Player.Jump.performed += OnJump;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips legacy input check (standard level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Player/PlayerInputView.cs\",\"content\":\"if (Input.GetKey(KeyCode.Space)) Jump();\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Player/PlayerInputView.cs\",\"content\":\"if (Input.GetKey(KeyCode.Space)) Jump();\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
