#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-vcontainer-singleton.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    mkdir -p "$TMPDIR_TEST/_Framework/Events"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks static Instance singleton pattern" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows EventBusAccessor (approved exception)" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBusAccessor.cs"
    echo 'private static IEventBus _instance;' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-singleton static readonly" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'private static readonly int JumpHash = Animator.StringToHash("Jump");' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips singleton check (standard level)" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades singleton block to warning" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
