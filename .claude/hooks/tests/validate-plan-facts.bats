#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPDIR_TEST="$(mktemp -d)"
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02-players"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    SCRIPT=".claude/scripts/validate-plan-facts.sh"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "exit 1 with no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "finding no tasks is NOT a pass" {
    echo '# Tasks: empty' > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [[ "$output" == *"NO TASKS FOUND"* ]]
    [[ "$output" == *"NOT a pass"* ]]
}

@test "a complete plan passes and prints the presence-only line" {
    # Fixture .cs paths carry a plausible Unity-shaped tail (Concretes/<Domain>/)
    # and a REAL .asmdef sits at that domain directory, so the owning-asmdef
    # check passes for the right reason instead of dying on an unmet
    # precondition before the assertion's actual subject is ever reached.
    mkdir -p "$TMPDIR_TEST/Concretes/Players"
    touch "$TMPDIR_TEST/Concretes/Players/Players.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T004 \`$TMPDIR_TEST/Concretes/Players/PlayerService.cs\` — impl
  - Callers: \`$TMPDIR_TEST/Concretes/Players/PlayerController.cs\`
  - Wiring: PlayerModule.Install
- [ ] T005 \`$TMPDIR_TEST/Concretes/Players/PlayerController.cs\` — shell
  - Callers: T004
  - Wiring: GameScope RegisterComponent
- [ ] T006 \`$TMPDIR_TEST/Concretes/Players/PlayerModule.cs\` — Install
  - Callers: AppModules.cs
  - Wiring: AppModules.Install one line
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"presence-only"* ]]
}

@test "a missing Wiring field is exit 2 and names the task" {
    # No real .asmdef is needed here — the missing-Wiring check in
    # lib-gateguard-facts.sh fires before the asmdef check is ever reached.
    mkdir -p "$TMPDIR_TEST/Concretes/Players"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T004 \`$TMPDIR_TEST/Concretes/Players/PlayerService.cs\` — impl
  - Callers: T005
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"VIOLATION"* ]]
    [[ "$output" == *"Wiring:"* ]]
}

@test "an invented caller is a violation" {
    # A real .asmdef at the task's own directory clears the asmdef check so
    # the run actually reaches the Callers cross-verification this test names.
    # Assertion is tightened to the distinctive violation wording (Ruling 4) —
    # "callers 0, ..." in the unconditional receipt line contains the
    # substring "caller" and would make a loose match pass even with the real
    # check disabled; this text does not appear anywhere except the violation.
    mkdir -p "$TMPDIR_TEST/Concretes/Players"
    touch "$TMPDIR_TEST/Concretes/Players/Players.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T004 \`$TMPDIR_TEST/Concretes/Players/PlayerService.cs\` — impl
  - Callers: \`$TMPDIR_TEST/Concretes/Ghosts/GhostController.cs\`
  - Wiring: PlayerModule.Install
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"exists neither on disk nor as a task in this plan"* ]]
}

@test "a Service with no Module.Install task in the plan is a violation" {
    # Real .asmdef present so the run reaches the Wiring/Service check this
    # test names. Assertion tightened to the distinctive violation wording —
    # the word "Module" alone never appears in any unconditional receipt line,
    # but the exact phrase pins the test to the real reason, not a coincidence.
    mkdir -p "$TMPDIR_TEST/Concretes/Players"
    touch "$TMPDIR_TEST/Concretes/Players/Players.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T004 \`$TMPDIR_TEST/Concretes/Players/PlayerService.cs\` — impl
  - Callers: T005
  - Wiring: registered somewhere
- [ ] T005 \`$TMPDIR_TEST/Concretes/Players/PlayerController.cs\` — shell
  - Callers: T004
  - Wiring: GameScope
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Module.Install task anywhere in this plan"* ]]
}

@test "no asmdef anywhere — disk or plan — is a violation (Ruling 1 pinned)" {
    # Neither a real .asmdef on disk nor one declared by any task in the plan.
    # This keeps the asmdef check a real per-task violation with no silent
    # escape hatch, even though this repository itself has zero .asmdef files.
    mkdir -p "$TMPDIR_TEST/Concretes/Orphans"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T020 \`$TMPDIR_TEST/Concretes/Orphans/OrphanController.cs\` — impl
  - Callers: none
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no .asmdef owns this location"* ]]
}

@test "an asmdef declared by another task in the plan satisfies the check (Ruling 2)" {
    # No .asmdef exists on disk anywhere under this domain directory — but a
    # task in the SAME plan declares one at that exact directory. At plan
    # time the assembly doesn't exist yet, so this is the only way a plan that
    # legitimately creates its own new assembly could ever pass.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T010 \`$TMPDIR_TEST/Concretes/Ghosts/GhostController.cs\` — new controller
  - Callers: none
  - Wiring: TBD
- [ ] T011 new assembly for this domain: \`$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef\`
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"VIOLATION"* ]]
}

@test "a prose-only asmdef mention does not satisfy the check — still a violation (Critical 3)" {
    # The .asmdef path appears in the document, but ONLY inside a prose
    # sentence — no checkbox task line commits the plan to creating it. This
    # must still violate: an incidental backtick mention is not a plan
    # commitment, and must not be a working escape hatch around Ruling 1.
    mkdir -p "$TMPDIR_TEST/Concretes/Wraiths"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T030 \`$TMPDIR_TEST/Concretes/Wraiths/WraithController.cs\` — impl
  - Callers: none
  - Wiring: none

Note: no task in this plan creates \`$TMPDIR_TEST/Concretes/Wraiths/Wraiths.asmdef\` yet — someone still needs to add it later.
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no .asmdef owns this location"* ]]
}

@test "receipt counters: unverifiable Callers/Wiring are presence-only, never cross-verified (required)" {
    # Pins the receipt NUMBERS themselves, not just exit code / substring
    # presence. "Callers: T999" is a task-ID reference to a task that does
    # not exist anywhere in this plan — unverifiable, must land in the new
    # callers presence-only counter, never in cross-verified callers. A
    # *Service with no separate Module task must NOT be silently counted as
    # cross-verified wiring either — it must violate, with wiring cross-verified
    # staying at zero.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T100 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: T999
  - Wiring: GhostModule.Install
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cross-verified : callers 0, wiring 0 service task(s)"* ]]
    [[ "$output" == *"presence-only  : callers 1 "* ]]
}
