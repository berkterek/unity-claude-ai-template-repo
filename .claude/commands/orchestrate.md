# Orchestrate — Automated WORKFLOW.md Executor

You are an orchestration agent. Your job is to read `docs/WORKFLOW.md` and execute every task automatically, one phase at a time. Each task runs a three-step pipeline: **coder → reviewer → committer**. After each phase you pause and ask the developer before moving on.

## Step 0 — Plugin Preflight & Argument Parsing

**Parse $ARGUMENTS first:**
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

---

## Step 0b — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder/unity-coder → committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

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
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [coder | unity-coder] (per task)
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after the standard reviewer step passes for each task, spawn a **unity-developer** subagent review pass before the committer.

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: WORKFLOW.md plan name, total phases and tasks, complexity score.
Wait for `go` before reading WORKFLOW.md or spawning any agents.

After receiving `go` → run:
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"SCOPE_GATE","pipeline":"orchestrate","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

Note: per-task COMMIT_GATE is intentionally omitted — orchestration is designed to run tasks hands-free. The Phase Gate ("Proceed? yes / no / stop") at the end of each phase serves as the human checkpoint before the next phase begins.

---

## Initialization

1. Verify `docs/WORKFLOW.md` exists. If not, stop: "WORKFLOW.md not found. Run `/plan-workflow` first."
2. Read `docs/WORKFLOW.md` completely.
3. Read `.claude/CLAUDE.md` for project constraints.
4. Read `docs/PROGRESS.md` if it exists — resume from where work left off.
5. **Codebase Pre-Scan** — before spawning any agents, read the knowledge graph (or fall back to file scan):

   Check `.claude/project-features.json`:
   - If `.graph == true`: Read `.claude/graph/graph.json`. If missing, run `/build-knowledge-graph --full --skip-mcp` first.
   - If `.graph != true`: run the original `find`-based scan (fallback below) and skip the jq queries.

   **Graph path (preferred):**
   - Existing `_Framework/`: `jq '.codebase.assemblies[] | select(.file | startswith("Assets/_Framework")) | {name, file}' .claude/graph/graph.json`
   - Existing Abstracts: `jq '.codebase.interfaces[] | select(.file | contains("/Games/Abstracts/")) | {name, file}' .claude/graph/graph.json`
   - Existing Concretes: `jq '.codebase.classes[] | select(.file | contains("/Games/Concretes/")) | {name, file, confidence}' .claude/graph/graph.json`
   - Cross-reference each WORKFLOW.md task output against the graph. If a file's class exists in the graph AND is registered in an installer, mark the task as a candidate to skip.

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
   Conflicts with WORKFLOW.md: [list files that already exist and need review, or "none"]
   Architecture issues found: [list any rule violations in existing files, or "none"]
   Graph confidence: [EXTRACTED | mostly_INFERRED | N/A (file-scan mode)]
   ```
   - If a WORKFLOW.md output file already exists and is correctly implemented, mark that task as a candidate to skip and ask the developer: "Task [X] output already exists and looks correct — skip or re-implement?"
6. Append to `docs/EVENTS.jsonl` (create if missing):
   ```jsonl
   {"event":"ORCHESTRATION_STARTED","plan":"[game name]","phases":[N],"tasks":[M],"timestamp":"[ISO8601]"}
   ```
7. Announce:
   ```
   ## Orchestration Starting
   Plan: [game name]
   Total phases: X | Total tasks: Y
   Resuming from: [Phase N, Task P or "beginning"]
   ```

---

## Execution Loop

Repeat for each phase (skip completed phases from PROGRESS.md):

### Phase Start

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"PHASE_STARTED","phase":[N],"name":"[Phase Name]","tasks":[count],"timestamp":"[ISO8601]"}
```

Print:
```
---
## Phase [N]: [Phase Name]
Goal: [phase goal from WORKFLOW.md]
Entry Criteria: [entry criteria]
Tasks: [count]
---
```

---

### Task Execution

Before executing tasks in a phase, check for `parallel_group` annotations in WORKFLOW.md:

**If no tasks have `parallel_group`:** Execute all tasks sequentially (existing behavior).

**If tasks have `parallel_group` AND complexity score ≥ 0.4:**
1. Group tasks by their `parallel_group` number. Tasks without a group number are sequential.
2. **Conflict check:** For each group, read each task's `outputs` field. If two tasks in the same group list the same output file → demote the later task to sequential and warn:
   ```
   ⚠ PARALLEL CONFLICT: [T1] and [T2] both write to [file]
   [T2] demoted to sequential. Running [T1] first.
   ```
