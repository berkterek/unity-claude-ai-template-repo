#!/usr/bin/env bats

setup() {
    UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export UNITY_HOOK_STATE_DIR
    HOOK=".claude/hooks/check-write-via-bash.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

# Builds the payload with jq --arg (no shell re-quoting of the command text —
# commands under test legitimately contain quotes of their own) and feeds it to
# the hook from a file.
run_cmd() {
    local payload="${UNITY_HOOK_STATE_DIR}/payload.json"
    jq -n --arg c "$1" '{tool_input:{command:$c}}' > "$payload"
    run bash -c "bash $HOOK < '$payload'"
}

# --- the motivating bypass -------------------------------------------------

@test "blocks the cat > asmdef bypass" {
    run_cmd "cat > _GameFolders/Scripts/Games/Sim/Sim.asmdef << EOF
{}
EOF"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"Write or Edit"* ]]
}

@test "blocks redirection into a .cs file" {
    run_cmd "echo 'class Foo {}' > Assets/Scripts/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks append redirection into a .cs file" {
    run_cmd "echo x >> Assets/Scripts/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks quoted redirection target" {
    run_cmd "printf '%s' x > \"Assets/Scripts/My Folder/Foo.asmdef\""
    [ "$status" -eq 2 ]
}

@test "blocks tee into a project file" {
    run_cmd "echo x | tee Assets/Scripts/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks tee -a into a project file" {
    run_cmd "echo x | tee -a Assets/Scripts/Foo.asmdef"
    [ "$status" -eq 2 ]
}

@test "blocks sed -i on a project file" {
    run_cmd "sed -i '' 's/a/b/' Assets/Scripts/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks cp into a project file" {
    run_cmd "cp /tmp/draft.cs Assets/Scripts/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks a .unity scene write via bash" {
    run_cmd "cat > Assets/_Scenes/Game.unity << EOF
x
EOF"
    [ "$status" -eq 2 ]
}

# --- must NOT block --------------------------------------------------------

@test "allows reading a project file" {
    run_cmd "cat Assets/Scripts/Foo.cs"
    [ "$status" -eq 0 ]
}

@test "allows grep over project files redirected to a temp file" {
    run_cmd "grep -r class Assets/Scripts/*.cs > /tmp/out.txt"
    [ "$status" -eq 0 ]
}

@test "allows writing a scratch file under /tmp" {
    run_cmd "cat > /tmp/scratch.cs << EOF
x
EOF"
    [ "$status" -eq 0 ]
}

@test "allows cp OUT of the project into /tmp" {
    run_cmd "cp Assets/Scripts/Foo.cs /tmp/backup.cs"
    [ "$status" -eq 0 ]
}

@test "allows unrelated commands" {
    run_cmd "git status --short"
    [ "$status" -eq 0 ]
}

@test "allows redirection to a non-project extension" {
    run_cmd "echo hi > notes.md"
    [ "$status" -eq 0 ]
}

# --- kill switches ---------------------------------------------------------

@test "minimal profile still blocks" {
    UNITY_HOOK_PROFILE=minimal run bash -c "jq -n '{tool_input:{command:\"echo x > Assets/Scripts/Foo.cs\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades to a warning" {
    UNITY_HOOK_MODE=warn run bash -c "jq -n '{tool_input:{command:\"echo x > Assets/Scripts/Foo.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "DISABLE_UNITY_HOOKS=1 skips the hook" {
    DISABLE_UNITY_HOOKS=1 run bash -c "jq -n '{tool_input:{command:\"echo x > Assets/Scripts/Foo.cs\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "empty command is a no-op" {
    run bash -c "echo '{}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
