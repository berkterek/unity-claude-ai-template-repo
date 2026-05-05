# Orchestrate — Automated WORKFLOW.md Executor

You are an orchestration agent. Your job is to read `docs/WORKFLOW.md` and execute every task automatically, one phase at a time. You dispatch a fresh subagent per task. After each phase you pause and ask the developer before moving on.

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

### Task Execution (for each task in the phase, in order)

For each task:

**1. Announce the task:**
```
### [P{phase}.T{task}] [Task Title]
Type: [type] | Agent: [agent type] | Complexity: [S/M/L/XL]
Inputs: [list]
Outputs: [list]
```

**2. Dispatch a fresh subagent** with this exact prompt structure:

```
You are a [agent type] agent implementing a specific task in a Unity project.

## Your Task
Task ID: [P{phase}.T{task}]
Title: [task title]
Type: [type]

## What You Must Build
[task description from WORKFLOW.md — full text]

## Input Files (read these first)
[list every input file path]

## Output Files (you must produce exactly these)
[list every output file path]

## Acceptance Criteria (all must pass)
[list every acceptance criterion]

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all architecture rules in .claude/rules/
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- Every logic class needs a test (see .claude/rules/testing.md)
- sealed classes by default
- #region tags required in _GameFolders/Scripts/

## When Done
- Run any available compile/test checks
- Commit your changes with message: "feat: [P{phase}.T{task}] [task title]"
- Report: DONE or BLOCKED with reason
```

**3. On subagent result:**

- **DONE** → Mark task complete, append to `docs/PROGRESS.md`, continue.
- **BLOCKED** → Stop immediately. Print:
  ```
  ⚠ BLOCKED at [P{phase}.T{task}]: [reason]
  Fix this before continuing. Run /orchestrate to resume.
  ```
  Update PROGRESS.md with blocked status. Exit.

**4. Update `docs/PROGRESS.md`** after every completed task:

```markdown
## Phase [N]: [Name] — IN PROGRESS / COMPLETE

- [x] P{phase}.T{task} — [title] — [commit hash if available]
- [ ] P{phase}.T{task} — [title] — pending
```

### Phase Gate

After all tasks in a phase complete:

1. Print the phase exit criteria from WORKFLOW.md.
2. Do a quick verification: do the output files from this phase exist?
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

## Progress Tracking

`docs/PROGRESS.md` is the source of truth for resuming. Format:

```markdown
# Execution Progress
**Plan:** [game name]
**Started:** [date]
**Last updated:** [date]

## Phase 1: Infrastructure Foundation — COMPLETE
- [x] P1.T1 — IEventBus + EventBus — abc1234
- [x] P1.T2 — ModuleInstaller base — def5678

## Phase 2: Core Game Logic — IN PROGRESS
- [x] P2.T1 — EnemyService — 9ab1234
- [ ] P2.T2 — ScoreService — pending
- [ ] P2.T3 — PlayerService — pending

## Phase 3: Unit Tests — PENDING
```

On startup, read this file and skip already-completed tasks.

## Rules

- **Never skip acceptance criteria.** If a subagent reports done but criteria are ambiguous, re-read the WORKFLOW.md criteria before proceeding.
- **Never continue past a BLOCKED task.** Fix it first.
- **Phase gates are mandatory.** Always pause and ask between phases.
- **One subagent per task.** Never batch multiple tasks into one subagent.
- **Subagents get no session history.** Write their prompt as if they know nothing about this conversation.
- **Unity MCP tasks:** For tasks with `Agent: unity-setup`, include a note in the subagent prompt: "Use Unity MCP tools (create_gameobject, add_component, etc.) for scene/prefab work. Do not edit .unity or .prefab files as text."

## On Completion

When all phases are done:

```
## 🎉 Orchestration Complete
All [N] phases, [M] tasks executed.

Summary:
- Phase 1: [N] tasks ✓
- Phase 2: [N] tasks ✓
...

Next step: Run /validate to verify the full build, then /review-code on key systems.
```

$ARGUMENTS
