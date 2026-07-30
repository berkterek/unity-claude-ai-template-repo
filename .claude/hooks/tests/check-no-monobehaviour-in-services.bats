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

@test "blocks real Unity engine API (AudioSource) in a pure-C# service" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    printf 'using UnityEngine;\npublic sealed class AudioService : IAudioService {\n    private AudioSource _source;\n}\n' > "$f"
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

@test "blocks pure-C# class leaking real Unity API (Transform, non-whitelisted name)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring/ScoreCalculator.cs"
    printf 'using UnityEngine;\npublic sealed class ScoreCalculator {\n    private Transform _t;\n}\n' > "$f"
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

@test "blocks runtime *Inspector.cs leaking real Unity API outside Editor/ folder" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/CustomAudioInspector.cs"
    printf 'using UnityEngine;\npublic sealed class CustomAudioInspector {\n    private GameObject _target;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

# --- math-type + Debug allow-list (check-no-monobehaviour-in-services.sh Check 3) ---

@test "allows service using only Mathf/Vector3 math value types" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring/ScoreService.cs"
    printf 'using UnityEngine;\npublic sealed class ScoreService : IScoreService {\n    public int Clamp(int v) => Mathf.Clamp(v, 0, 100);\n    public Vector3 Offset() => Vector3.forward;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows static Module using Debug.LogError null-guard" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioModule.cs"
    printf 'using UnityEngine;\npublic static class AudioModule {\n    public static void Install(object cfg) { if (cfg == null) { Debug.LogError(\"missing\"); return; } }\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks service calling SceneManager (scene API belongs in *Loader)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scenes"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scenes/BadSceneService.cs"
    printf 'using UnityEngine;\nusing UnityEngine.SceneManagement;\npublic sealed class BadSceneService : ISceneService {\n    public void Go() => SceneManager.LoadScene(\"Game\");\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "ignores Unity API names that appear only in comments or string literals" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring/CommentService.cs"
    printf 'using UnityEngine;\n// moved Transform and AudioSource logic to a Provider\npublic sealed class CommentService : ICommentService {\n    private readonly string _note = \"was SceneManager-driven\";\n    public float Half(float v) => Mathf.Max(0f, v * 0.5f);\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows service importing SceneManagement only for the Scene handle type" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scenes"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scenes/SceneService.cs"
    printf 'using UnityEngine.SceneManagement;\npublic sealed class SceneService : ISceneService {\n    private Scene _previous;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
