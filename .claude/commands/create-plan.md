# /create-plan — Researcher → Planner → Reviewer → Save → Implementer Pipeline

Creates a new plan file from scratch in the `Docs/` folder. Analyzes the codebase, identifies gaps, and produces a structured plan document.

## Usage

```
/create-plan <plan file name> <what to plan>
/create-plan PLAN_audio_spatial.md add spatial audio and mixer group support to AudioService
```

If no argument is given, ask: "What is the plan file name and what should be planned?"

## Pipeline

```
[1] RESEARCHER → [2] PLANNER → [3] REVIEWER → [4] SAVE → [5] IMPLEMENTER
```

---

## Step 1 — Researcher

Spawn an **Explore** subagent with this prompt:

```
You are a codebase analyst for this Unity project.

## Goal
Research the codebase to gather everything the planner needs to write a precise, actionable plan from scratch.

Specifically find:
1. Which files are directly related to the feature or bug described below
2. Current implementation state (what exists, what is partial, what is missing)
3. Method signatures, field names, and class names the planner will reference
4. Architecture constraints (DI wiring, event flow, editor vs runtime boundary)
5. Related existing plans in Docs/ that might overlap

## Plan To Create
File: $PLAN_FILE
Topic: $CHANGE_DESCRIPTION

## What to Read
1. Recent git log: `git log --oneline -15`
2. Existing plans in Docs/ — check for overlap
3. Source files relevant to the topic — look in Assets/ under the relevant module folders
4. .claude/skills/learned/ — load any relevant learned skills
5. .claude/rules/architecture.md — for DI and event patterns

## Output Format
### Current State
- What already exists related to this topic (files, classes, methods)
- What is partial or broken

### Missing / Broken
- Concrete gaps that the plan must address
- Which file each gap belongs to

### Technical Notes for Planner
- Exact method signatures, field names, serialized property paths
- Architecture constraints (editor-only? runtime? event bus?)
- Any gotchas or ordering dependencies

Report findings only. Do NOT write plan tasks or code.
```

---

## Step 2 — Planner

Spawn a **Plan** subagent (model: opus) with this prompt:

```
You are a senior technical writer for a Unity project.
Your job is to create a brand-new plan file from scratch.

## Plan File to Create
$PLAN_FILE  (will be saved to Docs/ folder)

## Feature / Bug to Plan
$CHANGE_DESCRIPTION

## Complexity Assessment

Before writing any plan tasks, score this task (0.0–1.0):

| Score | Label | Action |
|-------|-------|--------|
| 0.0–0.3 | Simple | Write tasks directly — single file, no new interfaces |
| 0.4–0.6 | Medium | Propose 2 approaches with trade-offs, pick one, justify in a `## Chosen Approach` section before tasks |
| 0.7–1.0 | Complex | Propose 3 approaches. After choosing one, run a second internal critique pass: check for hot-path allocations, missing CancellationTokens, and incomplete DI wiring. Document findings in `## Chosen Approach` |

Scoring signals:
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Single file, single method? −0.3

Print the score and label at the top of the plan before any tasks.

## Researcher Findings
$RESEARCHER_OUTPUT

## Project Context
- Editor-only work stays in Editor/ assembly unless a runtime change is explicitly required
- Runtime files may be touched only when the feature requires it — document clearly
- Scene objects and .asset/.prefab files are NOT directly edited by code — editor tooling writes them via SerializedObject
- VContainer for DI — no singletons, no static access
- IEventBus for cross-module communication — readonly struct events, zero allocation
- UniTask for all async work — no coroutines, no async void
- New Input System only — InputView owns PlayerControls

## Plan File Format

The plan must follow this exact structure:

```markdown
# PLAN — <Short Title>

> **Version:** v1 — <date>
> **Status:** Active
> **Scope:** <which systems are affected>

## Context

<2-3 paragraphs: what is the problem, why it matters, current state>

## Goals

- [ ] Goal 1
- [ ] Goal 2
- [ ] Goal 3

## Status

| Phase | Task | Status |
|-------|------|--------|
| 1 | Task 1 | ⏳ Pending |
| 2 | Task 2 | ⏳ Pending |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| path/to/File.cs | Add / Modify | what changes |

---

## Task 1 — <Title>

**Files:**
- `path/to/File.cs`

**Steps:**
1. [ ] Step description
2. [ ] Step description

**Code Skeleton:**
\`\`\`csharp
// method signature + key logic sketch (not full implementation)
\`\`\`

**Acceptance Criteria:**
- Criterion 1
- Criterion 2

---

## Task 2 — <Title>
...
```

