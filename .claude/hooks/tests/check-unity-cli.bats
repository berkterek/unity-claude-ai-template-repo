#!/usr/bin/env bats
# check-unity-cli.bats — suite for .claude/hooks/check-unity-cli.sh (+ judge .claude/scripts/check-unity-cli.py)
# Plan: docs/PLAN_unity_cli_verify.md Task 3. Written first (RED) — the hook does not exist yet.

setup() {
    UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export UNITY_HOOK_STATE_DIR
    HOOK=".claude/hooks/check-unity-cli.sh"
    JUDGE=".claude/scripts/check-unity-cli.py"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

# NOTE: `bash` here may resolve to a newer bash than /bin/bash under bats; S1 covers bash 3.2.
# Builds the payload with jq --arg (commands under test contain quotes of their own).
run_cmd() {
    local payload="${UNITY_HOOK_STATE_DIR}/payload.json"
    jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' > "$payload"
    run bash -c "bash $HOOK < '$payload'"
}

# A block must be loud: exit 2, the BLOCKED marker and the hook's name. A silent exit 2 is not accepted.
assert_blocked() {
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED"* ]]
    [[ "$output" == *"check-unity-cli"* ]]
}

assert_allowed() {
    [ "$status" -eq 0 ]
}

# --- parse checks ----------------------------------------------------------

@test "S1: hook parses under /bin/bash (bash 3.2 on macOS)" {
    run /bin/bash -n "$HOOK"
    [ "$status" -eq 0 ]
}

@test "S2: judge source compiles (no __pycache__ written)" {
    run python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$JUDGE"
    [ "$status" -eq 0 ]
}

# --- fail-closed -----------------------------------------------------------

@test "F1: fails closed on the narrow regex when the judge file is missing" {
    mkdir -p "$UNITY_HOOK_STATE_DIR/hooks"
    cp .claude/hooks/check-unity-cli.sh .claude/hooks/_lib.sh "$UNITY_HOOK_STATE_DIR/hooks/"
    HOOK="$UNITY_HOOK_STATE_DIR/hooks/check-unity-cli.sh"   # ../scripts does not exist here
    [ ! -e "$UNITY_HOOK_STATE_DIR/scripts" ]
    for c in 'unity command eval x' 'unity cmd eval x' 'unity shell' 'unity pipeline install'; do
        run_cmd "$c"
        assert_blocked
        [[ "$output" == *"conservative"* ]]
    done
    run_cmd 'unity test . --mode EditMode'
    [ "$status" -eq 0 ]
}

# --- must block ------------------------------------------------------------

@test "B1: blocks unity command eval" {
    run_cmd 'unity command eval "return 1;"'
    assert_blocked
}

@test "B2: blocks the cmd alias" {
    run_cmd 'unity cmd eval x'
    assert_blocked
}

@test "B3: blocks unity command eval_file" {
    run_cmd 'unity command eval_file snippet.cs'
    assert_blocked
}

@test "B4: blocks any named command, not only eval" {
    run_cmd 'unity command create_gameobject --name X'
    assert_blocked
}

@test "B5: blocks eval behind a global --project-path flag" {
    run_cmd 'unity --project-path /p command eval x'
    assert_blocked
}

@test "B6: blocks eval behind a global --json flag" {
    run_cmd 'unity --json command eval x'
    assert_blocked
}

@test "B7: blocks when flags precede the command name" {
    run_cmd 'unity command --detach --timeout 60 eval x'
    assert_blocked
}

@test "B8: blocks with an env assignment prefix" {
    run_cmd 'FOO=1 unity command eval x'
    assert_blocked
}

@test "B9: blocks behind env VAR=value" {
    run_cmd 'env UNITY_PROJECT_PATH=/p unity command eval x'
    assert_blocked
}

@test "B10: blocks after cd && " {
    run_cmd 'cd /p && unity command eval x'
    assert_blocked
}

@test "B11: blocks after a semicolon and after a pipe" {
    run_cmd 'true; unity command eval x'
    assert_blocked
    run_cmd 'echo x | unity command eval y'
    assert_blocked
}

@test "B12: blocks inside bash -c and sh -c" {
    run_cmd 'bash -c "unity command eval x"'
    assert_blocked
    run_cmd "sh -c 'unity command eval x'"
    assert_blocked
}

@test "B13: blocks inside shell eval" {
    run_cmd 'eval "unity command eval x"'
    assert_blocked
}

@test "B14: blocks inside a command substitution" {
    run_cmd 'echo $(unity command eval x)'
    assert_blocked
}

@test "B15: blocks an absolute binary path" {
    run_cmd '/Users/x/.unity/bin/unity command eval x'
    assert_blocked
}

@test "B16: blocks when the banned call is the second line of a multi-line command" {
    run_cmd $'echo hi\nunity command eval x'
    assert_blocked
}

@test "B17: blocks unity pipeline install and the pipe alias (scope addition b)" {
    run_cmd 'unity pipeline install --project-path /p'
    assert_blocked
    run_cmd 'unity pipe install'
    assert_blocked
}

@test "B18: blocks unity pipeline upgrade (scope addition b)" {
    run_cmd 'unity pipeline upgrade'
    assert_blocked
}

@test "B19: blocks unity run --command" {
    run_cmd 'unity run /p --command my_cmd -- --count 3'
    assert_blocked
}

@test "B20: blocks unity shell, with and without flags" {
    run_cmd 'unity shell'
    assert_blocked
    run_cmd 'unity shell --protocol ndjson'
    assert_blocked
}

@test "B21: blocks unity mcp configure (scope addition a)" {
    run_cmd 'unity mcp configure claude'
    assert_blocked
    run_cmd 'unity mcp --project-path /p configure'
    assert_blocked
}

@test "B22: blocks bare unity mcp, which starts a stdio server (scope addition a)" {
    run_cmd 'unity mcp'
    assert_blocked
    run_cmd 'unity mcp --project-path /p'
    assert_blocked
}

@test "B23: blocks the command name given after --" {
    run_cmd 'unity command -- eval x'
    assert_blocked
}

@test "B24: blocks behind timeout and gtimeout with their value flags" {
    run_cmd 'timeout 60 unity command eval x'
    assert_blocked
    run_cmd 'gtimeout -k 5 60 unity command eval x'
    assert_blocked
}

@test "B25: blocks behind nice -n" {
    run_cmd 'nice -n 10 unity command eval x'
    assert_blocked
}

@test "B26: blocks behind sudo with value flags" {
    run_cmd 'sudo -u root -g wheel unity command eval x'
    assert_blocked
}

@test "B27: blocks behind env -i, nohup, exec, command and time -p" {
    run_cmd 'env -i PATH=/x unity command eval x'
    assert_blocked
    run_cmd 'nohup unity command eval x'
    assert_blocked
    run_cmd 'exec unity command eval x'
    assert_blocked
    run_cmd 'command unity command eval x'
    assert_blocked
    run_cmd 'time -p unity command eval x'
    assert_blocked
}

@test "B28: blocks behind stdbuf and xargs with value flags" {
    run_cmd 'stdbuf -oL unity command eval x'
    assert_blocked
    run_cmd 'xargs -n 1 unity command eval'
    assert_blocked
}

@test "B29: blocks after shell keywords (for/if/brace/!/while)" {
    run_cmd 'for i in 1; do unity command eval x; done'
    assert_blocked
    run_cmd 'if true; then unity command eval x; fi'
    assert_blocked
    run_cmd '{ unity command eval x; }'
    assert_blocked
    run_cmd '! unity command eval x'
    assert_blocked
    run_cmd 'while unity command eval x; do :; done'
    assert_blocked
}

@test "B30: blocks a substitution inside an unquoted heredoc (bash expands it)" {
    run_cmd $'cat <<EOF\n$(unity command eval x)\nEOF'
    assert_blocked
    run_cmd $'cat <<EOF\n`unity command eval x`\nEOF'
    assert_blocked
}

@test "B31: blocks a capitalised binary name (case-insensitive filesystem runs it)" {
    run_cmd 'Unity command eval x'
    assert_blocked
}

@test "B32: blocks coproc" {
    run_cmd 'coproc unity command eval x'
    assert_blocked
    run_cmd 'coproc U { unity command eval x; }'
    assert_blocked
}

@test "B33: blocks pipeline install/upgrade behind a global value flag" {
    run_cmd 'unity pipeline --format json install'
    assert_blocked
    run_cmd 'unity pipe --color never upgrade'
    assert_blocked
}

@test "B34: blocks inside a function definition (function NAME { ... })" {
    run_cmd 'function f { unity command eval x; }; f'
    assert_blocked
}

@test "B35: blocks behind builtin eval" {
    run_cmd 'builtin eval "unity command eval x"'
    assert_blocked
}

@test "B36: blocks a command chained on the heredoc opener line (; separator)" {
    run_cmd $'cat <<EOF; unity command eval x\nbody\nEOF'
    assert_blocked
}

@test "B37: blocks a command chained on a quoted-heredoc opener line after a redirect" {
    run_cmd $'cat <<\'EOF\' >/dev/null && unity command eval x\nbody\nEOF'
    assert_blocked
}

@test "B38: blocks git commit -F - <<EOF && unity command eval" {
    run_cmd $'git commit -F - <<EOF && unity command eval x\nbody\nEOF'
    assert_blocked
}

@test "B39: blocks git commit -F - <<EOF; unity mcp" {
    run_cmd $'git commit -F - <<EOF; unity mcp\nbody\nEOF'
    assert_blocked
}

@test "B40: blocks a heredoc opener piped into unity shell" {
    run_cmd $'cat <<EOF | unity shell\nbody\nEOF'
    assert_blocked
}

@test "B41: blocks a backslash-newline continuation after unity" {
    run_cmd $'unity \\\ncommand eval x'
    assert_blocked
}

@test "B42: blocks a backslash-newline continuation after command" {
    run_cmd $'unity command\\\n eval x'
    assert_blocked
}

@test "B43: blocks a continuation inside bash -c" {
    run_cmd $'bash -c \'unity \\\ncommand eval x\''
    assert_blocked
}

@test "B44: blocks bash -c -- and sh -c --" {
    run_cmd "bash -c -- 'unity command eval x'"
    assert_blocked
    run_cmd "sh -c -- 'unity command eval x'"
    assert_blocked
}

# --- must allow ------------------------------------------------------------

@test "A1: allows a full unity test invocation" {
    run_cmd 'unity test /p --mode EditMode --report-format junit --output /tmp/r.xml --timeout 900'
    assert_allowed
}

@test "A2: allows unity with global flags and test" {
    run_cmd 'unity --non-interactive --no-banner test .'
    assert_allowed
}

@test "A3: allows the word command used as a --filter value" {
    run_cmd 'unity test . --filter command'
    assert_allowed
}

@test "A4: allows unity build" {
    run_cmd 'unity build /p --target StandaloneOSX'
    assert_allowed
}

@test "A5: allows unity run without --command, with args after --" {
    run_cmd 'unity run /p -- -executeMethod Builder.Build'
    assert_allowed
}

@test "A6: allows status, doctor and logs" {
    run_cmd 'unity status --project-path /p --json'
    assert_allowed
    run_cmd 'unity doctor --ci'
    assert_allowed
    run_cmd 'unity logs --tail 50'
    assert_allowed
}

@test "A7: allows editors, editors running, releases, version and help" {
    run_cmd 'unity editors'
    assert_allowed
    run_cmd 'unity editors running --format json'
    assert_allowed
    run_cmd 'unity releases'
    assert_allowed
    run_cmd 'unity --version'
    assert_allowed
    run_cmd 'unity --help'
    assert_allowed
    run_cmd 'unity help command'
    assert_allowed
}

@test "A8: allows the bare command listing, cmd --query, list and pipeline list" {
    run_cmd 'unity command'
    assert_allowed
    run_cmd 'unity cmd --query eval'
    assert_allowed
    run_cmd 'unity list'
    assert_allowed
    run_cmd 'unity pipeline list'
    assert_allowed
}

@test "A9: allows mcp --help, shell --help, plugin install plastic and vcs status" {
    run_cmd 'unity mcp --help'
    assert_allowed
    run_cmd 'unity shell --help'
    assert_allowed
    run_cmd 'unity plugin install plastic'
    assert_allowed
    run_cmd 'unity vcs status'
    assert_allowed
}

@test "A10: allows grep and echo that merely mention the banned command" {
    run_cmd 'grep -rn "unity command eval" docs/'
    assert_allowed
    run_cmd "echo 'unity command eval'"
    assert_allowed
}

@test "A11: allows a commit whose quoted heredoc message names the ban" {
    run_cmd $'git commit -m "$(cat <<\'EOF\'\nfeat: block `unity command eval`\nEOF\n)"'
    assert_allowed
}

@test "A12: allows reading the hook file (-unity- is not the token unity)" {
    run_cmd 'cat .claude/hooks/check-unity-cli.sh'
    assert_allowed
}

@test "A13: ignores a non-Bash payload even when it carries a banned command" {
    local payload="${UNITY_HOOK_STATE_DIR}/payload.json"
    jq -n '{tool_name:"Edit", tool_input:{command:"unity command eval x"}}' > "$payload"
    run bash -c "bash $HOOK < '$payload'"
    [ "$status" -eq 0 ]
}

@test "A14: allows listing flags the plugin skill passes on every call" {
    run_cmd 'unity command --limit 5'
    assert_allowed
    run_cmd 'unity command --sort name'
    assert_allowed
    run_cmd 'unity command --caller plugin --skill unity-cli'
    assert_allowed
}

@test "A15: allows mcp configure --list and --dry-run (scope addition a)" {
    run_cmd 'unity mcp configure --list'
    assert_allowed
    run_cmd 'unity mcp configure claude --dry-run'
    assert_allowed
}

@test "A16: allows a binary lookup and timeout wrapping unity test" {
    run_cmd 'command -v unity'
    assert_allowed
    run_cmd 'timeout 900 unity test /p --mode EditMode'
    assert_allowed
}

@test "A17: allows pipeline list behind a global value flag" {
    run_cmd 'unity pipeline --format json list'
    assert_allowed
}

@test "A18: allows git commit -F - with a quoted heredoc body that names the ban" {
    run_cmd $'git commit -F - <<\'EOF\'\nfeat: block unity command eval\nEOF'
    assert_allowed
}

# --- kill switches / modes -------------------------------------------------

@test "K1: DISABLE_HOOK_CHECK_UNITY_CLI=1 skips the hook" {
    DISABLE_HOOK_CHECK_UNITY_CLI=1 run_cmd 'unity command eval x'
    [ "$status" -eq 0 ]
}

@test "K2: minimal profile skips this standard-level hook (documents the gap)" {
    UNITY_HOOK_PROFILE=minimal run_cmd 'unity command eval x'
    [ "$status" -eq 0 ]
}

@test "K3: warn mode downgrades the block" {
    UNITY_HOOK_MODE=warn run_cmd 'unity command eval x'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (downgraded from BLOCKED)"* ]]
}

@test "K4: an unbalanced quote fails closed" {
    run_cmd 'unity command eval "x'
    assert_blocked
}
