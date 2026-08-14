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

@test "allows files inside the project's plural Editors/ folder" {
    # rules/architecture.md documents Scripts/Editors/ and _Framework/Editors/,
    # both compiled by an .asmdef with includePlatforms: ["Editor"]. Matching only
    # the singular Editor/ made this hook reject the project's own Editor folder.
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/_GameFolders/Scripts/Editors/AsmdefSetup/Tool.cs\",\"new_string\":\"using UnityEditor; class Tool {}\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "still blocks unguarded UnityEditor in a folder merely named Editorial" {
    # Guards against the plural fix widening into a substring match.
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Editorial/Foo.cs\",\"new_string\":\"using UnityEditor; class Foo { void F(){ EditorUtility.SetDirty(this); } }\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows runtime code with no UnityEditor usage" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/Foo.cs\",\"new_string\":\"using UnityEngine; class Foo : MonoBehaviour {}\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
