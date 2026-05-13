# Orchestrate — Automated WORKFLOW.md Executor

You are an orchestration agent. Your job is to read `docs/WORKFLOW.md` and execute every task automatically, one phase at a time. Each task runs a three-step pipeline: **coder → reviewer → committer**. After each phase you pause and ask the developer before moving on.

## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | Reviewer ve unity-developer yok — coder/unity-coder → committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before executing any task, score the overall workflow complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Pure C# target → **coder** / Unity target → **unity-coder-lite** |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Pure C# target → **coder** / Unity target → **unity-coder** + unity-developer review after each task |

**Agent routing per task — decide before spawning:**

| Target location | Simple | Medium/Complex |
|-----------------|--------|----------------|
| `_Framework/`, `Abstracts/`, pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring | **unity-coder-lite** | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder-lite** | **unity-coder** |

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
Coder Agent: [coder | unity-coder-lite | unity-coder] (per task)
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after the standard unity-reviewer step passes for each task, spawn a **unity-developer** subagent review pass before the committer.

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: WORKFLOW.md plan name, total phases and tasks, complexity score.
Wait for `go` before reading WORKFLOW.md or spawning any agents.

After receiving `go` → run:
```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"orchestrate","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
```

Note: per-task COMMIT_GATE is intentionally omitted — orchestration is designed to run tasks hands-free. The Phase Gate ("Proceed? yes / no / stop") at the end of each phase serves as the human checkpoint before the next phase begins.

---

## Initialization

1. Verify `docs/WORKFLOW.md` exists. If not, stop: "WORKFLOW.md not found. Run `/plan-workflow` first."
2. Read `docs/WORKFLOW.md` completely.
3. Read `.claude/CLAUDE.md` for project constraints.
4. Read `docs/PROGRESS.md` if it exists — resume from where work left off.
5. Append to `docs/EVENTS.jsonl` (create if missing):
   ```jsonl
   {"event":"ORCHESTRATION_STARTED","plan":"[game name]","phases":[N],"tasks":[M],"timestamp":"[ISO8601]"}
   ```
6. Announce:
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

Spawn a **tester** subagent with this prompt:

```
You are a senior C# Unity test engineer. Write failing unit tests BEFORE any implementation exists.

## Task
ID: [P{phase}.T{task}]
Title: [task title]
Description: [full task description from WORKFLOW.md]

## Acceptance Criteria (tests must cover these)
[list every criterion from WORKFLOW.md]

## Project Rules
- Read .claude/CLAUDE.md and .claude/rules/testing.md before writing any tests
- Use NSubstitute for mocking — only mock interfaces, never concrete classes
- Follow AAA pattern (Arrange / Act / Assert) — one assertion per test
- Test method naming: MethodName_WhenCondition_ExpectedBehavior
- Test class naming: [ClassName]Tests
- Tests must FAIL right now — no implementation exists yet

## When Done
List every test file you created with a summary of what each test covers.
Do NOT commit anything.
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
- Pure C# target (`_Framework/`, `Abstracts/`, no Unity API) → **coder**
- Unity/Mixed target (MonoBehaviour, Provider, Installer, scene wiring) → **unity-coder-lite** (Simple) or **unity-coder** (Medium/Complex)

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
1. Spawn Agent with `subagent_type: "unity-reviewer"`
2. Spawn Agent with `subagent_type: "codex:codex-rescue"`
3. Spawn Agent with `subagent_type: "claude"` (general reviewer)

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

2. Re-run the reviewer using the same priority order (unity-reviewer → codex:codex-rescue → claude) with the updated files.

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
1. Compile check via MCP refresh_assets
2. Test run via MCP run_tests
3. Quick scan for Unity-specific issues (null refs, missing SerializeField, event leaks)

If you find and fix issues, list them. If cannot fix, report blockers.
Report: VERIFIED or ISSUES FOUND with details.
```

If **VERIFIED** → append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"VERIFICATION_PASSED","phase":[N],"task":[P],"id":"P{phase}.T{task}","title":"[task title]","timestamp":"[ISO8601]"}
```
Then proceed to Step 4 Committer.

If **ISSUES FOUND** and fixed → append VERIFICATION_PASSED event and proceed to Step 4 Committer.

If **cannot fix** → stop. Print blockers and surface to developer before committing. Update PROGRESS.md with blocked status.

---

#### Step 4 — Committer

Spawn a **committer** subagent:

```
You are a release engineer. Commit completed work.

## Task Completed
ID: [P{phase}.T{task}]
Title: [task title]

## Files Changed
[coder/unity-setup output — list of files]

## Rules
- Run: git status, git diff to confirm what changed
- Stage only files related to this task
- Commit message format: "feat: [P{phase}.T{task}] [task title]"
- Do NOT push — user pushes manually
- Report: commit hash and message
```

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

Spawn a **unity-verifier** subagent to compile and run tests. If failures found → spawn **unity-fixer** to fix, re-verify (max 3 passes). If still failing after 3 passes → stop and report to user. Do not proceed to Step 2 until green.

Print: `✓ Ralph passed — compile and tests green.` or `⚠ Ralph failed after 3 passes — [issues]. Fix before proceeding.`

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

Spawn a **general-purpose** subagent with the validate prompt:

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
- **Reviewer tries unity-reviewer first.** Fall back to Codex, then to Claude reviewer agent if both are unavailable.

---

## On Completion

Run: `rm -f .claude/state/gate-cleared`

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
