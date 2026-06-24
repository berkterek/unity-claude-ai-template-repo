#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/guard-editor-runtime.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
}

@test "blocks unguarded UnityEditor usage in a runtime file" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Foo.cs\",\"new_string\":\"using UnityEditor; class Foo { void F(){ EditorUtility.SetDirty(this); } }\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows UnityEditor when wrapped in #if UNITY_EDITOR" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Foo.cs\",\"new_string\":\"#if UNITY_EDITOR\nusing UnityEditor;\n#endif\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows files already inside an Editor/ folder" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Editor/Tool.cs\",\"new_string\":\"using UnityEditor; class Tool {}\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows runtime code with no UnityEditor usage" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Foo.cs\",\"new_string\":\"using UnityEngine; class Foo : MonoBehaviour {}\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
