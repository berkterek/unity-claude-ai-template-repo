# /update-plan — Analyzer → Planner → Reviewer → Implementer Pipeline

Updates or extends an existing Docs plan file based on new findings, screenshots, or feature gaps.

## Usage

```
/update-plan <plan file> <what needs to change>
/update-plan Docs/PLAN_audio_system.md add spatial audio and mixer group support
```

If no argument is given, ask: "Which plan file and what needs to be added or changed?"

## Pipeline

```
[1] ANALYZER → [2] PLANNER → [3] REVIEWER → [4] SAVE → [5] IMPLEMENTER
```

---

## Step 1 — Analyzer

Spawn an **Explore** subagent with this prompt:

```
You are a codebase analyst for this Unity project.

## Goal
Analyze the existing plan and relevant source files to understand:
1. What is already implemented (match plan tasks to actual code)
2. What is missing or broken (gaps between plan and code)
3. Concrete technical findings the planner needs to write precise tasks

## Plan File
$PLAN_FILE

## Change Request
$CHANGE_DESCRIPTION

## What to Read
1. The plan file listed above
2. Recent git log: `git log --oneline -10`
3. Source files relevant to the change request
4. Any relevant .claude/skills/learned/ files

## Output Format
### Already Implemented
- List tasks/steps from the plan that are confirmed in code

### Gaps Found
- For each gap: what is missing, which file it belongs to, why it matters

### Technical Notes for Planner
- Concrete findings (method signatures, field names, patterns) the planner needs
- Constraints or gotchas discovered in the code

Report findings only. Do NOT write plan tasks or code.
```

If analyzer reports no gaps → inform the user: "Plan is already up to date. No changes needed." and stop.

---

## Step 2 — Planner

Spawn a **Plan** subagent (model: opus) with this prompt:

```
You are a senior technical writer for a Unity project.
Your job is to update an existing Docs plan file with new tasks.

## Plan File to Update
$PLAN_FILE

## Change Request
$CHANGE_DESCRIPTION

## Analyzer Findings
$ANALYZER_OUTPUT

## Parallel Group Assignment

After writing all new tasks, analyze dependencies across ALL tasks (existing + new) and update the `parallel_group` column in the Status table:

**Rules:**
- If Task B's inputs depend on Task A's outputs → they MUST be sequential (no shared group)
- If two tasks are fully independent (different files, no shared inputs/outputs) → assign the same `parallel_group` number
- Tasks with no parallel candidate get `—` (sequential by default)
- If the Status table has no `parallel_group` column yet, add it

**When orchestrate runs this plan:** tasks in the same `parallel_group` will spawn simultaneously (complexity ≥ 0.4). Tasks with `—` run sequentially.

## Instructions
1. Read the existing plan file carefully
2. Add a new revision note at the top (vN+1 format, today's date)
3. Update the status table if any phases changed status (add `parallel_group` column if missing)
4. Add new Task sections at the bottom (Task N+1, Task N+2, etc.) with:
   - Files to modify (exact paths)
   - Numbered steps with [ ] checkboxes
   - Code snippets showing method signatures and key logic (not full implementations)
   - Clear acceptance criteria
5. Keep existing tasks and content untouched — only append

## Output
Return the FULL updated plan file content.
Do NOT truncate existing content.
```

---

## Step 3 — Reviewer

First try **Codex** (`codex:rescue` subagent):

```
Review the following plan update for a Unity project.

## Plan File
$PLAN_FILE

## Change Request
$CHANGE_DESCRIPTION

## Updated Plan Content
$PLANNER_OUTPUT

## Review Criteria
1. Scope — do new tasks stay within the intended boundaries?
2. File paths — are all referenced files real paths in the project?
3. Task completeness — do steps have clear acceptance criteria?
4. No duplicates — do new tasks overlap with already-implemented work?
5. Revision note — is it present and correctly formatted?

## Output Format
APPROVED — plan is ready to save.

CHANGES NEEDED:
- [section] Issue and fix.
```

