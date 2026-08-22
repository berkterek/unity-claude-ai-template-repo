#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/session-restore.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR"
    # Safety net: the self-heal test intentionally strips an exec bit. If an
    # assertion fails mid-test, restore it so the working tree is never left dirty.
    chmod +x .claude/hooks/check-time-scale.sh 2>/dev/null || true
}

@test "session-restore deletes gate-cleared on session start" {
    touch "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/gate-cleared" ]
}

@test "session-restore is safe when gate-cleared is already absent" {
    rm -f "$UNITY_HOOK_STATE_DIR/gate-cleared"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
}

@test "session-restore writes session-start-time" {
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ -f "$UNITY_HOOK_STATE_DIR/session-start-time" ]
}

@test "session-restore resets a leaked subagent-depth counter to 0" {
    # The counter is monotonic, not self-healing: any spawn whose PostToolUse Stop
    # never fires leaves it high forever, and a high count makes
    # guard-pipeline-direct-work.sh exit 0 — a blocking hook silently no-op'd.
    echo 12 > "$UNITY_HOOK_STATE_DIR/subagent-depth"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(cat "$UNITY_HOOK_STATE_DIR/subagent-depth")" -eq 0 ]
}

@test "session-restore expires every deny-then-allow grant" {
    # Without this a file waved through once was waved through forever: the gates
    # became one-per-file-per-lifetime instead of one-per-session.
    for f in gateguard-facts-passed gateguard-facts-denied \
             guard-critical-passed guard-critical-denied \
             config-asmdef-passed config-asmdef-denied; do
        echo "/some/File.cs" > "$UNITY_HOOK_STATE_DIR/${f}.txt"
    done
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    for f in gateguard-facts-passed gateguard-facts-denied \
             guard-critical-passed guard-critical-denied \
             config-asmdef-passed config-asmdef-denied; do
        [ ! -e "$UNITY_HOOK_STATE_DIR/${f}.txt" ]
    done
}

@test "session-restore self-heals a hook missing its exec bit" {
    local target=".claude/hooks/check-time-scale.sh"
    chmod 644 "$target"
    [ ! -x "$target" ]              # precondition: bit is gone
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ -x "$target" ]               # session-restore restored it
}

# ── Unbounded state file growth (regression) ────────────────────────────────
# Several writers accumulate lines forever with no trim, unlike hook-logger.sh's
# tail -n 500 pattern (hook-logger.sh:49-55) or instinct-capture.sh:88-92.
# session-restore.sh is expected to apply the same trim at SessionStart.

@test "session-restore trims subagent-log.jsonl to 500 lines" {
    for i in $(seq 1 600); do echo "line-$i"; done > "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl" | tr -d ' ')" -eq 500 ]
}

@test "session-restore trim on subagent-log.jsonl keeps the newest lines" {
    for i in $(seq 1 600); do echo "line-$i"; done > "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(head -n 1 "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl")" = "line-101" ]
    [ "$(tail -n 1 "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl")" = "line-600" ]
}

@test "session-restore leaves subagent-log.jsonl under the threshold untouched" {
    for i in $(seq 1 400); do echo "line-$i"; done > "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl" | tr -d ' ')" -eq 400 ]
    [ "$(head -n 1 "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl")" = "line-1" ]
    [ "$(tail -n 1 "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl")" = "line-400" ]
}

@test "session-restore trims task-log.jsonl to 500 lines" {
    for i in $(seq 1 600); do echo "line-$i"; done > "$UNITY_HOOK_STATE_DIR/task-log.jsonl"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$UNITY_HOOK_STATE_DIR/task-log.jsonl" | tr -d ' ')" -eq 500 ]
}

@test "session-restore removes session-warnings.txt" {
    echo "some warning" > "$UNITY_HOOK_STATE_DIR/session-warnings.txt"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/session-warnings.txt" ]
}

@test "session-restore removes skills-invoked.txt" {
    echo "some-skill" > "$UNITY_HOOK_STATE_DIR/skills-invoked.txt"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/skills-invoked.txt" ]
}

@test "session-restore removes stale graph-health-warned sentinels but keeps today's" {
    touch "$UNITY_HOOK_STATE_DIR/graph-health-warned-2020-01-01"
    local today
    today="$(date -u +%Y-%m-%d)"
    touch "$UNITY_HOOK_STATE_DIR/graph-health-warned-${today}"
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$UNITY_HOOK_STATE_DIR/graph-health-warned-2020-01-01" ]
    [ -e "$UNITY_HOOK_STATE_DIR/graph-health-warned-${today}" ]
}

@test "session-restore is safe when none of the trimmed/cleared files exist" {
    rm -f "$UNITY_HOOK_STATE_DIR/subagent-log.jsonl" \
          "$UNITY_HOOK_STATE_DIR/task-log.jsonl" \
          "$UNITY_HOOK_STATE_DIR/session-warnings.txt" \
          "$UNITY_HOOK_STATE_DIR/skills-invoked.txt"
    rm -f "$UNITY_HOOK_STATE_DIR"/graph-health-warned-*
    run bash $HOOK < /dev/null
    [ "$status" -eq 0 ]
}
