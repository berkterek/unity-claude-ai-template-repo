#!/usr/bin/env bats
# This hook resolves the project root via `git rev-parse` and reads the project's
# own project-features.json, so tests run inside a throwaway git repo (SANDBOX)
# and invoke the hook by absolute path.

setup() {
    HOOK_ABS="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/.claude/hooks/block-graph-direct-read.sh"
    SANDBOX="$(mktemp -d)"
    export UNITY_HOOK_STATE_DIR="$SANDBOX/.claude/state"
    ( cd "$SANDBOX" && git init -q )
    mkdir -p "$SANDBOX/.claude/graph"
    echo '{"nodes":[]}' > "$SANDBOX/.claude/graph/graph.json"
}

teardown() {
    rm -rf "$SANDBOX"
}

set_hybrid() { echo "{\"hybrid_graph\":$1}" > "$SANDBOX/.claude/project-features.json"; }

@test "blocks direct read of graph.json when hybrid_graph is true" {
    set_hybrid true
    run bash -c "cd '$SANDBOX' && echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/graph/graph.json\"}}' | bash '$HOOK_ABS'"
    [ "$status" -eq 2 ]
}

@test "allows direct read of graph.json when hybrid_graph is false" {
    set_hybrid false
    run bash -c "cd '$SANDBOX' && echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/graph/graph.json\"}}' | bash '$HOOK_ABS'"
    [ "$status" -eq 0 ]
}

@test "allows reading a non-graph file even when hybrid_graph is true" {
    set_hybrid true
    echo 'x' > "$SANDBOX/.claude/graph/notes.txt"
    run bash -c "cd '$SANDBOX' && echo '{\"tool_input\":{\"file_path\":\"$SANDBOX/.claude/graph/notes.txt\"}}' | bash '$HOOK_ABS'"
    [ "$status" -eq 0 ]
}
