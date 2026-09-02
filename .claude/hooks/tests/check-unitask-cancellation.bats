#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-unitask-cancellation.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns on async UniTask with no CancellationToken parameter" {
    local f="$TMPDIR_TEST/LoaderService.cs"
    printf 'public class LoaderService{\n    public async UniTask LoadAsync()\n    {\n    }\n}\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "stays silent when the token is present" {
    local f="$TMPDIR_TEST/LoaderService.cs"
    printf 'public class LoaderService{\n    public async UniTask LoadAsync(CancellationToken ct)\n    {\n    }\n}\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "stays silent on an override — the signature is not ours to change" {
    local f="$TMPDIR_TEST/LoaderService.cs"
    printf 'public class LoaderService{\n    public override async UniTask LoadAsync()\n    {\n    }\n}\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "exempts test paths" {
    local d="$TMPDIR_TEST/Tests"; mkdir -p "$d"
    printf 'public async UniTask LoadAsync()\n{\n}\n' > "$d/LoaderTests.cs"
    fire "$d/LoaderTests.cs"
    [ -z "$output" ]
}

@test "ignores a non-.cs file" {
    printf 'async UniTask LoadAsync()\n{\n}\n' > "$TMPDIR_TEST/notes.md"
    fire "$TMPDIR_TEST/notes.md"
    [ -z "$output" ]
}
