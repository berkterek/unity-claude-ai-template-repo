# Instruction Loading Restructure — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load only the instructions relevant to the current work, without losing awareness of a rule at plan time, so rule adherence improves and the startup size warning disappears.

**Architecture:** Four always-loaded core rules plus a ≤200-line CLAUDE.md; every other rule gets `paths:` frontmatter. Three independent awareness nets cover what `paths:` cannot see: a rule + skill index injected by `session-restore.sh` on every SessionStart (compact included), a new regex-only `inject-rule-pointers.sh` on UserPromptSubmit for plan-time prompts, and the built-in `paths:` trigger at edit time. Long incident narratives move verbatim to `docs/incidents/`.

**Tech Stack:** Bash hooks (`_lib.sh` conventions), `jq`, `python3`, bats-core, Claude Code CLI (`claude -p`) for the behavioural probe.

**Spec:** `docs/superpowers/specs/2026-10-08-instruction-loading-design.md`

**End State:**
- `.claude/rules/`: 4 files without frontmatter (`architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`); the other 18 start with a `paths:` block. No file renamed, no Card renumbered.
- `.claude/CLAUDE.md` ≤ 200 lines and ≤ 25,000 chars; exactly one `@` import (`orchestrate-rules.md`).
- `docs/incidents/*.md` holds every narrative removed from CLAUDE.md, verbatim.
- `.claude/docs/rule-index.md` exists; `session-restore.sh` emits it plus the skill index as `additionalContext` on every SessionStart source.
- `.claude/hooks/inject-rule-pointers.sh` exists (profile `standard`) and is registered on UserPromptSubmit by the developer.
- `.claude/docs/auto-loaded-skills.md` is a plain `- \`path\` — description` list (no `@`); `auto-load-skills.sh` writes that format; `enforce-skill-for-keywords.sh` no longer treats a listed skill as "in context".
- `architecture.md` ≤ ~36k chars; every heading referenced from another file still exists.
- New bats suites green: `inject-rule-pointers.bats`, `auto-load-skills.bats`, `enforce-skill-for-keywords.bats`, `rule-frontmatter.bats`, `rule-read-audit.bats`; `session-restore.bats` extended; full `.claude/hooks/tests/` green.
- `.claude/tests/rule-awareness-probe/` exists with baseline and after results recorded in its README; after ≥ baseline.
- `/context` shows launch-loaded instruction files < 150k chars; no startup size warning.

## Global Constraints

- Rule file names and Card numbers never change (30+ files reference them by name and card number).
- Exactly one `settings.json` change: a UserPromptSubmit entry for `inject-rule-pointers.sh`, added by a Python script the developer explicitly authorized on 2026-10-08 (Task 4 Step 6). That authorization covers this one entry only.
- Never route around a blocking hook (no `cat >`, `tee`, `sed -i`, `cp` into project files). If `Write`/`Edit` is blocked, stop and surface it.
- Injected text is index/pointer size only — never a rule body.
- Keyword matching is regex only; no LLM classifier.
- New hook scripts must be `chmod +x`.
- **Commits:** run every "Commit" step normally. Exception: if the developer says "no commit until I say", hold all commits from then until they lift it.
- **Branch:** work on a dedicated branch created from `improvement`, never directly on `improvement`.
- Run bats from the repo root: `bats .claude/hooks/tests/<file>.bats`.

## Review Focus

1. `session-restore.sh` stdout polluted by a stray command (e.g. `git branch -D` prints "Deleted branch") → the JSON is invalid and the index is silently not delivered. Pinned in Task 3 (stdout must parse as JSON with the worktree-prune path exercised by code review; the git calls are redirected).
2. Turkish prompts ("Ayarlar ekranı yapalım, ses kaydedilsin") must still hit `save-load` and `ui-toolkit-runtime`. Pinned in Task 4.
3. Substring false positives ("show the latest commit" must not point at `testing`). Pinned in Task 4.
4. A disabled feature's rule (`ecs: false`) must never be injected. Pinned in Task 4.
5. Converting `auto-loaded-skills.md` to a plain list must not silently switch off skill enforcement, nor create duplicate entries for skills already listed in the old `@` format. Pinned in Task 5.

---

### Task 1: Spike — verify the loading assumptions

The whole design rests on these. Several steps need the developer (interactive `/context`, `/compact`). Nothing here is kept.

**Files:**
- Create (temporary): `.claude/rules/zz-spike-probe.md`, `docs/spike/probe.spikeprobe`
- Create: `docs/superpowers/specs/2026-10-08-instruction-loading-spike.md` (findings — kept)

- [ ] **Step 1: Create the probe rule and its trigger file**

`.claude/rules/zz-spike-probe.md`:
```markdown
---
paths:
  - "**/*.spikeprobe"
---
# Spike probe
If asked for the spike marker, the value is SPIKE-MARKER-7731.
```
`docs/spike/probe.spikeprobe`:
```
probe file
```

- [ ] **Step 2: Scoped rule absent before any file is touched**

Run: `claude -p "Without reading any file, reply with the spike marker value from your instructions, or exactly NONE." --permission-mode plan`
Expected: `NONE`

- [ ] **Step 3: Scoped rule loads on Read**

Run: `claude -p "Read docs/spike/probe.spikeprobe, then reply with the spike marker value from your instructions, or exactly NONE." --permission-mode plan`
Expected: contains `7731`

