#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-vcontainer-singleton.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks static Instance singleton pattern" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\",\"content\":\"public static AudioService Instance { get; private set; }\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows EventBusAccessor (approved exception)" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"_Framework/Events/EventBusAccessor.cs\",\"content\":\"private static IEventBus _instance;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-singleton static readonly" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\",\"content\":\"private static readonly int JumpHash = Animator.StringToHash(Jump);\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips singleton check (standard level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\",\"content\":\"public static AudioService Instance { get; private set; }\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades singleton block to warning" {
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\",\"content\":\"public static AudioService Instance { get; private set; }\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
