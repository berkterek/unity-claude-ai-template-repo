#!/usr/bin/env bats
#
# WARN hook — always exits 0. Tests assert on the message.
# The hook only inspects files that look Unity-facing (using UnityEngine /
# MonoBehaviour / ScriptableObject / Component), so every fixture carries one.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-null-propagation.sh"
    TMPDIR_TEST="$(mktemp -d)"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

fire() { run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"; }

@test "warns on ?. against a Unity-object field" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'using UnityEngine;\npublic class P:MonoBehaviour{ void A(){ _target?.TakeDamage(1); } }\n' > "$f"
    fire "$f"
    [ "$status" -eq 0 ]
    [[ "$output" == *"?."* ]]
}

@test "warns on 'is null' against a Unity object" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'using UnityEngine;\npublic class P:MonoBehaviour{ void A(){ if(_target is null) return; } }\n' > "$f"
    fire "$f"
    [[ "$output" == *"is null"* ]]
}

@test "stays silent on == null — the prescribed Unity check" {
    local f="$TMPDIR_TEST/PlayerController.cs"
    printf 'using UnityEngine;\npublic class P:MonoBehaviour{ void A(){ if(_target == null) return; } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "ignores a file with no Unity surface at all" {
    local f="$TMPDIR_TEST/PlainService.cs"
    printf 'public class PlainService{ void A(){ _bus?.Publish(e); } }\n' > "$f"
    fire "$f"
    [ -z "$output" ]
}

@test "exempts Editor paths" {
    local d="$TMPDIR_TEST/Editor"; mkdir -p "$d"
    printf 'using UnityEngine;\npublic class T{ void A(){ _target?.M(); } }\n' > "$d/Tool.cs"
    fire "$d/Tool.cs"
    [ -z "$output" ]
}