- [ ] **Step 4: Scoped rule loads on Write of a new file (issue #93248)**

Run: `claude -p "Create docs/spike/new.spikeprobe containing the word x, without reading any other file. Then reply with the spike marker value from your instructions, or exactly NONE." --permission-mode acceptEdits`
Expected: record the answer (`7731` = Write triggers; `NONE` = #93248 reproduces). Delete `docs/spike/new.spikeprobe` afterwards.

- [ ] **Step 5: Scoped rule inside a subagent's own Read**

Run: `claude -p "Spawn one general-purpose subagent. Its task: read docs/spike/probe.spikeprobe, then report the spike marker value from ITS OWN instructions, or NONE. Do not read the file yourself. Reply with exactly what the subagent reported." --permission-mode acceptEdits`
Expected: record (`7731` = subagents get scoped rules; `NONE` = they do not — Task 8's explicit reads are then load-bearing).

- [ ] **Step 6: Are `@` imports expanded at all?**

Temporarily append the line `IMPORT-MARKER-5519` to the end of `.claude/docs/quick-start.md` (imported by CLAUDE.md).
Run: `claude -p "Without reading any file, reply with the IMPORT-MARKER value in your instructions, or exactly NONE." --permission-mode plan`
Record the answer, then remove the line. Repeat once with the marker appended to `.claude/skills/plugins/r3.md` (a nested import via `auto-loaded-skills.md`).
`NONE` for the nested import means the 24 auto-loaded skills never reached the main session — report this to the developer before continuing; it changes the risk of Task 5 (from "regression" to "fix").

- [ ] **Step 7: Developer-run interactive checks**

Ask the developer to open an interactive `claude` session in the repo and report:
1. `/context` → the Memory files list and total. Then `Read docs/spike/probe.spikeprobe` and `/context` again — does `zz-spike-probe.md` appear, and was it absent from the startup total?
2. `/compact`, then ask "what is the spike marker value in your instructions?" — expected `NONE` (scoped rule dropped).

- [ ] **Step 8: Remove probe files and write findings**

Delete `.claude/rules/zz-spike-probe.md` and `docs/spike/`. Write `docs/superpowers/specs/2026-10-08-instruction-loading-spike.md` with one row per step: question, command, observed answer, consequence for the design.

**Decision gate:** if Step 3 is `NONE`, `paths:` does not work in this harness — stop and report; the design is invalid. Any other outcome is handled by the existing design; record which net covers it.

---

### Task 2: Rule-awareness probe + baseline

`reviewer-fixtures` cannot measure this change (the reviewer receives its criteria in the prompt). This probe measures whether a fresh session plans according to the rules.

**Files:**
- Create: `.claude/tests/rule-awareness-probe/README.md`
- Create: `.claude/tests/rule-awareness-probe/run-probe.sh`
- Create: `.claude/tests/rule-awareness-probe/prompts/{settings-persist,test-plan,milestone,heart-row}.txt`
- Create: `.claude/tests/rule-awareness-probe/prompts/{settings-persist,test-plan,milestone,heart-row}.markers`

**Interfaces:**
- Produces: `run-probe.sh [runs]` → prints `prompt<TAB>run<TAB>hits/total` per run and a per-prompt mean. Used again in Task 10.

- [ ] **Step 1: Write the prompts and answer keys**

`prompts/settings-persist.txt`:
```
Plan (do not implement, do not write files) a settings screen where "sound on/off" survives restarting the game. List each file you would create, its type, and the rule that decided it.
```
`prompts/settings-persist.markers` (one extended regex per line):
```
SaveData
Version
ISaveLoadService
SaveKeyHelper
UI Toolkit|UIDocument|UGUI
```
`prompts/test-plan.txt`:
```
Plan (do not implement, do not write files) the tests for a pure C# ScoreService and for a PlayerController MonoBehaviour that forwards Update to a MoveHandler. Name each test file, its test type and one example test method name.
```
`prompts/test-plan.markers`:
```
EditMode
PlayMode
NSubstitute
_When[A-Z]
Arrange
```
`prompts/milestone.txt`:
```
We want to start the module for wall material polish next. Plan how to proceed (do not write files).
```
`prompts/milestone.markers`:
```
[Mm]ilestone
ROADMAP
OPEN|open milestone
```
`prompts/heart-row.txt`:
```
Plan (do not implement, do not write files) adding three heart icons to the HUD that show player health.
```
`prompts/heart-row.markers`:
```
[Pp]refab
LayoutGroup
Raycast ?Target
```

- [ ] **Step 2: Write the runner**

`run-probe.sh`:
```bash
#!/usr/bin/env bash
# Rule-awareness probe — measures whether a FRESH session plans by the rules.
# Non-deterministic: one run proves nothing; compare means over >=3 runs.
# Usage: .claude/tests/rule-awareness-probe/run-probe.sh [runs]   (default 3)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS="${1:-3}"
cd "$DIR/../../.."   # repo root — the probe must load this repo's instructions

for prompt_file in "$DIR"/prompts/*.txt; do
    name="$(basename "$prompt_file" .txt)"
    markers="$DIR/prompts/${name}.markers"
    total=$(grep -c . "$markers")
    sum=0
    for run in $(seq 1 "$RUNS"); do
        answer=$(claude -p "$(cat "$prompt_file")" --permission-mode plan 2>/dev/null || true)
        hits=0
        while IFS= read -r re; do
            [ -z "$re" ] && continue
            printf '%s' "$answer" | grep -qE "$re" && hits=$((hits + 1))
        done < "$markers"
        sum=$((sum + hits))
        printf '%s\t%s\t%s/%s\n' "$name" "$run" "$hits" "$total"
    done
    printf '%s\tmean\t%s\n' "$name" "$(echo "scale=2; $sum / $RUNS" | bc)"
done
```
Run: `chmod +x .claude/tests/rule-awareness-probe/run-probe.sh`

- [ ] **Step 3: README with the run log**

`README.md`:
```markdown
# Rule-Awareness Probe

Measures what the instruction-loading layout makes a **fresh session plan**, by grepping a planning answer for
rule-mandated markers. It exists because `reviewer-fixtures` cannot see this: the reviewer is handed its
criteria in the prompt, so it is independent of which rules are loaded.

Non-deterministic and costs one `claude -p` call per prompt per run. Compare means, never single runs.
Do not edit a prompt or a marker to make a run look better — that resets the baseline.

Run: `.claude/tests/rule-awareness-probe/run-probe.sh 3`

## Recorded runs

| Date | Layout | settings-persist | test-plan | milestone | heart-row | Note |
|---|---|---|---|---|---|---|
```

- [ ] **Step 4: Run the baseline (before any other change)**

Run: `.claude/tests/rule-awareness-probe/run-probe.sh 3`
Record the four means in the README table with layout `baseline (all rules unscoped)`. Ask the developer for the `/context` Memory total and record it in the same row's Note.

- [ ] **Step 5: Commit** (only when the developer says so)

```bash
git add .claude/tests/rule-awareness-probe docs/superpowers/specs/2026-10-08-instruction-loading-spike.md
git commit -m "test: add rule-awareness probe and record loading baseline"
```

---

### Task 3: Rule index + awareness net 1 in `session-restore.sh`

**Files:**
- Create: `.claude/docs/rule-index.md`
- Modify: `.claude/hooks/session-restore.sh` (insert after the `source=compact` gate block; redirect git stdout in the worktree prune loop)
- Test: `.claude/hooks/tests/session-restore.bats`

**Interfaces:**
- Produces: `session-restore.sh` prints exactly one JSON object on stdout: `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<rule-index.md>\n\n<auto-loaded-skills.md>"}}`. Env overrides for tests: `UNITY_RULE_INDEX_FILE`, `UNITY_SKILL_INDEX_FILE`.
- Task 5 changes the content of `auto-loaded-skills.md`; this task only concatenates whatever is there.

- [ ] **Step 1: Write the failing tests** — append to `session-restore.bats`:

```bash
# ── Awareness net 1: rule + skill index on every SessionStart ───────────────
# Path-scoped rules are absent before a matching file is touched and dropped at
# /compact. The index re-enters on every source, compact included.
_index_fixture() {
    export UNITY_RULE_INDEX_FILE="$UNITY_HOOK_STATE_DIR/rule-index.md"
    export UNITY_SKILL_INDEX_FILE="$UNITY_HOOK_STATE_DIR/skills.md"
    printf 'RULE-INDEX-MARKER\n' > "$UNITY_RULE_INDEX_FILE"
    printf 'SKILL-INDEX-MARKER\n' > "$UNITY_SKILL_INDEX_FILE"
}

@test "session-restore emits rule and skill index as additionalContext on startup" {
    _index_fixture
    out=$(bash $HOOK 2>/dev/null <<< '{"hook_event_name":"SessionStart","source":"startup"}')
    echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
    echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("RULE-INDEX-MARKER")'
    echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("SKILL-INDEX-MARKER")'
}

@test "session-restore re-emits the index on compact" {
    _index_fixture
    out=$(bash $HOOK 2>/dev/null <<< '{"hook_event_name":"SessionStart","source":"compact"}')
    echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("RULE-INDEX-MARKER")'
}

@test "session-restore stdout is a single valid JSON object (nothing else leaks)" {
    _index_fixture
    out=$(bash $HOOK 2>/dev/null <<< '{"hook_event_name":"SessionStart","source":"startup"}')
    [ "$(echo "$out" | jq -s 'length')" -eq 1 ]
}

@test "session-restore prints nothing on stdout when no index file exists" {
    export UNITY_RULE_INDEX_FILE="$UNITY_HOOK_STATE_DIR/missing.md"
    export UNITY_SKILL_INDEX_FILE="$UNITY_HOOK_STATE_DIR/missing2.md"
    out=$(bash $HOOK 2>/dev/null <<< '{"hook_event_name":"SessionStart","source":"startup"}')
    [ -z "$out" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats .claude/hooks/tests/session-restore.bats`
Expected: the four new tests FAIL (no stdout today); existing tests PASS.

- [ ] **Step 3: Implement** — insert immediately after the `if [ "$_session_source" = "compact" ] … fi` block:

```bash
# ── Awareness net 1 — rule + skill index ────────────────────────────────────
# Path-scoped rules (.claude/rules/*.md with `paths:`) are not in context until a
# matching file is touched, and /compact drops them again. Without this, a session
# plans against rules it does not know exist. The index (what each scoped rule and
# reference skill governs, and when to Read it) is injected on EVERY SessionStart
# source, compact included — the same shape obra/superpowers uses for its
# bootstrap. It must stay above every early `exit 0` below, or a session with no
# saved state would start without it.
# Stdout carries ONLY this JSON; everything else in this script goes to stderr.
# Spec: docs/superpowers/specs/2026-10-08-instruction-loading-design.md
RULE_INDEX_FILE="${UNITY_RULE_INDEX_FILE:-${SCRIPT_DIR}/../docs/rule-index.md}"
SKILL_INDEX_FILE="${UNITY_SKILL_INDEX_FILE:-${SCRIPT_DIR}/../docs/auto-loaded-skills.md}"
_index_text=""
[ -f "$RULE_INDEX_FILE" ] && _index_text="$(cat "$RULE_INDEX_FILE")"
if [ -f "$SKILL_INDEX_FILE" ]; then
    _index_text="${_index_text:+${_index_text}

}$(cat "$SKILL_INDEX_FILE")"
fi
if [ -n "$_index_text" ]; then
    jq -n --arg idx "$_index_text" \
        '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $idx}}'
fi
```
In the worktree prune loop, change the two git calls so they cannot write to stdout:
```bash
                    git -C "$REPO_ROOT" worktree remove -f -f "$wt_path" >/dev/null 2>&1 || true
                    git -C "$REPO_ROOT" branch -D "worktree-${wt_name}" >/dev/null 2>&1 || true
```
and `git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true`.

- [ ] **Step 4: Write `.claude/docs/rule-index.md`**

```markdown
# Rule Index — Path-Scoped Rules

These rules are NOT in your context until a matching file is touched, and /compact drops them again.
When the work below is in scope — **including while only planning** — Read the file before deciding.
MCP tools (scene, prefab, component) never trigger auto-load: Read the rule yourself before MCP work.

| Before you… | Read |
|---|---|
| decide how anything is persisted, or name a `*SaveData` / `*Model` | `.claude/rules/save-load.md` |
| choose UGUI vs UI Toolkit, or plan any screen, menu, popup or HUD | `.claude/rules/ui-toolkit-runtime.md` |
| choose a test type, or write or plan a test | `.claude/rules/testing.md` |
| plan, start or prioritize a module; edit the GDD, TDD or ROADMAP | `.claude/rules/roadmap-milestones.md` |
| create or change a prefab, or place a second copy of an object | `.claude/rules/unity-prefabs.md` |
| place or move objects in a scene | `.claude/rules/scene-hierarchy.md` |
| choose IEventBus vs Action vs C# event vs R3 | `.claude/rules/event-patterns.md` |
| write async code | `.claude/rules/unity-async.md` |
| rename or add a serialized field | `.claude/rules/serialization.md` |
| use editor guards, platform defines, lifecycle order, DOTween cleanup | `.claude/rules/unity-lifecycle.md` |
| log anything | `.claude/rules/logging.md` |
| read player input | `.claude/rules/unity-input.md` |
| write hot-path code, materials, shaders, or UI raycast settings | `.claude/rules/performance.md` |
| write ECS code (only if feature `ecs` is enabled) | `.claude/rules/ecs-dots.md` |
| load assets at runtime (only if feature `addressables` is enabled) | `.claude/rules/addressables.md` |
| build a browser-based authoring tool | `.claude/rules/web-tool-architecture.md`, `web-tool-data-contract.md`, `web-tool-design-system.md` |

Always loaded, no action needed: `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats .claude/hooks/tests/session-restore.bats`
Expected: all PASS.

- [ ] **Step 6: Commit** (only when the developer says so)

```bash
git add .claude/docs/rule-index.md .claude/hooks/session-restore.sh .claude/hooks/tests/session-restore.bats
git commit -m "feat(hooks): inject rule and skill index on every SessionStart"
```

---

### Task 4: Awareness net 2 — `inject-rule-pointers.sh`

**Files:**
- Create: `.claude/hooks/inject-rule-pointers.sh`
- Test: `.claude/hooks/tests/inject-rule-pointers.bats`
- Modify (developer): `.claude/settings.json` UserPromptSubmit
- Modify: `.claude/docs/hooks-warning.md` (one row for the new hook)

**Interfaces:**
- Consumes: `.claude/project-features.json` (override `UNITY_PROJECT_FEATURES_FILE`), `.claude/rules/*.md` existence.
- Produces: on a match, `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"RULE CHECK — …\n  .claude/rules/<rule>.md …"}}`; otherwise no stdout. Exit 0 always.

- [ ] **Step 1: Write the failing tests** — `.claude/hooks/tests/inject-rule-pointers.bats`:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bats .claude/hooks/tests/inject-rule-pointers.bats`
Expected: FAIL — hook file does not exist.

- [ ] **Step 3: Implement** — `.claude/hooks/inject-rule-pointers.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# inject-rule-pointers.sh — UserPromptSubmit hook (awareness net 2)
#
# Path-scoped rules (.claude/rules/*.md with `paths:`) load only when a matching
# file is Read/Written/Edited. A planning prompt touches no file, so the rule that
# should shape the plan is absent and the model does not know it exists. This hook
# matches prompt keywords and injects a short POINTER — never the rule body —
# naming the rule files to Read before planning.
#
# Prior art: diet103/claude-code-infrastructure-showcase skill-rules.json. Regex
# only on purpose: its optional LLM classifier over-triggers on ~1/3 of off-topic
# prompts (its own benchmark comment).
#
# Deliberately NOT folded into enforce-skill-for-keywords.sh: that hook declares
# HOOK_PROFILE_LEVEL="strict", so under the default `standard` profile _lib.sh
# exits it before any matching runs.
#
# Spec: docs/superpowers/specs/2026-10-08-instruction-loading-design.md
#
# To add a mapping: append "stem|rule-basename[ rule-basename…]|feature" to RULE_MAP.
#   stem    — lowercase; matched at a word start ("test" hits "tests", not "latest")
#   feature — optional project-features.json key; skipped when that key is false
# ============================================================================
# Trigger: UserPromptSubmit
# Exit:    0 always — prints additionalContext JSON when a stem matches
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$PROMPT" ] && exit 0

FEATURES_FILE="${UNITY_PROJECT_FEATURES_FILE:-${SCRIPT_DIR}/../project-features.json}"
RULES_DIR="${SCRIPT_DIR}/../rules"

RULE_MAP=(
    # Persistence
    "save|save-load|"
    "persist|save-load|"
    "playerprefs|save-load|"
    "kayd|save-load|"
    "kayıt|save-load|"
    "kalıcı|save-load|"
    # UI — ui-toolkit-runtime Card 1 decides UGUI vs UI Toolkit before any file exists
    "screen|ui-toolkit-runtime|"
    "menu|ui-toolkit-runtime|"
    "popup|ui-toolkit-runtime|"
    "hud|ui-toolkit-runtime unity-prefabs|"
    "uxml|ui-toolkit-runtime|"
    "ui toolkit|ui-toolkit-runtime|"
    "ekran|ui-toolkit-runtime|"
    "arayüz|ui-toolkit-runtime|"
    # Testing
    "test|testing|testing"
    # Milestones
    "milestone|roadmap-milestones|"
    "roadmap|roadmap-milestones|"
    "plan-module|roadmap-milestones|"
    # Prefabs and scenes
    "prefab|unity-prefabs|"
    "scene|scene-hierarchy|"
    "sahne|scene-hierarchy|"
    # Optional features
    "ecs|ecs-dots|ecs"
    "dots|ecs-dots|ecs"
    "addressable|addressables|addressables"
    # Browser authoring tools
    "web tool|web-tool-architecture web-tool-data-contract web-tool-design-system|"
    "level editor|web-tool-architecture web-tool-data-contract web-tool-design-system|"
)

_feature_enabled() {
    local feature="$1"
    [ -z "$feature" ] && return 0
    [ -f "$FEATURES_FILE" ] || return 0
    # `.[$f] // true` would turn an explicit false into true — test with has().
    [ "$(jq -r --arg f "$feature" 'if has($f) then .[$f] else true end' "$FEATURES_FILE" 2>/dev/null)" != "false" ]
}

MATCHED=()
for entry in "${RULE_MAP[@]}"; do
    IFS='|' read -r stem rules feature <<< "$entry"
    printf '%s' "$PROMPT" | grep -qE "(^|[[:space:][:punct:]])${stem}" || continue
    _feature_enabled "$feature" || continue
    for rule in $rules; do
        [ -f "${RULES_DIR}/${rule}.md" ] || continue
        case " ${MATCHED[*]:-} " in *" ${rule} "*) continue ;; esac
        MATCHED+=("$rule")
    done
done

[ ${#MATCHED[@]} -eq 0 ] && exit 0

LIST=$(printf '  .claude/rules/%s.md\n' "${MATCHED[@]}")

jq -n --arg list "$LIST" '{
    hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: ("RULE CHECK — this request touches areas governed by path-scoped rules that are NOT in your context yet. Before planning, answering or writing code, Read each file below and state which of its Cards apply (or that none do):\n\n" + $list + "\n\nThis is a pointer, not the rule — do not plan from memory of it.")
    }
}'

exit 0
```
Run: `chmod +x .claude/hooks/inject-rule-pointers.sh`

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats .claude/hooks/tests/inject-rule-pointers.bats`
Expected: all PASS.

- [ ] **Step 5: Document the hook** — add one row to the table in `.claude/docs/hooks-warning.md`:

```markdown
| `inject-rule-pointers.sh` | UserPromptSubmit | Injects "Read `rules/X.md` before planning" when a prompt keyword maps to a path-scoped rule (awareness net 2). Regex only; skips rules of disabled features. Never blocks. |
```

- [ ] **Step 6: Register the hook (developer-approved Python edit, 2026-10-08)**

The developer explicitly authorized adding this one entry with a Python script. Run it **only after Steps 3–4 pass** — registering a script that does not exist yet fails every prompt. If `check-write-via-bash.sh` (or any hook) blocks it, stop and tell the developer; do not try another channel.
```bash
python3 - <<'PY'
import json
path = '.claude/settings.json'
with open(path, encoding='utf-8') as f:
    settings = json.load(f)
cmd = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/inject-rule-pointers.sh'
groups = settings.setdefault('hooks', {}).setdefault('UserPromptSubmit', [])
if any(h.get('command') == cmd for g in groups for h in g.get('hooks', [])):
    print('already registered')
else:
    groups.append({'hooks': [{'type': 'command', 'command': cmd, 'timeout': 5000,
                              'statusMessage': 'Checking rule pointers...'}]})
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print('registered')
PY
```
Verify: `jq '.hooks.UserPromptSubmit[].hooks[].command' .claude/settings.json | grep -c inject-rule-pointers` → `1`, and `git diff --stat .claude/settings.json` shows only that file with a small insertion (no reformatting of other entries — if the diff is large, `json.dump` changed formatting: revert and report).

- [ ] **Step 7: Commit** (only when the developer says so)

```bash
git add .claude/hooks/inject-rule-pointers.sh .claude/hooks/tests/inject-rule-pointers.bats .claude/docs/hooks-warning.md .claude/settings.json
git commit -m "feat(hooks): point plan-time prompts at path-scoped rules"
```

---

### Task 5: Auto-loaded skills become a described list (no `@`)

The 24 files are mostly nested (`third-party/unitask/SKILL.md`) and therefore **not** discoverable as skills — the `@` import is their only route into the main session today. Removing the import without a replacement would drop them; the replacement is the described list that Task 3 already injects.

**Files:**
- Modify: `.claude/hooks/auto-load-skills.sh`
- Modify: `.claude/hooks/enforce-skill-for-keywords.sh` (remove the auto-loaded skip, lines ~136-160)
- Modify: `.claude/docs/auto-loaded-skills.md` (one-time migration)
- Test: `.claude/hooks/tests/auto-load-skills.bats`, `.claude/hooks/tests/enforce-skill-for-keywords.bats`

**Interfaces:**
- Produces: entries of the form ``- `<relative path>` — <description, ≤140 chars>``. Description = frontmatter `description:` (folded `>` reads the next non-empty line), else the first `# ` heading, else empty.
- Env override for tests: `UNITY_AUTO_LOADED_SKILLS_FILE`.

- [ ] **Step 1: Write the failing tests** — `.claude/hooks/tests/auto-load-skills.bats`:

```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/auto-load-skills.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
    export UNITY_AUTO_LOADED_SKILLS_FILE="$UNITY_HOOK_STATE_DIR/auto-loaded-skills.md"
    printf '# Auto-Loaded Skills\n\n<!-- managed by auto-load-skills.sh — do not edit manually -->\n\n' > "$UNITY_AUTO_LOADED_SKILLS_FILE"
    REPO="$(pwd)"
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

_payload() { jq -n --arg f "$REPO/$1" '{tool_input: {file_path: $f}}'; }

@test "adds a plain described entry, never an @-import" {
    run bash $HOOK <<< "$(_payload .claude/skills/plugins/r3.md)"
    [ "$status" -eq 0 ]
    grep -qF -- '- `.claude/skills/plugins/r3.md` — R3' "$UNITY_AUTO_LOADED_SKILLS_FILE"
    ! grep -q '^@' "$UNITY_AUTO_LOADED_SKILLS_FILE"
}

@test "folded description (description: >) reads the next line" {
    run bash $HOOK <<< "$(_payload .claude/skills/third-party/netcode/SKILL.md)"
    line=$(grep -F 'netcode/SKILL.md' "$UNITY_AUTO_LOADED_SKILLS_FILE")
    [[ "$line" != *"— >"* ]]
    [[ "$line" =~ —\ [A-Za-z] ]]
}

@test "does not duplicate a skill already listed in the old @ format" {
    printf '@.claude/skills/plugins/r3.md\n' >> "$UNITY_AUTO_LOADED_SKILLS_FILE"
    run bash $HOOK <<< "$(_payload .claude/skills/plugins/r3.md)"
    [ "$(grep -c 'plugins/r3.md' "$UNITY_AUTO_LOADED_SKILLS_FILE")" -eq 1 ]
}

@test "ignores files outside the managed skill folders" {
    run bash $HOOK <<< "$(_payload .claude/rules/logging.md)"
    ! grep -q 'logging.md' "$UNITY_AUTO_LOADED_SKILLS_FILE"
}
```

`.claude/hooks/tests/enforce-skill-for-keywords.bats`:
```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    export UNITY_HOOK_PROFILE=strict   # this hook is strict-level
    HOOK=".claude/hooks/enforce-skill-for-keywords.sh"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}

teardown() { rm -rf "$UNITY_HOOK_STATE_DIR"; }

@test "a skill listed in auto-loaded-skills.md is still demanded until invoked" {
    # The list is a plain index now, not an @-import — being listed no longer
    # means being in context. Treating it as loaded silently disabled enforcement.
    grep -q 'unitask' .claude/docs/auto-loaded-skills.md
    run bash $HOOK <<< '{"prompt":"use unitask for the loader"}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"unitask"* ]]
}

@test "an invoked skill is not demanded again" {
    echo unitask > "$UNITY_HOOK_STATE_DIR/skills-invoked.txt"
    run bash $HOOK <<< '{"prompt":"use unitask for the loader"}'
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats .claude/hooks/tests/auto-load-skills.bats .claude/hooks/tests/enforce-skill-for-keywords.bats`
Expected: auto-load tests FAIL (writes `@` refs; ignores the env override); first enforce test FAILS (skip logic), second PASSES.

- [ ] **Step 3: Implement `auto-load-skills.sh`**

Replace the header comment line and everything from `CLAUDE_MD=` to the end with:
```bash
# PostToolUse hook: lists new skill files in .claude/docs/auto-loaded-skills.md
# as "- `path` — description". NOT an @-import: imports load at launch and count
# toward the instruction budget. session-restore.sh injects this list at every
# SessionStart, and agents read it at Step 0, so the model knows each skill exists
# and Reads it when relevant. Spec: docs/superpowers/specs/2026-10-08-instruction-loading-design.md

INDEX_FILE="${UNITY_AUTO_LOADED_SKILLS_FILE:-$PROJECT_ROOT/.claude/docs/auto-loaded-skills.md}"
SECTION_HEADER="# Auto-Loaded Skills"

# Already listed, in either the old @ format or the new one?
if [ -f "$INDEX_FILE" ] && grep -qF "$RELATIVE_PATH" "$INDEX_FILE"; then
    exit 0
fi

if [ ! -f "$INDEX_FILE" ] || ! grep -qF "$SECTION_HEADER" "$INDEX_FILE"; then
    printf '\n%s\n\n<!-- managed by auto-load-skills.sh — do not edit manually -->\n' "$SECTION_HEADER" >> "$INDEX_FILE"
fi

python3 - "$INDEX_FILE" "$SECTION_HEADER" "$RELATIVE_PATH" "$PROJECT_ROOT/$RELATIVE_PATH" << 'PYEOF'
import sys

index_path, section_header, rel_path, abs_path = sys.argv[1:5]

def describe(path):
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except OSError:
        return ''
    if lines and lines[0].strip() == '---':
        for i in range(1, len(lines)):
            if lines[i].strip() == '---':
                break
            if lines[i].startswith('description:'):
                value = lines[i][len('description:'):].strip().strip('"').strip("'")
                if value in ('>', '|', '>-', '|-', ''):
                    for nxt in lines[i + 1:]:
                        if nxt.strip():
                            value = nxt.strip()
                            break
                return value[:140]
    for line in lines:
        if line.startswith('# '):
            return line[2:].strip()[:140]
    return ''

desc = describe(abs_path)
entry = f'- `{rel_path}`' + (f' — {desc}' if desc else '') + '\n'

with open(index_path, encoding='utf-8') as f:
    lines = f.readlines()

insert_at = None
for i, line in enumerate(lines):
    if line.strip() == section_header:
        insert_at = i + 1
        for j in range(i + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped.startswith('- `') or stripped.startswith('@') or stripped.startswith('<!--') or not stripped:
                insert_at = j + 1
            elif stripped.startswith('#'):
                break
        break

if insert_at is not None:
    lines.insert(insert_at, entry)
    with open(index_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)
PYEOF

echo "auto-load-skills: listed $RELATIVE_PATH in auto-loaded-skills.md" >&2
exit 0
```

- [ ] **Step 4: Implement the `enforce-skill-for-keywords.sh` fix**

Delete the `AUTO_LOADED_FILE` / `AUTO_LOADED_CONTENT` block and the `# Skip if the skill is auto-loaded into context …` `if … continue … fi` block inside the loop. In their place, above the loop, add:
```bash
# auto-loaded-skills.md is a plain index since 2026-10-08, not an @-import, so a
# skill listed there is NOT in context. It used to be, and this hook skipped
# enforcement for listed skills; keeping that skip would now silently disable it.
```

- [ ] **Step 5: Migrate `.claude/docs/auto-loaded-skills.md`**

Rewrite it with the Write tool (not sed) to:
```markdown
# Auto-Loaded Skills

<!-- managed by auto-load-skills.sh — do not edit manually -->

Reference skills for this project. Not @-imported: injected at SessionStart as an index.
Read the file when its description matches the work.

```
followed by one line per existing entry in the same order, generated by running for each old `@path` the same `describe()` logic. Do it with a scratch script (scratch path is exempt from `check-write-via-bash.sh`), print the result, then Write it:
```bash
python3 - <<'PY'
import re
paths = [l[1:].strip() for l in open('.claude/docs/auto-loaded-skills.md') if l.startswith('@')]
def describe(path):
    lines = open(path, encoding='utf-8').read().splitlines()
    if lines and lines[0].strip() == '---':
        for i in range(1, len(lines)):
            if lines[i].strip() == '---': break
            if lines[i].startswith('description:'):
                v = lines[i][12:].strip().strip('"').strip("'")
                if v in ('>', '|', '>-', '|-', ''):
                    v = next((n.strip() for n in lines[i+1:] if n.strip()), '')
                return v[:140]
    return next((l[2:].strip()[:140] for l in lines if l.startswith('# ')), '')
for p in paths:
    d = describe(p)
    print(f'- `{p}`' + (f' — {d}' if d else ''))
PY
```
Verify: `grep -c '^- `' .claude/docs/auto-loaded-skills.md` → `24`; `grep -c '^@' .claude/docs/auto-loaded-skills.md` → `0`.

- [ ] **Step 6: Run tests**

Run: `bats .claude/hooks/tests/auto-load-skills.bats .claude/hooks/tests/enforce-skill-for-keywords.bats .claude/hooks/tests/session-restore.bats`
Expected: all PASS.

- [ ] **Step 7: Commit** (only when the developer says so)

```bash
git add .claude/hooks/auto-load-skills.sh .claude/hooks/enforce-skill-for-keywords.sh .claude/docs/auto-loaded-skills.md .claude/hooks/tests/auto-load-skills.bats .claude/hooks/tests/enforce-skill-for-keywords.bats
git commit -m "refactor(hooks): list reference skills as an injected index instead of @-imports"
```

---

### Task 6: CLAUDE.md → index; narratives → `docs/incidents/`

**Files:**
- Create: `docs/incidents/README.md` and the topic files below
- Modify: `.claude/CLAUDE.md`

**Move map** (identify each block by its bold lead phrase; move it **verbatim**, including its `>` sub-notes):

| Destination | Blocks |
|---|---|
| `docs/incidents/test-layers.md` | "A green hook suite is NOT evidence about a prompt"; "A silent hook is NOT a compliance check" |
| `docs/incidents/pretooluse-effective-content.md` | "A `PreToolUse` content-check hook must validate the EDIT's result" |
| `docs/incidents/plan-time-gates.md` | "Path rules are validated at PLAN time"; "The gateguard's fact demands are also validated at PLAN time"; "Plan coverage releases the deny-then-allow gates" and its three `>` notes (strict profile; 2026-09-07 cwd; 2026-09-09 rename) |
| `docs/incidents/ui-toolkit-status.md` | The "UI Toolkit is version-gated" bullet's `> **Status (2026-09-30)…` note |
| `docs/incidents/mcp-and-framework.md` | "A session's MCP tool list is frozen"; "An inspector reference on a prefab… SerializedOps applier"; "The framework is a package"; the whole "Unity official plugin (`unity@unity-agent-plugin`) — precedence" subsection |
| `docs/incidents/knowledge-graph.md` | The bullets on `graph.json` partitions, `extraction_version` vs `schema_version`, `GRAPH_DISK_MISMATCH`, `events[].file`, installer detection, scope `parent: null`, registration records, `registrations[].lifetime` |
| `docs/incidents/model-tiers.md` | "Layer 1 obeys the same rule…" and "There is no automatic model fallback…" paragraphs |
| `docs/incidents/subagent-depth.md` | Every `>` note under "Subagent Lifecycle Hooks", plus "Why not the native SubagentStart / SubagentStop events" and "None of the three touches gate state" |
| `docs/incidents/gate-markers.md` | The `sparc-approved`, `codex-reviewed`, `UNITY_GATE_TTL` notes under Director Gates; the compaction note and "Gate-cleared ≠ pipeline-executed" paragraph under Director Gate Rules |

Each incident file starts with `# <Topic>` and one line: `Moved verbatim from .claude/CLAUDE.md on 2026-10-08; the rule it supports is stated there in short form.`

- [ ] **Step 1: Snapshot the current file for the verbatim check**

Run: `git show HEAD:.claude/CLAUDE.md > "${TMPDIR:-/tmp}/CLAUDE.md.before"`

- [ ] **Step 2: Create the incident files** — cut each block from CLAUDE.md into its destination per the move map. `docs/incidents/README.md`:
```markdown
# Incidents

Dated root-cause narratives moved out of `.claude/CLAUDE.md` so they stop loading into every session.
CLAUDE.md keeps the short rule each one supports and links here. Nothing was deleted.
```

- [ ] **Step 3: Rewrite `.claude/CLAUDE.md` to this skeleton**

Sections, in order (kept text is the short rule; every moved block leaves a line ending `→ docs/incidents/<file>.md`):
1. `# Unity AI Template — Claude Code Configuration` + the existing one-paragraph intro.
2. `## Shell Commands (NON-NEGOTIABLE)` — unchanged.
3. `## Interaction Style` and `## What You Do NOT Do` — unchanged.
4. `## Important Constraints` — one bullet each, ≤2 lines:
   - `settings.json` is not editable by Claude; new hooks need `chmod +x`.
   - Hook exit 0 = warning, exit 2 = block.
   - Never route around a blocking hook (no Bash writes into project files) — `check-write-via-bash.sh`.
   - A green bats suite says nothing about a prompt; prompt changes need an agent probe (`reviewer-fixtures`, `rule-awareness-probe`) → `docs/incidents/test-layers.md`.
   - A silent hook is not a compliance check; only a `checked: <rule>` receipt is evidence → `docs/incidents/test-layers.md`.
   - A `PreToolUse` content hook judges the effective post-edit content, never disk, and its `Write` branch must be reachable → `docs/incidents/pretooluse-effective-content.md`.
   - Path rules and gateguard fact demands are validated at plan time (`validate-plan-paths.sh`, `validate-plan-facts.sh`); plan coverage releases deny-then-allow gates → `docs/incidents/plan-time-gates.md`.
   - Hook profiles: `UNITY_HOOK_PROFILE=minimal|standard|strict` (default standard) → `.claude/docs/hook-profiles.md`.
   - UI Toolkit is version-gated: game UI on 6000.0+, Editor-only below; read `ProjectSettings/ProjectVersion.txt` → `rules/ui-toolkit-runtime.md`, status `docs/incidents/ui-toolkit-status.md`.
   - Scenes: never `Write`/`Edit` `.unity`; use MCP. Prefab/SO references via the SerializedOps applier → `docs/incidents/mcp-and-framework.md`.
   - MCP tool list is frozen at session start; restart, never substitute Bash → `docs/incidents/mcp-and-framework.md`.
   - The framework is a package (`packages/framework/` is its only source); never vendor it → `docs/incidents/mcp-and-framework.md`.
   - Unity official plugin: this repo's rules win; `unity command eval` is forbidden → `docs/incidents/mcp-and-framework.md`.
   - `graph.json` is generated; never edit by hand; read `as_resolution` and `parent_source` before concluding → `docs/incidents/knowledge-graph.md`.
   - Agents: `subagent_type` = agent filename without `.md` → `.claude/docs/agents-index.md`.
5. `## Rules` — two lines: always loaded = `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`; every other rule is path-scoped and indexed in `.claude/docs/rule-index.md` (injected at SessionStart — Read the rule before deciding in its area, even while planning).
6. `## Required Stack` and `## Optional Features` tables — unchanged.
7. `## Session Start` — unchanged list, plus the graph query cheatsheet unchanged.
8. `## Reference (read on demand)` — the 13 former imports as backtick paths with a one-line purpose each: `knowledge-graph.md`, `quick-start.md`, `model-tiers.md`, `hooks-blocking.md`, `hooks-warning.md`, `commands.md`, `agents-index.md`, `architecture-summary.md`, `context-management.md`, `director-gates.md`, `setup-checklist.md`, `skills-index.md`, `auto-loaded-skills.md`.
9. `## Director Gates` — the gate table unchanged; the notes → `docs/incidents/gate-markers.md`.
10. `## NON-NEGOTIABLE: /orchestrate Rules` — keeps `@.claude/docs/orchestrate-rules.md` (the only remaining import).
11. `## NON-NEGOTIABLE: Director Gate Rules` — the numbered list, the 45-minute TTL sentence and the `pipeline-override` escape valve sentence; narratives → `docs/incidents/gate-markers.md`.
12. `## Subagent Lifecycle Hooks` — one table, plus: "`subagent-depth` is a hint, never fact; to reset, clear the counter and `subagent-depth-pending.jsonl` together" with the existing one-line command → `docs/incidents/subagent-depth.md`.
13. `## Model Tiers` — 3 lines (aliases, never pinned IDs except fallbacks; no automatic fallback) → `docs/incidents/model-tiers.md`.
14. `## Project Features` — unchanged (written by `/setup-project`).
15. `## Optional Plugins` table — unchanged.

- [ ] **Step 4: Verify size and imports**

Run: `wc -l -c .claude/CLAUDE.md; grep -c '^@' .claude/CLAUDE.md`
Expected: ≤ 200 lines, ≤ 25000 chars; `1`.

- [ ] **Step 5: Verify nothing was lost (verbatim check)**

Run:
```bash
python3 - <<'PY'
import glob, os
before = open(os.path.join(os.environ.get('TMPDIR', '/tmp'), 'CLAUDE.md.before'), encoding='utf-8').read().splitlines()
after = open('.claude/CLAUDE.md', encoding='utf-8').read()
moved = ''.join(open(p, encoding='utf-8').read() for p in glob.glob('docs/incidents/*.md'))
missing = [l for l in before if len(l) >= 120 and l not in after and l not in moved]
print(f'{len(missing)} long lines found in neither file')
for l in missing: print('  ', l[:110])
PY
```
Expected: `0 long lines found in neither file`. Any hit is a lost paragraph — restore it into its incident file.

- [ ] **Step 6: Verify every link resolves**

Run: `grep -oE 'docs/incidents/[a-z-]+\.md' .claude/CLAUDE.md | sort -u | while read f; do [ -f "$f" ] || echo "MISSING $f"; done`
Expected: no output.

- [ ] **Step 7: Commit** (only when the developer says so)

```bash
git add .claude/CLAUDE.md docs/incidents
git commit -m "docs: slim CLAUDE.md to an index and move incident narratives to docs/incidents"
```

---

### Task 7: `paths:` frontmatter on 18 rule files

**Files:**
- Modify: the 18 rule files below (prepend frontmatter only — no other change)
- Test: `.claude/hooks/tests/rule-frontmatter.bats`

| Rule | `paths:` |
|---|---|
| `event-patterns`, `unity-async`, `serialization`, `unity-lifecycle`, `logging`, `save-load` | `"**/*.cs"` |
| `unity-input` | `"**/*.cs"`, `"**/*.inputactions"` |
| `performance` | `"**/*.cs"`, `"**/Arts/**"`, `"**/*.{mat,shader,shadergraph}"` |
| `testing` | `"**/Tests/**"`, `"**/*Tests.cs"` |
| `ui-toolkit-runtime` | `"**/*.{uxml,uss,tss}"`, `"**/UI/**"` |
| `web-tool-architecture`, `web-tool-data-contract`, `web-tool-design-system` | `"tools/**"` |
| `unity-prefabs`, `scene-hierarchy` | `"**/*.{prefab,unity}"`, `"**/Prefabs/**"` |
| `ecs-dots` | `"**/Ecs/**"` |
| `addressables` | `"**/AddressableAssetsData/**"`, `"**/*Addressable*.cs"` |
| `roadmap-milestones` | `"docs/GDD*.md"`, `"docs/TDD*.md"`, `"docs/ROADMAP.md"`, `"docs/modules/**"` |

Format (YAML list, every glob quoted):
```markdown
---
paths:
  - "**/*.cs"
---
```

- [ ] **Step 1: Write the failing test** — `.claude/hooks/tests/rule-frontmatter.bats`:

```bash
#!/usr/bin/env bats
# Pins which rules are always loaded and which are path-scoped. A rule that loses
# its frontmatter loads into every session again; a core rule that gains one
# vanishes at plan time and after /compact.

setup() { cd "$BATS_TEST_DIRNAME/../../.." || exit 1; }

_globs() {  # print the quoted globs of a rule's paths: block, one per line
    awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} /^  - "/ {print}' ".claude/rules/$1.md" \
        | sed -E 's/^  - "(.*)"$/\1/'
}

@test "core rules have no frontmatter" {
    for r in architecture solid-oop csharp-unity bootstrap-pattern; do
        [ "$(head -1 .claude/rules/$r.md)" != "---" ] || { echo "core rule $r is scoped"; false; }
    done
}

@test "every non-core rule is path-scoped" {
    for f in .claude/rules/*.md; do
        r=$(basename "$f" .md)
        case "$r" in architecture|solid-oop|csharp-unity|bootstrap-pattern) continue ;; esac
        [ "$(head -1 "$f")" = "---" ] || { echo "$r has no frontmatter"; false; }
        [ -n "$(_globs "$r")" ] || { echo "$r has no quoted paths"; false; }
    done
}

@test "frontmatter uses only the paths key (any other key is silently ignored)" {
    for f in .claude/rules/*.md; do
        [ "$(head -1 "$f")" = "---" ] || continue
        bad=$(awk 'NR>1 && $0=="---" {exit} NR>1 && /^[a-z_]+:/ && !/^paths:/' "$f")
        [ -z "$bad" ] || { echo "$f: $bad"; false; }
    done
}

@test "C# layer rules trigger on .cs" {
    for r in event-patterns unity-async serialization unity-lifecycle logging save-load unity-input performance; do
        _globs "$r" | grep -qxF '**/*.cs' || { echo "$r missing **/*.cs"; false; }
    done
}

@test "domain rules carry their domain glob" {
    _globs testing | grep -qxF '**/Tests/**'
    _globs ui-toolkit-runtime | grep -qxF '**/*.{uxml,uss,tss}'
    _globs web-tool-architecture | grep -qxF 'tools/**'
    _globs unity-prefabs | grep -qxF '**/*.{prefab,unity}'
    _globs scene-hierarchy | grep -qxF '**/*.{prefab,unity}'
    _globs ecs-dots | grep -qxF '**/Ecs/**'
    _globs roadmap-milestones | grep -qxF 'docs/ROADMAP.md'
}

@test "every scoped rule is listed in the rule index" {
    for f in .claude/rules/*.md; do
        [ "$(head -1 "$f")" = "---" ] || continue
        r=$(basename "$f")
        grep -qF "$r" .claude/docs/rule-index.md || { echo "$r missing from rule-index.md"; false; }
    done
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats .claude/hooks/tests/rule-frontmatter.bats`
Expected: "every non-core rule is path-scoped" and later tests FAIL; "core rules have no frontmatter" PASSES.

- [ ] **Step 3: Prepend frontmatter** to each of the 18 files with the Edit tool, per the table. Change nothing else in the files.

- [ ] **Step 4: Check no tool parses a rule file's first line**

Run: `grep -rnE 'head -1|sed -n .?1p|readline\(\)' .claude/hooks .claude/scripts | grep -i rules`
Expected: no output. Any hit must be updated to skip the frontmatter before continuing.

- [ ] **Step 5: Run tests**

Run: `bats .claude/hooks/tests/rule-frontmatter.bats`
Expected: all PASS.

- [ ] **Step 6: Commit** (only when the developer says so)

```bash
git add .claude/rules .claude/hooks/tests/rule-frontmatter.bats
git commit -m "feat(rules): path-scope every non-core rule"
```

---

### Task 8: Explicit reads where `paths:` cannot fire

Planning commands touch no file before deciding; MCP agents never fire `paths:`; subagents may not (Task 1 Step 5). Each file below gets a uniform block directly after its frontmatter (or H1 if none):

```markdown
> **Rules to Read first** (path-scoped — not in context until a matching file is touched):
> `.claude/rules/<rule>.md`[, `.claude/rules/<rule>.md`]
```

| File | Rules |
|---|---|
| `.claude/agents/tester.md`, `.claude/agents/unity-test-builder.md` | `testing` |
| `.claude/agents/unity-ui-toolkit-builder.md` | `ui-toolkit-runtime` |
| `.claude/agents/unity-ui-builder.md` | `ui-toolkit-runtime`, `unity-prefabs`, `performance` |
| `.claude/agents/unity-setup.md` | `scene-hierarchy`, `unity-prefabs`, `ui-toolkit-runtime` |
| `.claude/agents/unity-scene-builder.md` | `scene-hierarchy`, `unity-prefabs` |
| `.claude/agents/reviewer.md`, `.claude/agents/unity-reviewer.md` | `logging`, `save-load`, `serialization`, `event-patterns`, `unity-async`, `performance` |
| `.claude/agents/migrator.md` | `unity-input`, `unity-async`, `event-patterns` |
| `.claude/agents/unity-optimizer.md` | `performance` |
| `.claude/commands/architect.md` | `ui-toolkit-runtime`, `roadmap-milestones`, `save-load`, `testing` |
| `.claude/commands/plan-module.md`, `.claude/commands/roadmap.md`, `.claude/commands/game-idea.md`, `.claude/commands/refine-gdd.md`, `.claude/commands/refine-tdd.md` | `roadmap-milestones` |
| `.claude/commands/orchestrate.md` | `roadmap-milestones`, `testing` |
| `.claude/commands/implement.md`, `.claude/commands/fix.md`, `.claude/commands/migrate.md` | `testing` |
| `.claude/commands/setup-project.md` | `save-load`, `logging` |
| `.claude/commands/scene-setup.md`, `.claude/commands/update-scene-hierarchy.md`, `.claude/commands/unity-scene-update.md`, `.claude/commands/create-prefab-scene.md` | `scene-hierarchy`, `unity-prefabs` |

**Files:**
- Modify: the 25 files in the table
- Test: `.claude/hooks/tests/rule-read-audit.bats`

- [ ] **Step 1: Write the failing test** — `.claude/hooks/tests/rule-read-audit.bats`:

```bash
#!/usr/bin/env bats
# Files whose work happens before any matching file is touched (planning), through
# MCP (never fires paths:), or in a subagent must Read their path-scoped rules
# explicitly. This pins the list so a later edit cannot drop one silently.

setup() { cd "$BATS_TEST_DIRNAME/../../.." || exit 1; }

AUDIT=(
  "agents/tester.md:testing"
  "agents/unity-test-builder.md:testing"
  "agents/unity-ui-toolkit-builder.md:ui-toolkit-runtime"
  "agents/unity-ui-builder.md:ui-toolkit-runtime unity-prefabs performance"
  "agents/unity-setup.md:scene-hierarchy unity-prefabs ui-toolkit-runtime"
  "agents/unity-scene-builder.md:scene-hierarchy unity-prefabs"
  "agents/reviewer.md:logging save-load serialization event-patterns unity-async performance"
  "agents/unity-reviewer.md:logging save-load serialization event-patterns unity-async performance"
  "agents/migrator.md:unity-input unity-async event-patterns"
  "agents/unity-optimizer.md:performance"
  "commands/architect.md:ui-toolkit-runtime roadmap-milestones save-load testing"
  "commands/plan-module.md:roadmap-milestones"
  "commands/roadmap.md:roadmap-milestones"
  "commands/game-idea.md:roadmap-milestones"
  "commands/refine-gdd.md:roadmap-milestones"
  "commands/refine-tdd.md:roadmap-milestones"
  "commands/orchestrate.md:roadmap-milestones testing"
  "commands/implement.md:testing"
  "commands/fix.md:testing"
  "commands/migrate.md:testing"
  "commands/setup-project.md:save-load logging"
  "commands/scene-setup.md:scene-hierarchy unity-prefabs"
  "commands/update-scene-hierarchy.md:scene-hierarchy unity-prefabs"
  "commands/unity-scene-update.md:scene-hierarchy unity-prefabs"
  "commands/create-prefab-scene.md:scene-hierarchy unity-prefabs"
)

@test "every audited file carries a Rules-to-Read-first block naming its rules" {
    fail=0
    for entry in "${AUDIT[@]}"; do
        file=".claude/${entry%%:*}"
        block=$(grep -A2 'Rules to Read first' "$file" || true)
        [ -n "$block" ] || { echo "$file: no Rules-to-Read-first block"; fail=1; continue; }
        for rule in ${entry#*:}; do
            [[ "$block" == *".claude/rules/${rule}.md"* ]] || { echo "$file: missing $rule"; fail=1; }
        done
    done
    [ "$fail" -eq 0 ]
}

@test "every rule named in the audit exists" {
    for entry in "${AUDIT[@]}"; do
        for rule in ${entry#*:}; do
            [ -f ".claude/rules/${rule}.md" ] || { echo "no rule $rule"; false; }
        done
    done
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats .claude/hooks/tests/rule-read-audit.bats`
Expected: first test FAILS listing all 25 files.

- [ ] **Step 3: Add the block to each file** with the Edit tool, placed directly after the frontmatter (or the H1 when there is none), using the exact two-line form above.

- [ ] **Step 4: Run tests**

Run: `bats .claude/hooks/tests/rule-read-audit.bats`
Expected: all PASS.

- [ ] **Step 5: Commit** (only when the developer says so)

```bash
git add .claude/agents .claude/commands .claude/hooks/tests/rule-read-audit.bats
git commit -m "feat(agents): read path-scoped rules explicitly where paths: cannot fire"
```

---

### Task 9: `architecture.md` dedup

**Files:**
- Modify: `.claude/rules/architecture.md` (only the reference prose below the Cards)

Replace each section's **body** with a pointer; keep the heading so anchors still resolve:

| Section in `architecture.md` | Replace body with |
|---|---|
| `### Code-First Static Module Pattern (NON-NEGOTIABLE)` | `Full pattern and code: \`rules/bootstrap-pattern.md\` → Cards 1–2 and "[Module]Module — Static Class". Summary: a module is one static class with \`Install(IContainerBuilder, Config)\`, added as one line in \`AppModules.Install()\`; \`EventBusModule\` is first.` |
| `### AppScope — Uses AppModules (NON-NEGOTIABLE)` | `Full code: \`rules/bootstrap-pattern.md\` → "AppScope". \`AppScope.cs\` never changes; it validates \`ConfigCatalog\` then calls \`AppModules.Install\`.` |
| `### EntryPoint — Lifecycle Yes, Frame Ticks No` | `Full rationale and code: \`rules/solid-oop.md\` → "EntryPoint — Lifecycle Yes, Frame Ticks No". \`IInitializable\`/\`IStartable\`/\`IAsyncStartable\`/\`IDisposable\` are used; \`ITickable\`/\`IFixedTickable\` are not — a service exposes \`Tick(float)\` and its domain's Mono shell forwards \`Update\`.` |
| `### GameScope — Scene Component Registration Only` | `Full rules: \`rules/bootstrap-pattern.md\` → Card 4 and "GameScope — Scene-Based Wiring". GameScope only calls \`RegisterComponent\` for scene MonoBehaviours; scene-lifetime pure C# services go through \`SceneModules\`.` |
| `## Provider Pattern` | `See Card 2 above. Do NOT open a Provider for prefab-local Unity access — that is Handler's job.` |
| `## No Singletons` | `See Card 1 above. App-wide → \`AppScope\` via \`AppModules\`; per-scene → \`MenuScope\`/\`GameScope\`.` |

Under `## IEvent System for Communication`, delete only the C# code block (the `LevelStartedEvent` / `CoinsChangedEvent` / Publish / Subscribe sample) and replace it with `Event struct shape, naming and the full decision tree: \`rules/event-patterns.md\` (loads on any \`.cs\`).` Keep the `### Subscribe / Unsubscribe Rules` table and notes — they are not duplicated elsewhere.

**Must stay untouched** (referenced from other files): Cards 1–7, `Scripts/ Folder Rules`, `Adding a Top-Level Folder`, `Domain Folder Convention`, `ARCHITECTURE.md — one per Concretes domain`, `NO GameContext / Service Locator`, `Avoid One-Caller Overfitting`, `Handler Factory — VContainer Func<> Pattern`, `EventBusAccessor`.

- [ ] **Step 1: Record the referenced headings**

Run: `grep -c '' .claude/rules/architecture.md; wc -c .claude/rules/architecture.md; grep -nE '^#{2,3} ' .claude/rules/architecture.md > "${TMPDIR:-/tmp}/arch-headings.before"`

- [ ] **Step 2: Apply the replacements** with the Edit tool, one section at a time.

- [ ] **Step 3: Verify headings and size**

Run:
```bash
grep -nE '^#{2,3} ' .claude/rules/architecture.md | cut -d: -f2- > "${TMPDIR:-/tmp}/arch-headings.after"
cut -d: -f2- "${TMPDIR:-/tmp}/arch-headings.before" | diff - "${TMPDIR:-/tmp}/arch-headings.after" && echo HEADINGS-UNCHANGED
wc -c .claude/rules/architecture.md
sed -n 28p .claude/rules/architecture.md
```
Expected: `HEADINGS-UNCHANGED`; ≤ 36000 chars; line 28 still inside Card 1 (cited by `reviewer-fixtures/README.md`).

- [ ] **Step 4: Run the full hook suite**

Run: `bats .claude/hooks/tests/`
Expected: all PASS.

- [ ] **Step 5: Commit** (only when the developer says so)

```bash
git add .claude/rules/architecture.md
git commit -m "docs(rules): replace duplicated reference prose in architecture.md with pointers"
```

---

### Task 10: Verify end to end

- [ ] **Step 1: Startup budget (developer)**

Ask the developer to open a fresh interactive session and report: is the size warning gone? `/context` Memory files total? Expected: no warning; launch-loaded instruction files < 150k chars; the 18 scoped rules absent.

- [ ] **Step 2: Each scoped rule loads on its trigger**

The template has no `.uxml`, prefab, `tools/` or `Ecs/` files, so create one throwaway trigger per glob family, probe, then delete them all:

| Trigger file | Rules it must load |
|---|---|
| `verify-probe/Probe.cs` | the 8 C# layer rules |
| `verify-probe/Tests/ProbeTests.cs` | `testing` |
| `verify-probe/UI/Probe.uxml` | `ui-toolkit-runtime` |
| `tools/probe/probe.js` | `web-tool-*` ×3 |
| `verify-probe/Probe.prefab` | `unity-prefabs`, `scene-hierarchy` |
| `verify-probe/Ecs/Probe.cs` | `ecs-dots` |
| `verify-probe/AddressableAssetsData/Probe.asset` | `addressables` |
| `docs/ROADMAP.md` (exists) | `roadmap-milestones` |

For each row run (example for the UI row):
`claude -p "Read verify-probe/UI/Probe.uxml. Then, without reading any other file, quote the heading of Card 1 of each rule file now in your instructions whose name contains ui-toolkit, or say NOT LOADED." --permission-mode plan`
Record loaded / not loaded per rule in `docs/superpowers/specs/2026-10-08-instruction-loading-spike.md` under a "Post-change verification" heading. Any NOT LOADED is a defect in that rule's glob — fix it and re-run. Delete `verify-probe/` and `tools/probe/` afterwards.

- [ ] **Step 3: Net 1 after compaction (developer)**

In an interactive session: `/compact`, then ask "Which file do you Read before choosing UGUI vs UI Toolkit?" Expected: `.claude/rules/ui-toolkit-runtime.md`.

- [ ] **Step 4: Net 2 at plan time**

Run: `claude -p "Ayarlar ekranı yapalım, ses açık/kapalı kaydedilsin. Sadece planla, dosya yazma." --permission-mode plan`
Expected: the answer shows it read `save-load.md` and `ui-toolkit-runtime.md` (cites a Card from each).

- [ ] **Step 5: Behavioural comparison**

Run: `.claude/tests/rule-awareness-probe/run-probe.sh 3`
Record a row with layout `scoped + 3 nets`. Expected: every prompt's mean ≥ its baseline mean. A lower mean on any prompt is a regression: report it to the developer with both rows before anything else.

- [ ] **Step 6: Full suites**

Run: `bats .claude/hooks/tests/` and `.claude/graph/test/verify-graphify.sh`
Expected: bats all PASS; graph `57 PASS, 1 KNOWN_FAIL, 0 FAIL` (unchanged — nothing under `.claude/graph/` was touched).

- [ ] **Step 7: Mark the spec implemented and commit** (only when the developer says so)

Set the spec's `**Status:**` to `Implemented — verified 2026-10-xx` and commit:
```bash
git add docs/superpowers/specs/2026-10-08-instruction-loading-design.md docs/superpowers/specs/2026-10-08-instruction-loading-spike.md .claude/tests/rule-awareness-probe/README.md
git commit -m "docs: record instruction-loading verification results"
```
