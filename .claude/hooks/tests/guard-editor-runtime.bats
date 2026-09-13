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

# --- Effective post-edit content (2026-09-13) -------------------------------
# An Edit's new_string is a SLICE of the file. The `#if UNITY_EDITOR` guard that makes the
# `using UnityEditor;` legal sits at the top and is almost never inside the slice, so judging
# the fragment alone blocked every edit to an already-correct runtime file. Disk is
# authoritative; the fragment is only the fallback when there is no file to splice into.

@test "allows an Edit whose fragment lacks the guard when the file on disk has it" {
    local f="$BATS_TEST_TMPDIR/Assets/Scripts/Guarded.cs"
    mkdir -p "$(dirname "$f")"
    printf '#if UNITY_EDITOR\nusing UnityEditor;\n#endif\nclass Guarded { void A(){} }\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"void A(){}\",\"new_string\":\"void A(){ EditorUtility.SetDirty(this); }\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "still blocks an Edit that introduces UnityEditor into an unguarded file on disk" {
    local f="$BATS_TEST_TMPDIR/Assets/Scripts/Plain.cs"
    mkdir -p "$(dirname "$f")"
    printf 'class Plain { void A(){} }\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"void A(){}\",\"new_string\":\"void A(){ UnityEditor.EditorUtility.SetDirty(this); }\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "a Write payload is judged whole, and blocks a brand-new unguarded file" {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"Assets/Scripts/New.cs\",\"content\":\"using UnityEditor; class New {}\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "an Edit REMOVING the only unguarded UnityEditor line is allowed — the file is fixable" {
    local f="$BATS_TEST_TMPDIR/Assets/Scripts/Fixable.cs"
    mkdir -p "$(dirname "$f")"
    printf 'using UnityEditor;\nclass Fixable { void A(){} }\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\",\"old_string\":\"using UnityEditor;\\n\",\"new_string\":\"\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
