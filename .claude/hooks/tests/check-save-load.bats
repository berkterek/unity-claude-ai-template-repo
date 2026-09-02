#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-save-load.sh"
    TMPDIR_TEST="$(mktemp -d)/_GameFolders/Scripts/Games/Concretes/Score"
    mkdir -p "$TMPDIR_TEST"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

write_payload() {
    jq -n --arg p "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'
}

run_hook() {
    run bash -c "echo '$(write_payload "$1" "$2" | tr -d '\n')' | bash $HOOK"
}

# --- Card 1: backend called directly ---

@test "blocks PlayerPrefs in a game service" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){PlayerPrefs.SetInt("s", 1);}'
    [ "$status" -eq 2 ]
}

@test "blocks File.WriteAllText in a game service" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){File.WriteAllText(p, j);}'
    [ "$status" -eq 2 ]
}

@test "blocks Application.persistentDataPath in a game service" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){var p = Application.persistentDataPath;}'
    [ "$status" -eq 2 ]
}

@test "blocks JsonConvert in a game service" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){var j = JsonConvert.SerializeObject(d);}'
    [ "$status" -eq 2 ]
}

@test "allows a service that injects ISaveLoadService" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'ScoreService(ISaveLoadService s) => _s = s;'
    [ "$status" -eq 0 ]
}

@test "ignores a backend name inside a line comment" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" '// PlayerPrefs.SetInt is forbidden — use ISaveLoadService'
    [ "$status" -eq 0 ]
}

# --- Card 4: inline key ---

@test "blocks an inline save-key string literal" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){_s.Save("score", d);}'
    [ "$status" -eq 2 ]
}

@test "blocks an inline key on a generic Load call" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){_s.Load<ScoreSaveData>("score");}'
    [ "$status" -eq 2 ]
}

@test "blocks an inline key on HasKey" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){if (_s.HasKey("score")) return;}'
    [ "$status" -eq 2 ]
}

@test "allows a SaveKeyHelper const as the key" {
    run_hook "$TMPDIR_TEST/ScoreService.cs" 'void B(){_s.Save(SaveKeyHelper.SCORE, d);}'
    [ "$status" -eq 0 ]
}

# --- Card 2: persisted type shape ---

@test "blocks a struct *SaveData" {
    run_hook "$TMPDIR_TEST/ScoreSaveData.cs" '[Serializable] public struct ScoreSaveData { public int Version = 1; public int Score; }'
    [ "$status" -eq 2 ]
}

@test "blocks a *SaveData with no [Serializable]" {
    run_hook "$TMPDIR_TEST/ScoreSaveData.cs" 'public sealed class ScoreSaveData { public int Version = 1; public int Score; }'
    [ "$status" -eq 2 ]
}

@test "blocks a *SaveData with no int Version" {
    run_hook "$TMPDIR_TEST/ScoreSaveData.cs" '[Serializable] public sealed class ScoreSaveData { public int Score; }'
    [ "$status" -eq 2 ]
}

@test "allows a correctly shaped *SaveData" {
    run_hook "$TMPDIR_TEST/ScoreSaveData.cs" '[Serializable] public sealed class ScoreSaveData { public int Version = 1; public int Score; }'
    [ "$status" -eq 0 ]
}

@test "does not apply the Card 2 shape rules to a *Model" {
    run_hook "$TMPDIR_TEST/ScoreModel.cs" 'public sealed class ScoreModel { public int Score; public int Combo; }'
    [ "$status" -eq 0 ]
}

# --- Scope ---

@test "exempts the framework DAL, the one legitimate File/JsonConvert site" {
    local d="$(mktemp -d)/_Framework/SaveLoadSystems"
    mkdir -p "$d"
    run_hook "$d/LocalSaveLoadDal.cs" 'void B(){File.WriteAllText(p, j);}'
    [ "$status" -eq 0 ]
}

@test "exempts test assemblies" {
    local d="$(mktemp -d)/_GameFolders/Scripts/Tests/EditModeTest"
    mkdir -p "$d"
    run_hook "$d/ScoreServiceTests.cs" 'void B(){PlayerPrefs.SetInt("s", 1);}'
    [ "$status" -eq 0 ]
}

# --- Edit path ---

@test "Edit path judges the post-edit content, not the file on disk" {
    local f="$TMPDIR_TEST/ScoreService.cs"
    echo 'void B(){PlayerPrefs.SetInt("s", 1);}' > "$f"
    local payload
    payload=$(jq -n --arg p "$f" \
        --arg o 'PlayerPrefs.SetInt("s", 1);' --arg n '_s.Save(SaveKeyHelper.SCORE, d);' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' | tr -d '\n')
    run bash -c "echo '$payload' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "Edit path still blocks an edit that introduces a violation" {
    local f="$TMPDIR_TEST/ScoreService.cs"
    echo 'void B(){}' > "$f"
    local payload
    payload=$(jq -n --arg p "$f" \
        --arg o 'void B(){}' --arg n 'void B(){PlayerPrefs.SetInt("s", 1);}' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' | tr -d '\n')
    run bash -c "echo '$payload' | bash $HOOK"
    [ "$status" -eq 2 ]
}

# --- Profile / mode ---

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    run bash -c "UNITY_HOOK_MODE=warn; export UNITY_HOOK_MODE; echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){PlayerPrefs.SetInt("s", 1);}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips this standard-level hook" {
    run bash -c "UNITY_HOOK_PROFILE=minimal; export UNITY_HOOK_PROFILE; echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){PlayerPrefs.SetInt("s", 1);}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}
