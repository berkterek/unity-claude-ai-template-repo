#!/usr/bin/env bats
# gateguard runs only at the 'strict' profile, so block-path tests set
# UNITY_HOOK_PROFILE=strict; the default-profile test confirms it is skipped.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/gateguard.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    # chmod before rm: a test that leaves a mode-000 file under TMPDIR_TEST
    # (the unreadable-lib probe) must not survive as an unreadable leftover if
    # rm itself fails partway — restore write/read/exec on everything first,
    # then remove. Bats runs teardown() even when the test body fails/aborts.
    chmod -R u+rwx "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST" 2>/dev/null || true
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "fact-gate: first Write of a new C# file is denied" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "fact-gate NEVER clears on retry inside a subagent" {
    # Deny-then-allow verifies nothing: a caller that merely retries walks through.
    # Acceptable for the Director, whose retry follows printing the facts where the
    # user can read them. A subagent reports to the Director, not the user, so
    # self-satisfying this gate cancels its only purpose. Observed in a derived
    # project: a subagent hit the gate, retried on its own, landed the file, and
    # never mentioned the block in its report.
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    local f="$TMPDIR_TEST/SubagentWrite.cs"
    for _ in 1 2 3; do
        UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
        [ "$status" -eq 2 ]
    done
}

@test "fact-gate tells a subagent that retrying will not help" {
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    local f="$TMPDIR_TEST/SubagentMessage.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK 2>&1"
    [[ "$output" == *"SUBAGENT"* ]]
    [[ "$output" == *"Report BLOCKED"* ]]
}

@test "fact-gate: a STALE depth count still blocks — no timeout releases this gate" {
    # Opposite of guard-pipeline-direct-work.sh on purpose: there 0 means ENFORCE,
    # here 0 means PASS. Nothing refreshes the depth file while an agent merely
    # runs, so a timeout would release any long-running subagent straight through.
    local depth="${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo 9 > "$depth"
    touch -t 200001010000 "$depth"
    local f="$TMPDIR_TEST/StaleDepth.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "fact-gate: a garbage depth value is read as Director, so the retry clears" {
    local depth="${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo "not-a-number" > "$depth"
    local f="$TMPDIR_TEST/GarbageDepth.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "fact-gate: second attempt on the same file is allowed" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "non-C# files are not gated" {
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$TMPDIR_TEST/data.json\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "skipped at standard profile (strict-level hook)" {
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=standard run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "plan coverage lets a SUBAGENT write a declared file" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: \`$TMPDIR_TEST/PlayerController.cs\`
  - Wiring: PlayerModule.Install
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "plan coverage without a gate does NOT let a subagent through" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: x
  - Wiring: y
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "a covered path with an invalid facts block gets the fix-the-plan message" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: x
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"fix the plan"* ]]
}

@test "missing lib-gateguard-facts.sh fails closed with exit 2, not 1" {
    local isolated="$TMPDIR_TEST/isolated-hook"
    mkdir -p "$isolated"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/_lib.sh "$isolated/_lib.sh"
    # Deliberately NOT copying lib-gateguard-facts.sh — the library is unavailable.
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    [ "$status" -eq 2 ]
}

@test "plan coverage does not cache a receipt: removing the gate and tasks.md re-blocks a previously-covered path" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/CachedReceipt.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: \`$TMPDIR_TEST/Caller.cs\`
  - Wiring: SomeModule.Install
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]

    # Coverage withdrawn: remove BOTH the gate and the declaring tasks.md.
    rm -f "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    rm -f "$UNITY_PLAN_ROOT/modules/02/tasks.md"

    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "lib-gateguard-facts.sh present but unreadable (mode 000) fails closed with exit 2" {
    local isolated="$TMPDIR_TEST/isolated-hook-unreadable"
    mkdir -p "$isolated"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/_lib.sh "$isolated/_lib.sh"
    cp .claude/hooks/lib-gateguard-facts.sh "$isolated/lib-gateguard-facts.sh"
    chmod 000 "$isolated/lib-gateguard-facts.sh"

    # Belt-and-braces: even if the test body fails before this line runs again,
    # teardown() below always restores permissions so the repo is never left
    # with an unreadable file (this copy lives under TMPDIR_TEST, which
    # teardown() already rm -rf's, but chmod 000 must not survive to block
    # that removal or a stray leftover on a filesystem where rm honors mode).
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    chmod 755 "$isolated/lib-gateguard-facts.sh"
    [ "$status" -eq 2 ]
}

@test "lib-gateguard-facts.sh path replaced by a directory fails closed with exit 2" {
    local isolated="$TMPDIR_TEST/isolated-hook-dir"
    mkdir -p "$isolated"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/_lib.sh "$isolated/_lib.sh"
    mkdir -p "$isolated/lib-gateguard-facts.sh"  # a directory, not a file, at that path
    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    [ "$status" -eq 2 ]
}

# --- I3: _lib.sh was sourced unguarded ---------------------------------------
# Probed before the fix: with _lib.sh absent the hook died at the `source` line
# under `set -e` with status 1 — and status 1 ALLOWS the write in this harness.
# The 20-line comment above the lib-gateguard-facts.sh guard described exactly
# this failure mode but applied the guard to only one of the two sources.
# _lib.sh is load-bearing for the gate decision (unity_plan_covers lives there),
# so it must fail closed, i.e. exit 2 — never 1.
@test "_lib.sh missing fails closed with exit 2, never the fail-open 1" {
    local isolated="$TMPDIR_TEST/isolated-hook-nolib"
    mkdir -p "$isolated"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/lib-gateguard-facts.sh "$isolated/lib-gateguard-facts.sh"
    # _lib.sh deliberately NOT copied.

    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    [ "$status" -ne 1 ]
    [ "$status" -eq 2 ]
}

@test "_lib.sh present but unreadable (mode 000) fails closed with exit 2" {
    local isolated="$TMPDIR_TEST/isolated-hook-libunread"
    mkdir -p "$isolated"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/_lib.sh "$isolated/_lib.sh"
    cp .claude/hooks/lib-gateguard-facts.sh "$isolated/lib-gateguard-facts.sh"
    chmod 000 "$isolated/_lib.sh"

    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    chmod 755 "$isolated/_lib.sh"
    [ "$status" -eq 2 ]
}

@test "_lib.sh path replaced by a directory fails closed with exit 2" {
    local isolated="$TMPDIR_TEST/isolated-hook-libdir"
    mkdir -p "$isolated/_lib.sh"
    cp .claude/hooks/gateguard.sh "$isolated/gateguard.sh"
    cp .claude/hooks/lib-gateguard-facts.sh "$isolated/lib-gateguard-facts.sh"

    local f="$TMPDIR_TEST/NewSystem.cs"
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $isolated/gateguard.sh"
    [ "$status" -eq 2 ]
}
