# Plan-Time Fact Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `gateguard.sh`'s fact demands from write time to plan time, and give all three depth-restricted gates a shared plan-coverage escape, so a subagent can land a planned file and `/orchestrate` works at the `strict` profile.

**Architecture:** One shared library (`lib-gateguard-facts.sh`) holds the fact rules; a plan-time script validates every task before SCOPE_GATE; the write-time hooks re-read the plan live instead of trusting a cached receipt. Mirrors the existing `lib-path-rules.sh` + `validate-plan-paths.sh` split exactly. No new state file.

**Tech Stack:** bash 3.2 (macOS default), `jq`, `python3` (already required by `_lib.sh`), `bats-core` for tests.

**Spec:** `docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md` — read it before Task 1; this plan argues from it.

**End State:**

When this plan is complete:

- `.claude/hooks/_lib.sh` exports `unity_gate_cleared_valid` and `unity_plan_covers`.
- `.claude/hooks/lib-gateguard-facts.sh` exists and exports `unity_find_task_line`, `unity_validate_task_facts`, `unity_task_mode`, `unity_gateguard_facts_summary`.
- `.claude/scripts/validate-plan-facts.sh` exists, exits 0/1/2 like `validate-plan-paths.sh`, and prints a receipt whose `presence-only` line names what it did not verify.
- `gateguard.sh`, `guard-critical-files.sh`, `check-config-protection.sh` each allow a write when the plan covers the path; without coverage every one of them behaves exactly as it does today.
- `settings.json` is still blocked unconditionally.
- `docs/modules/_templates/tasks.md` carries `Callers:` / `Wiring:` fields; `plan-module.md`, `create-plan.md`, `orchestrate.md` call the new validator as BLOCKING.
- `bats .claude/hooks/tests/` is green, including every pre-existing test **unmodified**.

A subagent at depth 2, with a valid `gate-cleared` and a task line declaring `PlayerService.cs` with both fields, can `Write` that file. The same subagent writing an undeclared file is still blocked with today's message.

---

## Deliberate refinement over the spec

The spec's library contract lists three functions. This plan adds a fourth,
`unity_task_mode`, and keeps the two automatic checks (duplicate type, asmdef)
in `validate-plan-facts.sh` rather than the library. Reason: both are
plan-time-only. At write time the file being created *is* the duplicate, so
running the check there would report every new file as a violation. Keeping
them out of the library makes that impossible by construction rather than by
a flag.

---

## File Structure

| File | Responsibility |
|---|---|
| `.claude/hooks/_lib.sh` (modify) | `unity_gate_cleared_valid`, `unity_plan_covers` — shared predicates every gate consults |
| `.claude/hooks/lib-gateguard-facts.sh` (create) | plan parsing + field rules; single source of truth |
| `.claude/scripts/validate-plan-facts.sh` (create) | plan-time caller: iterate all tasks, auto-checks, receipt |
| `.claude/hooks/gateguard.sh` (modify) | Guard 2 consults coverage + facts |
| `.claude/hooks/guard-critical-files.sh` (modify) | consults coverage only |
| `.claude/hooks/check-config-protection.sh` (modify) | consults coverage only, `.asmdef` branch |
| `.claude/hooks/guard-gate-cleared.sh` (modify) | uses the extracted TTL helper |
| `docs/modules/_templates/tasks.md` (modify) | schema fields |
| `.claude/commands/{plan-module,create-plan,orchestrate}.md` (modify) | wire the validator |

---

### Task 1: Extract the gate TTL helper

Today `GATE_TTL=2700` and the age computation live inline in
`guard-gate-cleared.sh:41-72`. Three more callers are about to need them.
Behaviour must not change.

The helper returns four states because callers need opposite directions on
uncertainty — the same reasoning `unity_subagent_depth` already documents:

| Return | Meaning |
|---|---|
| 0 | present and fresh |
| 1 | absent |
| 2 | age indeterminate (`python3` failed or returned non-numeric) |
| 3 | stale |

`guard-gate-cleared.sh` treats 2 as valid, preserving today's permissive
behaviour. `unity_plan_covers` (Task 3) treats 2 as not-covered.

**Files:**
- Modify: `.claude/hooks/_lib.sh` (append to end)
- Modify: `.claude/hooks/guard-gate-cleared.sh:41-72`
- Test: `.claude/hooks/tests/guard-gate-cleared.bats` (existing — must stay green)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/guard-gate-cleared.bats`:

```bash
@test "unity_gate_cleared_valid: 1 when the gate file is absent" {
    run bash -c "source .claude/hooks/_lib.sh; unity_gate_cleared_valid >/dev/null; echo \$?"
    [ "$output" = "1" ]
}

@test "unity_gate_cleared_valid: 0 and echoes the age when the gate is fresh" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "source .claude/hooks/_lib.sh; unity_gate_cleared_valid; echo \"status=\$?\""
    [[ "$output" == *"status=0"* ]]
}

