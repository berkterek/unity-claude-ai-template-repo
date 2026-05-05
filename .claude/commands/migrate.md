# /migrate — Migrator → Reviewer → Committer Pipeline

Migrates legacy code patterns to current standards: migrator converts, reviewer checks, committer commits.

## Usage

```
/migrate <what and where>
/migrate coroutines → UniTask in Assets/_Game/Scripts/Core/
/migrate singleton GameManager to VContainer in Assets/_Game/Scripts/
```

If no argument is given, ask:
1. What pattern needs migrating? (coroutine→UniTask, singleton→VContainer, Debug.Log→wrapper, Input.GetKey→New Input System, other)
2. Which files or folder?

## Pipeline

```
[1] MIGRATOR → [2] REVIEWER ⟲ (loop until APPROVED) → [3] COMMITTER
```

---

## Step 1 — Migrator

Spawn a **migrator** subagent with this prompt:

```
You are a Unity code migration specialist. Migrate legacy patterns in this project.

## Migration Task
$MIGRATION_DESCRIPTION

## Project Rules
- Read .claude/CLAUDE.md before making any changes
- Follow all rules in .claude/rules/
- Migrate conservatively: same behavior, different implementation
- Do NOT add features or refactor beyond the migration
- Every file you touch must compile and work after your edit
- Check every file that depends on the migrated code

## Common Migration Patterns

### Coroutine → UniTask
- IEnumerator + yield return → async UniTask
- WaitForSeconds → UniTask.Delay
- StartCoroutine → .Forget() or await
- Every async method must have CancellationToken parameter

### Singleton → VContainer
- Remove static Instance
- Register in the appropriate LifetimeScope installer
- Replace all call sites with injected interface

### Legacy Input → New Input System
- Input.GetKey / Input.GetAxis → PlayerControls actions
- All input reading must go through InputView

## When Done
List every file you changed with a one-line summary of what was migrated.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 2 — Reviewer

First try **Codex** (`codex:rescue` subagent):

```
Review this code migration.

## Migration
$MIGRATION_DESCRIPTION

## Files Changed
$MIGRATOR_OUTPUT

## Review Criteria
1. Correctness — same behavior before and after, no regressions
2. Completeness — all instances of the old pattern are migrated, no leftovers
3. Architecture — VContainer DI, no singletons, interfaces only across modules
4. UniTask rules — no async void, CancellationToken on every async method
5. Unity null safety — no ?. or is null on UnityEngine objects

## Output Format
APPROVED or CHANGES NEEDED with file:line issues.
```

If Codex unavailable → fall back to **reviewer** subagent.

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **migrator** subagent to fix every listed issue:
   ```
   You are a Unity code migration specialist. Fix the following review issues.

   ## Original Migration
   $MIGRATION_DESCRIPTION

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After migrator fixes → re-run the reviewer (Codex first, fall back to reviewer agent) with the updated files.

3. If APPROVED → proceed to Step 3.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 3 — Committer

Spawn a **committer** subagent with this prompt:

```
You are a release engineer. Commit this migration.

## Migration
$MIGRATION_DESCRIPTION

## Files Changed
$MIGRATOR_OUTPUT

## Rules
- Run: git status, git diff
- Stage only migration-related files
- Commit message format: "refactor: migrate <pattern> in <scope>"
- One commit per migration type (if multiple patterns were migrated, split commits)
- Do NOT push
- Report: commit hash(es) and message(s)
```

---

## Completion

Print:
```
## ✓ Migration Complete
Migration: [description]
Files changed: [count]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
