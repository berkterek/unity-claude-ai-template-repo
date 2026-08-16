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