3. Execute tasks in the same group simultaneously. Each spawns its own full pipeline (tester → coder → verifier → reviewer).
4. Wait for all tasks in the group to complete before starting the next group or sequential task.
5. If any task in a group fails → stop the entire group. Report all failures. Do not proceed until user resolves.
6. Commit all group outputs in a single commit after the group completes.

**If complexity score < 0.4:** Ignore `parallel_group` — run all tasks sequentially.

---

#### Sequential Task Execution (for each task without parallel_group, in order)

**Announce the task:**
```
### [P{phase}.T{task}] [Task Title]
Type: [type] | Agent: [agent type] | Complexity: [S/M/L/XL] | Group: [parallel_group or "sequential"]
Inputs: [list]
Outputs: [list]
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_STARTED","phase":[N],"task":[P],"id":"P{phase}.T{task}","title":"[task title]","agent":"[agent type]","timestamp":"[ISO8601]"}
```

Each task runs four steps in sequence (TDD: tests first, then implementation). A failure at any step stops the pipeline.

---

#### Step 1 — Test Writer (skip if `Agent: unity-setup`)

If `Agent: unity-setup` → skip this step, go directly to Step 2.

Spawn Agent with `subagent_type: "claude"` (`model: sonnet` — isolated tester is worker-tier) with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Task
ID: [P{phase}.T{task}]
Title: [task title]
Description: [full task description from WORKFLOW.md]

## Acceptance Criteria (tests must cover these)
[list every criterion from WORKFLOW.md]

## Your job
1. Write failing unit tests BEFORE any implementation exists.
2. Tests must FAIL right now — no implementation exists yet.
3. Do NOT commit anything.

When done: list every test file created with a summary of what each covers.
Report: DONE or BLOCKED with reason.
```

If **BLOCKED** → stop immediately. Print:
```
⚠ BLOCKED at [P{phase}.T{task}] Step 1 (Test Writer): [reason]
Fix this before continuing. Run /orchestrate to resume.
```
Update PROGRESS.md with blocked status.
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","phase":[N],"task":[P],"id":"P{phase}.T{task}","step":"tester","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 2 — Coder (or Unity Setup)

If `Agent: unity-setup` → spawn a **unity-setup** subagent.

**Coder agent — use routing table from Step 0:**
- Pure C# target (`_Framework/`, `Games/Abstracts/`, `Games/Concretes/` no Unity API) → **coder**
- Unity/Mixed target (MonoBehaviour, Provider, Installer, scene wiring) → **unity-coder**

**Model tier override:**
- If `FORCE_OPUS_TIER == true` → all spawned implementation agents (`coder`, `unity-coder`, `unity-setup`) use `model: opus` for this run
- Else → use default tier routing

**Coder prompt:**
```
You are a senior C# Unity developer implementing a specific task. Tests have already been written — your job is to make them pass.

## Task
ID: [P{phase}.T{task}]
Title: [task title]
Description: [full task description from WORKFLOW.md]

## Existing Tests (make these pass)
[tester output — list of test files and what they cover]

## Input Files (read these first)
[list every input file path]

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from WORKFLOW.md]

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
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

**Unity Setup prompt:**
```
You are a Unity scene architect setting up a specific task.

## Task
ID: [P{phase}.T{task}]
Title: [task title]
Description: [full task description from WORKFLOW.md]

## Input Files (read these first)
[list every input file path]

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from WORKFLOW.md]

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
⚠ BLOCKED at [P{phase}.T{task}] Step 1 (Coder): [reason]
Fix this before continuing. Run /orchestrate to resume.
```
Update PROGRESS.md with blocked status.
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","phase":[N],"task":[P],"id":"P{phase}.T{task}","step":"coder","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 3 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

**Reviewer prompt:**
```
Review the following Unity C# implementation.

## Task
ID: [P{phase}.T{task}]
Title: [task title]

## Files Changed
[coder output — list of files with summaries]

## Acceptance Criteria (must all pass)
[list every criterion from WORKFLOW.md]

## Review Criteria
1. Tests pass — all pre-written tests pass; no test files were modified
2. Acceptance criteria — does the implementation satisfy all of them?
3. Architecture — VContainer DI, no singletons, interfaces only across modules
4. Naming — PascalCase types, _camelCase private fields
5. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
6. Events — IEvent structs past-tense + Event suffix, published via IEventBus
7. UniTask — no async void outside lifecycle, CancellationToken on every async method
8. Unity null safety — no ?. or is null on UnityEngine objects
9. Serialization — FormerlySerializedAs on any renamed [SerializeField]
10. **Architecture drift (BLOCKING)** — implementation must match the TDD: no new singletons, no `ServiceLocator`, no `FindObjectOfType`, no new folders under `_GameFolders/Scripts/` that aren't in the TDD, and no new event structs when an existing `IEvent` covers the case. If the diff introduces any of these without a paired ADR entry, the review must return **CHANGES NEEDED** with reason "Architecture drift: `<specific drift>` — open an ADR or revert."

## Output Format
APPROVED — all criteria pass.

CHANGES NEEDED:
- [file:line] Issue and required fix.
(list every issue)
```

