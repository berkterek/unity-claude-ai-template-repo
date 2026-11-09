# Orchestrate — Module Task Executor

> **Rules to Read first** (path-scoped — not in context until a matching file is touched):
> `.claude/rules/roadmap-milestones.md`, `.claude/rules/testing.md`

Reads a module's `tasks.md` and runs every task automatically.
Usage: `/orchestrate docs/modules/01-core-loop/tasks.md`

---

## Step 0 — Argument Parsing & Plugin Preflight

**Parse $ARGUMENTS first:**
- `$ARGUMENTS` → the tasks.md path (required). Stop if it is missing:
  ```
  A tasks.md path is required. Usage: /orchestrate docs/modules/01-core-loop/tasks.md
  ```
- Check $ARGUMENTS for `--heavy` flag → if present, set `FORCE_OPUS_TIER=true`
- Print: `Mode: heavy (all implementation agents → opus tier)` if flag found, else nothing extra.

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:verification-before-completion` | Phase Gate — verify all acceptance criteria before proceeding | Skip verification gate |

Print availability status before proceeding:
```
Plugins: superpowers:verification-before-completion [✓/✗]
```

**Then run `.claude/skills/core/mcp-preflight.md` — MANDATORY, and pin the instance
before any agent is spawned.**

This is the longest MCP-driving pipeline in the project and it was the only one that never
ran the preflight. State 1.5 of that skill is the reason: with more than one Unity Editor
open, the bridge picks a default that may be **another project**, and every write and
`execute_code` then succeeds silently against it. Measured in a downstream `/orchestrate`
run — MCP was pointed at an unrelated project for part of the session; the visible symptom
was `run_tests` returning `tests_running` twice, whose obvious diagnosis ("a stuck job",
fixed with `clear_stuck`) would have been the wrong move on the right-looking evidence, and
two assembly measurements taken meanwhile had to be thrown away as invalid.

Pin it once, here, and repeat the pinned instance in every MCP agent's prompt — a subagent
does not inherit the Director's pin. Do not delegate this to the agents: by the time an
agent notices, it has already written somewhere.

---

## Step 0b — Read tasks.md & Complexity Scoring & SCOPE_GATE

**Step 0b.1 — Read tasks.md**

1. Read the tasks.md file given in `$ARGUMENTS`. If the file does not exist, stop:
   ```
   tasks.md not found: [path]
   Create the module plan first.
   ```
2. Parse the state from the checkboxes:
   - `- [x]` → COMPLETE (skip)
   - `- [ ]` → PENDING (run it)
3. Already-completed tasks are marked with an `[x]` checkbox — they are skipped.

**Step 0b.2 — Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder/unity-coder → committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

**Step 0b.3 — Complexity Scoring**

Before executing any task, score the overall workflow complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Pure C# target → **coder** / Unity target → **unity-coder** + unity-developer review after each task |

**Agent routing per task — decide before spawning:**

| Target location | Simple | Medium/Complex |
|-----------------|--------|----------------|
| `_Framework/`, `Games/Abstracts/`, `Games/Concretes/` pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring | **unity-coder** | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** | **unity-coder** |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputService, or a [Domain]Module? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [coder | unity-coder] (per task)
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after the standard reviewer step passes for each task, spawn a **unity-developer** subagent review pass before the committer.

**Step 0b.4 — Codebase Pre-Scan**

Before spawning any agents, read the knowledge graph (or fall back to file scan):

Check `.claude/project-features.json`:
- If `.graph == true`: Read `.claude/graph/graph.json`. If missing, run `/build-knowledge-graph --full --skip-mcp` first.
- If `.graph != true`: run the original `find`-based scan (fallback below) and skip the jq queries.

**Graph path (preferred):**
- Existing `_Framework/`: `jq '.codebase.assemblies[] | select(.file | startswith("Assets/_Framework")) | {name, file}' .claude/graph/graph.json`
- Existing Abstracts: `jq '.codebase.interfaces[] | select(.file | contains("/Games/Abstracts/")) | {name, file}' .claude/graph/graph.json`
- Existing Concretes: `jq '.codebase.classes[] | select(.file | contains("/Games/Concretes/")) | {name, file, confidence}' .claude/graph/graph.json`
- Cross-reference each tasks.md task output against the graph. If a file's class exists in the graph AND is registered in an installer, mark the task as a candidate to skip.

**Fallback (no graph):**
- Run `find _Framework -type f -name "*.cs" -o -name "*.asmdef" 2>/dev/null | sort`
- Run `find _GameFolders/Scripts/Games/Abstracts -type f -name "*.cs" 2>/dev/null | sort`
- Run `find _GameFolders/Scripts/Games/Concretes -type f -name "*.cs" 2>/dev/null | sort`
- If a file already exists, read it and note whether it follows architecture rules (VContainer, UniTask, naming, #region).

Print a **Pre-Scan Report**:
```
## Pre-Scan Report
_Framework: [list of subfolders/assemblies found, or "empty"]
Existing Abstracts: [list of interfaces, or "none"]
Existing Concretes: [list of classes, or "none"]
Conflicts with tasks.md: [list files that already exist and need review, or "none"]
Architecture issues found: [list any rule violations in existing files, or "none"]
Graph confidence: [EXTRACTED | mostly_INFERRED | N/A (file-scan mode)]
```

If a tasks.md output file already exists and is correctly implemented, mark that task as a candidate to skip and ask the developer: "Task [X] output already exists and looks correct — skip or re-implement?"

**Step 0b.4b — Plan Path Validation (BLOCKING — never skip)**

The Pre-Scan above looks at what **already exists**. This step looks at what the plan is about to **create** — the folder tree in `design.md`/`tasks.md` — and validates it against `rules/architecture.md` before a single agent spawns.

Run, on the module's plan directory:

```bash
.claude/scripts/validate-plan-paths.sh <plan-dir-or-files>
.claude/scripts/validate-plan-facts.sh <plan-dir-or-files>
.claude/scripts/validate-plan-executors.sh <plan-dir-or-files>
```

Then paste the tool's full output into the SCOPE_GATE block. `validate-plan-executors.sh` exit 2 on an
already-approved plan is **not** a stop: it lists the `[MAIN-SESSION]` / checkpoint tasks you will route per
Main-session budget below (agent by path; checkpoint → Phase Gate). Name that routing in the SCOPE_GATE block. Rules for reading it:

- **exit 2** → the plan contradicts `rules/architecture.md`. Do NOT proceed silently and do NOT "fix" it by inventing a folder. Present the conflict at SCOPE_GATE with the three options: (a) change the plan, (b) declare a real exception in `.claude/path-allowlist.txt` + `rules/architecture.md`, (c) stop. **The human picks.**
- **`NO PATHS FOUND`** → this is **not** a pass. Verify by hand that the plan really declares no script paths.
- **exit 0 with N paths checked** → this is the only green.

`validate-plan-facts.sh` reads the same way:

- **exit 2** → at least one task creating a new `.cs` file is missing `Callers:`/`Wiring:`, or a declared caller/module doesn't resolve on disk or in the plan. Do NOT proceed silently — present the violation at SCOPE_GATE, fix the plan or stop. **The human picks.**
- **`NO TASKS FOUND`** → this is **not** a pass — the script's own words are "this is NOT a pass". Verify by hand that the plan really declares no script paths.
- **exit 0 with N tasks checked** → this is the only green.

A hook exiting 0 is never evidence a rule was checked — only the printed `checked:` line is. Do not write "verified compliant" into any spec/AC on the basis of a hook staying silent.

**Step 0b.5 — SCOPE_GATE**

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.

```
## SCOPE_GATE — Module Orchestration

