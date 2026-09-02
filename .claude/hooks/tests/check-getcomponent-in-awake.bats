#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message, not the exit code.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-getcomponent-in-awake.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns on GetComponent inside Awake" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'public class PlayerController{ void Awake(){ _rb = GetComponent<Rigidbody>(); } }\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GetComponent"* ]]
}

@test "warns on GetComponentInChildren inside Awake" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'public class PlayerController{ void Awake(){ _a = GetComponentInChildren<Animator>(); } }\n' > "$f"
    fire "$f"
    [[ "$output" == *"GetComponentInChildren"* ]]
}

@test "stays silent when the file has no Awake at all" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'public class PlayerController{ void Start(){ _rb = GetComponent<Rigidbody>(); } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "stays silent on a SerializeField reference — the prescribed fix" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf '[SerializeField] private Rigidbody _rb;\npublic class P{ void Awake(){ } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "exempts test paths" {
    local d="$TMPDIR_TEST/Tests"; mkdir -p "$d"
    printf 'void Awake(){ GetComponent<Rigidbody>(); }\n' > "$d/PlayerTests.cs"
    fire "$d/PlayerTests.cs"
    [ -z "$output" ]
}
