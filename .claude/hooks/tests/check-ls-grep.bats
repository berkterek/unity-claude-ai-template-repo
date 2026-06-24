#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-ls-grep.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks ls | grep" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls | grep foo\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks ls -la | grep" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la | grep foo\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks ls after a separator (cd x && ls | grep)" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd /tmp && ls | grep foo\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows git ls-files | grep (not a directory listing)" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git ls-files | grep test\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows grep over a file whose name contains ls (original false positive)" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"grep -n pattern .claude/hooks/check-ls-grep.sh | head\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows content search via cat | grep" {
    run bash -c "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat foo.txt | grep bar\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-Bash tool calls" {
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