Plan: [tasks.md file path]
Module: [from the tasks.md title]
Milestone: [this module's milestone from ROADMAP.md] — open milestone is [Mn], [k] module(s) still Pending
Total tasks: [count]
Pending: [count] (completed [count] will be skipped)
Complexity: [score] — [Label]
Review Mode: [solo|lean|full]

SPARC — Specification: [one sentence from spec.md: what this module builds]
SPARC — Architecture: [new files per folder, e.g. "Concretes/Boards: 6 new, 2 edited"; the interfaces design.md adds]

Type `go` to approve scope and SPARC for the whole run:
```

Wait for `go` before spawning any agents. This one `go` is also the SPARC_GATE approval for every task in this run — the spec and architecture were already approved at `/plan-module` (ARCHITECTURE_GATE + plan review), so asking again per task re-asks a settled question.

> **Why SPARC moved here:** measured on a downstream project (Nov 2026): SPARC_GATE was shown 20 times across 4 `/orchestrate` runs — per task, and again whenever the 45-minute approval expired — costing ~26 minutes of waiting plus an interruption each time, for content the plan had already approved twice.

Read the `Milestone` line's values from `docs/ROADMAP.md`. This command does **not** enforce
the milestone constraint — it displays it, because this gate is the only enforcement point
`rules/roadmap-milestones.md` has. If the module's milestone is not the open one, say so in
one sentence above the block rather than leaving the human to compare two identifiers.

After receiving `go` → run (both files — the second is the SPARC approval):
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"SCOPE_GATE","pipeline":"orchestrate","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared" && touch "$(git rev-parse --show-toplevel)/.claude/state/sparc-approved"
```

**Approval expiry — renew in one line, never re-show the blocks.** Both files expire 45 minutes after `go` (`UNITY_GATE_TTL`; it is not an input — never extend it and never re-stamp a file without a fresh `go`). A long run outlives that. When a guard hook blocks with "expired", or before starting a task more than 40 minutes after the last approval, print exactly:
```
⏸ Approval expired (45 min). Next: [task id] [title] — [n] task(s) left. Type `go` to continue.
```
On `go`, re-run the command above, which re-stamps both files. Anything else from the user → treat it as a redirect.

Note: per-task COMMIT_GATE is intentionally omitted — orchestration is designed to run tasks hands-free. The Phase Gate (Checkpoint) at the end of each checkpoint serves as the human checkpoint before the next section begins.

---

## Step 1 — Initialization

Append to `docs/EVENTS.jsonl` (create if missing):
```jsonl
{"event":"ORCHESTRATION_STARTED","plan":"[tasks.md path]","tasks":[N],"timestamp":"[ISO8601]"}
```

Announce:
```
## Orchestration Starting
Plan: [tasks.md path]
Module: [from the tasks.md title]
Toplam task: [N]
Bekleyen task: [M]
Resuming from: [ilk pending task veya "beginning"]
```

---

## Execution Loop

### Main-session budget (NON-NEGOTIABLE)

You are the Director: you spawn, read one-line verdicts, and show gates. Each of your turns re-reads your whole
context, so a turn here costs what a whole coder spawn costs. Per task, your turns are: announce → spawn
(tester/coder) → codex-review → spawn verifier → commit → `task-done.sh`. Nothing else.

- **No verification here.** Never call `run_tests` / `get_test_job` yourself while the gate is open — Step 3.5 and
  the Phase Gate spawn `unity-verifier` (`guard-main-unity-tests.sh` blocks it). No "baseline" runs, no
  compile-check-after-every-coder: the verifier owns compile + tests.
- **No code reading here.** No `grep` / `sed -n` / `cat` / `Read` on source files to check an agent's work or to
  find a symbol. `code-map.md` rows go into prompts as text; the agents open the files. Need a fact the map lacks →
  spawn `unity-scout` (haiku) and paste its answer.
- **Scene / prefab / SO / asset work** goes to `unity-setup`, never your own MCP calls. A legacy plan task tagged
  `[MAIN-SESSION]` is run by the agent its path calls for (`.asmdef` is the only exception — only the Director may
  write one, `check-config-protection.sh`); a legacy "checkpoint: compile + tests, record counts" task is closed by
  the Phase Gate's Ralph result, not run separately.
- **Bookkeeping is one call:** `.claude/scripts/task-done.sh <tasks.md> <id[,id…]> <hash|none> <Codex|Claude>` ticks
  the checkbox and appends `VERIFICATION_PASSED` + `TASK_COMPLETED`. Never Edit tasks.md checkboxes or append
  EVENTS lines by hand.

> **Why:** measured on a downstream project (Nov 2026, 17 runs): main session = 66% of `/orchestrate` cost, 214
> turns per run at ~440k context. Per run: 84 Unity MCP calls (13 of them `get_test_job` polling), 33
> `grep`/`sed`/`cat`, 15 EVENTS appends, 15 tasks.md checkbox Edits, 9 state-marker writes — while
> `unity-verifier` was spawned once in the project's whole history and coders averaged 4 turns. The coders were
> cheap; the Director doing their verifier's job was not.

Repeat for each pending task in tasks.md (skip tasks with `- [x]` checkbox):

### Task Execution

Before executing tasks, check for `parallel_group` annotations in tasks.md:

**If no tasks have `parallel_group`:** Execute all tasks sequentially (existing behavior).

**If tasks have `parallel_group` AND complexity score ≥ 0.4:**
1. Group tasks by their `parallel_group` number. Tasks without a group number are sequential.
2. **Conflict check:** For each group, read each task's `outputs` field. If two tasks in the same group list the same output file → demote the later task to sequential and warn:
   ```
   ⚠ PARALLEL CONFLICT: [T1] and [T2] both write to [file]
   [T2] demoted to sequential. Running [T1] first.
   ```
3. Execute tasks in the same group simultaneously. Each task runs its own Step 1 (tester) and Step 2 (coder / unity-setup).
4. Wait for every task's Step 2 to finish, then run **one** Step 3 reviewer for the whole group: "Files Changed" is the union of every task's files, and "Acceptance Criteria" lists each task's criteria under its task ID — the output contract still requires one line per criterion of every task, plus the 12 review criteria once. On CHANGES NEEDED, the Review Loop spawns one coder per task that has a finding, then re-reviews the group (delta: only the previous findings and the files those coders touched). Then **one** Step 3.5 verifier for the group. **Size cap:** if the union holds more than 8 files, do not group the review — run Step 3 once per task instead (the verifier stays one per group). A large diff dilutes one reviewer's attention; the cap keeps the speed win on the many small groups and pays per-task cost only on the few large ones.
5. If any task in a group fails → stop the entire group. Report all failures. Do not proceed until user resolves.
6. Commit all group outputs in a single commit after the group completes.

> **Why one review per group:** measured on a downstream project (Nov 2026): 47 Codex reviewer spawns across 4 `/orchestrate` runs, one per task even inside a parallel group whose tasks were single asmdef edits or a 5-line record; one module's reviews alone took 1h09m. The group commits as one unit, so it is reviewed as one unit.

**If complexity score < 0.4:** Ignore `parallel_group` — run all tasks sequentially.

---

#### Sequential Task Execution (for each task, in order)

**Announce the task** — one line (see Rules → keep what you print short):
```
### [Task ID] [Task Title] — [agent type], group [parallel_group or "seq"]
```

No EVENTS line here — `task-done.sh` records the task when it closes.

Each task runs four steps in sequence (TDD: tests first, then implementation). A failure at any step stops the pipeline.

**Code map rows.** If `code-map.md` sits next to tasks.md, take this task's rows once — the `Read at:` line, the
header and separator rows, and every row whose `Task(s)` cell names this task ID:
```bash
grep -E '^(Read at:|\| *(Task|-|([^|]*[ ,])?<task id>[ ,|]))' <plan dir>/code-map.md
```
(no `\b`: BSD grep on macOS ignores it and returns the header alone). Then list which of those rows' files changed
since the map was read — `git diff --name-only <Read at sha> HEAD -- <the rows' files>` — and append
`Changed since map: <files>` (or `none`): for those files the line hint is stale, the symbol still holds. Keep the
result as `$CODE_MAP_ROWS` for the Step 1, 2 and 3 prompts below. No map, or no row for this task → write
`No code map rows for this task.` A parallel group's reviewer gets the rows of every task in the group.

> **Why:** measured on a downstream project (Nov 2026, modules 10-12): the source files a task depends on were
> found again by every agent that touched it — tester, coder, reviewer — through `grep` and `sed -n` (~800 `grep`
> calls in two days), although the planner had already located them. The rows hand the location on.

---

#### Step 1 — Test Writer (skip if `Agent: unity-setup` or `Test type: NoTest`)

Skip this step and go directly to Step 2 when either holds:
- `Agent: unity-setup`
- the task carries a `Test type: NoTest` line (`Test Type:` in `/create-plan` output — match case-insensitively). Valid only for a type that `.claude/rules/testing.md`'s Test Type Decision Tree or `/create-plan`'s Test Type Decision Matrix sends to NoTest, or for a non-code task (docs, assets, scene setup). A `NoTest` on any other `.cs` task is a plan defect: run this step anyway and say so in one line.

On a NoTest skip, append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TESTER_SKIPPED","id":"[task id]","reason":"NoTest","timestamp":"[ISO8601]"}
```

> **Why `NoTest` is read here:** before this line existed, only `unity-setup` skipped the tester. A plan with a legitimately untested task (an Editor-only tool, a config asset) had no way to say so — the tester was spawned with "write failing tests", and either invented tests the plan had ruled out or reported BLOCKED, which stops the run. Plans worked around it with hand-edited tester prompts, and plan reviewers rejected the workaround: a review → fix cycle per module, measured on a downstream project in Oct 2026.

Spawn Agent with `subagent_type: "claude"` (`model: sonnet` — isolated tester is worker-tier) with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Acceptance Criteria (tests must cover these)
[list every criterion from tasks.md]

## Code Map (where the code this task depends on lives)
$CODE_MAP_ROWS
Open these with a ranged Read (the line range is a hint; the symbol is the reference). Search the tree only for
something these rows do not name.

## Your job
1. Write failing unit tests BEFORE any implementation exists.
2. Tests must FAIL right now — no implementation exists yet.
3. Do NOT commit anything.

When done: list every test file created with a summary of what each covers.
Report: DONE or BLOCKED with reason.
```

If **BLOCKED** → stop immediately. Print:
```
⚠ BLOCKED at [task id] Step 1 (Test Writer): [reason]
Fix this before continuing. Run /orchestrate [tasks.md path] to resume.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"tester","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 2 — Coder (or Unity Setup)

**SPARC_GATE — already approved at SCOPE_GATE (Step 0b.5).** Do not show a per-task SPARC block. If `.claude/state/sparc-approved` has expired, use the one-line renewal from Step 0b.5. **Do not delete it when the coder returns — delete it at Completion, with `gate-cleared`.**

> Deleting it here deadlocks the first fix pass, and does so deterministically: every later step that spawns a `coder` / `unity-coder` again — the validator fix pass, the reviewer fix pass, the Ralph loop — hits `guard-sparc-approved.sh` exit **2** while the file is absent, and none of them re-opens the gate, so the pipeline blocks itself on an approval the human already gave. This bites hardest here, because `/orchestrate` runs many tasks per approval. The approval does not need the deletion to be bounded: `guard-sparc-approved.sh` calls `unity_gate_cleared_valid "sparc-approved"`, so the same 45-minute `UNITY_GATE_TTL` as `gate-cleared` applies, plus `session-restore.sh`'s SessionStart clear. Same shape as the compaction-revokes-`gate-cleared` bug: the file had a bound already, and a second, eager teardown was the defect.

`guard-sparc-approved.sh` exits **2** for any `coder` / `unity-coder` spawn while `.claude/state/sparc-approved` is absent. It gates **only** those two agent types — a `unity-setup` spawn passes untouched, so a setup-only task needs no SPARC_GATE. The file is independent of `gate-cleared`: opening one does not open the other.

If `Agent: unity-setup` → spawn a **unity-setup** subagent.

**Coder agent — use routing table from Step 0b.3:**
- Pure C# target (`_Framework/`, `Games/Abstracts/`, `Games/Concretes/` no Unity API) → **coder**
- Unity/Mixed target (MonoBehaviour, Provider, Installer, scene wiring) → **unity-coder**

**Model tier override:**
- If `FORCE_OPUS_TIER == true` → all spawned implementation agents (`coder`, `unity-coder`, `unity-setup`) use `model: opus` for this run
- Else → use default tier routing

**Coder prompt:**
```
You are a senior C# Unity developer implementing a specific task. Tests have already been written — your job is to make them pass.

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Existing Tests (make these pass)
[tester output — list of test files and what they cover]

## Input Files (read these first)
[list every input file path]

## Code Map (where the code this task depends on lives)
$CODE_MAP_ROWS
Open these with a ranged Read (the line range is a hint; the symbol is the reference). Search the tree only for
something these rows do not name, and list each such search under "Extra reads" in your report.

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from tasks.md]

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
- Before using an unfamiliar Unity API, check `docs/engine-reference/unity/deprecated-apis.md` — the reviewer applies gate `TD-UNITY-RISK` and will return CHANGES NEEDED on a deprecated call
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- Do NOT modify the test files — only write implementation code
- #region tags required in _GameFolders/Scripts/
- **Architecture Drift (BLOCKING).** Before introducing any new pattern, scan for an existing one:
  - New service / manager → check `_Framework/` and `Games/Abstracts/` for an interface to implement; if one exists, use it instead of inventing a parallel system.
  - New event → check existing `IEvent` structs under `_GameFolders/Scripts/Games/Concretes/Events/`; reuse before creating.
  - New folder under `_GameFolders/Scripts/` → forbidden unless the TDD explicitly lists it. Stop and report BLOCKED with reason "ADR required: new folder `<path>` not in TDD".
  - New singleton, ServiceLocator, static manager, or `Object.FindObjectOfType` call → forbidden. VContainer only.
  - If the task description requires a pattern that contradicts the TDD → stop and report BLOCKED with reason "ADR required: `<conflict>`. Pause for human decision before proceeding."

