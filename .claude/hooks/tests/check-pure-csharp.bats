#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-pure-csharp.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
    mkdir -p "$TMPDIR_TEST/_Framework/Events"
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks UnityEngine import in _Framework file" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBus.cs"
    echo 'using UnityEngine; namespace Framework.Events {}' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows UnityEngine in Games/Concretes Provider" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioProvider.cs"
    echo 'using UnityEngine; public class AudioProvider {}' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips check-pure-csharp (standard level)" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBus.cs"
    echo 'using UnityEngine; namespace Framework.Events {}' > "$f"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "standard profile runs check-pure-csharp" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBus.cs"
    echo 'using UnityEngine; namespace Framework.Events {}' > "$f"
    UNITY_HOOK_PROFILE=standard run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "DISABLE_UNITY_HOOKS=1 skips the hook" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBus.cs"
    echo 'using UnityEngine; namespace Framework.Events {}' > "$f"
    DISABLE_UNITY_HOOKS=1 run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
