#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-no-throwaway-editor-script.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

# $1 = file_path, $2 = content (optional)
run_hook() {
    local payload
    payload=$(jq -nc --arg p "$1" --arg c "${2-}" '{tool_input:{file_path:$p, content:$c}}')
    run bash -c "printf '%s' '$payload' | bash $HOOK"
}

# --- Signal 1: scratch Editor path ---

@test "blocks Assets/Editor/Temp/*.cs" {
    run_hook "Assets/Editor/Temp/WireKeyShadow.cs" "public static class WireKeyShadow { }"
    [ "$status" -eq 2 ]
    [[ "$output" == *"scratch Editor location"* ]]
}

@test "blocks Editor/Scratch/ and Editor/OneShot/ and Editor/Throwaway/" {
    for dir in Scratch OneShot Throwaway Tmp; do
        run_hook "Assets/Editor/$dir/Wire.cs" "class X { }"
        [ "$status" -eq 2 ]
    done
}

@test "scratch path match is case-insensitive" {
    run_hook "Assets/editor/temp/Wire.cs" "class X { }"
    [ "$status" -eq 2 ]
}

# --- Signal 2: self-declared disposable content ---

@test "blocks content with delete-this-file-once marker" {
    run_hook "Assets/Editor/Wire.cs" "// Delete this file once the prefab is committed."
    [ "$status" -eq 2 ]
    [[ "$output" == *"disposable"* ]]
}

@test "blocks throwaway marker" {
    run_hook "Assets/Editor/Wire.cs" "/// <summary>Throwaway wiring helper.</summary>"
    [ "$status" -eq 2 ]
}

@test "blocks temporary wiring helper marker" {
    run_hook "Assets/Editor/Wire.cs" "// temporary wiring helper for the shadow sprite"
    [ "$status" -eq 2 ]
}

@test "blocks EditorTemp namespace marker" {
    run_hook "Assets/Editor/Wire.cs" "namespace VoxelBlast.EditorTemp { }"
    [ "$status" -eq 2 ]
}

@test "blocks Turkish gecici editor script marker" {
    run_hook "Assets/Editor/Wire.cs" "// geçici editor script — sonra sil"
    [ "$status" -eq 2 ]
}

# --- Legitimate cases: must pass ---

@test "allows a permanent Editor tool" {
    run_hook "Assets/Editor/AudioImportTool.cs" "public static class AudioImportTool { public static void Apply() { } }"
    [ "$status" -eq 0 ]
}

@test "allows runtime gameplay code" {
    run_hook "_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs" "public sealed class PlayerController : MonoBehaviour { }"
    [ "$status" -eq 0 ]
}

@test "ignores non-cs files even in a scratch path" {
    run_hook "Assets/Editor/Temp/notes.md" "delete this file once done"
    [ "$status" -eq 0 ]
}

@test "allows empty file_path" {
    run bash -c "echo '{\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows a Temp/ path that is NOT under Editor/" {
    run_hook "Assets/Scripts/Temp/Helper.cs" "class Helper { }"
    [ "$status" -eq 0 ]
}

# --- Edit tool payload shape (new_string instead of content) ---

@test "detects disposable marker in an Edit payload new_string" {
    payload=$(jq -nc '{tool_input:{file_path:"Assets/Editor/Wire.cs", new_string:"// throwaway helper"}}')
    run bash -c "printf '%s' '$payload' | bash $HOOK"
    [ "$status" -eq 2 ]
}

# --- Escape valves ---

@test "override file with a reason allows the write" {
    echo "bulk AudioImporter pass — MCP has no importer API" > "$UNITY_HOOK_STATE_DIR/editor-script-override"
    run_hook "Assets/Editor/Temp/Wire.cs" "class X { }"
    [ "$status" -eq 0 ]
}

@test "EMPTY override file does NOT allow the write" {
    : > "$UNITY_HOOK_STATE_DIR/editor-script-override"
    run_hook "Assets/Editor/Temp/Wire.cs" "class X { }"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades the block to a warning" {
    payload=$(jq -nc '{tool_input:{file_path:"Assets/Editor/Temp/Wire.cs", content:"class X { }"}}')
    run bash -c "printf '%s' '$payload' | UNITY_HOOK_MODE=warn bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "DISABLE_UNITY_HOOKS=1 short-circuits the hook" {
    payload=$(jq -nc '{tool_input:{file_path:"Assets/Editor/Temp/Wire.cs", content:"class X { }"}}')
    run bash -c "printf '%s' '$payload' | DISABLE_UNITY_HOOKS=1 bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips this standard-level hook" {
    payload=$(jq -nc '{tool_input:{file_path:"Assets/Editor/Temp/Wire.cs", content:"class X { }"}}')
    run bash -c "printf '%s' '$payload' | UNITY_HOOK_PROFILE=minimal bash $HOOK"
    [ "$status" -eq 0 ]
}
