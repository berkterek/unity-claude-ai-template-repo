#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-no-monobehaviour-in-services.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks using UnityEngine in a pure-C# service" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    printf 'using UnityEngine;\npublic sealed class AudioService : IAudioService {}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Installer (VContainer ModuleInstaller needs UnityEngine)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioInstaller.cs"
    printf 'using UnityEngine;\npublic sealed class AudioInstaller : ModuleInstaller {}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows LifetimeScope subclass (Scope whitelist)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Infrastructure"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Infrastructure/ProjectLifetimeScope.cs"
    printf 'using UnityEngine;\npublic sealed class ProjectLifetimeScope : LifetimeScope {}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skips Editors/ folder editor code (Editors with trailing s)" {
    mkdir -p "$TMPDIR_TEST/Assets/_Framework/Editors"
    local f="$TMPDIR_TEST/Assets/_Framework/Editors/LogDumpOnStop.cs"
    printf 'using UnityEngine;\nusing UnityEditor;\npublic class LogDumpOnStop {}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
