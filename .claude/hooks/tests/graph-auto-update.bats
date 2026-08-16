#!/usr/bin/env bats

setup() {
    export CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR="$(mktemp -d)"
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
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING (graph-auto-update)"* ]]
}

@test "does not warn twice in the same session" {
    mkdir -p .claude/graph
    echo '{"codebase":{"scanned_files":0}}' > .claude/graph/graph.json
    # Sentinel is now date-keyed: graph-health-warned-YYYY-MM-DD
    touch "$UNITY_HOOK_STATE_DIR/graph-health-warned-$(date +%Y-%m-%d)"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING (graph-auto-update)"* ]]
}

@test "no warning when scanned_files > 0" {
    mkdir -p .claude/graph
    # Fixture needs >= 5 classes; health check fires when classes < 5 AND cs_count >= 20.
    # With 6000+ .cs files in the project, a single-class fixture always triggers the warning.
    echo '{"codebase":{"scanned_files":42,"classes":[{"name":"A"},{"name":"B"},{"name":"C"},{"name":"D"},{"name":"E"}]}}' > .claude/graph/graph.json
    rm -f "$UNITY_HOOK_STATE_DIR/graph-health-warned-$(date +%Y-%m-%d)"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARNING (graph-auto-update)"* ]]
}

@test "exits 0 always" {
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>/dev/null"
    [ "$status" -eq 0 ]
}

@test "template-mode: exits 0 and does not launch builder when Assets dir absent" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/.claude/graph" "$tmpdir/.claude/state"
    printf '{"graph":true,"unity_project_folder":"."}' > "$tmpdir/.claude/project-features.json"
    # Intentionally no Assets/ dir — template repo scenario.
    # No graph-builder.py either, so the builder-existence check exits first; either way the
    # builder is never launched and graph.json is never touched.
    local abs_hook
    abs_hook="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/$HOOK"
    run bash -c "cd '$tmpdir' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Scripts/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$tmpdir/.claude/state' bash '$abs_hook' 2>&1"
    [ "$status" -eq 0 ]
    # graph.json must not be created/modified by the hook (builder not launched)
    [ ! -f "$tmpdir/.claude/graph/graph.json" ]
    rm -rf "$tmpdir"
}

# The trigger log follows $_STATE_DIR, like the health warning above it — not
# the hook's cwd. Same class of defect as track-codex-review.sh's marker; here
# it only costs a misplaced log, but a hook that already resolved the correct
# directory and then wrote somewhere else is a bug regardless of the payload.
@test "trigger log lands in the state dir, not in the hook's cwd" {
    local tmpdir statedir
    tmpdir="$(mktemp -d)"
    statedir="$(mktemp -d)"   # deliberately OUTSIDE tmpdir, so the two are distinguishable
    mkdir -p "$tmpdir/.claude/graph"
    printf '{"graph":true,"unity_project_folder":"."}' > "$tmpdir/.claude/project-features.json"
    # Builder must exist or the hook exits before reaching the log write.
    : > "$tmpdir/.claude/graph/graph-builder.py"
    local abs_hook
    abs_hook="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/$HOOK"
    run bash -c "cd '$tmpdir' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$statedir' bash '$abs_hook' 2>&1"
    [ "$status" -eq 0 ]
    [ -f "$statedir/graph-updates.log" ]
    # A relative write would have created this instead.
    [ ! -e "$tmpdir/.claude/state" ]
    rm -rf "$tmpdir" "$statedir"
}

# Every path in this hook used to be cwd-relative, so from any cwd other than
# the repo root it did not find .claude/project-features.json and exited 0
# having done nothing — no log line, no health warning, no rebuild. Nothing
# reported the skip, so the graph went stale in silence.
@test "runs from a foreign cwd: CLAUDE_PROJECT_DIR anchors every path" {
    local statedir proj foreign
    statedir="$(mktemp -d)"
    proj="$(mktemp -d)"
    foreign="$(mktemp -d)"   # cwd with no .claude/ at all — a subagent's working dir
    mkdir -p "$proj/.claude/graph"
    printf '{"graph":true,"unity_project_folder":"."}' > "$proj/.claude/project-features.json"
    : > "$proj/.claude/graph/graph-builder.py"
    local abs_hook
    abs_hook="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/$HOOK"

    run bash -c "cd '$foreign' && echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR='$proj' UNITY_HOOK_STATE_DIR='$statedir' bash '$abs_hook' 2>&1"
    [ "$status" -eq 0 ]
    # Reached the log write, which means FEATURES and BUILDER both resolved.
    [ -f "$statedir/graph-updates.log" ]
    # And it did not fall back to the foreign cwd for anything.
    [ ! -e "$foreign/.claude" ]
    rm -rf "$statedir" "$proj" "$foreign"
}
