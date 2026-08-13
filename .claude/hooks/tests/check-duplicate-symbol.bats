#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-duplicate-symbol.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"

    # Paths must contain a literal Games/Abstracts|Concretes segment and must NOT
    # contain any component should_skip_path rejects (Editor/, Plugins/,
    # ThirdParty/, PackageCache/, Tests/, Test/, Spec/) — a rejected path exits 0
    # vacuously and would make every "blocks" assertion pass for the wrong reason.
    ROOT="$TMPDIR_TEST/proj/_GameFolders/Scripts/Games"
    DUP="$ROOT/Abstracts/Players/IPlayerService.cs"
    NEW="$ROOT/Abstracts/Players/IInventoryService.cs"

    # Fixtures live in the temp state dir and are reached via env overrides.
    # NEVER point these at the repo's own .claude/graph/graph.json — it is
    # tracked by git and a test that mutated it would dirty the working tree.
    export UNITY_FEATURES_FILE="$UNITY_HOOK_STATE_DIR/features.json"
    export UNITY_GRAPH_FILE="$UNITY_HOOK_STATE_DIR/graph.json"
    echo '{"graph": true}' > "$UNITY_FEATURES_FILE"
    write_graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)" populated
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

# write_graph <generated_at> <populated|empty>
write_graph() {
    local ts="$1" mode="$2" symbols='[]'
    if [ "$mode" = "populated" ]; then
        symbols='[{"name":"IPlayerService","file":"Games/Abstracts/Players/IPlayerService.cs","confidence":"EXTRACTED"}]'
    fi
    cat > "$UNITY_GRAPH_FILE" <<EOF
{
  "schema_version": "1.3.0",
  "generated_at": "$ts",
  "codebase": { "classes": [], "interfaces": $symbols }
}
EOF
}

run_hook() {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"
}

# --- Core behaviour ---

@test "blocks a NEW file whose symbol already exists in the graph" {
    run_hook "$DUP"
    [ "$status" -eq 2 ]
}

@test "block message names the existing file and the escape hatch" {
    run_hook "$DUP"
    [[ "$output" == *"Games/Abstracts/Players/IPlayerService.cs"* ]]
    [[ "$output" == *"DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1"* ]]
}

@test "allows a symbol that is not in the graph" {
    run_hook "$NEW"
    [ "$status" -eq 0 ]
}

@test "allows an already-existing file on disk (overwrite, not a new symbol)" {
    mkdir -p "$(dirname "$DUP")"
    touch "$DUP"
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

# --- Scope gates ---

@test "ignores paths outside Games/Abstracts and Games/Concretes" {
    run_hook "$TMPDIR_TEST/proj/_GameFolders/Scripts/Games/Ecs/Systems/IPlayerService.cs"
    [ "$status" -eq 0 ]
}

@test "ignores non-.cs files" {
    run_hook "$ROOT/Abstracts/Players/IPlayerService.asmdef"
    [ "$status" -eq 0 ]
}

@test "ignores paths should_skip_path rejects" {
    run_hook "$TMPDIR_TEST/proj/_GameFolders/Scripts/Games/Abstracts/Editor/IPlayerService.cs"
    [ "$status" -eq 0 ]
}

# --- Profile and mode switches ---

@test "minimal profile skips this hook" {
    UNITY_HOOK_PROFILE=minimal run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades the block to a warning" {
    UNITY_HOOK_MODE=warn run_hook "$DUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1 disables just this hook" {
    DISABLE_HOOK_CHECK_DUPLICATE_SYMBOL=1 run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "DISABLE_UNITY_HOOKS=1 disables it too" {
    DISABLE_UNITY_HOOKS=1 run_hook "$DUP"
    [ "$status" -eq 0 ]
}

# --- The four silent-degrade gates ---

@test "degrades silently when the graph feature is disabled" {
    echo '{"graph": false}' > "$UNITY_FEATURES_FILE"
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently when the graph feature key is absent" {
    echo '{}' > "$UNITY_FEATURES_FILE"
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently when the graph file is missing" {
    export UNITY_GRAPH_FILE="$UNITY_HOOK_STATE_DIR/does-not-exist.json"
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently on an empty-but-fresh graph (shipped-template case)" {
    write_graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)" empty
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently on a populated-but-stale graph (second template guard)" {
    write_graph "2020-01-01T00:00:00Z" populated
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently when generated_at is absent" {
    printf '{"codebase":{"classes":[],"interfaces":[{"name":"IPlayerService","file":"x.cs"}]}}\n' > "$UNITY_GRAPH_FILE"
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

@test "degrades silently when generated_at is unparseable" {
    write_graph "not-a-timestamp" populated
    run_hook "$DUP"
    [ "$status" -eq 0 ]
}

# --- Regression guard: the repo's own tracked graph must never be touched ---

@test "the repo's committed graph.json is never modified by this hook" {
    local before after
    before=$(git -C "$PWD" status --porcelain .claude/graph/graph.json)
    run_hook "$DUP"
    after=$(git -C "$PWD" status --porcelain .claude/graph/graph.json)
    [ "$before" = "$after" ]
}