## When Done
List every file you created or modified with a one-line summary.
Confirm all tests now pass.
Do NOT commit anything.
Report: DONE or BLOCKED with reason.
```

For a task Step 1 skipped as `NoTest`: drop "Tests have already been written — your job is to make them pass." and the `## Existing Tests` section, add `No tests for this task (Test type: NoTest) — do not write any.`, and replace `Confirm all tests now pass.` with `Confirm the project compiles.`

**Unity Setup prompt:**
```
You are a Unity scene architect setting up a specific task.

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Input Files (read these first)
[list every input file path]

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from tasks.md]

## Rules
- Use Unity MCP tools for all scene/prefab work — do NOT read or edit .unity or .prefab files as raw text
- Check editor state first: mcpforunity://editor/state → wait until ready_for_tools == true
- Attach MonoBehaviours via MCP manage_components
- Register new components in the scene LifetimeScope installer

## Prefab Rules (NON-NEGOTIABLE — apply to every GameObject you create)
- Every GameObject placed in a scene must be a prefab instance
  — Exception: empty hierarchy organizers with no components (e.g. [Systems], [UI], [Gameplay])
- Save all prefabs under _GameFolders/Prefabs/<Domain>/  (Enemies/, Player/, UI/, VFX/, Environment/…)
- Root GameObject: logic components only (Provider, Controller, Collider, Rigidbody, injected MonoBehaviours)
- Body child GameObject: visual components only (MeshRenderer, SkinnedMeshRenderer, Animator, VFX)
- Never put Renderer components on the root; never put logic scripts on Body
- When multiple objects share the same base structure → create a base prefab first, then Prefab Variants
- Never duplicate a prefab manually — always use Prefab Variants

## Material Rules (NON-NEGOTIABLE)
- All material assets (.mat) must be saved under `Arts/Materials/<Domain>/` — NEVER inside `Prefabs/` folders
- Domain subfolder mirrors prefab domain: Items/, Environment/, Characters/, VFX/, UI/
- Every material must use a URP shader: `Universal Render Pipeline/Lit` or `Universal Render Pipeline/Simple Lit`
- Standard (Built-in) shader is FORBIDDEN — objects will render magenta in URP
- If you find a material using Standard shader → report as BLOCKED, do not proceed

## Canvas Prefab Rules (NON-NEGOTIABLE)
Before creating any Canvas prefab, check _GameFolders/Prefabs/UI/Canvases/ for an existing BaseCanvas.prefab:
- If BaseCanvas.prefab does NOT exist yet → create it first with: Canvas + CanvasScaler (Scale With Screen Size, 1080×1920, match 0.5) + GraphicRaycaster. Save to _GameFolders/Prefabs/UI/Canvases/BaseCanvas.prefab
- Every subsequent Canvas prefab (CanvasHUD, CanvasJoystick, CanvasOverlay, CanvasPopup, etc.) MUST be a Prefab Variant of BaseCanvas — NEVER a standalone prefab
- Variants override ONLY: Canvas.sortingOrder, Canvas.renderMode (if needed), and their own children
- If you find existing standalone Canvas prefabs that are NOT variants of BaseCanvas → stop and report this as a BLOCKED issue. Do not silently proceed

## Base Prefab Pattern — General (NON-NEGOTIABLE)
Before creating 2 or more prefabs of the same domain that share the same component set, check if a base prefab exists:
- If creating multiple Enemy prefabs → check for BaseEnemy.prefab first
- If creating multiple Obstacle prefabs → check for BaseObstacle.prefab first
- Same rule applies to any domain with 2+ structurally similar prefabs
- Signal: "these two prefabs would have the same components on root and Body child" → use Base + Variant

## When Done
List every scene/prefab/asset you created or modified.
Do NOT commit anything.
Report: DONE or BLOCKED with reason.
```

