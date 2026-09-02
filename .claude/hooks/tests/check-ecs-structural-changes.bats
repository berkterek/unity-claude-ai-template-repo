#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.
# Two gates precede detection and both are tested: the path must be under
# Games/Ecs/Systems/, and the ECS feature must not be disabled. The feature
# gate reads `.cwd` from the payload, NOT $UNITY_FEATURES_FILE — a test that
# set the env var instead would silently exercise nothing.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-ecs-structural-changes.sh"
    ROOT="$(mktemp -d)"
    SYS="$ROOT/_GameFolders/Scripts/Games/Ecs/Systems"
    mkdir -p "$SYS" "$ROOT/.claude"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$ROOT"; }

fire() { # $1 = file, $2 = cwd ("" for none)
    run bash -c "echo '{\"cwd\":\"$2\",\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"
}

@test "warns on EntityManager.AddComponent in an ECS system" {
    printf 'public partial class S{ void OnUpdate(){ EntityManager.AddComponent(e, c); } }\n' > "$SYS/MoveSystem.cs"
    fire "$SYS/MoveSystem.cs" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"EntityCommandBuffer"* ]]
}

@test "warns on EntityManager.DestroyEntity as well" {
    printf 'public partial class S{ void OnUpdate(){ EntityManager.DestroyEntity(e); } }\n' > "$SYS/KillSystem.cs"
    fire "$SYS/KillSystem.cs" ""
    [ -n "$output" ]
}

@test "stays silent when the change goes through an EntityCommandBuffer" {
    printf 'public partial class S{ void OnUpdate(){ ecb.AddComponent(e, c); } }\n' > "$SYS/MoveSystem.cs"
    fire "$SYS/MoveSystem.cs" ""
    [ -z "$output" ]
}

@test "ignores a file outside Games/Ecs/Systems/" {
    local f="$ROOT/_GameFolders/Scripts/Games/Concretes/S.cs"
    mkdir -p "$(dirname "$f")"
    printf 'EntityManager.AddComponent(e, c);\n' > "$f"
    fire "$f" ""
    [ -z "$output" ]
}

@test "silent when the project declares ecs:false" {
    printf '{"ecs": false}\n' > "$ROOT/.claude/project-features.json"
    printf 'public partial class S{ void OnUpdate(){ EntityManager.AddComponent(e, c); } }\n' > "$SYS/MoveSystem.cs"
    fire "$SYS/MoveSystem.cs" "$ROOT"
    [ -z "$output" ]
}

@test "still warns when the project declares ecs:true" {
    printf '{"ecs": true}\n' > "$ROOT/.claude/project-features.json"
    printf 'public partial class S{ void OnUpdate(){ EntityManager.AddComponent(e, c); } }\n' > "$SYS/MoveSystem.cs"
    fire "$SYS/MoveSystem.cs" "$ROOT"
    [ -n "$output" ]
}
