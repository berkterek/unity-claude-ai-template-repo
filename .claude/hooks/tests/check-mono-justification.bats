#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-mono-justification.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMP="$(mktemp -d)"
    # The hook scopes itself to _GameFolders/Scripts/Games/ and reads the file from
    # DISK (it is a PostToolUse hook), so every fixture must be a real file under a
    # path containing that segment — and must avoid every should_skip_path component
    # (Editor/, Plugins/, ThirdParty/, PackageCache/, Tests/, Test/, Spec/).
    DOMAIN="$TMP/proj/_GameFolders/Scripts/Games/Concretes/Players"
    mkdir -p "$DOMAIN"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMP"
}

run_hook() {
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$1\"}}' | bash $HOOK"
}

# Writes $2 as the body of a file at $1 and echoes the path.
mk() {
    printf '%s\n' "$2" > "$1"
}

# Pads a file to >150 lines so Check 2 fires.
pad() {
    for i in $(seq 1 "$2"); do echo "    // filler line $i" >> "$1"; done
}

# --- Check 1: unjustified MonoBehaviour (Card 0) ---

@test "warns on MonoBehaviour with no SerializeField and no Unity callback" {
    F="$DOMAIN/Unjustified.cs"
    mk "$F" 'using UnityEngine;
public sealed class Unjustified : MonoBehaviour
{
    public void DoWork() { }
}'
    run_hook "$F"
    [ "$status" -eq 0 ]                       # warn-only hook — never blocks
    [[ "$output" == *"no [SerializeField] fields and no Unity callbacks"* ]]
}

@test "SerializeField alone justifies MonoBehaviour — no warning" {
    F="$DOMAIN/Justified.cs"
    mk "$F" 'using UnityEngine;
public sealed class Justified : MonoBehaviour
{
    [SerializeField] private Rigidbody _rigidbody;
}'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" != *"no Unity callbacks"* ]]
}

@test "a Unity lifecycle callback alone justifies MonoBehaviour — no warning" {
    for cb in Awake Start OnEnable OnDisable OnDestroy Update FixedUpdate LateUpdate OnTriggerEnter OnCollisionEnter; do
        F="$DOMAIN/Cb$cb.cs"
        mk "$F" "using UnityEngine;
public sealed class Cb$cb : MonoBehaviour
{
    private void $cb() { }
}"
        run_hook "$F"
        [ "$status" -eq 0 ]
        [[ "$output" != *"no Unity callbacks"* ]]
    done
}

@test "a [SerializeField] appearing only in a comment does not justify" {
    F="$DOMAIN/CommentOnly.cs"
    mk "$F" 'using UnityEngine;
public sealed class CommentOnly : MonoBehaviour
{
    // [SerializeField] private Rigidbody _rb;   <- commented out
    public void DoWork() { }
}'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no [SerializeField] fields and no Unity callbacks"* ]]
}

@test "non-MonoBehaviour class is never warned about" {
    F="$DOMAIN/PureService.cs"
    mk "$F" 'public sealed class PureService : IPureService
{
    public void DoWork() { }
}'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Check 2: oversized shell (> 150 lines) — the documented promise in solid-oop.md ---

@test "warns when a MonoBehaviour shell exceeds 150 lines" {
    F="$DOMAIN/Fat.cs"
    mk "$F" 'using UnityEngine;
public sealed class Fat : MonoBehaviour
{
    [SerializeField] private Rigidbody _rigidbody;
    private void Update() { }'
    pad "$F" 200
    echo "}" >> "$F"
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"exceeds 150 lines"* ]]
}

