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

# --- _Framework/<Subfolder>/ scope ---------------------------------------
# The unit here is an ASSEMBLY boundary, not a feature boundary: an .asmdef flag
# (noEngineReferences, platform filters) is per-folder and unenforceable per-file,
# so the folder IS the boundary. Before this scope existed a _Framework doc fell
# through to exit 0 — silently accepted and never validated, which is worse than
# a block because nothing told the author the doc went unchecked.

fw_setup() {
    FW_ROOT="$TMPDIR_TEST/proj/Assets/_Framework"
    FW_DIR="$FW_ROOT/$1"
    FW_DOC="$FW_DIR/ARCHITECTURE.md"
    mkdir -p "$FW_DIR"
}

fw_valid_doc() {
    printf '# %s\n## Purpose\nOne sentence describing what this assembly is for.\n## Boundary\nWhat it never does, and which layer owns that instead.\n## How to extend\nContract in the abstracts folder, implementation beside it, wired in the domain module.\n## Gotchas\nThe mistake people actually make here.\n' "$1" > "$FW_DOC"
}

@test "_Framework: a well-formed subfolder doc passes" {
    fw_setup Logging
    fw_valid_doc Logging
    run_hook "$FW_DOC"
    [ "$status" -eq 0 ]
}

@test "_Framework: a subfolder doc is now VALIDATED, not silently accepted" {
    fw_setup Logging
    printf '# Logging\n## Purpose\nx\n## Gotchas\nx\n' > "$FW_DOC"   # two of four headings
    run_hook "$FW_DOC"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Headings must be exactly these four"* ]]
}

@test "_Framework: the 40-line cap applies to subfolder docs too" {
    fw_setup Logging
    fw_valid_doc Logging
    for _ in $(seq 1 40); do echo "filler line" >> "$FW_DOC"; done
    run_hook "$FW_DOC"
    [ "$status" -eq 2 ]
    [[ "$output" == *"the cap is 40"* ]]
}

@test "_Framework: class-name symbols are rejected in subfolder docs too" {
    fw_setup Logging
    fw_valid_doc Logging
    printf 'Route everything through LoggingService.\n' >> "$FW_DOC"
    run_hook "$FW_DOC"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Class names rot"* ]]
}

@test "_Framework: a doc at the _Framework root is blocked" {
    # The root is a container for independent assemblies whose whole point is that
    # they do not reference each other — one doc cannot speak for all of them.
    mkdir -p "$TMPDIR_TEST/proj/Assets/_Framework"
    ROOT_DOC="$TMPDIR_TEST/proj/Assets/_Framework/ARCHITECTURE.md"
    printf '# Framework\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$ROOT_DOC"
    run_hook "$ROOT_DOC"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not directly under _Framework/"* ]]
}

@test "_Framework: a .cs write warns when the subfolder owns an asmdef and the doc is missing" {
    fw_setup Events
    : > "$FW_DIR/FrameworkEvents.asmdef"
    printf 'public sealed class Bus { }\n' > "$FW_DIR/Bus.cs"
    run_hook "$FW_DIR/Bus.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing"* ]]
    [[ "$output" == *"ARCHITECTURE.md"* ]]
}

@test "_Framework: a .cs write stays silent once the subfolder doc exists" {
    fw_setup Events
    : > "$FW_DIR/FrameworkEvents.asmdef"
    fw_valid_doc Events
    printf 'public sealed class Bus { }\n' > "$FW_DIR/Bus.cs"
    run_hook "$FW_DIR/Bus.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

@test "_Framework: a subfolder with no asmdef is exempt — it is not an assembly boundary" {
    # Installers/ holds a single interface and owns no .asmdef, so it belongs to
    # whichever assembly picks it up. Derived from the .asmdef rather than a
    # hand-kept skip list, so a future non-assembly folder is exempt automatically.
    fw_setup Installers
    printf 'public interface IInstaller { }\n' > "$FW_DIR/IInstaller.cs"
    run_hook "$FW_DIR/IInstaller.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

@test "_Framework: a folder that later GAINS an asmdef starts being asked for a doc" {
    fw_setup Installers
    printf 'public interface IInstaller { }\n' > "$FW_DIR/IInstaller.cs"
    run_hook "$FW_DIR/IInstaller.cs"
    [[ "$output" != *"Missing"* ]]
    : > "$FW_DIR/FrameworkInstallers.asmdef"
    run_hook "$FW_DIR/IInstaller.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing"* ]]
}

@test "Games/Concretes scope is unchanged by the _Framework addition" {
    write_valid_doc
    run_hook "$DOC"
    [ "$status" -eq 0 ]
    printf '# Players\n## Purpose\nx\n' > "$DOC"
    run_hook "$DOC"
    [ "$status" -eq 2 ]
}

# --- Allowlisted Scripts/<Folder>/ scope --------------------------------------
# The third scope is DERIVED from path-allowlist.txt, not hardcoded. That file's own
# stated grounds for an entry is "the folder needs its own .asmdef", which is exactly
# the assembly-boundary criterion _Framework/ uses — so one rule covers both and the
# two lists cannot drift apart. A project that declares a folder there gets the gate
# on the same day, with no hook edit.
#
# There is NO marker to register and no registry function to extend. An earlier draft
# of this work referred to an `arch_doc_marker()` — that function never existed; the
# mechanism is _arch_doc_scope() plus path-allowlist.txt.

