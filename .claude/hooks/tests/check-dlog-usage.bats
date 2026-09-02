#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-dlog-usage.sh"
    TMPDIR_TEST="$(mktemp -d)/_GameFolders/Scripts/Games/Concretes/Score"
    mkdir -p "$TMPDIR_TEST"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

# Write payload: content comes from tool_input, never from disk.
write_payload() {
    jq -n --arg p "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'
}

@test "blocks Debug.Log in a game service" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){Debug.Log("x");}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks Debug.LogWarning in a game service" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){Debug.LogWarning("x");}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows DLog in a game service" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){DLog.Log(LogTag.General, m);}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows Debug.LogError null-guard in a Module (bootstrap-pattern mandate)" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreModule.cs" 'if (c == null) { Debug.LogError("[ScoreModule] missing."); return; }' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "still blocks plain Debug.Log inside a Module" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreModule.cs" 'void B(){Debug.Log("x");}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Debug.Log inside #if UNITY_EDITOR" {
    local c='#if UNITY_EDITOR
Debug.Log("x");
#endif'
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" "$c" | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks Debug.Log after an #if UNITY_EDITOR block has closed" {
    local c='#if UNITY_EDITOR
Debug.Log("editor only");
#endif
Debug.Log("ships to device");'
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" "$c" | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "ignores Debug.Log inside a line comment" {
    run bash -c "echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" '// Debug.Log is forbidden here' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "exempts DLog.cs itself" {
    local d="$(mktemp -d)/_Framework/Logging"
    mkdir -p "$d"
    run bash -c "echo '$(write_payload "$d/DLog.cs" 'UnityEngine.Debug.Log(m);' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "ignores files outside runtime game paths" {
    local d="$(mktemp -d)/Assets/Plugins"
    mkdir -p "$d"
    run bash -c "echo '$(write_payload "$d/Vendor.cs" 'Debug.Log("x");' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "Edit path judges the post-edit content, not the file on disk" {
    # A file that already violates on disk must still be editable to remove the violation.
    local f="$TMPDIR_TEST/ScoreService.cs"
    echo 'void B(){Debug.Log("x");}' > "$f"
    local payload
    payload=$(jq -n --arg p "$f" \
        --arg o 'Debug.Log("x");' --arg n 'DLog.Log(LogTag.General, "x");' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' | tr -d '\n')
    run bash -c "echo '$payload' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "Edit path still blocks an edit that introduces a violation" {
    local f="$TMPDIR_TEST/ScoreService.cs"
    echo 'void B(){}' > "$f"
    local payload
    payload=$(jq -n --arg p "$f" \
        --arg o 'void B(){}' --arg n 'void B(){Debug.Log("x");}' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' | tr -d '\n')
    run bash -c "echo '$payload' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    run bash -c "UNITY_HOOK_MODE=warn; export UNITY_HOOK_MODE; echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){Debug.Log("x");}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips this standard-level hook" {
    run bash -c "UNITY_HOOK_PROFILE=minimal; export UNITY_HOOK_PROFILE; echo '$(write_payload "$TMPDIR_TEST/ScoreService.cs" 'void B(){Debug.Log("x");}' | tr -d '\n')' | bash $HOOK"
    [ "$status" -eq 0 ]
}