@test "unity_gate_cleared_valid: 3 when the gate is older than the TTL" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    python3 -c "import os,time; p='${UNITY_HOOK_STATE_DIR}/gate-cleared'; os.utime(p,(time.time()-3000,time.time()-3000))"
    run bash -c "source .claude/hooks/_lib.sh; unity_gate_cleared_valid >/dev/null; echo \$?"
    [ "$output" = "3" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/guard-gate-cleared.bats`
Expected: FAIL — `unity_gate_cleared_valid: command not found`

- [ ] **Step 3: Add the helper to `_lib.sh`**

Append to `.claude/hooks/_lib.sh`:

```bash
# unity_gate_cleared_valid — is a Director Gate open and still within its TTL?
#
# Echoes the gate's age in seconds (empty when indeterminate) and returns:
#   0 = present and fresh    1 = absent
#   2 = age indeterminate    3 = stale
#
# Four states, not two, because callers need OPPOSITE directions on state 2 —
# the same split unity_subagent_depth documents. guard-gate-cleared.sh treats 2
# as valid (its historical behaviour: a failed age computation defaulted to 0).
# unity_plan_covers treats 2 as not-covered, because there a pass would release
# a gate on a stale approval.
UNITY_GATE_TTL=2700

unity_gate_cleared_valid() {
    local gate_file="${UNITY_HOOK_STATE_DIR}/gate-cleared"
    [ -f "$gate_file" ] || return 1

    local age
    age=$(python3 -c "import os,time; print(int(time.time() - os.path.getmtime('$gate_file')))" 2>/dev/null) || return 2
    case "$age" in
        ''|*[!0-9]*) return 2 ;;
    esac

    echo "$age"
    [ "$age" -le "$UNITY_GATE_TTL" ] || return 3
    return 0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/guard-gate-cleared.bats`
Expected: PASS, all tests including the pre-existing ones

- [ ] **Step 5: Rewrite `guard-gate-cleared.sh` to use the helper**

Replace lines 39-72 of `.claude/hooks/guard-gate-cleared.sh` (from the
`# UNITY_HOOK_STATE_DIR is set by _lib.sh` comment through the stale check)
with:

```bash
# UNITY_HOOK_STATE_DIR is set by _lib.sh using git rev-parse — always absolute path.
# TTL lives in _lib.sh as UNITY_GATE_TTL (2700s / 45 min): covers slow SPARC/plan
# phases while limiting the window during which an interrupted pipeline's gate
# remains valid.
GATE_FILE="${UNITY_HOOK_STATE_DIR}/gate-cleared"

_gate_blocked() {
    local reason="$1"
    echo "" >&2
    echo "  GATE VIOLATION ─────────────────────────────────────────────" >&2
    echo "  Cannot spawn '$SUBAGENT_TYPE' — $reason" >&2
    echo "" >&2
    echo "  Every pipeline command must show SCOPE_GATE (or ARCHITECTURE_GATE" >&2
    echo "  for /new-module) and receive 'go' from the user before spawning" >&2
    echo "  any pipeline agents." >&2
    echo "" >&2
    echo "  To clear the gate:" >&2
    echo "    1. Show the required gate block to the user" >&2
    echo "    2. Wait for 'go'" >&2
    echo "    3. Run: mkdir -p \"\$(git rev-parse --show-toplevel)/.claude/state\" && echo '{\"gate\":\"cleared\"}' > \"\$(git rev-parse --show-toplevel)/.claude/state/gate-cleared\"" >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    exit 2
}

set +e
GATE_AGE=$(unity_gate_cleared_valid)
GATE_STATUS=$?
set -e

case "$GATE_STATUS" in
    1) _gate_blocked "no Director Gate has been cleared." ;;
    3) _gate_blocked "the Director Gate has expired (age ${GATE_AGE}s > ${UNITY_GATE_TTL}s TTL). Re-show the gate and get a fresh 'go'." ;;
    2) : ;;  # age indeterminate — historical behaviour was to treat it as fresh
esac

exit 0
```

- [ ] **Step 6: Run the full hook suite**

Run: `bats .claude/hooks/tests/`
Expected: PASS — no test file other than `guard-gate-cleared.bats` was touched

- [ ] **Step 7: Commit**

```bash
git add .claude/hooks/_lib.sh .claude/hooks/guard-gate-cleared.sh .claude/hooks/tests/guard-gate-cleared.bats
git commit -m "refactor(hooks): extract unity_gate_cleared_valid into _lib.sh

Four return states so each caller can resolve uncertainty in its own safe
direction, matching the unity_subagent_depth pattern. Behaviour of
guard-gate-cleared.sh is unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Plan parser — `unity_find_task_line`

Given a script path, find the task that declares it in any
`docs/**/tasks.md` (excluding `_templates/`) and emit that task line plus its
indented body.

Matching is **suffix-based both ways** so a plan writing
`_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` matches a hook
receiving an absolute path. Basename-only matching is deliberately NOT used —
two domains can hold a same-named file, and a loose match would let an
undeclared file ride on a declared one's task.

**Files:**
- Create: `.claude/hooks/lib-gateguard-facts.sh`
- Create: `.claude/hooks/tests/lib-gateguard-facts.bats`

- [ ] **Step 1: Write the failing test**

Create `.claude/hooks/tests/lib-gateguard-facts.bats`:

```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPDIR_TEST="$(mktemp -d)"
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02-players"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1

    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
# Tasks: Players

- [ ] T004 [parallel_group:1] `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — implementation
  ```csharp
  public interface IFake { }
  ```
  - Callers: `Concretes/Players/PlayerController.cs`
  - Wiring: PlayerModule.Install → Register<PlayerService>()
  - Acceptance: tests pass

- [ ] T005 `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs` — shell
  - Callers: scene prefab Player.prefab
  - Wiring: GameScope RegisterComponent
EOF
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "find_task_line: locates the declaring task by full path" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" == *"T004"* ]]
    [[ "$output" == *"Wiring: PlayerModule.Install"* ]]
}

@test "find_task_line: matches an absolute path against a repo-relative plan entry" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '/abs/repo/_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" == *"T004"* ]]
}

@test "find_task_line: body stops at the next task line" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" != *"T005"* ]]
}

@test "find_task_line: a draft interface inside a code fence is not a field" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [[ "$output" != *"public interface IFake"* ]]
}

@test "find_task_line: empty for an undeclared path" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs'"
    [ -z "$output" ]
}

@test "find_task_line: ignores the _templates directory" {
    mkdir -p "$UNITY_PLAN_ROOT/modules/_templates"
    cp "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" "$UNITY_PLAN_ROOT/modules/_templates/tasks.md"
    rm "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_find_task_line '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: FAIL — `lib-gateguard-facts.sh: No such file or directory`

- [ ] **Step 3: Create the library with the parser**

Create `.claude/hooks/lib-gateguard-facts.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# lib-gateguard-facts.sh — single source of truth for the fact rules that used
# to live only inside gateguard.sh's write-time Guard 2.
#
# Two callers, no cache, same shape as lib-path-rules.sh:
#   scripts/validate-plan-facts.sh  — plan time, every task, before the gate
#   hooks/gateguard.sh              — write time, one path, recomputed live
#
# The plan document IS the manifest. Nothing here writes state; a plan edit is
# picked up on the very next call.
# ============================================================================

# Root under which tasks.md files are searched. Overridable for tests only.
UNITY_PLAN_ROOT="${UNITY_PLAN_ROOT:-docs}"

# unity_plan_task_files — every plan tasks.md, templates excluded.
unity_plan_task_files() {
    find "$UNITY_PLAN_ROOT" -name 'tasks.md' -not -path '*/_templates/*' 2>/dev/null | sort
}

# unity_find_task_line <script-path>
#
# Emits the declaring task line plus its indented body, or nothing.
# Suffix matching runs both ways so an absolute write-time path matches a
# repo-relative plan entry. Basename-only matching is deliberately absent:
# two domains may hold a same-named file, and a loose match would let an
# undeclared file ride through on a declared one's task.
unity_find_task_line() {
    local target="$1"
    [ -n "$target" ] || return 0

    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk -v target="$target" '
          function is_match(p,   t) {
              if (p == target) return 1
              # target ends with p  (plan is repo-relative, target absolute)
              if (length(target) > length(p) && substr(target, length(target) - length(p) + 1) == p) return 1
              # p ends with target  (plan absolute, target repo-relative)
              if (length(p) > length(target) && substr(p, length(p) - length(target) + 1) == target) return 1
              return 0
          }
          /^[[:space:]]*```/ { fence = !fence; next }
          fence && capturing { next }
          fence { next }
          /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
              if (capturing) exit
              if (match($0, /`[^`]*\.cs`/)) {
                  p = substr($0, RSTART + 1, RLENGTH - 2)
                  if (is_match(p)) { capturing = 1; print; next }
              }
              next
          }
          capturing { print }
        ' "$f"
    done < <(unity_plan_task_files)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/lib-gateguard-facts.sh .claude/hooks/tests/lib-gateguard-facts.bats