aw_setup() {
    AW_HOME="$TMPDIR_TEST/aw"
    mkdir -p "$AW_HOME/.claude"
    export CLAUDE_PROJECT_DIR="$AW_HOME"
    printf 'Scripts/Simulation   # reason: engine-free deterministic sim, own asmdef\n' \
        > "$AW_HOME/.claude/path-allowlist.txt"
    AW_ROOT="$AW_HOME/proj/_GameFolders/Scripts"
}

aw_doc() {
    printf '# %s\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n' "$1"
}

@test "allowlisted: a subfolder that owns an asmdef is the documented unit" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/Boards/SimBoards.asmdef"
    printf 'public sealed class Grid { }\n' > "$AW_ROOT/Simulation/Boards/Grid.cs"
    run_hook "$AW_ROOT/Simulation/Boards/Grid.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Simulation/Boards/ARCHITECTURE.md"* ]]
}

@test "allowlisted: the doc is validated like any other" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/Boards/SimBoards.asmdef"
    printf '# Boards\n## Purpose\nx\n' > "$AW_ROOT/Simulation/Boards/ARCHITECTURE.md"
    run_hook "$AW_ROOT/Simulation/Boards/ARCHITECTURE.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Headings must be exactly these four"* ]]
}

@test "allowlisted: when the folder ITSELF is the assembly, the doc sits at its root" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/SimCore.asmdef"
    printf 'public sealed class Grid { }\n' > "$AW_ROOT/Simulation/Boards/Grid.cs"
    run_hook "$AW_ROOT/Simulation/Boards/Grid.cs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Simulation/ARCHITECTURE.md"* ]]
    [[ "$output" != *"Simulation/Boards/ARCHITECTURE.md"* ]]
}

@test "allowlisted: a root doc satisfies the whole folder when it is one assembly" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/SimCore.asmdef"
    aw_doc Simulation > "$AW_ROOT/Simulation/ARCHITECTURE.md"
    printf 'public sealed class Grid { }\n' > "$AW_ROOT/Simulation/Boards/Grid.cs"
    run_hook "$AW_ROOT/Simulation/Boards/Grid.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

@test "a Scripts/ folder that is NOT allowlisted is entirely out of scope" {
    aw_setup
    mkdir -p "$AW_ROOT/Randomstuff/Foo"
    : > "$AW_ROOT/Randomstuff/Foo/Foo.asmdef"
    printf 'public sealed class X { }\n' > "$AW_ROOT/Randomstuff/Foo/X.cs"
    run_hook "$AW_ROOT/Randomstuff/Foo/X.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

@test "allowlisted: a subfolder owning no asmdef is exempt — no boundary, nothing to ask" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Notes"
    printf 'public sealed class N { }\n' > "$AW_ROOT/Simulation/Notes/N.cs"
    run_hook "$AW_ROOT/Simulation/Notes/N.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

@test "Games, Tests and Editors are never treated as allowlisted scopes" {
    # They are the three legal top-level folders, not exceptions — and Games/ already
    # has its own scope. A stray allowlist entry must not give them a second meaning.
    aw_setup
    printf 'Scripts/Games\nScripts/Tests\nScripts/Editors\n' >> "$AW_HOME/.claude/path-allowlist.txt"
    mkdir -p "$AW_ROOT/Tests/Foo"
    : > "$AW_ROOT/Tests/Foo/Foo.asmdef"
    printf 'public sealed class T { }\n' > "$AW_ROOT/Tests/Foo/T.cs"
    run_hook "$AW_ROOT/Tests/Foo/T.cs"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Missing"* ]]
}

# --- The two triggers must not contradict each other -------------------------
# Trigger A resolves the documented unit from the .asmdef and, when the scope root
# IS the assembly, warns for a doc at that root. Trigger B used to block that exact
# path unconditionally — so the only way to satisfy the warn was to write a file the
# validator refused. Both now answer with the same resolution.

@test "no contradiction: the doc Trigger A asks for is one Trigger B accepts" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/SimCore.asmdef"
    printf 'public sealed class Grid { }\n' > "$AW_ROOT/Simulation/Boards/Grid.cs"

    run_hook "$AW_ROOT/Simulation/Boards/Grid.cs"
    [[ "$output" == *"Missing"* ]]
    # Take the path the warn names and write exactly that file.
    demanded=$(printf '%s\n' "$output" | grep -o '/[^ ]*ARCHITECTURE\.md' | head -1)
    [ -n "$demanded" ]
    aw_doc Simulation > "$demanded"

    run_hook "$demanded"
    [ "$status" -eq 0 ]
}

@test "a root doc is still blocked when the scope root owns no asmdef" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation/Boards"
    : > "$AW_ROOT/Simulation/Boards/SimBoards.asmdef"   # the SUBFOLDER is the assembly
    aw_doc Simulation > "$AW_ROOT/Simulation/ARCHITECTURE.md"
    run_hook "$AW_ROOT/Simulation/ARCHITECTURE.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"owns no .asmdef of its own"* ]]
}

@test "a root doc at an assembly root is still shape-validated" {
    aw_setup
    mkdir -p "$AW_ROOT/Simulation"
    : > "$AW_ROOT/Simulation/SimCore.asmdef"
    printf '# Simulation\n## Purpose\nx\n' > "$AW_ROOT/Simulation/ARCHITECTURE.md"
    run_hook "$AW_ROOT/Simulation/ARCHITECTURE.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Headings must be exactly these four"* ]]
}
