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

@test "allows justified MonoBehaviour with [SerializeField] (structural)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Shop"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Shop/ShopManager.cs"
    printf 'using UnityEngine;\npublic class ShopManager : MonoBehaviour {\n    [SerializeField] private int _slots;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows justified MonoBehaviour with a Unity lifecycle callback (structural)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Spawning"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Spawning/SpawnDirector.cs"
    printf 'using UnityEngine;\npublic class SpawnDirector : MonoBehaviour {\n    private void Update() {}\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks unjustified pure-C# class leaking UnityEngine (non-whitelisted name)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring/ScoreCalculator.cs"
    printf 'using UnityEngine;\npublic sealed class ScoreCalculator {\n    public int Total;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Handler with Unity ctor ref (Handler name exemption survives)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Players"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Players/MoveHandler.cs"
    printf 'using UnityEngine;\npublic sealed class MoveHandler {\n    public MoveHandler(Rigidbody rb) {}\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks runtime *Inspector.cs outside Editor/ folder (old name-escape removed)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/CustomAudioInspector.cs"
    printf 'using UnityEngine;\npublic sealed class CustomAudioInspector {\n    public int Value;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