git commit -m "feat(hooks): add lib-gateguard-facts.sh plan parser

unity_find_task_line locates the task declaring a script path. Suffix
matching both ways; basename-only matching deliberately omitted so an
undeclared file cannot ride on a same-named declared one.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Field rules — `unity_task_mode` and `unity_validate_task_facts`

**Files:**
- Modify: `.claude/hooks/lib-gateguard-facts.sh` (append)
- Modify: `.claude/hooks/tests/lib-gateguard-facts.bats` (append)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/lib-gateguard-facts.bats`:

```bash
@test "task_mode: new when the file is absent from disk" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_task_mode '$TMPDIR_TEST/Absent.cs'"
    [ "$output" = "new" ]
}

@test "task_mode: edit when the file exists" {
    touch "$TMPDIR_TEST/Present.cs"
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_task_mode '$TMPDIR_TEST/Present.cs'"
    [ "$output" = "edit" ]
}

@test "validate: a new task carrying both fields passes" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs' new"
    [ "$status" -eq 0 ]
}

@test "validate: a new task missing Wiring is rejected with a reason" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T009 `_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs` — impl
  - Callers: `Concretes/Players/PlayerController.cs`
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Players/ScoreService.cs' new"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Wiring:"* ]]
}

@test "validate: an undeclared path is rejected" {
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs' new"
    [ "$status" -eq 2 ]
    [[ "$output" == *"no task"* ]]
}

@test "validate: a test file is exempt from both fields" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T003 `_GameFolders/Scripts/Tests/GameEditModeTest/PlayerServiceTests.cs` — EditMode test
  - Acceptance: passes
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '_GameFolders/Scripts/Tests/GameEditModeTest/PlayerServiceTests.cs' new"
    [ "$status" -eq 0 ]
}

@test "validate: a signalled rename on a SerializeField file demands FormerlySerializedAs" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf '[SerializeField] private float _speed;\n' > "$TMPDIR_TEST/dom/Mover.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T020 \`$TMPDIR_TEST/dom/Mover.cs\` — rename _speed to _moveSpeed
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/Mover.cs' edit"
    [ "$status" -eq 2 ]
    [[ "$output" == *"FormerlySerializedAs"* ]]
}

@test "validate: the same rename passes once FormerlySerializedAs is declared" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf '[SerializeField] private float _speed;\n' > "$TMPDIR_TEST/dom/Mover.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T020 \`$TMPDIR_TEST/dom/Mover.cs\` — rename _speed to _moveSpeed
  - FormerlySerializedAs: _speed -> _moveSpeed
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/Mover.cs' edit"
    [ "$status" -eq 0 ]
}

