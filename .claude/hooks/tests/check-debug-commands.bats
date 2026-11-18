#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-debug-commands.sh"
    ROOT_TEST="$(mktemp -d)"
    TMPDIR_TEST="$ROOT_TEST/_GameFolders/Scripts/Games/Concretes/Levels"
    INFRA_TEST="$ROOT_TEST/_GameFolders/Scripts/Games/Concretes/Infrastructure"
    mkdir -p "$TMPDIR_TEST" "$INFRA_TEST"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$ROOT_TEST"
}

run_write() {
    jq -n --arg p "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$ROOT_TEST/in.json"
    run bash -c "bash $HOOK < '$ROOT_TEST/in.json'"
}

guarded() {
    printf '#if UNITY_EDITOR || DEVELOPMENT_BUILD\npublic sealed class LevelDebugCommands\n{\n    public void Win()\n    {\n        %s\n    }\n}\n#endif\n' "$1"
}

# --- *DebugCommands.cs content ---

@test "blocks Publish in a DebugCommands file" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded '_eventBus.Publish(new LevelCompleteEvent());')"
    [ "$status" -eq 2 ]
}

@test "blocks FindFirstObjectByType" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded 'Object.FindFirstObjectByType<LevelView>();')"
    [ "$status" -eq 2 ]
}

@test "blocks FindObjectOfType" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded 'Object.FindObjectOfType<LevelView>();')"
    [ "$status" -eq 2 ]
}

@test "blocks Container.Resolve" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded 'gameScope.Container.Resolve<ILevelService>().CompleteLevel();')"
    [ "$status" -eq 2 ]
}

@test "blocks missing dev-only guard" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" 'public sealed class LevelDebugCommands { public void Win() { _levelService.CompleteLevel(); } }'
    [ "$status" -eq 2 ]
}

@test "allows the guard written in either order" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded '_levelService.CompleteLevel();' | sed 's/UNITY_EDITOR || DEVELOPMENT_BUILD/DEVELOPMENT_BUILD || UNITY_EDITOR/')"
    [ "$status" -eq 0 ]
}

@test "allows a clean command class" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded '_levelService.CompleteLevel();')"
    [ "$status" -eq 0 ]
}

@test "allows an Edit that removes the Publish line" {
    local f="$TMPDIR_TEST/LevelDebugCommands.cs"
    guarded '_eventBus.Publish(new LevelCompleteEvent());' > "$f"
    jq -n --arg p "$f" --arg o '_eventBus.Publish(new LevelCompleteEvent());' --arg n '_levelService.CompleteLevel();' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' > "$ROOT_TEST/in.json"
    run bash -c "bash $HOOK < '$ROOT_TEST/in.json'"
    [ "$status" -eq 0 ]
}

@test "blocks an Edit that adds a Publish line" {
    local f="$TMPDIR_TEST/LevelDebugCommands.cs"
    guarded '_levelService.CompleteLevel();' > "$f"
    jq -n --arg p "$f" --arg o '_levelService.CompleteLevel();' --arg n '_eventBus.Publish(new LevelCompleteEvent());' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' > "$ROOT_TEST/in.json"
    run bash -c "bash $HOOK < '$ROOT_TEST/in.json'"
    [ "$status" -eq 2 ]
}

@test "ignores Publish in a non-DebugCommands file" {
    run_write "$TMPDIR_TEST/LevelService.cs" 'public void Complete() { _eventBus.Publish(new LevelCompleteEvent()); }'
    [ "$status" -eq 0 ]
}

@test "ignores comment-only Publish" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded '// never Publish here: _eventBus.Publish(x);')"
    [ "$status" -eq 0 ]
}

# --- accessor fencing ---

@test "blocks DebugCommandRegistryAccessor in game code" {
    run_write "$TMPDIR_TEST/LevelService.cs" 'void A() { DebugCommandRegistryAccessor.Instance.Register(this); }'
    [ "$status" -eq 2 ]
}

@test "allows DebugCommandRegistryAccessor in DebugCommandsModule.cs" {
    run_write "$INFRA_TEST/DebugCommandsModule.cs" '#if UNITY_EDITOR || DEVELOPMENT_BUILD
builder.RegisterBuildCallback(c => DebugCommandRegistryAccessor.Set(c.Resolve<IDebugCommandRegistry>()));
#endif'
    [ "$status" -eq 0 ]
}

@test "allows DebugCommandRegistryAccessor inside the framework package" {
    mkdir -p "$ROOT_TEST/packages/framework/Editors"
    run_write "$ROOT_TEST/packages/framework/Editors/DebugCommandsMenu.cs" 'var r = DebugCommandRegistryAccessor.Instance;'
    [ "$status" -eq 0 ]
}

@test "still blocks when a fixed-name temp file is left in /tmp (macOS mktemp suffix)" {
    touch /tmp/unity_hook_XXXXXX.cs
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "$(guarded '_eventBus.Publish(new LevelCompleteEvent());')"
    rm -f /tmp/unity_hook_XXXXXX.cs
    [ "$status" -eq 2 ]
}

@test "blocks a guard that wraps only part of the file" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" 'public sealed class LevelDebugCommands
{
#if UNITY_EDITOR || DEVELOPMENT_BUILD
    public void Win() { _levelService.CompleteLevel(); }
#endif
}'
    [ "$status" -eq 2 ]
}

@test "allows comments before the guard" {
    run_write "$TMPDIR_TEST/LevelDebugCommands.cs" "// Level cheats
$(guarded '_levelService.CompleteLevel();')"
    [ "$status" -eq 0 ]
}

@test "ignores non-C# files" {
    run_write "$ROOT_TEST/docs/LevelDebugCommands.md" '_eventBus.Publish(x);'
    [ "$status" -eq 0 ]
}
