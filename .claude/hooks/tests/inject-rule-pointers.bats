#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/inject-rule-pointers.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_PROJECT_FEATURES_FILE="$UNITY_HOOK_STATE_DIR/features.json"
    printf '{"ecs": false, "addressables": false, "testing": true}\n' > "$UNITY_PROJECT_FEATURES_FILE"
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

_prompt() { jq -n --arg p "$1" '{prompt: $p}'; }

@test "Turkish settings prompt points at save-load and ui-toolkit-runtime" {
    run bash $HOOK <<< "$(_prompt 'Ayarlar ekranı yapalım, ses kaydedilsin')"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e .
    [[ "$output" == *"rules/save-load.md"* ]]
    [[ "$output" == *"rules/ui-toolkit-runtime.md"* ]]
}

@test "English persistence prompt points at save-load" {
    run bash $HOOK <<< "$(_prompt 'Persist the best score between sessions')"
    [[ "$output" == *"rules/save-load.md"* ]]
}

@test "keyword matches only at a word start — 'latest' is not 'test'" {
    run bash $HOOK <<< "$(_prompt 'show me the latest commit')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "'tests' still matches the test stem" {
    run bash $HOOK <<< "$(_prompt 'write tests for the score service')"
    [[ "$output" == *"rules/testing.md"* ]]
}

@test "a disabled feature's rule is never injected" {
    run bash $HOOK <<< "$(_prompt 'add an ECS system for enemies')"
    [[ "$output" != *"ecs-dots.md"* ]]
}

@test "an enabled feature's rule is injected" {
    printf '{"ecs": true}\n' > "$UNITY_PROJECT_FEATURES_FILE"
    run bash $HOOK <<< "$(_prompt 'add an ECS system for enemies')"
    [[ "$output" == *"rules/ecs-dots.md"* ]]
}

@test "web tool prompt points at all three web-tool rules" {
    run bash $HOOK <<< "$(_prompt 'build a level editor web tool')"
    [[ "$output" == *"web-tool-architecture.md"* ]]
    [[ "$output" == *"web-tool-data-contract.md"* ]]
    [[ "$output" == *"web-tool-design-system.md"* ]]
}

@test "each rule appears once even when several keywords hit it" {
    run bash $HOOK <<< "$(_prompt 'save and persist the settings screen menu')"
    [ "$(grep -o 'rules/save-load.md' <<< "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "no keyword → no output" {
    run bash $HOOK <<< "$(_prompt 'tweak this a bit')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "empty payload exits 0 silently" {
    run bash $HOOK <<< '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "runs under the default standard profile" {
    UNITY_HOOK_PROFILE=standard run bash $HOOK <<< "$(_prompt 'save the score')"
    [[ "$output" == *"rules/save-load.md"* ]]
}

@test "skipped under the minimal profile" {
    UNITY_HOOK_PROFILE=minimal run bash $HOOK <<< "$(_prompt 'save the score')"
    [ -z "$output" ]
}
