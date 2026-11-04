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

@test "skips third-party Plugins code with legacy Input" {
    mkdir -p "$TMPDIR_TEST/Assets/Plugins/UniRx/Examples"
    local f="$TMPDIR_TEST/Assets/Plugins/UniRx/Examples/Sample.cs"
    echo "if (Input.GetKey(KeyCode.Space)) Jump();" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "warns on an input read inside FixedUpdate" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf '%s\n' "private void FixedUpdate()" "{" "    var move = _controls.Player.Move.ReadValue<Vector2>();" "}" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inside FixedUpdate"* ]]
}

@test "a 3000-line file with no FixedUpdate finishes inside the 5s hook limit" {
    # Regression: the FixedUpdate scan spawned greps per line (~1.5ms/line) even when the
    # file had no FixedUpdate. alarm 5 kills a slow run (exit 142).
    local f="$TMPDIR_TEST/BoardService.cs"
    for i in $(seq 1 3000); do echo "    public int M$i(int x) { return x + $i; }"; done > "$f"
    run perl -e 'alarm 5; exec @ARGV' bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
