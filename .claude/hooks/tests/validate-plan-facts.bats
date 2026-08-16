#!/usr/bin/env bats

# NOTE ON ASSERTION STYLE: bare `[[ "$output" == *"..."* ]]` does NOT reliably
# fail a Bats 1.13 test unless it is the LAST statement in the @test body —
# confirmed by direct probe (a failing `[[ ]]` mid-test silently reports
# "ok" while a failing `[ ]` or a failing simple command at the same
# position correctly reports "not ok"). Likely the same class of bash
# `errexit` exemption that applies to negated (`!`) pipelines. To make every
# assertion in this file actually load-bearing regardless of its position,
# substring checks go through the two helpers below — both are ordinary
# simple-command function calls, which DO propagate failure at any position.
assert_output_contains() {
    printf '%s' "$output" | grep -qF -- "$1"
}

refute_output_contains() {
    [ -z "$(printf '%s' "$output" | grep -F -- "$1")" ]
}

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
    assert_output_contains "NO TASKS FOUND"
    assert_output_contains "NOT a pass"
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
    # Assertions pinned to the EXACT receipt numbers this fixture produces
    # (re-derived independently, not merely trusted): T004 (*Service) resolves
    # its one backticked Callers: token against T005's declared path (1
    # cross-verified caller) and finds T006's declared PlayerModule.cs task
    # (1 cross-verified service wiring). T005 and T006 each declare a
    # non-backticked Callers: (a task ID, then bare prose) and non-*Service
    # Wiring: — 2 presence-only callers, 2 presence-only wiring. A loose
    # substring check (Open 3 in the review) is unconditionally printed on
    # every path including NO-TASKS-FOUND and cannot fail; exact counts can.
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 1, wiring 1 service task(s)"
    assert_output_contains "presence-only  : callers 2 "
    assert_output_contains "presence-only  : wiring 2 "
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
    assert_output_contains "VIOLATION"
    assert_output_contains "Wiring:"
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
    assert_output_contains "exists neither on disk nor as a task in this plan"
}

@test "a Wiring: with no extractable module identifier is presence-only, not a violation" {
    # "registered somewhere" names no *Module identifier at all — nothing a
    # machine can resolve, so nothing is claimed either way. This is
    # deliberately the SAME fixture the old, pre-Ruling-round-3 version of
    # this test used to (incorrectly) treat as a violation: under the
    # unified extraction rule an unnamed Wiring: is presence-only, never a
    # false violation and never a false cross-verification.
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
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 2 "
}

@test "a Wiring: naming a module that exists nowhere is a violation, never cross-verified (Open)" {
    # Reviewer's exact probe: disk holds only GhostModule.cs; the task names
    # SuperGhostModule, which exists neither as a plan task nor on disk.
    # Unanchored substring matching (the pre-fix defect) would have let
    # "GhostModule" inside "SuperGhostModule" satisfy the check via overlap;
    # whole-identifier comparison must not.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts/GhostModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T500 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: SuperGhostModule.Install (SuperGhostModule.cs does not exist anywhere)
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Module.Install task anywhere in this plan"
}

@test "an unrelated domain's Module.cs task does not cross-verify a service naming a DIFFERENT module (domain-blindness closed)" {
    # Before the ruling, branch (a) checked ALL_TASK_PATHS for ANY *Module.cs
    # checkbox task anywhere in the plan — so an unrelated Audio domain's
    # AudioModule.cs task would have wrongly cross-verified ANY *Service in
    # the plan regardless of what its own Wiring: text said. This fixture
    # deliberately extracts a REAL identifier ("GhostModule") from
    # GhostService's own Wiring: — so branch (a)/(b) DO run — and proves
    # they require that SPECIFIC name, not just "some *Module.cs exists
    # somewhere": AudioModule.cs (present, unrelated) must NOT satisfy a
    # Wiring: that names GhostModule (absent from both the plan and disk).
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts" "$TMPDIR_TEST/Concretes/Audio"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef" "$TMPDIR_TEST/Concretes/Audio/Audio.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T400 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: GhostModule.Install
- [ ] T401 \`$TMPDIR_TEST/Concretes/Audio/AudioModule.cs\` — Install, unrelated domain
  - Callers: none
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Module.Install task anywhere in this plan"
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
    assert_output_contains "no .asmdef owns this location"
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
    refute_output_contains "VIOLATION"
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
    assert_output_contains "no .asmdef owns this location"
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
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : callers 1 "
}

@test "a task naming itself as its own caller is a violation (Open 1)" {
    # ALL_TASK_PATHS includes the task's own declared path, so a Callers:
    # entry pointing at the task's own file used to resolve against itself —
    # the receipt claimed a caller relationship was cross-verified when the
    # plan asserted only that the file calls itself. The task's own path must
    # be excluded from the pool the caller loop resolves against.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T300 \`$TMPDIR_TEST/Concretes/Ghosts/GhostController.cs\` — impl
  - Callers: \`$TMPDIR_TEST/Concretes/Ghosts/GhostController.cs\`
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "exists neither on disk nor as a task in this plan"
}

@test "an on-disk domain Module.cs named in Wiring: satisfies the service check (Ruling)" {
    # Per bootstrap-pattern.md: once a domain's first module has landed,
    # every subsequent service in that domain registers in the EXISTING
    # [Domain]Module.cs — it is normal for such a service to have no Module
    # task in the plan at all. UNITY_FACTS_REPO_ROOT points the on-disk
    # search at a disposable fixture tree (never this repo's real source) so
    # the on-disk fallback can be exercised without depending on this
    # repository's actual (empty) _GameFolders/ tree.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts/GhostModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T200 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: GhostModule.Install
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 1 service task(s)"
}

@test "AppModules.cs alone does NOT satisfy the service check — presence-only, never cross-verified (Ruling exemption pinned)" {
    # AppModules.cs ends in "Modules.cs" (plural), not "Module.cs" — the
    # bare-word extractor's \b anchor never yields "AppModule" as an
    # identifier out of "AppModules.Install" (the trailing "s" breaks the
    # word boundary), so this Wiring: text extracts NO module identifier at
    # all. Per bootstrap-pattern.md a service registers in [Domain]Module.cs,
    # which then contributes one line to AppModules.cs — AppModules.cs
    # itself is never the registration target, and correctly resolves as
    # presence-only rather than either a false violation or a false
    # cross-verify, even when AppModules.cs exists on disk.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Infrastructure"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T201 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: AppModules.Install one line
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 1 "
}
