#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPDIR_TEST="$(mktemp -d)"
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02-players"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: Players

- [ ] T004 [parallel_group:1] `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — implementation
  ```csharp
  public interface IFake { }
  ```
  - Callers: `Concretes/Players/PlayerController.cs`
  - Wiring: PlayerModule.Install → Register<PlayerService>()
  - Acceptance: tests pass

- [ ] T005 `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs` — shell
  - Callers: scene prefab Player.prefab
  - Wiring: GameScope RegisterComponent
EOF
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "find_task_line: locates the declaring task by full path" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" == *"T004"* ]]
    [[ "$output" == *"Wiring: PlayerModule.Install"* ]]
}

@test "find_task_line: matches an absolute path against a repo-relative plan entry" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '/abs/repo/_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" == *"T004"* ]]
}

@test "find_task_line: body stops at the next task line" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" != *"T005"* ]]
}

@test "find_task_line: a draft interface inside a code fence is not a field" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" != *"public interface IFake"* ]]
}

@test "find_task_line: empty for an undeclared path" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs'"
    [ -z "$output" ]
}

@test "find_task_line: ignores the _templates directory" {
    mkdir -p "$UNITY_PLAN_ROOT/modules/_templates"
    cp "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" "$UNITY_PLAN_ROOT/modules/_templates/tasks.md"
    rm "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ -z "$output" ]
}
