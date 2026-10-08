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

@test "'write tests' matches the write-test stem" {
    run bash $HOOK <<< "$(_prompt 'write tests for the score service')"
    [[ "$output" == *"rules/testing.md"* ]]
}

@test "a question about test results is not a request to write tests" {
    for p in 'tüm testler geçti mi?' 'did the tests pass?' 'testi nasıl durduracağız'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" != *"rules/testing.md"* ]] || { echo "fired on: $p"; return 1; }
    done
}

@test "asking to write or plan tests still points at testing" {
    for p in 'LevelService için test yazalım' 'testlerini yaz' 'add a unit test' 'bir EditMode test planla'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" == *"rules/testing.md"* ]] || { echo "missed: $p"; return 1; }
    done
}

@test "a test word plus an action word points at testing in any word order" {
    for p in 'write a test for ScoreService' 'write the tests' 'add a test for the timer' \
             'create tests for LevelService' '/create-test LevelService' '/generate-tests' \
             'testleri yaz' 'testlerini ekle' 'bunun için testler yazalım' 'bunun testini yazalım'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" == *"rules/testing.md"* ]] || { echo "missed: $p"; return 1; }
    done
}

@test "an action verb inside a longer word does not count" {
    for p in 'addressables test sahnesi nerede' 'the test plane is tilted'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" != *"rules/testing.md"* ]] || { echo "fired on: $p"; return 1; }
    done
}

@test "English verb forms and test file names still point at testing" {
    for p in 'adding tests for the timer' 'I planned the tests' 'ScoreServiceTests.cs ekle' 'create LevelServiceTests.cs'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" == *"rules/testing.md"* ]] || { echo "missed: $p"; return 1; }
    done
}

@test "Turkish 'test planı' forms point at testing" {
    for p in 'test planı çıkar' 'test planı hazırla' 'bir test planı lazım' 'test planını yap'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" == *"rules/testing.md"* ]] || { echo "missed: $p"; return 1; }
    done
}

@test "the rule-awareness probe's test-plan prompt points at testing" {
    run bash $HOOK <<< "$(_prompt "$(cat .claude/tests/rule-awareness-probe/prompts/test-plan.txt)")"
    [[ "$output" == *"rules/testing.md"* ]]
}

@test "running the game in play mode is not a testing request" {
    for p in 'PlayMode ile oyunu çalıştır' 'play mode da oyunu açıp bak'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" != *"rules/testing.md"* ]] || { echo "fired on: $p"; return 1; }
    done
}

@test "keywords inside pasted content are ignored" {
    run bash $HOOK <<< "$(_prompt $'bu sonucu yorumla\n<pasted_content id="ab12">\nsave the HUD prefab scene with UniTask\n</pasted_content id="ab12">')"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "keywords typed next to pasted content still match" {
    run bash $HOOK <<< "$(_prompt $'<pasted_content id="ab12">\nsome log\n</pasted_content id="ab12">\nbunu kaydedelim')"
    [[ "$output" == *"rules/save-load.md"* ]]
}

@test "UniTask prompt points at unity-async" {
    run bash $HOOK <<< "$(_prompt 'Pause menüsünde UniTask ile 2 saniye bekleyelim')"
    [[ "$output" == *"rules/unity-async.md"* ]]
}

@test "English and Turkish async prompts point at unity-async" {
    for p in 'make the loader async' 'replace this coroutine' 'bunu asenkron yapalım'; do
        run bash $HOOK <<< "$(_prompt "$p")"
        [[ "$output" == *"rules/unity-async.md"* ]] || { echo "missed: $p"; return 1; }
    done
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
