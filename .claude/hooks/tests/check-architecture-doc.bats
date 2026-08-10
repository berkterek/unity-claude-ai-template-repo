#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-architecture-doc.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
    # Paths must avoid every should_skip_path component (Editor/, Plugins/,
    # ThirdParty/, PackageCache/, Tests/, Test/, Spec/) or the cases pass
    # vacuously.
    ROOT="$TMPDIR_TEST/proj/_GameFolders/Scripts/Games"
    DOMAIN_DIR="$ROOT/Concretes/Players"
    DOC="$DOMAIN_DIR/ARCHITECTURE.md"
    mkdir -p "$DOMAIN_DIR"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

run_hook() {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"
}

write_valid_doc() {
    printf '# Players\n## Purpose\nMoves and damages the player character.\n## Boundary\nNever tracks score.\n## How to extend\nInterface in Abstracts, pure C# logic in Concretes, register in PlayerModule.Install.\n## Gotchas\nPrefab-local refs are serialized, not injected.\n' > "$DOC"
}

# --- Trigger B: well-formed doc passes ---

@test "accepts a well-formed doc" {
    write_valid_doc
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

# --- Trigger B: heading contract ---

@test "blocks reordered headings" {
    printf '# P\n## Boundary\nx\n## Purpose\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "blocks a missing heading" {
    printf '# P\n## Purpose\nx\n## Boundary\nx\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "blocks an extra fifth heading" {
    printf '# P\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n## Extra\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "blocks a misspelled heading" {
    printf '# P\n## Purpouse\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "blocks a doc with no H1" {
    printf '## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

# --- Trigger B: fence-strip regression guard ---
# A naive `grep -c '^# '` counts a `# comment` inside a ``` fence as a second
# H1 and spuriously blocks a legal doc. Verified: 2 instead of 1.

@test "allows a # comment inside a fenced code block (fence-strip guard)" {
    {
        printf '# Players\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\n'
        printf '```\n# this is a shell comment, not a heading\n```\n'
    } > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

@test "allows a ## line inside a fenced code block" {
    {
        printf '# Players\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\n'
        printf '```\n## not a real heading\n```\n'
    } > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

# --- Trigger B: line cap and the wc -l regression guard ---
# `wc -l` reports one fewer on a file with no trailing newline, so a 41-line doc
# would slip past a <= 40 cap. This case fails against a wc -l implementation.

@test "blocks a 41-line doc with no trailing newline (wc -l guard)" {
    {
        printf '# Players\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\n'
        for i in $(seq 1 32); do printf 'line%s\n' "$i"; done
        printf 'final line with no newline'
    } > "$DOC"
    [ "$(awk 'END{print NR}' "$DOC")" -eq 41 ]
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "accepts a doc at exactly 40 lines" {
    {
        printf '# Players\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\n'
        for i in $(seq 1 32); do printf 'line%s\n' "$i"; done
    } > "$DOC"
    [ "$(awk 'END{print NR}' "$DOC")" -eq 40 ]
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

# --- Trigger B: class-name ban ---

@test "blocks a class name in ## Boundary" {
    printf '# P\n## Purpose\nx\n## Boundary\nConfig arrives via AudioConfiguration.\n## How to extend\nx\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "blocks a class name in ## How to extend — the ban is section-independent" {
    printf '# P\n## Purpose\nx\n## Boundary\nx\n## How to extend\nImplement IMoveHandler and add a MoveHandler.\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

@test "allows PlayerModule.Install — the Module suffix is deliberately exempt" {
    printf '# P\n## Purpose\nx\n## Boundary\nx\n## How to extend\nRegister it in PlayerModule.Install.\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

@test "allows lowercase prose words that share a banned suffix" {
    printf '# P\n## Purpose\nx\n## Boundary\nthe service layer lives elsewhere\n## How to extend\nadd a handler and a provider\n## Gotchas\nthe view is a shell only\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 0 ]
}

@test "block message points at /knowledge-graph for concrete names" {
    printf '# P\n## Purpose\nx\n## Boundary\nx\n## How to extend\nUse MoveHandler.\n## Gotchas\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
    [[ "$output" == *"knowledge-graph"* ]]
}

# --- Trigger B: placement ---

@test "blocks ARCHITECTURE.md under Abstracts/" {
    mkdir -p "$ROOT/Abstracts/Players"
    printf '# Players\n' > "$ROOT/Abstracts/Players/ARCHITECTURE.md"
    run_hook "$ROOT/Abstracts/Players/ARCHITECTURE.md"
    [ "$status" -eq 2 ]
}

@test "blocks a stray ARCHITECTURE.md directly under Concretes/" {
    printf '# Stray\n' > "$ROOT/Concretes/ARCHITECTURE.md"
    run_hook "$ROOT/Concretes/ARCHITECTURE.md"
    [ "$status" -eq 2 ]
}

@test "ignores an ARCHITECTURE.md outside Games/" {
    printf '# Elsewhere\n' > "$TMPDIR_TEST/ARCHITECTURE.md"
    run_hook "$TMPDIR_TEST/ARCHITECTURE.md"
    [ "$status" -eq 0 ]
}

# --- Trigger A: missing doc warns, never blocks ---

@test "warns (exit 0) when a .cs lands in a domain with no doc" {
    run_hook "$DOMAIN_DIR/PlayerService.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing"* ]]
}

@test "silent when the domain doc already exists" {
    write_valid_doc
    run_hook "$DOMAIN_DIR/PlayerService.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Regression guard: an earlier draft exempted Infrastructure/ from the nag.
# The exemption was removed on purpose — this case fails if it returns.
@test "Infrastructure/ is NOT exempt from the missing-doc warning" {
    mkdir -p "$ROOT/Concretes/Infrastructure"
    run_hook "$ROOT/Concretes/Infrastructure/AppModules.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing"* ]]
}

@test "warns on a .cs with no domain folder instead of deferring to the other hook" {
    run_hook "$ROOT/Concretes/Foo.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No domain folder"* ]]
}

@test "ignores a non-.cs, non-ARCHITECTURE.md file" {
    run_hook "$DOMAIN_DIR/PlayerConfiguration.asset"
    [ "$status" -eq 0 ]
}

@test "ignores an empty file_path" {
    run bash -c "echo '{\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- Implementation guards ---

@test "does not use wc -l for the line count" {
    run bash -c "grep -c 'awk .END{print NR}.' $HOOK"
    [ "$output" -ge 1 ]
}

@test "Module is absent from the class-name alternation (deliberate exemption)" {
    run bash -c "grep -c 'Installer)' $HOOK"
    [ "$output" -ge 1 ]
    run bash -c "grep -c 'Module|' $HOOK || true"
    [ "$output" -eq 0 ]
}

# --- Profile and mode gating ---

@test "UNITY_HOOK_PROFILE=minimal skips this standard-level hook" {
    printf '# P\n## Boundary\nx\n' > "$DOC"
    run bash -c "UNITY_HOOK_PROFILE=minimal bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$DOC\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades a block to exit 0" {
    printf '# P\n## Boundary\nx\n' > "$DOC"
    run bash -c "UNITY_HOOK_MODE=warn bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$DOC\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}

@test "DISABLE_HOOK_CHECK_ARCHITECTURE_DOC=1 bypasses the hook" {
    printf '# P\n## Boundary\nx\n' > "$DOC"
    run bash -c "DISABLE_HOOK_CHECK_ARCHITECTURE_DOC=1 bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$DOC\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}