If **BLOCKED** → stop immediately. Print:
```
⚠ BLOCKED at [task id] Step 2 (Coder): [reason]
Fix this before continuing. Run /orchestrate [tasks.md path] to resume.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"coder","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 3 — Reviewer

For a task inside a `parallel_group`, this step runs once for the whole group, after every task's Step 2 — see Task Execution item 4. A sequential task is reviewed alone.

Reviewer priority — try in order, fall back if unavailable:
1. Codex, run from this session — no subagent: write the reviewer prompt below to a file in the session scratchpad and run `.claude/scripts/codex-review.sh <that file>` with Bash (`timeout: 600000`). Exit 0 → its stdout is the verdict. Exit 1 or 3 → step 2. Never spawn `codex:codex-rescue` for a review: it loads every rule (~70k tokens) only to forward this same call.
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

**Reviewer prompt:**
```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review the following Unity C# implementation.

## Task
ID: [task id]
Title: [task title]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The orchestration ledger is NOT part of any task and
must never be reported as a scope violation: `.claude/**`, `docs/**`, `*.json`,
`*.jsonl`, `*.md` (unless a `.md` is itself listed under "Files Changed").

## Files Changed
[coder output — list of files with summaries]

## Code Map (existing code the change depends on — for checking contracts)
$CODE_MAP_ROWS
Use these locations with a ranged Read before searching the tree. The map lists what the change depends on,
**not who calls it**: the caller count in criterion 12 still needs a search of the whole tree — never answer it
from the map.