@test "validate: an ordinary edit with no rename signal needs no fields" {
    mkdir -p "$TMPDIR_TEST/dom"
    printf 'public class AppModules { }\n' > "$TMPDIR_TEST/dom/AppModules.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<EOF
- [ ] T030 \`$TMPDIR_TEST/dom/AppModules.cs\` — add PlayerModule.Install line
  - Acceptance: compiles
EOF
    run bash -c "source .claude/hooks/lib-gateguard-facts.sh; unity_validate_task_facts '$TMPDIR_TEST/dom/AppModules.cs' edit"
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: FAIL — `unity_task_mode: command not found`

- [ ] **Step 3: Append the field rules to the library**

Append to `.claude/hooks/lib-gateguard-facts.sh`:

```bash
# unity_task_mode <script-path> — "new" if the path is absent from disk, else "edit".
#
# Never declared in the plan: this is the same IS_WRITE test gateguard.sh already
# performs, so there is nothing for an author to get wrong. The plan-internal
# rule (an earlier task in the same plan created it, so a later one is an edit)
# lives in validate-plan-facts.sh, which is the only caller that iterates tasks
# in order.
unity_task_mode() {
    [ -f "$1" ] && echo "edit" || echo "new"
}

# _unity_has_field <body> <FieldName> — non-empty "- FieldName: value" sub-bullet?
_unity_has_field() {
    printf '%s\n' "$1" | grep -qE "^[[:space:]]*-[[:space:]]*$2:[[:space:]]*[^[:space:]]"
}

# unity_validate_task_facts <script-path> <new|edit>
#
# 0 = pass. 2 = fail, with a one-line reason on stdout.
#
# NEW  : Callers: and Wiring: are both required. Files under Tests/ are exempt —
#        the question is structurally empty for them (no callers, no wiring).
# EDIT : fields are not required. FormerlySerializedAs: becomes required only
#        when the task text signals a rename AND the target file contains
#        [SerializeField]. Known gap, documented in the spec: a rename nobody
#        wrote into the task text is not detectable at plan time.
unity_validate_task_facts() {
    local target="$1" mode="$2" body
    body=$(unity_find_task_line "$target")

    if [ -z "$body" ]; then
        echo "no task in any tasks.md declares this path"
        return 2
    fi

    case "$target" in
        */Tests/*) return 0 ;;
    esac

    if [ "$mode" = "new" ]; then
        _unity_has_field "$body" "Callers" || { echo "task declares no 'Callers:' field"; return 2; }
        _unity_has_field "$body" "Wiring"  || { echo "task declares no 'Wiring:' field";  return 2; }
        return 0
    fi

    if printf '%s\n' "$body" | grep -qiE 'rename|yeniden adlandır|eski ad|→'; then
        if grep -q '\[SerializeField\]' "$target" 2>/dev/null; then
            _unity_has_field "$body" "FormerlySerializedAs" || {
                echo "task signals a rename on a file containing [SerializeField] but declares no 'FormerlySerializedAs:' field — without it every configured value in every scene, prefab and ScriptableObject silently resets to default"
                return 2
            }
        fi
    fi
    return 0
}

# unity_gateguard_facts_summary — one-line provenance receipt, printed by both callers.
unity_gateguard_facts_summary() {
    echo "rules         : lib-gateguard-facts.sh (plan root: ${UNITY_PLAN_ROOT})"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: PASS, 15 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/lib-gateguard-facts.sh .claude/hooks/tests/lib-gateguard-facts.bats
git commit -m "feat(hooks): add task fact rules to lib-gateguard-facts.sh

Callers/Wiring required on new files, Tests/ exempt, FormerlySerializedAs
demanded when a task signals a rename on a SerializeField-bearing file.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The shared predicate — `unity_plan_covers`

This is the function all three gates consult. Every uncertain outcome must
resolve to "not covered". Under `set -euo pipefail` an internal error exits a
hook with status 1, which is **not blocking** — a silent fail-open. The
predicate therefore runs in a subshell and any non-zero exit means not covered.

**Files:**
- Modify: `.claude/hooks/_lib.sh` (append)
- Modify: `.claude/hooks/tests/lib-gateguard-facts.bats` (append)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/lib-gateguard-facts.bats`:

```bash
@test "plan_covers: false with no gate-cleared, even for a declared path" {
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: true with a fresh gate and a declared path" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -eq 0 ]
}

@test "plan_covers: false when the gate is stale" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    python3 -c "import os,time; p='${UNITY_HOOK_STATE_DIR}/gate-cleared'; os.utime(p,(time.time()-3000,time.time()-3000))"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: false for an undeclared path even with a fresh gate" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Enemies/EnemyService.cs'"
    [ "$status" -ne 0 ]
}

@test "plan_covers: false when the plan root is unreadable — no fail-open" {
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    run bash -c "UNITY_PLAN_ROOT=/nonexistent-plan-root source .claude/hooks/_lib.sh; unity_plan_covers '_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs'"
    [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: FAIL — `unity_plan_covers: command not found`

- [ ] **Step 3: Append the predicate to `_lib.sh`**

Append to `.claude/hooks/_lib.sh`:

```bash
# unity_plan_covers <script-path>
#
# 0 = a human-approved plan declares this path. Non-zero = it does not.
#
# Two conditions, both required:
#   1. a Director Gate is open and fresh  (unity_gate_cleared_valid == 0)
#   2. some docs/**/tasks.md declares this path
#
# gateguard.sh layers a third check (the facts block must validate) on top.
# guard-critical-files.sh and check-config-protection.sh consult coverage only:
# their demand is "investigate and confirm the change is intentional", which a
# task declared in the plan and approved at SCOPE_GATE already satisfies.
#
# Runs in a subshell with `set +e` so that ANY failure inside — an unreadable
# plan root, a missing library, a broken awk — surfaces as non-zero rather than
# killing the calling hook with status 1, which the harness does NOT treat as
# blocking. No uncertainty may ever produce a pass.
unity_plan_covers() {
    local target="$1"
    (
        set +e
        # shellcheck source=lib-gateguard-facts.sh
        . "${UNITY_HOOK_DIR:-$(dirname "${BASH_SOURCE[0]}")}/lib-gateguard-facts.sh" 2>/dev/null || exit 1
        unity_gate_cleared_valid >/dev/null
        [ $? -eq 0 ] || exit 1
        [ -n "$(unity_find_task_line "$target")" ] || exit 1
        exit 0
    )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/lib-gateguard-facts.bats`
Expected: PASS, 20 tests

- [ ] **Step 5: Run the full suite**

Run: `bats .claude/hooks/tests/`
Expected: PASS — no pre-existing test modified

- [ ] **Step 6: Commit**

```bash
git add .claude/hooks/_lib.sh .claude/hooks/tests/lib-gateguard-facts.bats
git commit -m "feat(hooks): add unity_plan_covers shared predicate

Subshell isolation so any internal failure reads as not-covered; a hook
exiting 1 is not blocking, so a fail-open here would be silent.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Plan-time validator script

**Files:**
- Create: `.claude/scripts/validate-plan-facts.sh`
- Create: `.claude/hooks/tests/validate-plan-facts.bats`

- [ ] **Step 1: Write the failing test**

Create `.claude/hooks/tests/validate-plan-facts.bats`:

```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    TMPDIR_TEST="$(mktemp -d)"
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02-players"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    SCRIPT=".claude/scripts/validate-plan-facts.sh"
}

teardown() {
    rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"
}

@test "exit 1 with no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "finding no tasks is NOT a pass" {
    echo '# Tasks: empty' > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [[ "$output" == *"NO TASKS FOUND"* ]]
    [[ "$output" == *"NOT a pass"* ]]
}

@test "a complete plan passes and prints the presence-only line" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — impl
  - Callers: `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs`
  - Wiring: PlayerModule.Install
- [ ] T005 `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs` — shell
  - Callers: T004
  - Wiring: GameScope RegisterComponent
- [ ] T006 `_GameFolders/Scripts/Games/Concretes/Players/PlayerModule.cs` — Install
  - Callers: AppModules.cs
  - Wiring: AppModules.Install one line
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"presence-only"* ]]
}

@test "a missing Wiring field is exit 2 and names the task" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — impl
  - Callers: T005
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"VIOLATION"* ]]
    [[ "$output" == *"Wiring:"* ]]
}

@test "an invented caller is a violation" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — impl
  - Callers: `_GameFolders/Scripts/Games/Concretes/Ghosts/GhostController.cs`
  - Wiring: PlayerModule.Install
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"caller"* ]]
}

@test "a Service with no Module.Install task in the plan is a violation" {
    cat > "$UNITY_PLAN_ROOT/modules/02-players/tasks.md" <<'EOF'
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — impl
  - Callers: T005
  - Wiring: registered somewhere
- [ ] T005 `_GameFolders/Scripts/Games/Concretes/Players/PlayerController.cs` — shell
  - Callers: T004
  - Wiring: GameScope
EOF
    run bash "$SCRIPT" "$UNITY_PLAN_ROOT/modules/02-players/tasks.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Module"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/validate-plan-facts.bats`
Expected: FAIL — `.claude/scripts/validate-plan-facts.sh: No such file or directory`

- [ ] **Step 3: Write the validator**

Create `.claude/scripts/validate-plan-facts.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# validate-plan-facts.sh — PLAN-TIME fact validation.
#
# Runs the SAME rules the write-time hook uses (.claude/hooks/lib-gateguard-facts.sh)
# over every task in a plan, before SCOPE_GATE.
#
# Why this exists: the five facts gateguard.sh demanded at write time are all
# properties of the plan, answerable before any agent spawns. Demanding them at
# write time made them unanswerable inside a subagent, which deadlocked
# /orchestrate. See docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md
#
# Usage:
#   .claude/scripts/validate-plan-facts.sh docs/modules/02-players/
#   .claude/scripts/validate-plan-facts.sh docs/.../tasks.md
#
# Exit codes:  0 = every task passed (prints a receipt)
#              2 = at least one violation (prints each, with the reason)
#              1 = usage error / nothing to scan
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib-gateguard-facts.sh
source "${SCRIPT_DIR}/../hooks/lib-gateguard-facts.sh"

if [ $# -eq 0 ]; then
    echo "usage: validate-plan-facts.sh <plan-file-or-dir> [...]" >&2
    exit 1
fi

FILES=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r f; do FILES+=("$f"); done < <(find "$arg" -type f -name 'tasks.md' | sort)
    elif [ -f "$arg" ]; then
        FILES+=("$arg")
    else
        echo "not found: $arg" >&2
        exit 1
    fi
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "no tasks.md to scan under: $*" >&2
    exit 1
fi

ALL_TASK_PATHS=$(grep -ohE '`[^`]*\.cs`' "${FILES[@]}" 2>/dev/null | tr -d '`' | sort -u)

VIOLATIONS=0; CHECKED=0; NEW=0; EDIT=0; EXEMPT=0
CALLERS_OK=0; WIRING_SVC_OK=0; WIRING_PRESENCE=0
SEEN_PATHS=""

_violation() {
    VIOLATIONS=$((VIOLATIONS + 1))
    echo ""
    echo "VIOLATION [$VIOLATIONS] $1"
    echo "    $2"
}

# Iterate task-declaring lines in document order so the plan-internal
# "an earlier task created it" rule can classify later occurrences as edits.
while IFS= read -r p; do
    [ -z "$p" ] && continue
    CHECKED=$((CHECKED + 1))
    BODY=$(unity_find_task_line "$p")
    BASE=$(basename "$p" .cs)

    case "$p" in
        */Tests/*) EXEMPT=$((EXEMPT + 1)); continue ;;
    esac

    # new vs edit: absent from disk AND not created by an earlier task
    MODE=$(unity_task_mode "$p")
    if [ "$MODE" = "new" ] && printf '%s\n' "$SEEN_PATHS" | grep -qxF "$p"; then
        MODE="edit"
    fi
    SEEN_PATHS="${SEEN_PATHS}
${p}"
    [ "$MODE" = "new" ] && NEW=$((NEW + 1)) || EDIT=$((EDIT + 1))

    if ! MSG=$(unity_validate_task_facts "$p" "$MODE"); then
        _violation "$p" "$MSG"
        continue
    fi
    [ "$MODE" = "edit" ] && continue

    # --- automatic check #2: duplicate type ---
    # Plan-time only. At write time the file being created IS the match, so this
    # check deliberately lives here and not in the library.
    if DUP=$(grep -rln "class ${BASE}\b" Assets/ _GameFolders/ 2>/dev/null | grep -v "/${BASE}.cs$" | head -1); then
        if [ -n "$DUP" ]; then
            _violation "$p" "a type named ${BASE} already exists in ${DUP} — confirm no existing type serves this purpose"
            continue
        fi
    fi

    # --- automatic check #3: owning asmdef ---
    ASMDEF=""; DIR_WALK=$(dirname "$p")
    while [ "$DIR_WALK" != "." ] && [ "$DIR_WALK" != "/" ]; do
        FOUND=$(find "$DIR_WALK" -maxdepth 1 -name '*.asmdef' 2>/dev/null | head -1)
        if [ -n "$FOUND" ]; then ASMDEF="$FOUND"; break; fi
        DIR_WALK=$(dirname "$DIR_WALK")
    done
    if [ -z "$ASMDEF" ]; then
        _violation "$p" "no .asmdef owns this location — the file would land in no assembly"
        continue
    fi

    # --- Callers: cross-verification ---
    CALLER_LINE=$(printf '%s\n' "$BODY" | grep -E '^[[:space:]]*-[[:space:]]*Callers:' | head -1)
    CALLER_BAD=""
    for c in $(printf '%s\n' "$CALLER_LINE" | grep -oE '`[^`]*\.cs`' | tr -d '`'); do
        if [ ! -f "$c" ] && ! printf '%s\n' "$ALL_TASK_PATHS" | grep -qF "$c"; then
            CALLER_BAD="$c"; break
        fi
    done
    if [ -n "$CALLER_BAD" ]; then
        _violation "$p" "declared caller ${CALLER_BAD} exists neither on disk nor as a task in this plan"
        continue
    fi
    CALLERS_OK=$((CALLERS_OK + 1))

    # --- Wiring: cross-verification (services only) ---
    case "$BASE" in
        *Service)
            if printf '%s\n' "$ALL_TASK_PATHS" | grep -qE 'Module\.cs$' \
               || grep -qhE 'Module\.(Install|cs)' "${FILES[@]}" 2>/dev/null; then
                WIRING_SVC_OK=$((WIRING_SVC_OK + 1))
            else
                _violation "$p" "a *Service with no Module.Install task anywhere in this plan — state where it is registered"
                continue
            fi
            ;;
        *) WIRING_PRESENCE=$((WIRING_PRESENCE + 1)) ;;
    esac
done < <(grep -hoE '^[[:space:]]*-[[:space:]]*\[[ xX]\].*`[^`]*\.cs`' "${FILES[@]}" 2>/dev/null \
            | grep -oE '`[^`]*\.cs`' | tr -d '`')

echo ""
echo "--- Plan Facts Validation ---"
echo "files scanned  : ${#FILES[@]}"
echo "tasks checked  : $CHECKED   (new: $NEW, edit: $EDIT, test-exempt: $EXEMPT)"
echo "cross-verified : callers $CALLERS_OK, wiring $WIRING_SVC_OK service task(s)"
echo "presence-only  : wiring $WIRING_PRESENCE (non-service — NOT machine-verified)"
echo "$(unity_gateguard_facts_summary)"

if [ "$VIOLATIONS" -gt 0 ]; then
    echo "result         : $VIOLATIONS VIOLATION(S) — the plan cannot satisfy the write-time gate."
    echo ""
    echo "Fix the plan, not the hook. Show this block at SCOPE_GATE and let the human decide."
    exit 2
fi

if [ "$CHECKED" -eq 0 ]; then
    echo "result         : NO TASKS FOUND — this is NOT a pass."
    echo "                 Either the plan declares no script paths, or the parser"
    echo "                 missed them. Verify by hand before treating this as green."
    exit 0
fi

echo "result         : OK — all $CHECKED task(s) pass."
exit 0
```

- [ ] **Step 4: Make it executable and run the tests**

```bash
chmod +x .claude/scripts/validate-plan-facts.sh
bats .claude/hooks/tests/validate-plan-facts.bats
```
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add .claude/scripts/validate-plan-facts.sh .claude/hooks/tests/validate-plan-facts.bats
git commit -m "feat(scripts): add validate-plan-facts.sh plan-time validator

Mirrors validate-plan-paths.sh: same exit codes, same 'no tasks found is
NOT a pass' rule, receipt names what it did not verify.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: gateguard Guard 2 rewrite

**Files:**
- Modify: `.claude/hooks/gateguard.sh:66-90` (the Guard 2 comment block and depth check)
- Modify: `.claude/hooks/tests/gateguard.bats` (append only — existing tests must not change)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/gateguard.bats`:

```bash
@test "plan coverage lets a SUBAGENT write a declared file" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: \`$TMPDIR_TEST/PlayerController.cs\`
  - Wiring: PlayerModule.Install
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "plan coverage without a gate does NOT let a subagent through" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: x
  - Wiring: y
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "a covered path with an invalid facts block gets the fix-the-plan message" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/PlayerService.cs"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T004 \`$f\` — impl
  - Callers: x
EOF
    UNITY_HOOK_PROFILE=strict run bash -c "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" == *"fix the plan"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/gateguard.bats`
Expected: FAIL on the first new test with status 2 (the subagent is still blocked)

- [ ] **Step 3: Insert the coverage branch**

In `.claude/hooks/gateguard.sh`, immediately **before** the line
`GATEGUARD_DEPTH=$(unity_subagent_depth)` (currently line 86), insert:

```bash
# --- Plan coverage: the approved plan answers the fact demands, not a retry ---
#
# The five demands below are properties of the plan, answerable before any agent
# spawns. Demanding them at write time made them unanswerable inside a subagent
# (its output goes to the Director, not the human), which deadlocked every
# pipeline: guard-pipeline-direct-work.sh blocks the Director, this blocked the
# subagent, nobody could write. See
# docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md
#
# Coverage is recomputed live from docs/**/tasks.md on every call — there is no
# cached receipt, so a plan edit invalidates itself immediately.
if unity_plan_covers "$FILE_PATH"; then
    if FACTS_MSG=$(unity_validate_task_facts "$FILE_PATH" "$(unity_task_mode "$FILE_PATH")"); then
        echo "$FILE_PATH" >> "$FACTS_PASSED_FILE"
        exit 0
    fi
    # Covered but invalid: retrying cannot help — the problem is in tasks.md.
    # A distinct message so the Director takes the right action.
    echo "" >&2
    echo "  GateGuard — PLAN COVERS THIS PATH, BUT ITS FACTS BLOCK IS INVALID" >&2
    echo "  File: $FILE_PATH" >&2
    echo "" >&2
    echo "  $FACTS_MSG" >&2
    echo "" >&2
    echo "  Retrying will not clear this. Go fix the plan, then re-run:" >&2
    echo "    .claude/scripts/validate-plan-facts.sh <plan dir>" >&2
    unity_hook_block "GateGuard: fix the plan's facts block for $FILE_PATH."
fi
```

Also add the library source near the top, after `source "${SCRIPT_DIR}/_lib.sh"`:

```bash
# shellcheck source=lib-gateguard-facts.sh
source "${SCRIPT_DIR}/lib-gateguard-facts.sh"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/gateguard.bats`
Expected: PASS — including every pre-existing test, **unmodified**. If a
pre-existing test needed editing, the ad-hoc path was changed by accident;
revert and re-do Step 3.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/gateguard.sh .claude/hooks/tests/gateguard.bats
git commit -m "feat(hooks): gateguard honours plan coverage instead of depth

A subagent can land a file its approved plan declares. Without coverage the
deny-then-allow gate behaves exactly as before, depth-0 restriction intact.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: guard-critical-files coverage escape

Without this, Module 02 writes nine files and then deadlocks on the mandatory
`AppModules.cs` edit — the template's own acceptance criterion.

**Files:**
- Modify: `.claude/hooks/guard-critical-files.sh:143` (before `GCF_DEPTH=...`)
- Modify: `.claude/hooks/tests/guard-critical-files.bats` (append only)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/guard-critical-files.bats`:

```bash
@test "AppModules.cs edit passes for a subagent when the plan declares it" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/AppModules.cs"
    printf 'public static class AppModules { }\n' > "$f"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T030 \`$f\` — add PlayerModule.Install line
  - Acceptance: compiles
EOF
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/guard-critical-files.sh"
    [ "$status" -eq 0 ]
}

@test "AppModules.cs edit still blocks a subagent when no plan declares it" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo '# no tasks' > "$UNITY_PLAN_ROOT/modules/02/tasks.md"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/AppModules.cs"
    printf 'public static class AppModules { }\n' > "$f"
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/guard-critical-files.sh"
    [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/guard-critical-files.bats`
Expected: FAIL on the first new test with status 2

- [ ] **Step 3: Insert the coverage branch**

In `.claude/hooks/guard-critical-files.sh`, inside the `if [ "$CRITICAL" = true ]`
block, immediately **before** `GCF_DEPTH=$(unity_subagent_depth)`, insert:

```bash
    # Plan coverage releases this gate. This hook's demand is "investigate and
    # confirm the change is intentional and scoped" — a task declared in the plan
    # and approved by a human at SCOPE_GATE has already answered it. Requiring
    # Callers:/Wiring: for a one-line AppModules.cs edit would be noise, so
    # coverage alone is checked here; gateguard.sh layers the facts check on top.
    #
    # This branch is what lets a module actually register itself: every new module
    # must edit AppModules.cs by definition, and without it a pipeline writes all
    # its files and then deadlocks on the last line.
    if unity_plan_covers "$FILE_PATH"; then
        exit 0
    fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/guard-critical-files.bats`
Expected: PASS, existing tests unmodified

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/guard-critical-files.sh .claude/hooks/tests/guard-critical-files.bats
git commit -m "feat(hooks): guard-critical-files honours plan coverage

Every new module must edit AppModules.cs; without this the pipeline writes
every file and then deadlocks on its own registration line.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: check-config-protection `.asmdef` coverage escape

`settings.json` and `.inputactions` stay unconditionally blocked. Only the
`.asmdef` deny-then-allow branch gains the escape.

**Files:**
- Modify: `.claude/hooks/check-config-protection.sh:100` (inside the `.asmdef` branch)
- Modify: `.claude/hooks/tests/check-config-protection.bats` (append only)

- [ ] **Step 1: Write the failing test**

Append to `.claude/hooks/tests/check-config-protection.bats`:

```bash
@test "asmdef edit passes for a subagent when the plan declares it" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02"
    echo 2 > "${UNITY_HOOK_STATE_DIR}/subagent-depth"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/Game.asmdef"
    echo '{"name":"Game"}' > "$f"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T031 \`$TMPDIR_TEST/Players.cs\` — add reference in \`$f\`
  - Callers: T004
  - Wiring: n/a
EOF
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/check-config-protection.sh"
    [ "$status" -eq 0 ]
}

@test "settings.json is blocked even under full plan coverage" {
    export UNITY_PLAN_ROOT="$TMPDIR_TEST/docs"
    mkdir -p "$UNITY_PLAN_ROOT/modules/02" "$TMPDIR_TEST/.claude"
    echo '{"gate":"cleared"}' > "${UNITY_HOOK_STATE_DIR}/gate-cleared"
    local f="$TMPDIR_TEST/.claude/settings.json"
    echo '{}' > "$f"
    cat > "$UNITY_PLAN_ROOT/modules/02/tasks.md" <<EOF
- [ ] T099 \`$f\` — disable a hook
  - Callers: none
  - Wiring: none
EOF
    run bash -c "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$f\"}}' | bash .claude/hooks/check-config-protection.sh"
    [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats .claude/hooks/tests/check-config-protection.bats`
Expected: FAIL on the first new test with status 2; the second already passes and must keep passing

- [ ] **Step 3: Insert the coverage branch**

In `.claude/hooks/check-config-protection.sh`, inside the
`if [ "$EXT" = "asmdef" ]` deny-then-allow branch (around line 100), as its
**first** statement:

```bash
        # Plan coverage releases the .asmdef gate only. settings.json,
        # .inputactions, manifest.json and packages-lock.json are never released
        # by coverage — disabling a hook to work around an error must stay closed,
        # and that is the failure this whole mechanism was written in response to.
        if unity_plan_covers "$FILE_PATH"; then
            exit 0
        fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats .claude/hooks/tests/check-config-protection.bats`
Expected: PASS, existing tests unmodified

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/check-config-protection.sh .claude/hooks/tests/check-config-protection.bats
git commit -m "feat(hooks): plan coverage releases .asmdef edits only

settings.json stays unconditionally blocked — pinned by its own test.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Schema and command wiring

**Files:**
- Modify: `docs/modules/_templates/tasks.md`
- Modify: `.claude/commands/plan-module.md:103`
- Modify: `.claude/commands/create-plan.md:393`
- Modify: `.claude/commands/orchestrate.md:132`

- [ ] **Step 1: Add the fields to the template**

In `docs/modules/_templates/tasks.md`, add a schema note under the title and the
two fields to every non-test task. The T002/T004 examples become:

```markdown
> **Every task that creates a new `.cs` file MUST declare `Callers:` and `Wiring:`.**
> Files under `Tests/` are exempt. Edit tasks need no fields, except
> `FormerlySerializedAs:` when the task renames a `[SerializeField]`.
> Validated before SCOPE_GATE by `.claude/scripts/validate-plan-facts.sh`.

- [ ] T002 [parallel_group:1] `_GameFolders/Scripts/Games/Abstracts/[Domain]/IXxxService.cs` — interface
  - Callers: `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs`, T003 (EditMode test)
  - Wiring: n/a (interface — implementations are wired by [Domain]Module)
  - Test type: EditMode
  - Acceptance: Interface derleniyor

- [ ] T004 `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxService.cs` — implementation
  - Callers: `_GameFolders/Scripts/Games/Concretes/[Domain]/XxxController.cs`
  - Wiring: [Domain]Module.Install → Register<XxxService>().AsImplementedInterfaces()
  - Acceptance: T003 testleri geçiyor
```

- [ ] **Step 2: Wire the validator into all three commands**

In each of `plan-module.md`, `create-plan.md`, `orchestrate.md`, immediately
after the existing `validate-plan-paths.sh` invocation, add:

```
.claude/scripts/validate-plan-facts.sh <same argument as above>
```

with the same BLOCKING annotation the path validator carries in that file. In
`create-plan.md:393` the surrounding line already reads
`- **Then run, BLOCKING:** ...`; match it.

- [ ] **Step 3: Verify the template validates against itself**

Run: `.claude/scripts/validate-plan-facts.sh docs/modules/_templates/tasks.md`
Expected: exit 2 with `no .asmdef owns this location` for the `[Domain]`
placeholder paths — this is correct, the template is not a real plan. Confirm
the message is the asmdef one and **not** a missing-field one; a missing-field
violation here means Step 1 was applied incompletely.

- [ ] **Step 4: Run the full suite**

Run: `bats .claude/hooks/tests/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add docs/modules/_templates/tasks.md .claude/commands/plan-module.md .claude/commands/create-plan.md .claude/commands/orchestrate.md
git commit -m "feat(plans): add Callers/Wiring schema and wire the facts validator

Three commands now run validate-plan-facts.sh as BLOCKING before their gate,
alongside the existing path validator.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: End-to-end verification

No new code. This proves the deadlock is gone before Module 02 relies on it.

**Files:**
- Create: `/tmp/fact-gate-e2e/` (throwaway)

- [ ] **Step 1: Build a fixture plan and simulate a subagent write**

```bash
rm -rf /tmp/fact-gate-e2e && mkdir -p /tmp/fact-gate-e2e/docs/modules/99
cd "$(git rev-parse --show-toplevel)"
mkdir -p .claude/state
echo '{"gate":"cleared"}' > .claude/state/gate-cleared
echo 2 > .claude/state/subagent-depth
cat > /tmp/fact-gate-e2e/docs/modules/99/tasks.md <<'EOF'
- [ ] T001 `/tmp/fact-gate-e2e/PlayerService.cs` — impl
  - Callers: `/tmp/fact-gate-e2e/PlayerController.cs`
  - Wiring: PlayerModule.Install
EOF
UNITY_PLAN_ROOT=/tmp/fact-gate-e2e/docs UNITY_HOOK_PROFILE=strict \
  bash -c 'echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/fact-gate-e2e/PlayerService.cs\"}}" | bash .claude/hooks/gateguard.sh'
echo "gateguard exit: $?"
```
Expected: `gateguard exit: 0` — a depth-2 subagent landed a planned file.

- [ ] **Step 2: Prove the ad-hoc path is unchanged**

```bash
UNITY_PLAN_ROOT=/tmp/fact-gate-e2e/docs UNITY_HOOK_PROFILE=strict \
  bash -c 'echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/fact-gate-e2e/Undeclared.cs\"}}" | bash .claude/hooks/gateguard.sh'
echo "gateguard exit: $?"
```
Expected: `gateguard exit: 2` with the SUBAGENT "Report BLOCKED" message.

- [ ] **Step 3: Prove settings.json is still closed**

```bash
bash -c 'echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\".claude/settings.json\"}}" | bash .claude/hooks/check-config-protection.sh'
echo "config-protection exit: $?"
```
Expected: `config-protection exit: 2`

- [ ] **Step 4: Clean up the simulated state**

```bash
rm -f .claude/state/gate-cleared
echo 0 > .claude/state/subagent-depth
rm -rf /tmp/fact-gate-e2e
```

- [ ] **Step 5: Full suite, then commit the plan's completion**

```bash
bats .claude/hooks/tests/
git add -A
git commit -m "test(hooks): verify the plan-time fact gate end to end

Depth-2 subagent lands a planned file; an undeclared file still blocks;
settings.json still blocks.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

**Spec coverage.** Every spec section maps to a task: library contract → T2/T3;
`unity_plan_covers` → T4; `tasks.md` schema → T3 (rules) + T9 (template);
plan-time validator incl. auto-checks and receipt → T5; write-time gates →
T6/T7/T8; TTL extraction → T1; testing table → the test step of each task;
backward compatibility → nothing needed (no real plans exist); residual risks →
carried in the spec, not implemented by design.

**Known deviation.** The spec implies the automatic checks live in the library;
this plan puts them in `validate-plan-facts.sh` and adds `unity_task_mode` to
the library. Reasoned in "Deliberate refinement over the spec" above.

**Not covered by any task, by design.** `subagent-depth` leak, write-time
serialized-field diffing, merging the two plan validators, any `settings.json`
change — all listed under the spec's Out of scope.