On **CHANGES NEEDED** → automatically enter the review loop (no user prompt needed):

**Review Loop** (max 3 passes):

1. Spawn a **coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Task Context
   ID: [P{phase}.T{task}] — [task title]

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. Re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3 (Committer).

4. If still **CHANGES NEEDED** after 3 passes → stop. Print remaining issues and ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted, update PROGRESS.md as blocked

---

#### Step 3.5 — Bounded Verification

Spawn a **unity-verifier** subagent:

```
You are a Unity verification agent. Run a final bounded check on completed work.

## Task
ID: [P{phase}.T{task}]
Title: [task title]

## Files Changed
[list from coder output]

## Acceptance Criteria
[from WORKFLOW.md]

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

### Step B — Test Run (only if Step A passes with zero errors)
5. Call MCP `run_tests` and report results.
6. If tests fail → attempt fixes, re-run (max 2 attempts).

### Step C — Unity-Specific Issues (only if Steps A and B pass)
7. **Play Mode entry (BLOCKING).** Use MCP `manage_editor` to enter Play Mode. Wait up to 10 s for `editor_state.isPlaying == true`. If Play Mode never engages → report ISSUES FOUND with reason "PlayMode failed to start".
8. **Console error pattern scan (BLOCKING).** While in Play Mode for at least 2 frames, then exit Play Mode and call `read_console`. Search the full console output for ANY of:
   - `VContainerException` — DI binding missing
   - `NullReferenceException` originating from `_GameFolders/` or `_Framework/`
   - `MissingReferenceException`
   - `MissingComponentException`
   - Any log line at level `Error` containing `Installer`, `Resolve`, or `Bind`
9. If ANY of the patterns above appear:
   - Attempt to fix (max 2 attempts), re-enter Play Mode, re-scan.
   - If still present → Report: ISSUES FOUND with the full matching log lines.
   - Do NOT report VERIFIED while any pattern persists.
10. Quick scan for the remaining Unity-specific issues (missing SerializeField, event leaks, leftover Debug.Log spam). These are WARNING-level — list them but do not block.

If you find and fix issues, list them. If cannot fix, report blockers.
Report: VERIFIED or ISSUES FOUND with details.
```

**CRITICAL:** If the verifier reports compile or assembly errors and cannot fix them → the pipeline **MUST STOP**. Do NOT spawn the committer. Print:
```
⛔ BLOCKED at [P{phase}.T{task}] Step 3.5 (Verification): Assembly/compile errors found.
[paste error list]
Fix these errors before this task can be committed.
Run /orchestrate to resume after fixing.
```
Update PROGRESS.md with blocked status. Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","phase":[N],"task":[P],"id":"P{phase}.T{task}","step":"verifier","reason":"compile errors","timestamp":"[ISO8601]"}
```
Exit.

If **VERIFIED** → append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"VERIFICATION_PASSED","phase":[N],"task":[P],"id":"P{phase}.T{task}","title":"[task title]","timestamp":"[ISO8601]"}
```
Then proceed to Step 4 Committer.

If **ISSUES FOUND** and fixed → append VERIFICATION_PASSED event and proceed to Step 4 Committer.

If **cannot fix** → stop. Print blockers and surface to developer before committing. Update PROGRESS.md with blocked status.

---

#### Step 4 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Task completed: `[P{phase}.T{task}]` — `[task title]`
- Files changed: `[coder/unity-setup output — list of files]`
- Run: `git status`, `git diff` to confirm what changed
- Stage only files related to this task
- Commit message format: `"feat: [P{phase}.T{task}] [task title]"`
- Do NOT push — user pushes manually
- Report: commit hash and message

---

#### After Each Task

Update `docs/PROGRESS.md`:
```markdown
- [x] P{phase}.T{task} — [title] — [commit hash] — Reviewer: [Codex|Claude]
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_COMPLETED","phase":[N],"task":[P],"id":"P{phase}.T{task}","title":"[task title]","commit":"[hash]","reviewer":"[Codex|Claude]","timestamp":"[ISO8601]"}
```

---

### Phase Gate

After all tasks in a phase complete, run the automated QA sequence before asking the developer:

#### Step 1 — Ralph (compile + test green)

Spawn a **unity-verifier** subagent with this prompt:

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
6. If compile is clean → call MCP `run_tests` and report results.

Report: GREEN (compile clean, tests pass) or ERRORS (list all failures).
```

If failures found → spawn **unity-fixer** to fix, re-verify (max 3 passes). If still failing after 3 passes → **stop and report to user. Do not proceed to Step 2 until green.**

Print: `✓ Ralph passed — compile and tests green.` or `⛔ Ralph failed after 3 passes — [issues]. Fix before proceeding.`

#### Step 2 — Silent Failure Hunt

Spawn a **unity-linter** subagent with this prompt:

```
Audit all files changed in this phase for silent failure patterns:
- catch blocks that swallow exceptions without logging
- async void outside Unity lifecycle methods
- IEventBus subscriptions without matching Unsubscribe
- UniTask.Forget() without an error handler
- empty catch blocks

Files to audit: [list of output files from this phase's tasks]

Report each finding as: [file:line] — [pattern] — [fix]
If none found: CLEAN
```

Print findings or `✓ Silent failure hunt — CLEAN.`

#### Step 3 — Validate

Spawn a **general-purpose** subagent (`model: sonnet`) with the validate prompt:

```
You are a strict QA gate. Validate phase [N] of this orchestration.

WORKFLOW.md phase [N] tasks and acceptance criteria: [paste from WORKFLOW.md]
PROGRESS.md reported status: [paste phase section]

Checks:
1. All output files exist at specified paths
2. Files are not empty or placeholder
3. Every acceptance criterion is met (read the code to verify)

Output:
PASS — all criteria met.
FAIL:
- [task] [criterion] — [what's missing]
```

If **FAIL** → print failures, ask user: `Validation failed. Fix issues and type "retry" to re-run QA, or "skip" to proceed anyway.`
- `retry` → restart from Step 1
- `skip` → proceed with warning logged

If **PASS** → proceed to developer prompt.

**If `superpowers:verification-before-completion` is available:** Invoke it now before reporting Phase complete. Verify all acceptance criteria from WORKFLOW.md phase [N] are genuinely met.

#### Step 4 — Developer Prompt

Print:
```
## Phase [N] QA Complete ✓
Ralph: green | Silent failures: [CLEAN / N findings] | Validate: PASS

Ready to start Phase [N+1]: [name]
Goal: [goal]
Tasks: [count]

Proceed? (yes / no / stop)
```

**Wait for the developer's response.**
- `yes` → append to `docs/EVENTS.jsonl`:
  ```jsonl
  {"event":"PHASE_COMPLETED","phase":[N],"name":"[Phase Name]","tasks_done":[count],"timestamp":"[ISO8601]"}
  ```
  Then continue to next phase.
- `no` or `stop` → exit gracefully, remind them to run `/continue` to resume.

---

## Progress Tracking

`docs/PROGRESS.md` format:

```markdown
# Execution Progress
**Plan:** [game name]
**Started:** [date]
**Last updated:** [date]

## Phase 1: Infrastructure Foundation — COMPLETE
- [x] P1.T1 — IEventBus + EventBus — abc1234 — Reviewer: Codex
- [x] P1.T2 — ModuleInstaller base — def5678 — Reviewer: Claude

## Phase 2: Core Game Logic — IN PROGRESS
- [x] P2.T1 — EnemyService — 9ab1234 — Reviewer: Codex
- [ ] P2.T2 — ScoreService — pending
- [ ] P2.T3 — PlayerService — pending

## Phase 3: Unit Tests — PENDING
```

On startup, read this file and skip already-completed tasks.

---

## Rules

- **Never skip acceptance criteria.** Re-read WORKFLOW.md criteria if a result is ambiguous.
- **Never continue past a BLOCKED task.** Fix it first.
- **Phase gates are mandatory.** Always pause and ask between phases.
- **One pipeline per task.** Never batch multiple tasks into one subagent call.
- **Subagents get no session history.** Write every prompt as if they know nothing about this conversation.
- **Reviewer tries Codex first.** Fall back to unity-reviewer if Codex is unavailable.

---

## On Completion

Run: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"`

```
## Orchestration Complete
All [N] phases, [M] tasks executed.

Summary:
- Phase 1: [N] tasks ✓
- Phase 2: [N] tasks ✓
...

Next step: Run /validate to verify the full build, then /review-code on key systems.
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"ORCHESTRATION_COMPLETE","phases":[N],"tasks":[M],"timestamp":"[ISO8601]"}
```

$ARGUMENTS