## Acceptance Criteria (must all pass)
[list every criterion from tasks.md]

## Review Criteria
1. Tests pass — all pre-written tests pass; no test files were modified. For a `Test type: NoTest` task there are no tests by design: do not flag their absence; flag only a test file the coder added
2. Acceptance criteria — does the implementation satisfy all of them?
3. Architecture (gate `TD-ARCHITECTURE`) — VContainer DI, no singletons, interfaces only across modules
4. Naming — PascalCase types, _camelCase private fields
5. Performance (gate `TD-PERFORMANCE`) — no allocations in Update/FixedUpdate, no LINQ on hot paths
6. Events — IEvent structs past-tense + Event suffix, published via IEventBus
7. UniTask — no async void outside lifecycle, CancellationToken on every async method
8. Unity null safety — no ?. or is null on UnityEngine objects
9. Serialization — FormerlySerializedAs on any renamed [SerializeField]
10. **Architecture drift (BLOCKING)** — implementation must match the TDD: no new singletons, no `ServiceLocator`, no `FindObjectOfType`, no new folders under `_GameFolders/Scripts/` that aren't in the TDD, and no new event structs when an existing `IEvent` covers the case. If the diff introduces any of these without a paired ADR entry, the review must return **CHANGES NEEDED** with reason "Architecture drift: `<specific drift>` — open an ADR or revert."
11. Unity engine risk (gate `TD-UNITY-RISK`) — no API listed in `docs/engine-reference/unity/deprecated-apis.md` is used; the change does not fall in an area listed in `breaking-changes.md`; where `current-best-practices.md` names a better alternative, it was used or the deviation is stated
12. Scope discipline (gate `CD-SCOPE`) — **count the callers of every type, method and field this change introduces.** **Zero callers anywhere is a violation** — name it, including an interface nobody implements or consumes, a private method nothing invokes, and a field nothing reads. **Exactly one production caller is not a violation** — the test suite is the second caller (`rules/architecture.md` → one-caller rule); do not read this exception as "never flag an abstraction". Also: no file was changed that the task did not require, and no unrelated code was refactored. This overlaps item 10 on "no new folders not in the TDD"; item 10 is stricter (BLOCKING, needs a paired ADR) and stays — do not delete either as redundant

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for EVERY acceptance criterion AND every one of the 12 review
criteria above. No item may be omitted, merged, or answered "n/a" without a stated
reason. Format:

  <ID> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