If Codex is unavailable → fall back to a **general-purpose** subagent with the same prompt.

If reviewer reports **CHANGES NEEDED** → automatically re-run the pipeline (no user prompt):

1. Re-spawn the **Analyzer** with original change request + reviewer feedback appended.
2. Re-spawn the **Planner** (opus) with original inputs + analyzer output + reviewer feedback.
3. Re-spawn the **Reviewer** on the new planner output.

Repeat up to **2 more times** (3 total reviewer passes).

After 3 failed passes → stop and show the user all accumulated feedback. Ask:
- `skip` → save the last planner output as-is (user accepts responsibility)
- `stop` → abort, do not save

---

## Step 4 — Save

After APPROVED → write the updated content to `$PLAN_FILE`.

---

## Step 5 — Implementer

After saving, ask the user:

> "Plan saved. Implement now? (yes / no)"

If **no** → print completion summary and stop.

If **yes** → read the plan file. Extract the complexity score printed at the top of the plan by the Planner (e.g. `Complexity: 0.6 — Medium`). Then check for `parallel_group` annotations in the Status table.

**If `parallel_group` annotations exist AND complexity score ≥ 0.4:**
1. Group tasks by `parallel_group` number. Tasks with `—` are sequential.
2. **Conflict check:** For each group, check if two tasks write to the same output file → demote the later task to sequential and warn:
   ```
   ⚠ PARALLEL CONFLICT: [Task A] and [Task B] both write to [file]
   [Task B] demoted to sequential.
   ```
3. Spawn one **general-purpose** subagent per task in the same group simultaneously.
4. Wait for all tasks in the group to complete before starting the next group or sequential task.
5. If any task in a group fails → stop. Report all failures. Do not proceed until user resolves.
6. After all groups and sequential tasks complete → run reviewer + committer as normal.

**If no `parallel_group` annotations OR complexity < 0.4:** spawn a single **general-purpose** subagent with this prompt:

```
You are a senior C# Unity developer implementing a plan.

## Plan File
$PLAN_FILE

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- BLOCKED tasks: skip entirely, do not implement

## Instructions
1. Read the plan file
2. Identify all tasks NOT marked BLOCKED and NOT already checked off
3. Implement them in order, task by task
4. After each task: mark its checkboxes as [x] in the plan file
5. After all tasks: run a final compile check (look for syntax errors in changed files)

## When Done
- List every file created or modified with a one-line summary
- Report: DONE or BLOCKED (with reason and task name)
```

Each parallel task subagent uses this same prompt with its specific task ID and title scoped in.

After implementer finishes → spawn the **Reviewer** (Codex first, fall back to general-purpose) with:

```
Review the implementation of the following plan.

## Plan File
$PLAN_FILE

## Files Changed
$IMPLEMENTER_OUTPUT

## Review Criteria
1. Architecture — VContainer DI, no singletons, interfaces only across modules
2. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
3. UniTask — no async void outside lifecycle, CancellationToken on every async method
4. Unity null safety — no ?. or is null on UnityEngine objects
5. BLOCKED tasks were not implemented

## Output Format
APPROVED or CHANGES NEEDED with file:line issues.
```

If **CHANGES NEEDED** → spawn a **coder** subagent to fix each issue, then re-run the reviewer (max 2 fix passes).

If **APPROVED** → spawn a **committer** subagent:

```
You are a release engineer. Commit the implementation of a plan.

## Plan Implemented
$PLAN_FILE

## Files Changed
$IMPLEMENTER_OUTPUT

## Rules
- Run: git status, git diff
- Stage only files related to this plan
- Commit message format: "feat: <short description in English>"
- Do NOT push
- Report: commit hash and message
```

---

## Completion

Print:
```
## ✓ Plan Updated & Implemented
File: [plan file path]
Changes: [one-line summary]
Reviewer: [Codex | Claude] — APPROVED
Commit: [hash] — [message]   (only if implemented)
```

$ARGUMENTS
