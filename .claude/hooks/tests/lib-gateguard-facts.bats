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

@test "find_task_line: does not match on basename alone across domains" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: Players

- [ ] T010 `_GameFolders/Scripts/Games/Concretes/AI/Service.cs` — implementation
  - Wiring: PlayerModule.Install → Register<Service>()
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/Service.cs'"
    [ -z "$output" ]
}

@test "find_task_line: does not match a suffix that lacks a path-component boundary" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: Players

- [ ] T011 `Concretes/Players/Service.cs` — implementation
  - Wiring: PlayerModule.Install → Register<Service>()
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '/repo/OtherConcretes/Players/Service.cs'"
    [ -z "$output" ]
}

@test "task_mode: new when the file is absent from disk" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_task_mode '$TMPDIR_TEST/Absent.cs'"
    [ "$output" = "new" ]
}

@test "task_mode: edit when the file exists" {
    touch "$TMPDIR_TEST/Present.cs"
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_task_mode '$TMPDIR_TEST/Present.cs'"
    [ "$output" = "edit" ]
}

@test "validate: a new task carrying both fields passes" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs' new"
    [ "$status" -eq 0 ]
}

@test "validate: a new task missing Wiring is rejected with a reason" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T009 `_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs` — impl
  - Callers: `Concretes/Players/PlayerController.cs`
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs' new"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Wiring:"* ]]
}

@test "validate: an undeclared path is rejected" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs' new"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no task"* ]]
}

@test "validate: a test file is exempt from both fields" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T003 `_GameFolders/Scripts/Tests/GameEditModeTest/PlayerServiceTests.cs` — EditMode test
  - Acceptance: passes
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Tests/GameEditModeTest/PlayerServiceTests.cs' new"
    [ "$status" -eq 0 ]
}

@test "validate: a signalled rename on a SerializeField file demands FormerlySerializedAs" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf '[SerializeField] private float _speed;\n' > "$TMPDIR_TEST/dom/Mover.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T020 \`$TMPDIR_TEST/dom/Mover.cs\` — rename _speed to _moveSpeed
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/Mover.cs' edit"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FormerlySerializedAs"* ]]
}

@test "validate: the same rename passes once FormerlySerializedAs is declared" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf '[SerializeField] private float _speed;\n' > "$TMPDIR_TEST/dom/Mover.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T020 \`$TMPDIR_TEST/dom/Mover.cs\` — rename _speed to _moveSpeed
  - FormerlySerializedAs: _speed -> _moveSpeed
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/Mover.cs' edit"
    [ "$status" -eq 0 ]
}

@test "validate: an ordinary edit with no rename signal needs no fields" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf 'public class AppModules { }\n' > "$TMPDIR_TEST/dom/AppModules.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T030 \`$TMPDIR_TEST/dom/AppModules.cs\` — add PlayerModule.Install line
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/AppModules.cs' edit"
    [ "$status" -eq 0 ]
}

@test "validate: a new task with Wiring present but empty is rejected" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T040 `_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs` — impl
  - Callers: `Foo.cs`
  - Wiring:
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs' new"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Wiring:"* ]]
}

@test "validate: a rename signal on a file WITHOUT SerializeField passes without FormerlySerializedAs" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf 'public class Foo { }\n' > "$TMPDIR_TEST/dom/Foo.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T050 \`$TMPDIR_TEST/dom/Foo.cs\` — rename _speed to _moveSpeed
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/Foo.cs' edit"
    [ "$status" -eq 0 ]
}

@test "plan_covers: false with no gate-cleared, even for a declared path" {
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: true with a fresh gate and a declared path" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -eq 0 ]
}

@test "plan_covers: false when the gate is stale" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    python3 -c "import os,time; p='${UNITY_HOOK_STATE_DIR}/gate-cleared'; os.utime(p,(time.time()-3000,time.time()-3000))"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: false for an undeclared path even with a fresh gate" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: false when the plan root is unreadable — no fail-open" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "export UNITY_PLAN_ROOT=/nonexistent-plan-root; source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: false when the gate age is indeterminate" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    # Override python3 specifically (unity_gate_cleared_valid's only age-computation
    # dependency) rather than breaking PATH wholesale — PATH=/nonexistent would also
    # take out `dirname` inside unity_plan_covers' own library-sourcing line, failing
    # the call for the wrong reason before it ever reaches the age check.
    run bash -c "source .claude/hooks/_lib.sh; python3() { return 1; }; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}
