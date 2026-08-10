#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-domain-folder-structure.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
    # Paths must contain a literal Games/Abstracts|Concretes segment and must NOT
    # contain any component should_skip_path rejects (Editor/, Plugins/,
    # ThirdParty/, PackageCache/, Tests/, Test/, Spec/) — otherwise every case
    # would pass vacuously with exit 0 and the suite would prove nothing.
    ROOT="$TMPDIR_TEST/proj/_GameFolders/Scripts/Games"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

run_hook() {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"
}

# --- Layer names in the domain position: blocked (14 forms) ---

@test "blocks Services/ as first segment under Concretes" {
    run_hook "$ROOT/Concretes/Services/AudioService.cs"
    [ "$status" -eq 2 ]
}

@test "blocks singular Service/ as first segment" {
    run_hook "$ROOT/Concretes/Service/AudioService.cs"
    [ "$status" -eq 2 ]
}

@test "blocks Views/ as first segment" {
    run_hook "$ROOT/Concretes/Views/HUDView.cs"
    [ "$status" -eq 2 ]
}

@test "blocks Manager/ as first segment" {
    run_hook "$ROOT/Concretes/Manager/EnemyManager.cs"
    [ "$status" -eq 2 ]
}

@test "blocks Controllers/ as first segment" {
    run_hook "$ROOT/Concretes/Controllers/PlayerController.cs"
    [ "$status" -eq 2 ]
}

@test "blocks Interfaces/ as first segment under Abstracts" {
    run_hook "$ROOT/Abstracts/Interfaces/IAudioService.cs"
    [ "$status" -eq 2 ]
}

@test "blocks CONFIGS/ — matching is case-insensitive" {
    run_hook "$ROOT/Concretes/CONFIGS/AudioConfiguration.cs"
    [ "$status" -eq 2 ]
}

@test "blocks ProViDers/ — mixed case still matches" {
    run_hook "$ROOT/Concretes/ProViDers/BasicAudioProvider.cs"
    [ "$status" -eq 2 ]
}

# --- Catch-all names in the domain position: blocked (3 forms) ---

@test "blocks Core/ as first segment (catch-all)" {
    run_hook "$ROOT/Concretes/Core/GameFlow.cs"
    [ "$status" -eq 2 ]
}

@test "blocks lowercase core/ (catch-all, case-insensitive)" {
    run_hook "$ROOT/Concretes/core/GameFlow.cs"
    [ "$status" -eq 2 ]
}

@test "blocks Generals/ as first segment (catch-all)" {
    run_hook "$ROOT/Concretes/Generals/Helpers.cs"
    [ "$status" -eq 2 ]
}

@test "blocks singular General/ as first segment" {
    run_hook "$ROOT/Concretes/General/Helpers.cs"
    [ "$status" -eq 2 ]
}

@test "catch-all message differs from layer message (points at _Framework)" {
    run_hook "$ROOT/Concretes/Core/GameFlow.cs"
    [ "$status" -eq 2 ]
    [[ "$output" == *"_Framework/"* ]]
}

# --- No domain folder at all: blocked ---

@test "blocks a .cs file directly under Concretes/" {
    run_hook "$ROOT/Concretes/Foo.cs"
    [ "$status" -eq 2 ]
}

@test "blocks a .cs file directly under Abstracts/" {
    run_hook "$ROOT/Abstracts/IFoo.cs"
    [ "$status" -eq 2 ]
}

# --- Below the domain folder is free: never inspected ---

@test "allows Players/Services/ — layer name below a domain is legal" {
    run_hook "$ROOT/Concretes/Players/Services/MoveService.cs"
    [ "$status" -eq 0 ]
}

@test "allows Players/Handlers/ — no file-count threshold exists" {
    run_hook "$ROOT/Concretes/Players/Handlers/MoveHandler.cs"
    [ "$status" -eq 0 ]
}

@test "allows Players/Core/ — catch-all ban is first-segment only, by design" {
    run_hook "$ROOT/Concretes/Players/Core/Internals.cs"
    [ "$status" -eq 0 ]
}

@test "allows a flat domain folder" {
    run_hook "$ROOT/Concretes/Players/PlayerService.cs"
    [ "$status" -eq 0 ]
}

@test "allows the mirrored Abstracts side of a real domain" {
    run_hook "$ROOT/Abstracts/Players/IPlayerService.cs"
    [ "$status" -eq 0 ]
}

@test "allows a singular mass-noun domain" {
    run_hook "$ROOT/Concretes/Audio/AudioService.cs"
    [ "$status" -eq 0 ]
}

@test "allows Infrastructure/ as a domain" {
    run_hook "$ROOT/Concretes/Infrastructure/AppModules.cs"
    [ "$status" -eq 0 ]
}

# --- Out of scope: exits 0 ---

@test "ignores ARCHITECTURE.md — this hook is .cs only" {
    run_hook "$ROOT/Concretes/Services/ARCHITECTURE.md"
    [ "$status" -eq 0 ]
}

@test "ignores a path with no Games/Abstracts|Concretes segment" {
    run_hook "$TMPDIR_TEST/proj/_Framework/Events/EventBus.cs"
    [ "$status" -eq 0 ]
}

@test "ignores a path outside the project entirely" {
    run_hook "$TMPDIR_TEST/elsewhere/Foo.cs"
    [ "$status" -eq 0 ]
}

@test "ignores an empty file_path" {
    run bash -c "echo '{\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "respects should_skip_path — Editor code is exempt" {
    run_hook "$ROOT/Concretes/Services/Editor/AudioServiceEditor.cs"
    [ "$status" -eq 0 ]
}

# --- Regression guard: the hook must not be a silent no-op ---
# An earlier draft extracted the Abstracts|Concretes side with `sed -E`, which
# errors on BSD sed and emits empty output, making every check fall through.
# This asserts the extraction actually works.

@test "no sed used for side extraction (silent-no-op regression guard)" {
    run bash -c "grep -c '^[^#]*sed ' $HOOK || true"
    [ "$output" -eq 0 ]
}

# --- Profile and mode gating ---

@test "UNITY_HOOK_PROFILE=minimal skips this standard-level hook" {
    run bash -c "UNITY_HOOK_PROFILE=minimal bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$ROOT/Concretes/Services/A.cs\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades a block to exit 0" {
    run bash -c "UNITY_HOOK_MODE=warn bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$ROOT/Concretes/Services/A.cs\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}

@test "DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1 bypasses the hook" {
    run bash -c "DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1 bash -c \"echo '{\\\"tool_input\\\":{\\\"file_path\\\":\\\"$ROOT/Concretes/Services/A.cs\\\"}}' | bash $HOOK\""
    [ "$status" -eq 0 ]
}
