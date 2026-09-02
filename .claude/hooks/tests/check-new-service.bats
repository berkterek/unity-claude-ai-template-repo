#!/usr/bin/env bats
#
# BLOCKING hook (exit 2) — unlike the warn hooks in this directory, the exit
# code is the assertion. It reads the effective POST-edit content, so the two
# Edit tests at the bottom are the ones that would catch a regression to
# disk-based checking, which makes an already-violating file unfixable.

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-new-service.sh"
    G="$(mktemp -d)/_GameFolders/Scripts/Games/Concretes/Players"
    mkdir -p "$G"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$G"; }

write() { # $1 file, $2 content
    local p
    p=$(jq -nc --arg f "$1" --arg c "$2" \
        '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
    run bash -c "echo '$p' | bash $HOOK"
}

@test "blocks new *Service()" {
    write "$G/PlayerController.cs" 'void Awake(){ _audio = new AudioService(_provider); }'
    [ "$status" -eq 2 ]
}

@test "blocks new *Provider()" {
    write "$G/PlayerController.cs" 'void Awake(){ _p = new BasicAudioProvider(); }'
    [ "$status" -eq 2 ]
}

@test "allows new *Service() inside a Module — RegisterFactory needs it" {
    write "$G/PlayerModule.cs" 'builder.RegisterFactory(c => id => new LevelService(id));'
    [ "$status" -eq 0 ]
}

@test "allows new *Handler() inside a Controller shell" {
    write "$G/PlayerController.cs" 'void Awake(){ _move = new MoveHandler(_rigidbody, _config); }'
    [ "$status" -eq 0 ]
}

@test "blocks new *Handler() outside a Controller or View" {
    write "$G/PlayerService.cs" 'void A(){ _move = new MoveHandler(_rb, _config); }'
    [ "$status" -eq 2 ]
}

@test "allows constructor injection — the prescribed form" {
    write "$G/PlayerService.cs" 'public PlayerService(IAudioService audio){ _audio = audio; }'
    [ "$status" -eq 0 ]
}

@test "ignores a mention inside a line comment" {
    write "$G/PlayerService.cs" '// never write new AudioService() here'
    [ "$status" -eq 0 ]
}

@test "ignores files outside _GameFolders/Scripts/" {
    local d="$(mktemp -d)/Assets/Plugins"; mkdir -p "$d"
    write "$d/Vendor.cs" 'var s = new AudioService();'
    [ "$status" -eq 0 ]
}

@test "Edit path judges the post-edit content, not the file on disk" {
    local f="$G/PlayerService.cs"
    echo 'void A(){ _audio = new AudioService(); }' > "$f"
    local p
    p=$(jq -nc --arg f "$f" --arg o 'new AudioService()' --arg n 'audio' \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')
    run bash -c "echo '$p' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "Edit path still blocks an edit that introduces a violation" {
    local f="$G/PlayerService.cs"
    echo 'void A(){ }' > "$f"
    local p
    p=$(jq -nc --arg f "$f" --arg o 'void A(){ }' --arg n 'void A(){ _a = new AudioService(); }' \
        '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}')
    run bash -c "echo '$p' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "UNITY_HOOK_MODE=warn downgrades block to warning" {
    local p
    p=$(jq -nc --arg f "$G/PlayerController.cs" --arg c 'var s = new AudioService();' \
        '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
    run bash -c "UNITY_HOOK_MODE=warn; export UNITY_HOOK_MODE; echo '$p' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "minimal profile skips this standard-level hook" {
    local p
    p=$(jq -nc --arg f "$G/PlayerController.cs" --arg c 'var s = new AudioService();' \
        '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}')
    run bash -c "UNITY_HOOK_PROFILE=minimal; export UNITY_HOOK_PROFILE; echo '$p' | bash $HOOK"
    [ "$status" -eq 0 ]
}