**`GAP` requires a violation you can point at.** If you looked and the criterion is met, the verdict is `CONFIRMED` — write it and move on. A `GAP` whose own evidence sentence says no violation is present ("no `?.` misuse found", "namespace format itself is fine") is **invalid**, and so is a `GAP` for something that merely *could* have been done differently. Measured 2026-08-21 on a planted-defect fixture: 4 of 10 criteria came back `GAP` with evidence that contradicted the verdict — the per-item line requirement pressures invention. Filling every line is mandatory; finding a fault on every line is not.

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Presence of a symbol is not evidence
that its contract is correct.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** Measured on the
> piggy-doku module 03 T007a-d fixture (3 passes, 2026-08-18). With the old prompt
> Codex made 1 tool call, addressed 3 of 12 criteria, returned a reasonless APPROVED,
> and reported the orchestration ledger (`graph.json`, `EVENTS.jsonl`, `tasks.md` —
> the dirty worktree a bare `git diff` sweeps in) as a scope violation. A seeded
> known defect (a required field's contract doc removed) was **missed**. With the
> scope lock + per-item output contract above, the same agent on the same seeded
> fixture caught the defect (`GAP` with the exact line), produced 0 false positives,
> and answered all 14 items with `file:line`. The failure was the prompt's shape, not
> the Codex CLI.

On **CHANGES NEEDED** → automatically enter the review loop (no user prompt needed):

**Review Loop** (max 3 passes):

1. Spawn a **coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Task Context
   ID: [task id] — [task title]

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Code Map (where the code this task depends on lives)
   $CODE_MAP_ROWS

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. Re-run the reviewer using the same priority order (`codex-review.sh` → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3.5 (Verifier).

4. If still **CHANGES NEEDED** after 3 passes → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`)
   with `$WHAT_WAS_RETRIED` = the reviewer loop, `$N` = 3, `$PASS_TYPE` = reviewer, and every
   remaining finding listed. Fill `Skipping ships:` from the reviewer's own findings — it
   already named the rule each one violates. `skip` proceeds to commit.

---

#### Step 3.5 — Bounded Verification

Spawn a **unity-verifier** subagent (`model: sonnet`). **Never run these checks yourself** — not "just a quick
compile", not "the tests are small" (see Main-session budget). Your only input from this step is its verdict line:

```
You are a Unity verification agent. Run a final bounded check on completed work.

## Task
ID: [task id]
Title: [task title]

## Files Changed
[list from coder output]

## Acceptance Criteria
[from tasks.md]

## Your Task (max 3 internal iterations)

### Step A — Compile & Assembly Check (BLOCKING — do not proceed past this if errors exist)
1. Call MCP `refresh_assets` to trigger a Unity recompile.
2. Call MCP `get_logs` (or equivalent) and read ALL console output.
3. Search for ANY of these patterns in the log output:
   - "error CS" — C# compiler errors
   - "Assembly" followed by "error" or "failed"
   - "has compiler errors" or "Scripts have compiler errors"
   - "is not allowed to reference" — assembly reference violation
   - Any line starting with "Error:" in the compiler output
4. If ANY compile or assembly error is found:
   - List every error with file path and line number
   - Attempt to fix the errors (max 2 fix attempts)
   - After each fix, call `refresh_assets` again and re-read logs
   - If errors persist after 2 fix attempts → Report: ISSUES FOUND (cannot fix) with full error list
   - Do NOT proceed to test run if compile errors remain
5. **A clean console is not proof the DLL is current — probe it before running tests.** On a failed
   compile Unity keeps the last good assembly loaded (measured: `358/358` green with four call sites
   broken). Ask both directions:
   - `unity_reflect(action: "search", query: "[Director fills: a type this task DELETED, or none]", scope: "all")`
   - `unity_reflect(action: "search", query: "[Director fills: a type this task ADDED, or none]", scope: "all")`
   Probe only the types named here — never a type an earlier task added: it resolved at that task's
   verify and says nothing about this build.
   A deleted type still resolving, or an added type not resolving → Report: STALE ASSEMBLY and stop —
   do not fix, there may be no code defect. If nothing was added or deleted, say the probe was not
   applicable. Your report must name the probe result: `probe: current` / `probe: n/a` / `STALE ASSEMBLY`.

### Step B — Test Run (only if Step A passes with zero errors)
6. Call MCP `run_tests` and report results.
7. If tests fail → attempt fixes, re-run (max 2 attempts).

### Step C — Unity-Specific Issues (only if Steps A and B pass)
8. **Play Mode entry (BLOCKING).** Use MCP `manage_editor` to enter Play Mode. Wait up to 10 s for `editor_state.isPlaying == true`. If Play Mode never engages → report ISSUES FOUND with reason "PlayMode failed to start".
9. **Console error pattern scan (BLOCKING).** While in Play Mode for at least 2 frames, then exit Play Mode and call `read_console`. Search the full console output for ANY of:
   - `VContainerException` — DI binding missing
   - `NullReferenceException` originating from `_GameFolders/` or `_Framework/`
   - `MissingReferenceException`
   - `MissingComponentException`
   - Any log line at level `Error` containing `Installer`, `Resolve`, or `Bind`
10. If ANY of the patterns above appear:
   - Attempt to fix (max 2 attempts), re-enter Play Mode, re-scan.
   - If still present → Report: ISSUES FOUND with the full matching log lines.
   - Do NOT report VERIFIED while any pattern persists.
11. Quick scan for the remaining Unity-specific issues (missing SerializeField, event leaks, leftover Debug.Log spam). These are WARNING-level — list them but do not block.

If you find and fix issues, list them. If cannot fix, report blockers.
Report: VERIFIED (with the probe line from step 5), STALE ASSEMBLY, or ISSUES FOUND with details.
```

**STALE ASSEMBLY** → stop exactly as for compile errors below, but say the Editor is serving an old DLL — do not
spawn a fixer for it.

**CRITICAL:** If the verifier reports compile or assembly errors and cannot fix them → the pipeline **MUST STOP**. Do NOT spawn the committer. Print:
```
⛔ BLOCKED at [task id] Step 3.5 (Verification): Assembly/compile errors found.
[paste error list]
Fix these errors before this task can be committed.
Run /orchestrate [tasks.md path] to resume after fixing.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"verifier","reason":"compile errors","timestamp":"[ISO8601]"}
```
Exit.

If **VERIFIED**, or **ISSUES FOUND** and fixed → proceed to Step 4 Committer (`task-done.sh` writes the
`VERIFICATION_PASSED` line after the commit).

If **cannot fix** → stop. Print blockers and surface to developer before committing.

---

#### Step 4 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Task completed: `[task id]` — `[task title]`
- Files changed: `[coder/unity-setup output — list of files]`
- Run: `git status --short <the task's files>` to confirm what changed — never a full `git diff` here: the
  reviewer already read the diff, and its output would stay in your context for the rest of the run
- Stage only files related to this task
- Commit message format: `"feat: [task id] [task title]"`
- Do NOT push — user pushes manually
- Report: commit hash and message

---

#### After Each Task

One Bash call — ticks the checkbox and appends `VERIFICATION_PASSED` + `TASK_COMPLETED` (a parallel group passes
all its ids at once):
```bash
.claude/scripts/task-done.sh <tasks.md path> <task id[,task id…]> <commit hash|none> <Codex|Claude> <clean|fixed> ["what the verifier fixed"]
```
`clean` = the verifier said VERIFIED and changed nothing; `fixed` = ISSUES FOUND and fixed — put what it fixed in the
quoted note, copied from its report (a few words, e.g. `asmdef ref missing (CS0234)`). The script writes one
`VERIFIER_RESULT` line per call: that line is the only record of what the per-task verifier catches, so never omit
it when a verifier ran. Exit 1 = an id has no checkbox line or the result is not `clean`/`fixed` — fix the argument,
do not Edit tasks.md by hand.

---

### Phase Gate (Checkpoint)

Lines starting with `**Checkpoint:**` in tasks.md are phase gate points.

On reaching each Checkpoint:

1. Run the automated QA sequence below before asking the developer.

#### Step 1 — Ralph (compile + test green)

**Skip check — first.** Skip Ralph when both hold, and print `✓ Ralph skipped — tree unchanged since [task id]
VERIFIED (probe: current).`:
- the checkpoint's last task (or last group) got `VERIFIED` from Step 3.5 with `probe: current`, and
- no code-writing agent (coder, unity-coder, unity-setup, fixer) ran after that verdict.

Step 3.5 compiled the whole project, probed the assembly and ran the full suite on this exact tree, so Ralph
would repeat it byte for byte (measured downstream: `unity-verifier` 51 `run_tests` across 42 spawns). Anything
else — a later fix, a skipped or `ISSUES FOUND` verifier, `probe: n/a` or no `probe:` line — runs Ralph in full:
an edit-only last task has nothing to probe, and Ralph's probe covers every type the whole phase added or deleted.

Otherwise spawn a **unity-verifier** subagent with this prompt:

```
Run a full compile and test check for the end of a phase.

1. Call MCP `refresh_assets` to trigger Unity recompile.
2. Call MCP `get_logs` and read ALL console output.
3. Search for ANY compile or assembly error:
   - "error CS" — C# compiler errors
   - "Assembly" with "error" or "failed"
   - "has compiler errors" / "Scripts have compiler errors"
   - "is not allowed to reference" — assembly violation
4. If ANY compile/assembly error found → list all errors. Attempt fixes (max 2). Re-check after each fix.
5. If errors persist → Report: COMPILE ERRORS with full list. Do NOT run tests.
6. **A clean console is not proof the DLL is current — probe it before running tests.** On a
   failed compile Unity keeps the last good assembly loaded, and a green suite then describes
   code that predates this phase (measured: `358/358` green with four call sites broken).
   Name a type this phase changed and ask both directions:
   - `unity_reflect(action: "search", query: "<a type this phase DELETED>", scope: "all")`
   - `unity_reflect(action: "search", query: "<a type this phase ADDED>", scope: "all")`

   A deleted type still resolving, or an added type not resolving → Report: STALE ASSEMBLY
   and stop. Do not run the tests and do not spawn a fixer: there may be no code defect, and
   a fix pass spent here edits correct code. If nothing was added or deleted, say the probe
   was not applicable.
7. If the assembly is current → call MCP `run_tests` and report results.
8. **Play check — only when the checkpoint text asks for one.** Read `docs/play-check.md` first: it is the
   recipe (how to reach the play state from the Bootstrap scene, which objects/entities to inspect, ready-made
   `execute_code` snippets). Follow it; do not rediscover the entry path with `grep` / `FindObjectsByType` probes.
   No recipe → spend at most 15 tool calls finding the path, then stop and report
   `PLAY CHECK PARTIAL — <what was not verified>`. Never repeat a `sleep` + state probe more than 3 times. Before
   you finish, write or extend `docs/play-check.md` with what you learned (entry steps, snippets that worked,
   dead ends), so the next checkpoint starts from it.

Report: GREEN (compile clean, assembly current, tests pass), GREEN (ASSEMBLY UNPROBED) — compile
clean and tests pass, but nothing was added or deleted, so assembly freshness is NOT established —
STALE ASSEMBLY, or ERRORS (list all failures). Never report the plain GREEN when the probe did not
run: the whole point of the probe is that a clean console and a green suite are both true about the
*previous* build.
```

If failures found → spawn **unity-fixer** to fix, re-verify (max 2 passes — compile/test-fix bound, see `.claude/docs/director-gates.md` → Retry and Pass Limits; this also matches the "Attempt fixes (max 2)" instruction inside the verifier prompt above, which the old outer bound of 3 contradicted). If still failing after 2 passes → **stop and report to user. Do not proceed to Step 2 until green.**

Print: `✓ Ralph passed — compile and tests green.` or `⛔ Ralph failed after 2 passes — [issues]. Fix before proceeding.`
A `PLAY CHECK PARTIAL` line from the verifier is not a failure: copy it verbatim into the Step 4 developer prompt
after the Ralph field, so the developer sees what was left unchecked.

> **Why item 8:** measured on nile module 31 (Nov 2026): the two longest `unity-verifier` spawns (110 and 66 tool
> calls, 10 and 5 min) were checkpoint Play checks — 63 and 32 `execute_code` probes plus `sleep` loops, each one
> rediscovering how to reach the battle scene from Bootstrap. Together they were 35% of the verifier's turns.

#### Step 2 — Silent Failure Hunt

Run `bash .claude/scripts/silent-failure-extract.sh [output .cs files of this checkpoint's tasks]`.
**Empty output → print `✓ Silent failure hunt — CLEAN.` and do not spawn the linter.** Otherwise
spawn a **unity-linter** subagent with the excerpt pasted in — it judges the excerpt and opens a
file only when the excerpt cannot decide a finding:

```
Audit these excerpts for silent failure patterns:
- catch blocks that swallow exceptions without logging
- empty catch blocks
- async void outside Unity lifecycle methods
- IEventBus subscriptions without matching Unsubscribe (the excerpt lists both when counts differ)
- UniTask.Forget() without an error handler

[script output]

Read a file only when its excerpt cannot decide a finding (e.g. the Unsubscribe lives in a base class).
Report each finding as: [file:line] — [pattern] — [fix]
If none found: CLEAN
```

Print findings or `✓ Silent failure hunt — CLEAN.`

#### Step 3 — Validate

Spawn a **general-purpose** subagent (`model: sonnet`) with the validate prompt:

```
You are a strict QA gate. Validate the tasks completed up to this checkpoint.

tasks.md checkpoint tasks and acceptance criteria: [paste from tasks.md]

Checks:
1. All output files exist at specified paths
2. Files are not empty or placeholder
3. Every acceptance criterion is met (read the code to verify)

Output:
PASS — all criteria met.
FAIL:
- [task] [criterion] — [what's missing]
```

If **FAIL** → print failures, then show **QUALITY_GATE** (`.claude/docs/director-gates.md`)
with the failures as the CHANGES NEEDED items, **substituting `retry` for `fix`**: what failed
here is a whole validation stage, not a file a coder can be pointed at, so the retry re-runs
the stage instead of spawning a coder. Omit the optional `list` line — the failures are
already printed in full above.
- `retry` → restart from Step 1
- `skip` → proceed with warning logged
- `stop` → abort

If **PASS** → proceed to developer prompt.

**If `superpowers:verification-before-completion` is available:** Invoke it now before reporting Checkpoint complete. Verify all acceptance criteria from tasks.md up to this checkpoint are genuinely met.

#### Step 4 — Developer Prompt

Print:
```
## Checkpoint: [checkpoint metni]
Ralph: [green (probe: current / ASSEMBLY UNPROBED) / skipped — tree unchanged since [task id] VERIFIED (probe: current)] | Silent failures: [CLEAN / N findings] | Validate: PASS

Remaining tasks to continue with: [list]

Önerilen: `stop` → /clear → /orchestrate [tasks.md path] — checked tasks are skipped; a fresh session does not re-read this section's history every turn.
Devam? (yes / no / stop)
```

The recommendation line is printed at every checkpoint, not only when the context looks large. A fresh session pays its startup context once (~120k tokens written to cache, about the price of 10 turns that each re-read 150k of accumulated history); the next section runs dozens of turns, and on nile (Nov 2026) 53% of main-session cost was exactly this re-read history.

**Wait for the developer's response.**
- `yes` → append to `docs/EVENTS.jsonl`:
  ```jsonl
  {"event":"CHECKPOINT_COMPLETED","checkpoint":"[checkpoint metni]","timestamp":"[ISO8601]"}
  ```
  Then continue to next tasks.
- `no` or `stop` → append to `docs/EVENTS.jsonl`:
  ```jsonl
  {"event":"ORCHESTRATION_PAUSED","checkpoint":"[checkpoint metni]","timestamp":"[ISO8601]"}
  ```
  Exit gracefully. Remind them to run `/orchestrate [tasks.md path]` to resume.

---

## Rules

- **Never skip acceptance criteria.** Re-read tasks.md criteria if a result is ambiguous.
- **Never continue past a BLOCKED task.** Fix it first.
- **Checkpoints are mandatory.** Always pause and ask at every `**Checkpoint:**` line.
- **One pipeline per task.** Never batch multiple tasks into one subagent call.
- **Subagents get no session history.** Write every prompt as if they know nothing about this conversation.
- **Reviewer tries Codex first.** Fall back to unity-reviewer if Codex is unavailable.
- **Keep what you print to the user short.** Per task, two lines plus an optional third: the announce line (`### [id] [title] — [agent], group [n]`), then one result line (`✓ [id] committed [hash] — [n] files, review: [verdict]` or `⛔ [id] BLOCKED — [reason]`), then — only when the task **created** files, tests and fakes included — one line `new: [file names, no paths]`. Edited files stay out of chat. The `new:` line is the one detail kept on purpose: in the same downstream logs the only design objection the user raised mid-run (a hand-written `FakeBoardState` where NSubstitute would do) came from reading the Director's progress text, not from any gate. Other files, inputs/outputs, review criteria and agent reports go to `docs/EVENTS.jsonl` and the commit, not to the chat. Print full detail only where the user must decide: a gate, a BLOCKED task, an EXHAUSTION_GATE, a Checkpoint. Measured on a downstream project (Nov 2026): the Director wrote ~678k characters of chat text against ~13k characters of C# — every line of it is generation time and reading time.

---

## On Completion

Run: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared" "$(git rev-parse --show-toplevel)/.claude/state/sparc-approved"`

Both, and only here — `sparc-approved` is held open for the whole run (SPARC_GATE) precisely so the fix passes can re-spawn a coder.

Update the module's status — **both places, tasks.md first**:
1. In the module's own `tasks.md`, set the header line: `> Status: ✅ Complete`
2. In `docs/ROADMAP.md`, find the module's row and set its Status: `→ ✅ Complete`

Both are **mirrors of the checkboxes in `tasks.md`**, which are what a status is derived
from at rest. Update them in that order and never the reverse. A ROADMAP-only update is
silently reverted by the next `/roadmap` run, because `/roadmap` reads the module's own
header; and a header that disagrees with its own checkboxes is the stale side. (Measured in
a downstream project: a `tasks.md` header read `⏳ Pending` while all 41 of its checkboxes
were ticked, and the stale header carried a wrong status into the table for weeks.)

> **That measurement was re-run and it is a class, not one file.** In the same project,
> 10 of 19 module plans disagreed with their own checkboxes — three headers read
> `⏳ Pending` against a fully-ticked list, six others had no `> Status:` line at all. The
> ROADMAP table nonetheless looked correct, because exactly one row had been hand-fixed
> earlier; the single repair is what hid the other nine. Writing both places here stops
> the class from growing, and does nothing about the files authored before it did — those
> need a one-time backfill from their checkboxes (`/status` reports them, see below).
> Generalizes past status: a derived field is stale for every artifact created before the
> writer that derives it, and a spot-check that lands on the one repaired row reads as
> "the table is fine".

```
## Orchestration Complete

tasks.md: [path]
Completed tasks: [N]
Skipped (already complete): [M]

Next step: update ROADMAP.md with /roadmap
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"ORCHESTRATION_COMPLETE","plan":"[tasks.md path]","tasks":[N],"skipped":[M],"timestamp":"[ISO8601]"}
```

$ARGUMENTS
