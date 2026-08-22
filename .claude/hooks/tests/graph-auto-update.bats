#!/usr/bin/env bats

setup() {
    export CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/graph-auto-update.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    # These tests overwrite the REAL .claude/graph/graph.json with a stub, so every
    # generated graph file must be backed up and restored — not just the root document.
    #
    # Backing up graph.json ALONE was correct before the v1.3.0 partition architecture,
    # when it was the only generated file. Since partitioning, `scenes[]` and `prefabs[]`
    # live in the tracked sibling files scenes.json and prefabs.json, and a re-partition
    # off a stub graph.json empties them. In piggy-doku-repo that gutted 256 lines of
    # COMMITTED graph data and left it dirty in the working tree, silently, on every
    # suite run. The list must name every partition file the builder writes.
    GRAPH_FILES=(graph.json scenes.json prefabs.json)
    GRAPH_BACKUP_DIR="$(mktemp -d)"
    for _gf in "${GRAPH_FILES[@]}"; do
        [ -f ".claude/graph/$_gf" ] && cp ".claude/graph/$_gf" "$GRAPH_BACKUP_DIR/$_gf"
    done
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    if [ -n "${GRAPH_BACKUP_DIR:-}" ] && [ -d "$GRAPH_BACKUP_DIR" ]; then
        for _gf in "${GRAPH_FILES[@]}"; do
            if [ -f "$GRAPH_BACKUP_DIR/$_gf" ]; then
                cp "$GRAPH_BACKUP_DIR/$_gf" ".claude/graph/$_gf"
            else
                # Absent before the test must stay absent after it — restoring nothing
                # would leave a stub-derived partition file behind as a new artifact.
                rm -f ".claude/graph/$_gf"
            fi
        done
        rm -rf "$GRAPH_BACKUP_DIR"
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

# ── Concurrency + observability ──────────────────────────────────────────────
# This hook fires once per written file, so a coder writing six files launches
# six rebuilds against one graph.json. graph-builder.py rewrites it wholesale
# and only re-adds communities[]/analysis{} in a post-pass at the very end,
# so overlapping runs can leave a valid graph with those sections gone — and
# with the background job's stderr going to /dev/null, silently.

# Fake builder: records that it ran, then holds long enough to overlap.
_mk_proj() {
    local p="$1" hold="$2"
    mkdir -p "$p/.claude/graph" "$p/Assets"
    printf '{"graph":true,"unity_project_folder":"."}' > "$p/.claude/project-features.json"
    cat > "$p/.claude/graph/graph-builder.py" <<PY
import time, pathlib, sys
d = pathlib.Path(__file__).resolve().parent
with open(d / "runs.txt", "a") as f:
    f.write("run\n")
sys.stderr.write("graph_cluster.py failed (non-fatal): boom\n")
time.sleep($hold)
PY
}

_fire() {   # _fire <proj> <statedir>
    echo '{"tool_name":"Write","tool_input":{"file_path":"Assets/T.cs"}}' \
      | CLAUDE_PROJECT_DIR="$1" UNITY_HOOK_STATE_DIR="$2" bash "$ABS_HOOK" >/dev/null 2>&1
}

setup_conc() {
    PROJ="$(mktemp -d)"; SDIR="$(mktemp -d)"
    ABS_HOOK="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/$HOOK"
}

@test "concurrent writes launch exactly one rebuild — the lock holds" {
    setup_conc
    _mk_proj "$PROJ" 2
    _fire "$PROJ" "$SDIR"
    _fire "$PROJ" "$SDIR"   # lock is held by the first — must be skipped
    _fire "$PROJ" "$SDIR"
    sleep 1                 # first builder still sleeping; count while it holds
    [ "$(wc -l < "$PROJ/.claude/graph/runs.txt" | tr -d ' ')" = "1" ]
    wait
    rm -rf "$PROJ" "$SDIR"
}

@test "the lock is released when the rebuild finishes" {
    setup_conc
    _mk_proj "$PROJ" 0
    _fire "$PROJ" "$SDIR"
    sleep 1
    [ ! -d "$SDIR/graph-rebuild.lock" ]
    # A later write is therefore not blocked by the previous run's lock.
    _fire "$PROJ" "$SDIR"
    sleep 1
    [ "$(wc -l < "$PROJ/.claude/graph/runs.txt" | tr -d ' ')" = "2" ]
    rm -rf "$PROJ" "$SDIR"
}

@test "a stale lock older than 10 min is reclaimed, not wedged forever" {
    setup_conc
    _mk_proj "$PROJ" 0
    mkdir -p "$SDIR/graph-rebuild.lock"
    # 20 minutes old — the owning process died without running its EXIT trap.
    touch -t "$(date -v-20M +%Y%m%d%H%M 2>/dev/null || date -d '20 min ago' +%Y%m%d%H%M)" "$SDIR/graph-rebuild.lock"
    _fire "$PROJ" "$SDIR"
    sleep 1
    [ -f "$PROJ/.claude/graph/runs.txt" ]
    rm -rf "$PROJ" "$SDIR"
}

@test "builder stderr is kept, not discarded to /dev/null" {
    setup_conc
    _mk_proj "$PROJ" 0
    _fire "$PROJ" "$SDIR"
    sleep 1
    [ -f "$SDIR/graph-rebuild.err" ]
    grep -q "graph_cluster.py failed" "$SDIR/graph-rebuild.err"
    rm -rf "$PROJ" "$SDIR"
}

# ── Unbounded log growth (regression) ───────────────────────────────────────
# graph-updates.log is appended to on every matching Write/Edit with no trim
# anywhere in this hook, unlike hook-logger.sh's tail -n 500 pattern
# (hook-logger.sh:49-55) or instinct-capture.sh:88-92.
@test "graph-updates.log is trimmed to 500 lines, newest kept" {
    mkdir -p .claude/graph
    echo '{"codebase":{"scanned_files":42,"classes":[{"name":"A"},{"name":"B"},{"name":"C"},{"name":"D"},{"name":"E"}]}}' > .claude/graph/graph.json
    touch "$UNITY_HOOK_STATE_DIR/graph-health-warned-$(date +%Y-%m-%d)"
    for i in $(seq 1 600); do echo "line-$i"; done > "$UNITY_HOOK_STATE_DIR/graph-updates.log"
    run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"Assets/Test.cs\"}}' | CLAUDE_PROJECT_DIR= UNITY_HOOK_STATE_DIR='$UNITY_HOOK_STATE_DIR' bash $HOOK 2>&1"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$UNITY_HOOK_STATE_DIR/graph-updates.log" | tr -d ' ')" -le 500 ]
    # newest kept: the just-appended trigger line must survive the trim
    tail -n 1 "$UNITY_HOOK_STATE_DIR/graph-updates.log" | grep -q "Assets/Test.cs"
    # oldest lines must be gone
    ! grep -q "^line-1$" "$UNITY_HOOK_STATE_DIR/graph-updates.log"
}
