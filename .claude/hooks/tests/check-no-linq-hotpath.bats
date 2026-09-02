#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.
# It fires only when BOTH conditions hold: the file imports System.Linq AND it
# declares a hot-path method. Either alone is silent, and both halves are tested.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-no-linq-hotpath.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns when System.Linq and Update() are in the same file" {
    local f="$TMPDIR_TEST/EnemyController.cs"
    printf 'using System.Linq;\npublic class E{ void Update(){ } }\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Linq"* ]]
}

@test "warns for a Tick hot path too, not just Update" {
    local f="$TMPDIR_TEST/MoveHandler.cs"
    printf 'using System.Linq;\npublic class M{ public void Tick(float dt){ } }\n' > "$f"
    fire "$f"
    [ -n "$output" ]
}

@test "stays silent with System.Linq but no hot path" {
    local f="$TMPDIR_TEST/LevelBuilder.cs"
    printf 'using System.Linq;\npublic class L{ void Build(){ } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "stays silent with a hot path but no System.Linq" {
    local f="$TMPDIR_TEST/EnemyController.cs"
    printf 'public class E{ void Update(){ } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "ignores a non-existent file" {
    fire "$TMPDIR_TEST/Missing.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
