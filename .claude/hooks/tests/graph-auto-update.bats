#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/graph-auto-update.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    GRAPH_BACKUP=""
    # Back up real graph.json if it exists
    if [ -f ".claude/graph/graph.json" ]; then
        GRAPH_BACKUP="$(mktemp)"
        cp .claude/graph/graph.json "$GRAPH_BACKUP"
    fi
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    # Restore real graph.json
    if [ -n "${GRAPH_BACKUP:-}" ] && [ -f "$GRAPH_BACKUP" ]; then
        cp "$GRAPH_BACKUP" .claude/graph/graph.json
        rm -f "$GRAPH_BACKUP"
    fi
}

@test "warns once when graph.json has scanned_files=0" {
    mkdir -p .claude/graph
    echo '{"codebase":{"scanned_files":0}}' > .claude/graph/graph.json
    rm -f "$UNITY_HOOK_STATE_DIR/graph-empty-warned"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (graph-auto-update)"* ]]
}

@test "does not warn twice in the same session" {
    mkdir -p .claude/graph
    echo '{"codebase":{"scanned_files":0}}' > .claude/graph/graph.json
    # Sentinel is now date-keyed: graph-health-warned-YYYY-MM-DD
    touch "$UNITY_HOOK_STATE_DIR/graph-health-warned-$(date +%Y-%m-%d)"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING (graph-auto-update)"* ]]
}

@test "no warning when scanned_files > 0" {
    mkdir -p .claude/graph
    # Fixture includes classes so the health check (which inspects classes count) sees a healthy graph.
    echo '{"codebase":{"scanned_files":42,"classes":[{"name":"Foo"}]}}' > .claude/graph/graph.json
    rm -f "$UNITY_HOOK_STATE_DIR/graph-health-warned-$(date +%Y-%m-%d)"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING (graph-auto-update)"* ]]
}

@test "exits 0 always" {
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>/dev/null"
    [ "$status" -eq 0 ]
}
