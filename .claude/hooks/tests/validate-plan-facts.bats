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
  - Wiring: registered in \`PlayerModule.cs\`
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
  - Wiring: registered in \`SuperGhostModule.cs\`
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Wiring: names SuperGhostModule.cs — no such module exists"
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
  - Wiring: registered in \`GhostModule.cs\`
- [ ] T401 \`$TMPDIR_TEST/Concretes/Audio/AudioModule.cs\` — Install, unrelated domain
  - Callers: none
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Wiring: names GhostModule.cs — no such module exists"
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
  - Wiring: registered in \`GhostModule.cs\`
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
  - Wiring: registered in \`GhostModule.cs\`
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 1 service task(s)"
}

@test "AppModules.cs alone does NOT satisfy the service check — presence-only, never cross-verified (Ruling exemption pinned)" {
    # AppModules.cs ends in "Modules.cs" (plural), not "Module.cs" — the
    # token regex requires a singular "Module.cs" ending, so even a fully
    # BACKTICKED \`AppModules.cs\` yields NO module identifier at all (this
    # fixture deliberately uses the backticked form, the strongest shape an
    # author could write, to prove the exclusion is structural rather than an
    # accident of missing backticks). Per bootstrap-pattern.md a service
    # registers in [Domain]Module.cs,
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
  - Wiring: \`AppModules.cs\` gets one line
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 1 "
}

# ---------------------------------------------------------------------------
# Round 4 — the receipt stops parsing prose.
#
# A *Service earns cross-verified wiring ONLY when its Wiring: line holds
# EXACTLY ONE backticked `<Name>Module.cs` token that resolves to another
# checkbox task in this plan (never a /Tests/ one) or to a file on disk.
# Every other shape is presence-only — an honest under-claim, never a
# violation and never a false green. The three tests immediately below are
# the three attacks that broke the previous heuristic extractor.
# ---------------------------------------------------------------------------

@test "prose naming a module with no backticks is presence-only, never cross-verified (attack 1)" {
    # Attack 1: "modeled on AudioModule, but actually registered in GhostModule"
    # with only AudioModule.cs on disk. The old extractor took the
    # FIRST-mentioned token and reported cross-verified — it had no notion of
    # which mention is the asserted target. With no backticked token at all,
    # there is nothing unambiguous to resolve, so the honest answer is
    # presence-only.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Audio"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Audio/AudioModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T600 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: modeled on AudioModule, but actually registered in GhostModule
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 1 "
}

@test "a negation or TBD hedge mentioning a real on-disk module is presence-only (attack 2)" {
    # Attack 2: "NOT registered in GhostModule — TBD" and
    # "TBD (compare GhostModule)" both booked as green against a real on-disk
    # GhostModule.cs. A hedge-word blacklist is unbounded; requiring a single
    # backticked token makes both shapes presence-only without enumerating
    # any English at all. Two tasks so both hedge shapes are covered.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts" "$TMPDIR_TEST/Concretes/Wraiths"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef" "$TMPDIR_TEST/Concretes/Wraiths/Wraiths.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts/GhostModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T610 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: NOT registered in GhostModule — TBD
- [ ] T611 \`$TMPDIR_TEST/Concretes/Wraiths/WraithService.cs\` — impl
  - Callers: none
  - Wiring: TBD (compare GhostModule)
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 2 "
}

@test "a /Tests/ stub Module task does NOT satisfy a production service (attack 3)" {
    # Attack 3: a /Tests/-exempt stub GhostModule.cs task cross-verified a
    # production GhostService, because branch (a) compared basenames with no
    # path awareness. A task that is itself exempt from every check in this
    # script cannot be the evidence that another task is wired.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts" "$TMPDIR_TEST/Tests/GhostPlayModeTest"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T620 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: registered in \`GhostModule.cs\`
- [ ] T621 \`$TMPDIR_TEST/Tests/GhostPlayModeTest/GhostModule.cs\` — test stub
  - Callers: none
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Wiring: names GhostModule.cs — no such module exists"
}

@test "two backticked module tokens on one Wiring: line are presence-only, not cross-verified" {
    # Both named modules exist on disk, so under any "first token wins" or
    # "any token resolves" rule this would report cross-verified. Two tokens
    # means the line does not say which one is the asserted registration
    # target, so the machine has resolved nothing and must say so.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts" \
             "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Audio"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Ghosts/GhostModule.cs"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Games/Concretes/Audio/AudioModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T630 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: \`GhostModule.cs\` or possibly \`AudioModule.cs\`
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "presence-only  : wiring 1 "
}

@test "exactly one backticked module token resolving to another checkbox task is cross-verified" {
    # Branch (a) in isolation: nothing on disk (UNITY_FACTS_REPO_ROOT points
    # at an empty tree), so the ONLY thing that can satisfy the check is the
    # sibling non-/Tests/ checkbox task declaring GhostModule.cs.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T640 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: registered in \`GhostModule.cs\`
- [ ] T641 \`$TMPDIR_TEST/Concretes/Ghosts/GhostModule.cs\` — Install
  - Callers: none
  - Wiring: none
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    assert_output_contains "cross-verified : callers 0, wiring 1 service task(s)"
}

@test "an on-disk /Tests/ module does NOT satisfy a production service (Round 5)" {
    # Branch (b)'s counterpart to attack 3. The ONLY GhostModule.cs anywhere
    # is an on-disk test stub under a /Tests/ segment; nothing in the plan
    # declares one. Before Round 5 this printed "wiring 1 service task(s)"
    # and passed — a production service reading as cross-verified on the
    # strength of a test stub. The /Tests/ glob here is textually identical
    # to the task-exempt glob at the top of the main loop, so the two cannot
    # drift. MyTests/, Tests.Extra/ and lowercase tests/ deliberately do NOT
    # match either glob — those modules are fully validated, not a gap.
    mkdir -p "$TMPDIR_TEST/Concretes/Ghosts"
    touch "$TMPDIR_TEST/Concretes/Ghosts/Ghosts.asmdef"

    FAKE_ROOT="$TMPDIR_TEST/fakerepo"
    mkdir -p "$FAKE_ROOT/_GameFolders/Scripts/Tests/GhostPlayModeTest"
    touch "$FAKE_ROOT/_GameFolders/Scripts/Tests/GhostPlayModeTest/GhostModule.cs"
    export UNITY_FACTS_REPO_ROOT="$FAKE_ROOT"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T700 \`$TMPDIR_TEST/Concretes/Ghosts/GhostService.cs\` — impl
  - Callers: none
  - Wiring: registered in \`GhostModule.cs\`
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    assert_output_contains "cross-verified : callers 0, wiring 0 service task(s)"
    assert_output_contains "Wiring: names GhostModule.cs — no such module exists"
    refute_output_contains "wiring 1 service task(s)"
}

# =============================================================================
# C1 — the validator must validate the document it was HANDED.
#
# Reproduction before the fix: task PATHS came from the argument, task BODIES
# came from an independent `find "$UNITY_PLAN_ROOT" -name tasks.md`. A bare
# task in the argument's document silently borrowed the Callers:/Wiring: of a
# same-path task in an unrelated plan, and the human at the gate approved a
# receipt describing a document they were not looking at.
#
# The whole existing suite structurally could not express this: every setup()
# exports UNITY_PLAN_ROOT and every test passes an argument inside it. These
# pass an argument OUTSIDE the root, with a conflicting same-path task inside.
# =============================================================================

@test "C1: a bare task in the ARGUMENT does not borrow facts from a same-path task under UNITY_PLAN_ROOT" {
    local outside="$TMPDIR_TEST/outside/badplan"
    mkdir -p "$outside"

    # Fully specified, under UNITY_PLAN_ROOT — the document NOT being validated.
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: unrelated plan

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — implementation
  - Callers: `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs`
  - Wiring: `PlayerModule.cs`
EOF

    # Bare, outside the root — the document actually handed to the validator.
    cat > "$outside/tasks.md" <<'EOF'
# Tasks: badplan

- [ ] T950 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — implementation
EOF

    run bash "$SCRIPT" "$outside/tasks.md"
    assert_output_contains "VIOLATION"
    assert_output_contains "Callers"
    refute_output_contains "OK — all"
    [ "$status" -eq 2 ]
}

@test "C1: a complete task in the ARGUMENT is not condemned by a bare same-path task under UNITY_PLAN_ROOT" {
    # The mirror direction. Before the fix the bodies came from whichever
    # tasks.md `find` reached first, so this could just as easily fail on facts
    # that ARE present in the document under review.
    local outside="$TMPDIR_TEST/outside/goodplan"
    local fake_root="$TMPDIR_TEST/fakerepo"
    mkdir -p "$outside" "$fake_root/_GameFolders/Scripts/Games/Concretes/Players"
    touch "$fake_root/_GameFolders/Scripts/Games/Concretes/Players/Players.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: unrelated plan

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — bare, no fields
EOF

    cat > "$outside/tasks.md" <<EOF
# Tasks: goodplan

- [ ] T100 \`$fake_root/_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs\` — implementation
  - Callers: \`$fake_root/_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs\`
  - Wiring: registered in \`PlayerModule.cs\`
- [ ] T101 \`$fake_root/_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs\` — shell
  - Callers: scene prefab
  - Wiring: GameScope
- [ ] T102 \`$fake_root/_GameFolders/Scripts/Games/Concretes/Players/PlayerModule.cs\` — installer
  - Callers: AppModules
  - Wiring: AppModules.Install
EOF

    UNITY_FACTS_REPO_ROOT="$fake_root" run bash "$SCRIPT" "$outside/tasks.md"
    refute_output_contains "VIOLATION"
    assert_output_contains "OK — all"
    [ "$status" -eq 0 ]
}

@test "C1: new-vs-edit is anchored to the repo root, not the invoking shell's cwd" {
    # A relative task path that happens to exist under the CWD used to flip the
    # task from "new" to "edit", and "edit" short-circuits past the
    # Callers:/Wiring: requirement entirely — the fail-open direction.
    local fake_root="$TMPDIR_TEST/fakerepo2"
    local decoy="$TMPDIR_TEST/decoycwd"
    mkdir -p "$fake_root/Concretes/Players" "$decoy/Concretes/Players"
    touch "$fake_root/Concretes/Players/Players.asmdef"
    # Present under the CWD, absent under the repo root.
    touch "$decoy/Concretes/Players/PlayerService.cs"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks

- [ ] T200 `Concretes/Players/PlayerService.cs` — implementation, no fields declared
EOF

    local abs_script="$PWD/$SCRIPT"
    cd "$decoy"
    UNITY_FACTS_REPO_ROOT="$fake_root" run bash "$abs_script" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    assert_output_contains "(new: 1, edit: 0"
    assert_output_contains "VIOLATION"
    assert_output_contains "Callers"
    [ "$status" -eq 2 ]
}

@test "C2: checkbox lines inside a fenced code block are not enumerated as tasks" {
    # /create-plan writes docs/superpowers/plans/<name>.md, a narrative that
    # quotes example task lines inside ``` fences. The library suppresses
    # fences; this script's own enumeration did not, so every fenced EXAMPLE
    # was reported "no task in any tasks.md declares this path" and the command
    # hard-blocked on its own output. The same pollution ran the other way too:
    # a fenced example module could have cross-verified a real service.
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Plan narrative

