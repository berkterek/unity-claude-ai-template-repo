#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-input-system.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks Input.GetKey usage" {
    local f="$TMPDIR_TEST/PlayerInputView.cs"
    echo "if (Input.GetKey(KeyCode.Space)) Jump();" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks Input.GetAxis usage" {
    local f="$TMPDIR_TEST/PlayerInputView.cs"
    echo "float h = Input.GetAxis(\"Horizontal\");" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows new Input System usage" {
    local f="$TMPDIR_TEST/PlayerInputView.cs"
    echo "_controls.Player.Jump.performed += OnJump;" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips legacy input check (standard level)" {
    local f="$TMPDIR_TEST/PlayerInputView.cs"
    echo "if (Input.GetKey(KeyCode.Space)) Jump();" > "$f"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    local f="$TMPDIR_TEST/PlayerInputView.cs"
    echo "if (Input.GetKey(KeyCode.Space)) Jump();" > "$f"
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
