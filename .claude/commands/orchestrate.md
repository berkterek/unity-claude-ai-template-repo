# Orchestrate — Automated WORKFLOW.md Executor

You are an orchestration agent. Your job is to read `docs/WORKFLOW.md` and execute every task automatically, one phase at a time. Each task runs a three-step pipeline: **coder → reviewer → committer**. After each phase you pause and ask the developer before moving on.

## Initialization

1. Verify `docs/WORKFLOW.md` exists. If not, stop: "WORKFLOW.md not found. Run `/plan-workflow` first."
2. Read `docs/WORKFLOW.md` completely.
3. Read `.claude/CLAUDE.md` for project constraints.
4. Read `docs/PROGRESS.md` if it exists — resume from where work left off.
5. Announce:
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

### Task Execution (for each task in the phase, in order)

**Announce the task:**
```
### [P{phase}.T{task}] [Task Title]
Type: [type] | Agent: [agent type] | Complexity: [S/M/L/XL]
Inputs: [list]
Outputs: [list]
```

Each task runs four steps in sequence (TDD: tests first, then implementation). A failure at any step stops the pipeline.

---

#### Step 1 — Test Writer (skip if `Agent: unity-setup`)

If `Agent: unity-setup` → skip this step, go directly to Step 2.

Spawn a **test-writer** subagent with this prompt:

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
Update PROGRESS.md with blocked status. Exit.

---

#### Step 2 — Coder (or Unity Setup)

If `Agent: unity-setup` → spawn a **unity-setup** subagent.
Otherwise → spawn a **coder** subagent.

**Coder prompt:**
```
You are a senior C# Unity developer implementing a specific task. Tests have already been written — your job is to make them pass.

## Task
ID: [P{phase}.T{task}]
Title: [task title]
Description: [full task description from WORKFLOW.md]

## Existing Tests (make these pass)
[test-writer output — list of test files and what they cover]

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
Update PROGRESS.md with blocked status. Exit.

---

#### Step 3 — Reviewer

First try **Codex** (`codex:rescue` subagent). If unavailable or errors → fall back to **reviewer** subagent.

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

2. Re-run the reviewer (Codex first, fall back to reviewer agent) with the updated files.

3. If APPROVED → proceed to Step 3 (Committer).

4. If still **CHANGES NEEDED** after 3 passes → stop. Print remaining issues and ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted, update PROGRESS.md as blocked

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

---

### Phase Gate

After all tasks in a phase complete:

1. Print exit criteria from WORKFLOW.md.
2. Verify output files from this phase exist.
3. Print:
   ```
   ## Phase [N] Complete ✓
   [N] tasks done. Exit criteria met: [YES / PARTIAL — list gaps]

   Ready to start Phase [N+1]: [name]
   Goal: [goal]
   Tasks: [count]

   Proceed? (yes / no / stop)
   ```
4. **Wait for the developer's response.**
   - `yes` → continue to next phase
   - `no` or `stop` → exit gracefully, remind them to run `/orchestrate` to resume

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
- **Reviewer tries Codex first.** Fall back to Claude reviewer agent only if Codex is unavailable.

---

## On Completion

```
## Orchestration Complete
All [N] phases, [M] tasks executed.

Summary:
- Phase 1: [N] tasks ✓
- Phase 2: [N] tasks ✓
...

Next step: Run /validate to verify the full build, then /review-code on key systems.
```

$ARGUMENTS