## Instructions
1. Use the researcher findings to write precise tasks (real file paths, real method names)
2. Start with v1 and today's date
3. Each task must have: files, numbered steps with [ ] checkboxes, code skeleton, acceptance criteria
4. If a task touches runtime code, mark it clearly: **[RUNTIME]**
5. If a task is risky or uncertain, mark it: **[BLOCKED — needs investigation]**

## Output
Return the FULL plan file content.
```

---

## Step 3 — Reviewer

First try **Codex** (`codex:rescue` subagent):

```
Review the following NEW plan for a Unity project.

## Plan File
$PLAN_FILE

## Feature Being Planned
$CHANGE_DESCRIPTION

## Plan Content
$PLANNER_OUTPUT

## Review Criteria
1. Scope — does each task clearly state whether it is editor-only or runtime?
2. File paths — are all referenced files real paths confirmed in the codebase?
3. Task completeness — do all tasks have files, steps, and acceptance criteria?
4. Architecture alignment — do proposed changes respect VContainer DI, IEventBus, SerializedObject patterns?
5. Overlap — does this duplicate an existing plan in Docs/?
6. Format — does it follow the required plan format (Context, Goals, Status table, File Map, Task sections)?
7. BLOCKED tasks — are risky or uncertain tasks clearly marked?

## Output Format
APPROVED — plan is ready to save.

CHANGES NEEDED:
- [section] Issue and fix.
(list every issue)
```

If Codex is unavailable → fall back to a **general-purpose** subagent with the same prompt.

If reviewer reports **CHANGES NEEDED** → automatically re-run the pipeline (no user prompt):

1. Re-spawn the **Researcher** with the original topic + reviewer feedback appended.
2. Re-spawn the **Planner** (opus) with original inputs + researcher output + reviewer feedback.
3. Re-spawn the **Reviewer** on the new planner output.

Repeat up to **2 more times** (3 total reviewer passes).

After 3 failed passes → stop and show the user all accumulated feedback. Ask:
- `skip` → save the last planner output as-is (user accepts responsibility)
- `stop` → abort, do not save

---

## Step 4 — Save

After APPROVED:
- Write the plan content to `Docs/$PLAN_FILE`
- Print: `Plan created: Docs/$PLAN_FILE`

---

## Step 5 — Implementer

After saving, ask the user:

> "Plan saved. Implement now? (yes / no)"

If **no** → print completion summary and stop.

If **yes** → spawn a **general-purpose** subagent with this prompt:

```
You are a senior C# Unity developer implementing a plan.

## Plan File
Docs/$PLAN_FILE

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- IEventBus for cross-system communication — readonly struct events, zero allocation
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

After implementer finishes → spawn the **Reviewer** (Codex first, fall back to general-purpose) with:

```
Review the implementation of the following plan for a Unity project.

## Plan File
Docs/$PLAN_FILE

## Files Changed
$IMPLEMENTER_OUTPUT

## Review Criteria
1. Architecture — VContainer DI, no singletons, interfaces only across modules
2. Naming — PascalCase types, _camelCase private fields, SCREAMING_SNAKE_CASE constants
3. Namespace — must be in Layer.Module format (e.g. Game.Concretes.Audio)
4. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
5. Events — IEvent structs past-tense with Event suffix, published via IEventBus
6. UniTask — no async void outside lifecycle, CancellationToken on every async method
7. Unity null safety — no ?. or is null on UnityEngine objects
8. BLOCKED tasks were not implemented

## Output Format
APPROVED — implementation is correct, nothing to change.

CHANGES NEEDED:
- [file:line] Issue and fix.
```

If **CHANGES NEEDED** → spawn a **coder** subagent to fix each issue, then re-run the reviewer (max 2 fix passes). After 2 failed passes → show remaining issues to the user.

If **APPROVED** → spawn a **committer** subagent:

```
You are a release engineer. Commit the implementation of a plan for a Unity project.

## Plan Implemented
Docs/$PLAN_FILE

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
## ✓ Plan Created & Implemented
File: Docs/[plan file]
Topic: [one-line summary]
Reviewer: [Codex | Claude] — APPROVED
Commit: [hash] — [message]   (only if implemented)
```

$ARGUMENTS
