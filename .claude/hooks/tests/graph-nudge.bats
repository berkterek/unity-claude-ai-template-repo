#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export CLAUDE_PROJECT_DIR="$(mktemp -d)"
    mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
    echo '{"graph": true}' > "$CLAUDE_PROJECT_DIR/.claude/project-features.json"
    HOOK="$BATS_TEST_DIRNAME/../graph-nudge.sh"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$CLAUDE_PROJECT_DIR"
}

read_cs() {
    echo "{\"session_id\":\"s1\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$1\"}}" | bash "$HOOK"
}

@test "nudges on a Read of an indexed .cs" {
    run read_cs "/p/Assets/_GameFolders/Scripts/Games/Concretes/A/Foo.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"additionalContext"* ]]
}

@test "6th nudge in a session is silent" {
    for i in 1 2 3 4 5; do read_cs "/p/Assets/_Framework/X.cs" >/dev/null; done
    run read_cs "/p/Assets/_Framework/X.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a graph-traversal call sets the stamp and silences later reads" {
    echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"python3 .claude/graph/graph-traversal.py what Foo"}}' | bash "$HOOK"
    [ -f "$UNITY_HOOK_STATE_DIR/graph-query-s1-main.stamp" ]
    run read_cs "/p/Assets/_Framework/X.cs"
    [ -z "$output" ]
}

@test "an MCP graph tool sets the stamp" {
    echo '{"session_id":"s1","tool_name":"mcp__graph_mcp__what","tool_input":{}}' | bash "$HOOK"
    [ -f "$UNITY_HOOK_STATE_DIR/graph-query-s1-main.stamp" ]
}

@test "non-indexed path is silent" {
    run read_cs "/p/Packages/foo/Bar.cs"
    [ -z "$output" ]
}

@test "bash cat of an indexed .cs nudges" {
    run bash -c "echo '{\"session_id\":\"s1\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat Assets/_Framework/X.cs\"}}' | bash '$HOOK'"
    [[ "$output" == *"additionalContext"* ]]
}

@test "graph feature off is silent" {
    echo '{"graph": false}' > "$CLAUDE_PROJECT_DIR/.claude/project-features.json"
    run read_cs "/p/Assets/_Framework/X.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DISABLE_HOOK_GRAPH_NUDGE and minimal profile are silent" {
    DISABLE_HOOK_GRAPH_NUDGE=1 run read_cs "/p/Assets/_Framework/X.cs"
    [ -z "$output" ]
    UNITY_HOOK_PROFILE=minimal run read_cs "/p/Assets/_Framework/X.cs"
    [ -z "$output" ]
}

@test "malformed JSON exits 0 silently" {
    run bash -c "echo 'not json' | bash '$HOOK'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "output never contains deny or permissionDecision" {
    run read_cs "/p/Assets/_Framework/X.cs"
    [[ "$output" != *"deny"* ]]
    [[ "$output" != *"permissionDecision"* ]]
}

@test "a main-session graph query does not silence a subagent" {
    echo '{"session_id":"s1","tool_name":"mcp__graph_mcp__what","tool_input":{}}' | bash "$HOOK"
    run bash -c "echo '{\"session_id\":\"s1\",\"agent_id\":\"a1\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/p/Assets/_Framework/X.cs\"}}' | bash '$HOOK'"
    [[ "$output" == *"additionalContext"* ]]
}

@test "every decision is logged with its reason" {
    read_cs "/p/Assets/_Framework/X.cs" >/dev/null
    echo '{"session_id":"s1","tool_name":"mcp__graph_mcp__what","tool_input":{}}' | bash "$HOOK"
    read_cs "/p/Assets/_Framework/X.cs" >/dev/null
    run cat "$UNITY_HOOK_STATE_DIR/graph-nudge.log"
    [[ "$output" == *"nudge"* ]]
    [[ "$output" == *"stamp"* ]]
    [[ "$output" == *"quiet-recent-query"* ]]
}
