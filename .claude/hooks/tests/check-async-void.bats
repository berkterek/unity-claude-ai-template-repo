#!/usr/bin/env bats
#
# check-async-void.sh is a WARN hook: it always exits 0. Asserting on the exit
# code alone would pass whether or not the hook noticed anything, so every test
# here asserts on the emitted message. `run` captures stdout and stderr together.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-async-void.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns on async void outside a Unity lifecycle method" {
    local f="$TMPDIR_TEST/LoaderService.cs"
    printf 'public class LoaderService{ async void LoadAll(){ await T(); } }\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"async void"* ]]
}

@test "stays silent on async void Start — Unity lifecycle is exempt" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'public class PlayerController{ async void Start(){ await T(); } }\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "stays silent on async UniTask" {
    local f="$TMPDIR_TEST/LoaderService.cs"
    printf 'public class LoaderService{ async UniTask LoadAsync(CancellationToken ct){ } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "exempts test paths" {
    local d="$TMPDIR_TEST/Tests"; mkdir -p "$d"
    printf 'async void LoadAll(){}\n' > "$d/LoaderTests.cs"
    fire "$d/LoaderTests.cs"
    [ -z "$output" ]
}

@test "ignores a non-existent file" {
    fire "$TMPDIR_TEST/Missing.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