@test "does NOT warn about size at exactly 150 lines" {
    F="$DOMAIN/Exact.cs"
    mk "$F" 'using UnityEngine;
public sealed class Exact : MonoBehaviour
{
    [SerializeField] private Rigidbody _rigidbody;'
    # file currently has 4 lines; pad to exactly 150
    pad "$F" 146
    [ "$(wc -l < "$F" | tr -d ' ')" -eq 150 ]
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" != *"exceeds 150 lines"* ]]
}

@test "both checks can fire on the same file" {
    F="$DOMAIN/FatAndUnjustified.cs"
    mk "$F" 'using UnityEngine;
public sealed class FatAndUnjustified : MonoBehaviour
{
    public void DoWork() { }'
    pad "$F" 200
    echo "}" >> "$F"
    run_hook "$F"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no [SerializeField] fields and no Unity callbacks"* ]]
    [[ "$output" == *"exceeds 150 lines"* ]]
}

# --- Scope and path exclusions ---

@test "ignores non-cs files" {
    F="$DOMAIN/notes.md"
    mk "$F" 'class Foo : MonoBehaviour { }'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ignores files outside _GameFolders/Scripts/Games/" {
    OUT="$TMP/proj/_Framework/Events"; mkdir -p "$OUT"
    F="$OUT/Thing.cs"
    mk "$F" 'using UnityEngine;
public sealed class Thing : MonoBehaviour { public void DoWork() { } }'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "skips test paths via should_skip_path" {
    T="$TMP/proj/_GameFolders/Scripts/Games/Tests/ProjPlayModeTest"; mkdir -p "$T"
    F="$T/FooTests.cs"
    mk "$F" 'using UnityEngine;
public sealed class FooTests : MonoBehaviour { public void DoWork() { } }'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "skips Editor paths via should_skip_path" {
    E="$TMP/proj/_GameFolders/Scripts/Games/Editor"; mkdir -p "$E"
    F="$E/MyTool.cs"
    mk "$F" 'using UnityEngine;
public sealed class MyTool : MonoBehaviour { public void DoWork() { } }'
    run_hook "$F"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a file that does not exist on disk is a silent no-op (PostToolUse contract)" {
    run_hook "$DOMAIN/NeverWritten.cs"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "empty file_path exits 0" {
    run bash -c "echo '{\"tool_input\":{}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- Profile / kill switches ---

@test "DISABLE_HOOK_CHECK_MONO_JUSTIFICATION=1 silences the hook" {
    F="$DOMAIN/Unjustified2.cs"
    mk "$F" 'using UnityEngine;
public sealed class Unjustified2 : MonoBehaviour { public void DoWork() { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | DISABLE_HOOK_CHECK_MONO_JUSTIFICATION=1 bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "minimal profile skips this standard-level hook" {
    F="$DOMAIN/Unjustified3.cs"
    mk "$F" 'using UnityEngine;
public sealed class Unjustified3 : MonoBehaviour { public void DoWork() { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | UNITY_HOOK_PROFILE=minimal bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DISABLE_UNITY_HOOKS=1 silences the hook" {
    F="$DOMAIN/Unjustified4.cs"
    mk "$F" 'using UnityEngine;
public sealed class Unjustified4 : MonoBehaviour { public void DoWork() { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | DISABLE_UNITY_HOOKS=1 bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Regression: the callback list is the blocking hook's escape hatch --------
# check-no-monobehaviour-in-services.sh early-exits on unity_monobehaviour_is_justified.
# A Unity message the list omits is not stderr noise there — it is exit 2 on a legal
# Controller. These four were measured blocked before the list was extended.

@test "OnValidate alone justifies a MonoBehaviour" {
    F="$DOMAIN/ValidateOnly.cs"
    mk "$F" 'using UnityEngine;
public sealed class ValidateOnly : MonoBehaviour { private void OnValidate() { transform.position = Vector3.zero; } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "OnMouseDown alone justifies a MonoBehaviour" {
    F="$DOMAIN/MouseOnly.cs"
    mk "$F" 'using UnityEngine;
public sealed class MouseOnly : MonoBehaviour { private void OnMouseDown() { transform.position = Vector3.zero; } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "OnDrawGizmos alone justifies a MonoBehaviour" {
    F="$DOMAIN/GizmoOnly.cs"
    mk "$F" 'using UnityEngine;
public sealed class GizmoOnly : MonoBehaviour { private void OnDrawGizmosSelected() { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "OnApplicationPause alone justifies a MonoBehaviour" {
    F="$DOMAIN/AppPauseOnly.cs"
    mk "$F" 'using UnityEngine;
public sealed class AppPauseOnly : MonoBehaviour { private void OnApplicationPause(bool paused) { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "an ordinary On*-named handler is NOT mistaken for a Unity callback" {
    F="$DOMAIN/OrdinaryHandler.cs"
    mk "$F" 'using UnityEngine;
public sealed class OrdinaryHandler : MonoBehaviour { private void OnScoreChanged(int s) { } }'
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$F\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no [SerializeField] fields and no Unity callbacks"* ]]
}
