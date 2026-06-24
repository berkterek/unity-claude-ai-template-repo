#!/usr/bin/env bats
# Hooks run in a fresh `bash $HOOK` here, which does NOT inherit the interactive
# shell's `grep` function (e.g. an aliased ugrep) — so the real PATH grep is used,
# matching production. The POSIX regex fix makes detection grep-flavor independent.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-enum-byte-base.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "ecs disabled: real IEvent enum violation is NOT blocked (feature gate)" {
    local feat="$TMPDIR_TEST/features.json"; echo '{"ecs":false}' > "$feat"
    local f="$TMPDIR_TEST/FooEvent.cs"
    printf 'public struct FooEvent : IEvent { public Dir D; }\npublic enum Dir { Up, Down }\n' > "$f"
    UNITY_FEATURES_FILE="$feat" run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "ecs enabled: blocks enum without byte base in an IEvent struct" {
    local feat="$TMPDIR_TEST/features.json"; echo '{"ecs":true}' > "$feat"
    local f="$TMPDIR_TEST/FooEvent.cs"
    printf 'public struct FooEvent : IEvent { public Dir D; }\npublic enum Dir { Up, Down }\n' > "$f"
    UNITY_FEATURES_FILE="$feat" run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "ecs enabled: blocks multi-interface struct where IEvent is not first" {
    local feat="$TMPDIR_TEST/features.json"; echo '{"ecs":true}' > "$feat"
    local f="$TMPDIR_TEST/BarEvent.cs"
    printf 'public struct BarEvent : IDisposable, IEvent { public Dir D; public void Dispose(){} }\npublic enum Dir { Up, Down }\n' > "$f"
    UNITY_FEATURES_FILE="$feat" run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "ecs enabled: IEventBus injection + plain enum is NOT blocked (no IEventBus over-match)" {
    local feat="$TMPDIR_TEST/features.json"; echo '{"ecs":true}' > "$feat"
    local f="$TMPDIR_TEST/ChestController.cs"
    printf 'public class ChestController { private IEventBus _eventBus; private enum State { A, B } }\n' > "$f"
    UNITY_FEATURES_FILE="$feat" run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "ecs enabled: enum that already has byte base is allowed" {
    local feat="$TMPDIR_TEST/features.json"; echo '{"ecs":true}' > "$feat"
    local f="$TMPDIR_TEST/FooEvent.cs"
    printf 'public struct FooEvent : IEvent { public Dir D; }\npublic enum Dir : byte { Up, Down }\n' > "$f"
    UNITY_FEATURES_FILE="$feat" run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
