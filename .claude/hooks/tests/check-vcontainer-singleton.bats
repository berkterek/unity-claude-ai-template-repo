#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-vcontainer-singleton.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    TMPDIR_TEST="$(mktemp -d)"
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    mkdir -p "$TMPDIR_TEST/_Framework/Events"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "blocks static Instance singleton pattern" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows EventBusAccessor (approved exception)" {
    local f="$TMPDIR_TEST/_Framework/Events/EventBusAccessor.cs"
    echo 'private static IEventBus _instance;' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows DebugCommandRegistryAccessor (approved exception)" {
    mkdir -p "$TMPDIR_TEST/packages/framework/DebugCommands"
    local f="$TMPDIR_TEST/packages/framework/DebugCommands/DebugCommandRegistryAccessor.cs"
    echo 'private static IDebugCommandRegistry _instance;' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows non-singleton static readonly" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'private static readonly int JumpHash = Animator.StringToHash("Jump");' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips singleton check (standard level)" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    UNITY_HOOK_PROFILE=minimal run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "UNITY_HOOK_MODE=warn downgrades singleton block to warning" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    UNITY_HOOK_MODE=warn run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

# --- Effective post-edit content (PreToolUse must accept a fix, and see a new file) ---

@test "Write that removes a singleton passes although disk still has it" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    echo 'public static AudioService Instance { get; private set; }' > "$f"
    jq -n --arg p "$f" --arg c 'public sealed class AudioService { }' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 0 ]
}

@test "Write that creates a new file with a singleton is blocked" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/NewService.cs"
    jq -n --arg p "$f" --arg c 'public static NewService Instance { get; private set; }' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 2 ]
}

@test "Edit that deletes the singleton line passes" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    printf 'public sealed class AudioService\n{\n    private static AudioService _instance;\n}\n' > "$f"
    jq -n --arg p "$f" --arg o '    private static AudioService _instance;' --arg n '' \
        '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 0 ]
}

@test "blocks a private static Instance auto-property" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    jq -n --arg p "$f" --arg c 'private static AudioService Instance { get; set; }' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 2 ]
}

@test "blocks public static Instance field and expression-bodied property" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/AudioService.cs"
    jq -n --arg p "$f" --arg c 'public static AudioService Instance => _i;' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 2 ]
    jq -n --arg p "$f" --arg c 'internal static AudioService Instance;' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 2 ]
}

@test "still blocks when a fixed-name temp file is left in /tmp (macOS mktemp suffix)" {
    touch /tmp/unity_hook_XXXXXX.cs
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/NewService.cs"
    jq -n --arg p "$f" --arg c 'private static NewService _instance;' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    rm -f /tmp/unity_hook_XXXXXX.cs
    [ "$status" -eq 2 ]
}

@test "a static method calling a library's Instance is not a singleton" {
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/Bridge.cs"
    jq -n --arg p "$f" --arg c 'private static void Add(object c) => SRDebug.Instance.AddOptionContainer(c);' \
        '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}' > "$TMPDIR_TEST/in.json"
    run bash -c "bash $HOOK < '$TMPDIR_TEST/in.json'"
    [ "$status" -eq 0 ]
}
