#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.
# This hook is unusual: it compares old_string against new_string, so it only
# ever fires on an Edit payload. A Write payload carries neither and is silent
# by construction — that is tested, so the silence is not mistaken for coverage.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/warn-serialization.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

edit() { # $1 file, $2 old_string, $3 new_string
    local p
    p=$(jq -nc --arg f "$1" --arg o "$2" --arg n "$3" \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')
    run bash -c "echo '$p' | bash $HOOK"
}

@test "warns when a serialized field is renamed with no FormerlySerializedAs" {
    edit "$TMPDIR_TEST/Player.cs" \
        '[SerializeField] private float _speed;' \
        '[SerializeField] private float _moveSpeed;'
    [ "$status" -eq 0 ]
    [[ "$output" == *"FormerlySerializedAs"* ]]
    [[ "$output" == *"_speed"* ]]
}

@test "stays silent when FormerlySerializedAs is present" {
    edit "$TMPDIR_TEST/Player.cs" \
        '[SerializeField] private float _speed;' \
        '[FormerlySerializedAs("_speed")] [SerializeField] private float _moveSpeed;'
    [ -z "$output" ]
}

@test "stays silent when the field name is unchanged" {
    edit "$TMPDIR_TEST/Player.cs" \
        '[SerializeField] private float _speed;' \
        '[SerializeField] private float _speed = 5f;'
    [ -z "$output" ]
}

@test "stays silent on a Write payload — there is no old_string to compare" {
    local p
    p=$(jq -nc '{tool_name:"Write",tool_input:{file_path:"/x/Player.cs",content:"[SerializeField] private float _moveSpeed;"}}')
    run bash -c "echo '$p' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores a non-.cs file" {
    edit "$TMPDIR_TEST/notes.md" \
        '[SerializeField] private float _speed;' \
        '[SerializeField] private float _moveSpeed;'
    [ -z "$output" ]
}
