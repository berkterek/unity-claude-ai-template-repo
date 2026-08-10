#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-test-scene-exists.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMP="$(mktemp -d)"
    PROJ="$TMP/proj"
    # The hook reads the test file from DISK (PostToolUse) and resolves scenes by
    # find-ing */_Scenes/TestScenes/<name>.unity under the payload's `cwd`.
    TESTDIR="$PROJ/_GameFolders/Scripts/Tests/ProjPlayModeTest"
    SCENEDIR="$PROJ/_Scenes/TestScenes"
    mkdir -p "$TESTDIR" "$SCENEDIR"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMP"
}

# $1 = file_path, $2 = cwd (optional, defaults to $PROJ)
run_hook() {
    local cwd="${2:-$PROJ}"
    local payload
    payload=$(jq -nc --arg p "$1" --arg c "$cwd" '{tool_input:{file_path:$p}, cwd:$c}')
    run bash -c "printf '%s' '$payload' | bash $HOOK"
}

mk_test_file() {
    printf '%s\n' "$2" > "$1"
}

# --- Missing scene: warns ---

@test "warns when a referenced TestScenes scene does not exist" {
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'private const string ScenePath = "TestScenes/PlayerMovementTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]                      # warn-only — never blocks
    [[ "$output" == *"not found in _Scenes/TestScenes/"* ]]
    [[ "$output" == *"PlayerMovementTest.unity"* ]]
    [[ "$output" == *"/create-test"* ]]
}

@test "lists every missing scene when several are referenced" {
    F="$TESTDIR/MultiTests.cs"
    mk_test_file "$F" 'const string A = "TestScenes/AlphaTest";
const string B = "TestScenes/BetaTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AlphaTest.unity"* ]]
    [[ "$output" == *"BetaTest.unity"* ]]
}

# --- Scene present: silent ---

@test "silent when the scene exists under _Scenes/TestScenes/" {
    touch "$SCENEDIR/PlayerMovementTest.unity"
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'private const string ScenePath = "TestScenes/PlayerMovementTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "only the genuinely missing scene is reported when one of two exists" {
    touch "$SCENEDIR/AlphaTest.unity"
    F="$TESTDIR/MultiTests.cs"
    mk_test_file "$F" 'const string A = "TestScenes/AlphaTest";
const string B = "TestScenes/BetaTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BetaTest.unity"* ]]
    [[ "$output" != *"AlphaTest.unity"* ]]
}

@test "a scene reference carrying an explicit .unity suffix still resolves" {
    touch "$SCENEDIR/GammaTest.unity"
    F="$TESTDIR/GammaTests.cs"
    mk_test_file "$F" 'yield return SceneManager.LoadSceneAsync("TestScenes/GammaTest.unity");'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Scope ---

@test "ignores a file with no TestScenes/ reference at all" {
    F="$TESTDIR/PureLogicTests.cs"
    mk_test_file "$F" 'Assert.AreEqual(1, 1);'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores EditMode test files (PlayModeTest path only)" {
    E="$PROJ/_GameFolders/Scripts/Tests/ProjEditModeTest"; mkdir -p "$E"
    F="$E/FooTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/MissingTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores non-test production code" {
    D="$PROJ/_GameFolders/Scripts/Games/Concretes/Players"; mkdir -p "$D"
    F="$D/PlayerController.cs"
    mk_test_file "$F" 'const string S = "TestScenes/MissingTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a file that does not exist on disk is a silent no-op (PostToolUse contract)" {
    run_hook "$TESTDIR/NeverWritten.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "empty file_path exits 0" {
    run bash -c "echo '{\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- project-features.json gating ---

@test "testing:false in project-features.json silences the hook" {
    mkdir -p "$PROJ/.claude"
    echo '{"testing": false}' > "$PROJ/.claude/project-features.json"
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/PlayerMovementTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "testing:true in project-features.json keeps the hook active" {
    mkdir -p "$PROJ/.claude"
    echo '{"testing": true}' > "$PROJ/.claude/project-features.json"
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/PlayerMovementTest";'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PlayerMovementTest.unity"* ]]
}

# --- Profile / kill switches ---

@test "DISABLE_HOOK_CHECK_TEST_SCENE_EXISTS=1 silences the hook" {
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/PlayerMovementTest";'
    payload=$(jq -nc --arg p "$F" --arg c "$PROJ" '{tool_input:{file_path:$p}, cwd:$c}')
    run bash -c "printf '%s' '$payload' | DISABLE_HOOK_CHECK_TEST_SCENE_EXISTS=1 bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "minimal profile skips this standard-level hook" {
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/PlayerMovementTest";'
    payload=$(jq -nc --arg p "$F" --arg c "$PROJ" '{tool_input:{file_path:$p}, cwd:$c}')
    run bash -c "printf '%s' '$payload' | UNITY_HOOK_PROFILE=minimal bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DISABLE_UNITY_HOOKS=1 silences the hook" {
    F="$TESTDIR/PlayerMovementTests.cs"
    mk_test_file "$F" 'const string S = "TestScenes/PlayerMovementTest";'
    payload=$(jq -nc --arg p "$F" --arg c "$PROJ" '{tool_input:{file_path:$p}, cwd:$c}')
    run bash -c "printf '%s' '$payload' | DISABLE_UNITY_HOOKS=1 bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
