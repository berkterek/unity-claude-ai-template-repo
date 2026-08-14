#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-critical-files.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks editing an EXISTING AppScope" {
    # The hook allows brand-new critical files (creation is safe) and only blocks
    # edits to files that already exist — so the test file must exist on disk.
    local f="$TMPDIR_TEST/AppScope.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks editing an EXISTING .asmdef" {
    local f="$TMPDIR_TEST/Game.asmdef"
    echo '{}' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows creating a NEW .asmdef" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$TMPDIR_TEST/Brand.New.asmdef\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks editing an EXISTING EventBus" {
    local f="$TMPDIR_TEST/EventBus.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks editing an EXISTING Installer" {
    local f="$TMPDIR_TEST/AudioInstaller.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows creating a NEW Installer (file does not exist yet)" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$TMPDIR_TEST/NewModuleInstaller.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "critical edit passes on the Director's SECOND attempt" {
    local f="$TMPDIR_TEST/AppModules.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "critical edit NEVER passes on retry inside a subagent" {
    # Same reasoning as gateguard.sh and check-config-protection.sh: deny-then-allow
    # verifies nothing, and a subagent reports to the Director rather than the user,
    # so letting it clear the gate itself cancels the gate's only purpose.
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    local f="$TMPDIR_TEST/EventBus.cs"
    echo "// existing" > "$f"
    for _ in 1 2 3; do
        run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
        [ "$status" -eq 2 ]
    done
}

@test "a STALE depth count still blocks — no timeout releases this gate" {
    # Opposite of guard-pipeline-direct-work.sh on purpose: there 0 means ENFORCE,
    # here 0 means PASS, so a timeout would release a long-running subagent.
    local depth="${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo 5 > "$depth"
    touch -t 200001010000 "$depth"
    local f="$TMPDIR_TEST/AppScope.cs"
    echo "// existing" > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows a normal non-critical file" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/EnemyModel.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
