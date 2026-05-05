# /implement — Coder → Reviewer → Committer Pipeline

Implements a feature or task using a three-agent pipeline: coder writes, reviewer checks, committer commits.

## Usage

```
/implement <task description>
/implement add BoxCollectedEvent publishing to BayManager
```

If no argument is given, ask: "What needs to be implemented?"

## Pipeline

```
[1] CODER → [2] REVIEWER ⟲ (loop until APPROVED) → [3] COMMITTER
```

---

## Step 1 — Coder

Spawn a **coder** subagent with this prompt:

```
You are a senior C# Unity developer. Implement the following task.

## Task
$TASK_DESCRIPTION

## Project Rules (read first)
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- IEventBus for cross-system communication
- #region tags required in _GameFolders/Scripts/

## When Done
List every file you created or modified with a one-line summary of the change.
Report: DONE or BLOCKED with reason.
```

If coder reports **BLOCKED** → stop, show the blocker to the user, do not continue.

---

## Step 2 — Reviewer

First try **Codex** (`codex:rescue` subagent):

```
Review the following Unity C# implementation.

## What Was Implemented
$TASK_DESCRIPTION

## Files Changed
$CODER_OUTPUT

## Review Criteria
1. Architecture — VContainer DI, no singletons, interfaces only across modules
2. Naming — PascalCase types, _camelCase private fields
3. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
4. Events — IEvent structs past-tense with Event suffix, published via IEventBus
5. UniTask — no async void outside lifecycle, CancellationToken on every async method
6. Unity null safety — no ?. or is null on UnityEngine objects
7. Serialization — FormerlySerializedAs on any renamed [SerializeField]

## Output Format
APPROVED — if all criteria pass, nothing to change.

CHANGES NEEDED:
- [file:line] Issue description and fix.
(list every issue)
```

If Codex is unavailable → fall back to **reviewer** subagent with the same prompt.

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Original Task
   $TASK_DESCRIPTION

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After coder fixes → re-run the reviewer (Codex first, fall back to reviewer agent) with the updated files.

3. If APPROVED → proceed to Step 3.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 3 — Committer

Spawn a **committer** subagent with this prompt:

```
You are a release engineer. Commit all staged changes.

## What Was Implemented
$TASK_DESCRIPTION

## Files Changed
$CODER_OUTPUT

## Rules
- Run: git status, git diff to see all changes
- Stage only files related to this task
- Commit message format: "feat: <short description in English>"
- One commit unless the changes are clearly separable into logical units
- Do NOT push — user pushes manually
- Report: commit hash and message when done
```

---

## Completion

Print:
```
## ✓ Implemented
Task: [task description]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
