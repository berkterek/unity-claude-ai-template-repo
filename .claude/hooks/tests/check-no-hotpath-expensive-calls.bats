#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.
# Detection is scoped to the body of a hot-path method, so the "same call
# outside a hot path" case is tested explicitly — that is the boundary that
# separates a real finding from a false positive.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-no-hotpath-expensive-calls.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns on GetComponent inside Update" {
    local f="$TMPDIR_TEST/EnemyController.cs"
    printf 'public class E{\n    void Update()\n    {\n        var rb = GetComponent<Rigidbody>();\n    }\n}\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "stays silent on a hot path with no expensive call" {
    local f="$TMPDIR_TEST/EnemyController.cs"
    printf 'public class E{\n    void Update()\n    {\n        _handler.Tick(Time.deltaTime);\n    }\n}\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "stays silent when the file declares no hot-path method" {
    local f="$TMPDIR_TEST/LevelBuilder.cs"
    printf 'public class L{\n    void Build()\n    {\n        var rb = GetComponent<Rigidbody>();\n    }\n}\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "ignores a non-.cs file" {
    printf 'void Update(){ GetComponent<Rigidbody>(); }\n' > "$TMPDIR_TEST/notes.md"
    fire "$TMPDIR_TEST/notes.md"
    [ -z "$output" ]
}
