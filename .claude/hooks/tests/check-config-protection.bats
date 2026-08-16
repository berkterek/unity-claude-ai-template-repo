#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPDIR_TEST="$(mktemp -d)"
    HOOK=".claude/hooks/check-config-protection.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    rm -rf "$TMPDIR_TEST"
}

@test "blocks edits to settings.json" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks edits to EXISTING .asmdef files outside test folders" {
    EXISTING="${UNITY_HOOK_STATE_DIR}/GameAssembly.asmdef"
    echo '{}' > "$EXISTING"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows CREATING a new .asmdef — no existing boundary to break" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"${UNITY_HOOK_STATE_DIR}/Brand.New.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "asmdef edit passes on the SECOND attempt — deny-then-allow" {
    # Same gate guard-critical-files.sh uses. Without it an approved reference
    # change could never land, and a permanent block is what pushes agents into
    # `cat >` workarounds (see check-write-via-bash.sh).
    EXISTING="${UNITY_HOOK_STATE_DIR}/Retry.asmdef"
    echo '{}' > "$EXISTING"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "asmdef edit NEVER passes on retry inside a subagent" {
    # A subagent reports to the Director, not the user, so letting it satisfy the
    # gate by retrying cancels the gate's only purpose. Depth > 0 repeats forever.
    echo 3 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    EXISTING="${UNITY_HOOK_STATE_DIR}/SubagentRetry.asmdef"
    echo '{}' > "$EXISTING"
    for _ in 1 2 3; do
        run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
        [ "$status" -eq 2 ]
    done
}

@test "a STALE depth count still blocks — no timeout releases this gate" {
    # Deliberately the OPPOSITE of guard-pipeline-direct-work.sh. There a stale
    # count read as 0 makes the hook ENFORCE; here 0 means "Director", which lets
    # the retry PASS. Nothing touches the depth file while an agent merely runs, so
    # a timeout would hand any long-running subagent the exact bypass this gate
    # removes. A leaked count costs the Director one visible reset instead.
    DEPTH="${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo 7 > "$DEPTH"
    touch -t 200001010000 "$DEPTH"
    EXISTING="${UNITY_HOOK_STATE_DIR}/StaleDepth.asmdef"
    echo '{}' > "$EXISTING"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "a garbage depth value is read as Director, not as subagent" {
    # Unparseable is not evidence of a subagent — a missing/corrupt file is the
    # fresh-session case, so it must not lock the Director out.
    echo "not-a-number" > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    EXISTING="${UNITY_HOOK_STATE_DIR}/GarbageDepth.asmdef"
    echo '{}' > "$EXISTING"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$EXISTING\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "settings.json stays hard-blocked on every retry — never deny-then-allow" {
    # The asmdef gate must not leak into settings.json: hook registration is a
    # human-only action, so a second attempt must fail exactly like the first.
    run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "manifest.json stays hard-blocked on every retry" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Packages/manifest.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Packages/manifest.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows edits to test assembly .asmdef files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Tests/EditModeTest/MyProject.EditModeTest.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows edits to regular .cs files" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Games/Concretes/Audio/AudioService.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile still blocks settings.json (minimal level)" {
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\".claude/settings.json\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "asmdef edit passes for a subagent when the plan declares it" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/Game.asmdef"
    echo '{"name":"Game"}' > "$f"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T031 \`$f\` — add the Players assembly reference
  - Callers: T004
  - Wiring: n/a
EOF
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/check-config-protection.sh"
    [ "$status" -eq 0 ]
}

@test "settings.json is blocked even under full plan coverage" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02" "$TMPDIR_TEST/.claude"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/.claude/settings.json"
    echo '{}' > "$f"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T099 \`$f\` — disable a hook
  - Callers: none
  - Wiring: none
EOF
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/check-config-protection.sh"
    [ "$status" -eq 2 ]
}