Here is what a task looks like:

```markdown
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — example
- [ ] T005 `_GameFolders/Scripts/Games/Concretes/Players/PlayerModule.cs` — example
```

That is the shape.
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    refute_output_contains "VIOLATION"
    assert_output_contains "NO TASKS FOUND"
    assert_output_contains "NOT a pass"
    [ "$status" -eq 0 ]
}

@test "M5: the summary counts examined tasks, never crediting /Tests/ exemptions as passes" {
    local fake_root="$TMPDIR_TEST/fakerepo3"
    mkdir -p "$fake_root/Concretes/Players"
    touch "$fake_root/Concretes/Players/Players.asmdef"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
# Tasks

- [ ] T300 \`$fake_root/Concretes/Players/PlayerController.cs\` — shell
  - Callers: scene prefab
  - Wiring: GameScope
- [ ] T301 \`$fake_root/Scripts/Tests/PlayModeTest/PlayerControllerTests.cs\` — test
- [ ] T302 \`$fake_root/Scripts/Tests/PlayModeTest/PlayerServiceTests.cs\` — test
EOF
    UNITY_FACTS_REPO_ROOT="$fake_root" run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    assert_output_contains "test-exempt: 2"
    assert_output_contains "all 1 examined task(s) pass (2 test-exempt, not examined)"
    refute_output_contains "all 3 task(s) pass"
    [ "$status" -eq 0 ]
}

@test "M5: a plan of nothing but /Tests/ tasks is NOT reported as a pass" {
    local fake_root="$TMPDIR_TEST/fakerepo4"
    mkdir -p "$fake_root/Scripts/Tests/PlayModeTest"

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
# Tasks

- [ ] T400 \`$fake_root/Scripts/Tests/PlayModeTest/AlphaTests.cs\` — test
- [ ] T401 \`$fake_root/Scripts/Tests/PlayModeTest/BetaTests.cs\` — test
EOF
    UNITY_FACTS_REPO_ROOT="$fake_root" run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    assert_output_contains "NO TASKS EXAMINED"
    assert_output_contains "this is NOT a pass"
    refute_output_contains "OK — all"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Fence state must reset at every file boundary.
#
# _declared_subjects passes ALL files to a SINGLE awk. Without `FNR == 1
# { fence = 0 }`, an odd number of ``` lines in one file leaves `fence` set
# when awk moves to the next file, hiding every task in every following file
# from the enumerator — which then reports a clean pass over a document it
# never examined. Reachable only via the directory/multi-file argument, which
# is exactly what /plan-module and /orchestrate document passing.
# =============================================================================

@test "fence: an unterminated code fence in one plan file does not hide tasks in the next" {
    local fake_root="$TMPDIR_TEST/fenceroot"
    mkdir -p "$fake_root/Concretes/Players"
    touch "$fake_root/Concretes/Players/Players.asmdef"
    mkdir -p "$UNITY_PLAN_ROOT/modules/01-alpha" "$UNITY_PLAN_ROOT/modules/02-beta"

    # Alpha: three ``` lines — an odd count, so the fence is still OPEN at EOF.
    cat > "$UNITY_PLAN_ROOT/modules/01-alpha/tasks.md" <<EOF
# Alpha

- [ ] T500 \`$fake_root/Concretes/Players/Alpha.cs\` — shell
  - Callers: scene prefab
  - Wiring: GameScope

\`\`\`csharp
// illustrative only
\`\`\`

\`\`\`csharp
// second block, never closed
EOF

    # Beta: one real task that MUST be caught — it declares no Callers:.
    cat > "$UNITY_PLAN_ROOT/modules/02-beta/tasks.md" <<EOF
# Beta

- [ ] T501 \`$fake_root/Concretes/Players/EvilService.cs\` — service
  - Wiring: PlayersModule
EOF

    UNITY_FACTS_REPO_ROOT="$fake_root" run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules"

    [ "$status" -eq 2 ]
    assert_output_contains "files scanned  : 2"
    assert_output_contains "tasks checked  : 2"
    assert_output_contains "EvilService.cs"
    refute_output_contains "result         : OK"
}
