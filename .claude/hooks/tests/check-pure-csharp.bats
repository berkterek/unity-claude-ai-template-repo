#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-pure-csharp.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMP_FILE="$(mktemp /tmp/test_XXXXXX.cs)"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    rm -f "$TMP_FILE"
}

@test "blocks UnityEngine import in _Framework file" {
    echo 'using UnityEngine; namespace Framework.Events {}' > "$TMP_FILE"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"_Framework/Events/EventBus.cs\",\"content\":\"using UnityEngine;\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows UnityEngine in Games/Concretes Provider" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioProvider.cs\",\"content\":\"using UnityEngine;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips check-pure-csharp (standard level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"_Framework/Events/EventBus.cs\",\"content\":\"using UnityEngine;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "standard profile runs check-pure-csharp" {
    UNITY_HOOK_PROFILE=standard run bash -c "echo '{\"tool_input\":{\"file_path\":\"_Framework/Events/EventBus.cs\",\"content\":\"using UnityEngine;\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "DISABLE_UNITY_HOOKS=1 skips the hook" {
    DISABLE_UNITY_HOOKS=1 run bash -c "echo '{\"tool_input\":{\"file_path\":\"_Framework/Events/EventBus.cs\",\"content\":\"using UnityEngine;\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
