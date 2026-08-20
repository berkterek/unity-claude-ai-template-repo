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

## Step 0 — Knowledge Graph Query

If `.claude/project-features.json` has `graph == true` AND `.claude/graph/graph.json` exists:

```bash
python3 -c "
import json
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
classes = cb.get('classes', [])
interfaces = cb.get('interfaces', [])
events = cb.get('events', [])
installers = cb.get('vcontainer', {}).get('installers', [])
print('CLASSES (%d):' % len(classes))
for c in classes:
    print('  %s | mono=%s | deps=%s | pub=%s | sub=%s' % (
        c['name'], c.get('is_mono_behaviour', False),
        c.get('dependencies', []), c.get('events_published', []), c.get('events_subscribed', [])))
print('INTERFACES (%d):' % len(interfaces))
for i in interfaces: print('  %s' % i['name'])
print('EVENTS (%d):' % len(events))
for e in events: print('  %s' % e['name'])
print('INSTALLERS (%d):' % len(installers))
for inst in installers:
    regs = [r.get('type','') for r in inst.get('registrations', [])]
    print('  %s | registrations=%s' % (inst['name'], regs))
"
```

Keep this output in your active context as `GRAPH_CONTEXT`. You will embed it into subagent prompts below.

If graph is disabled or missing → set `GRAPH_CONTEXT` to empty, proceed.

---

## Step 1 — Researcher

Spawn an **Explore** subagent (`model: haiku`) with this prompt:

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
File: [INSERT HERE: the plan file name from the /create-plan argument]
Topic: [INSERT HERE: the change description from the /create-plan argument]

## Knowledge Graph (class/interface/event/installer inventory — use as primary reference)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0 — if empty, write "No graph available, scan source files."]

## What to Read
1. Recent git log: `git log --oneline -15`
2. Existing plans in Docs/ — check for overlap
3. Source files relevant to the topic — look in Assets/ under the relevant module folders (use graph above to identify which files to read — skip files unrelated to the topic)
4. .claude/skills/learned/ — load any relevant learned skills
5. .claude/rules/architecture.md — for DI and event patterns

## Scene & Prefab Pre-Scan (MANDATORY if topic touches UI, scene objects, or VContainer registration)

Graph age check: read `.claude/graph/graph.json` → check `metadata.generated_at`. If < 24h old, use graph. If stale or missing, note it and skip graph queries.

**If graph is fresh:**
- For each prefab the plan will touch: read `codebase.prefabs[]` — list components and isVariant
- For the affected scene: read `codebase.scenes[].gameobjects[]` — list all GO names and children
- For affected VContainer scopes: read `codebase.vcontainer[]` — list registrations

**After graph queries, check these fields (now captured by the graph extractor):**
- `active: false` entries — `RegisterComponentInHierarchy<T>()` fails silently if the GO is inactive at registration time. Flag every `active: false` GO that a VContainer registration depends on.
- `duplicate: true` entries — same GO name appearing more than once under the same parent. Flag all duplicates.

If graph is stale (> 24h) or MCP was skipped during last build, note affected GOs as "unverified — rebuild graph with Unity Editor open before implementing" in Technical Notes.

## Output Format
### Current State
- What already exists related to this topic (files, classes, methods)
- What is partial or broken

### Scene / Prefab State (new)
- Active/inactive status of relevant GOs
- Any duplicate GOs found
- VContainer registrations that depend on scene objects (`RegisterComponentInHierarchy`)
- Prefab variants that will be affected

### Missing / Broken
- Concrete gaps that the plan must address
- Which file each gap belongs to

### Technical Notes for Planner
- Exact method signatures, field names, serialized property paths
- Architecture constraints (editor-only? runtime? event bus?)
- Any gotchas or ordering dependencies
- **VContainer scene preconditions:** for every `RegisterComponentInHierarchy<T>()` the plan will add, explicitly state: "GO must be active in scene at registration time"

Report findings only. Do NOT write plan tasks or code.
```

---

## Step 2 — Planner

Spawn a **Plan** subagent (model: opus) with this prompt:

```
You are a senior technical writer for a Unity project.
Your job is to create a brand-new plan file from scratch.

## Plan File to Create
[INSERT HERE: the plan file name from the /create-plan argument]

## Feature / Bug to Plan
[INSERT HERE: the change description from the /create-plan argument]

## Step 0 — Modify Pre-Read (MANDATORY before writing any task)

Before scoring complexity or writing any tasks:

1. From the Researcher Findings, identify every file listed under "What to Modify" or implied as an existing file to be changed.
2. Read each of those files now.
3. For each file, note:
   - Current method signatures that the plan will call or override
   - Existing field names and types (avoid renaming without `[FormerlySerializedAs]`)
   - Subscribe/Unsubscribe pairs already in place (avoid duplicate subscriptions)
   - Any namespace that could collide with UnityEngine types (Camera, Random, Object, Input, Physics, Collider, Transform)

If a file the plan intends to modify does not exist yet → it is an Add, not a Modify. Correct the File Map accordingly.

Only after reading all Modify files → proceed to Complexity Assessment.

---

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
[INSERT HERE: the full output from the Step 1 Researcher/Explore subagent]

## Project Context
- Editor-only work stays in Editor/ assembly unless a runtime change is explicitly required
- Runtime files may be touched only when the feature requires it — document clearly
- Scene objects and .asset/.prefab files are NOT directly edited by code — editor tooling writes them via SerializedObject
- VContainer for DI — no singletons, no static access
- IEventBus for cross-module communication — readonly struct events, zero allocation
- UniTask for all async work — no coroutines, no async void
- New Input System only — `InputService` (pure C#, pull-based) owns PlayerControls

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

**Test Type:** EditMode | PlayMode-ECS | PlayMode-Scene | NoTest
_(see Test Type Decision Matrix below — apply it to the primary file for this task)_

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

## Test Type Decision Matrix

For each task, apply this decision matrix to its **primary file** to fill the `**Test Type:**` field:

**Path-based (fastest):**
| Path contains | Decision |
|---------------|----------|
| `Games/Abstracts/` or `Games/Concretes/` | **EditMode** |
| `Games/Ecs/Systems/` | **PlayMode-ECS** |
| `Games/Ecs/Components/` or `Games/Ecs/Authorings/` | **NoTest** |
| `_Framework/` | **EditMode** |
| `Editor/` | **NoTest** |

**Class type fallback (when path unknown):**
| Class type | Decision |
|------------|----------|
| Extends `LifetimeScope` | **NoTest** |
| `MonoBehaviour` with no logic (thin adapter) | **NoTest** |
| `MonoBehaviour` WITH logic | **PlayMode-Scene** |
| `ISystem` or `SystemBase` | **PlayMode-ECS** |
| `IComponentData` struct or `Baker<T>` | **NoTest** |
| Pure C# service/model/util | **EditMode** |
| `ScriptableObject` config | **NoTest** |

Apply this matrix **per task**. Do NOT guess — if uncertain, prefer `PlayMode-Scene` for MonoBehaviours with logic, `EditMode` for pure C#.

## Parallel Group Assignment

After writing all tasks, analyze task dependencies and assign `parallel_group` numbers in the Status table:

**Rules:**
1. **Compile-time dependency (most important):** If Task B's code references a type, interface, or method that Task A *introduces* (even in a different file), Task B MUST be sequential after Task A. Different files ≠ safe to parallelize when there is a type dependency.
   - Example: Task A creates `IGameFlowService.cs`, Task B creates `PauseInputHandler.cs` that calls `IGameFlowService.ResumeGame()` → Task B is sequential after Task A.
2. **File write conflict:** If two tasks write to the same file → they MUST be sequential.
3. **Independent:** If two tasks write to entirely different files AND neither task's code references types introduced by the other → assign the same `parallel_group` number.
4. Tasks with no parallel candidate get `—` (sequential by default).

Add a `parallel_group` column to the Status table:

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Add IEnemyService | ⏳ Pending | 1 |
| 1 | Add IAudioService | ⏳ Pending | 1 |
| 2 | Wire both in AppModules | ⏳ Pending | — |

**When orchestrate runs this plan:** tasks in the same `parallel_group` will spawn simultaneously (complexity ≥ 0.4). Tasks with `—` run sequentially.

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

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

Reviewer prompt:
```
You are acting as a PLAN REVIEWER, not a fixer. Do not modify the plan file or any
other file — do not rewrite tasks, do not "helpfully" correct a path. Your only output
is the verdict format below; the Planner applies the fixes.

Review the following NEW plan for a Unity project.

## Plan File
[INSERT HERE: the plan file name from the /create-plan argument]

## Feature Being Planned
[INSERT HERE: the change description from the /create-plan argument]

## Plan Content
[INSERT HERE: the full plan content from the Planner agent]

## Review Criteria
1. Scope — does each task clearly state whether it is editor-only or runtime?
2. File paths — are all referenced files real paths confirmed in the codebase?
3. Task completeness — do all tasks have files, steps, and acceptance criteria?
4. Architecture alignment — do proposed changes respect VContainer DI, IEventBus, SerializedObject patterns?
5. Overlap — does this duplicate an existing plan in Docs/?
6. Format — does it follow the required plan format (Context, Goals, Status table, File Map, Task sections)?
7. BLOCKED tasks — are risky or uncertain tasks clearly marked?

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 7 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <plan section, or file:line for criterion 2> | <evidence>

Criterion 2 (file paths are real) may only be CONFIRMED after you have actually
verified each path exists on disk — state how you checked. An unverified path is the
single most expensive defect a plan can carry, because every task downstream of it
inherits the mistake.

Then, for a plan that has any GAP:

CHANGES NEEDED:
- [section] Issue and fix.
(list every issue)

Revision classification (add one line after CHANGES NEEDED):
REVISION_TYPE: INCREMENTAL   ← small fixes, no structural changes
REVISION_TYPE: BREAKING      ← removes/renames existing tasks, changes module structure, or contradicts a previous plan decision
```

If Codex is unavailable → fall back to a **general-purpose** subagent (`model: opus` — plan review is lead-tier) with the same prompt.

If reviewer reports **CHANGES NEEDED**:

- **REVISION_TYPE: INCREMENTAL** → automatically re-run the pipeline (no user prompt):
  1. Re-spawn the **Researcher** with the original topic + reviewer feedback appended.
  2. Re-spawn the **Planner** (opus) with original inputs + researcher output + reviewer feedback.
  3. Re-spawn the **Reviewer** on the new planner output.

- **REVISION_TYPE: BREAKING** → stop immediately and show the user:
  ```
  ⚠️  BREAKING REVISION DETECTED (v[N])

  The reviewer flagged a structural change — this means the codebase
  was not fully read before planning. Proceeding risks another round
  of breaking fixes during implementation.

  Reviewer feedback:
  [INSERT HERE: the full CHANGES NEEDED list]

  Options:
    re-research  — re-run Researcher with expanded scope, then re-plan
    accept       — proceed with breaking revision (user accepts risk)
    stop         — abort
  ```
  Wait for user input before continuing.

Repeat INCREMENTAL passes up to **2 more times** (3 total reviewer passes).

After 3 failed INCREMENTAL passes → stop and show the user all accumulated feedback. Ask:
- `skip` → save the last planner output as-is (user accepts responsibility)
- `stop` → abort, do not save

---

## Step 4 — Save

After APPROVED:
- Write the plan content to the plan file path from the /create-plan argument
- **Then run, BLOCKING:** `.claude/scripts/validate-plan-paths.sh <plan file path>`
  - exit 2 → the plan declares a folder that contradicts `rules/architecture.md`. Do not print "Plan created". Show the violation and either fix the plan or take the declared-exception route (`.claude/path-allowlist.txt` + `rules/architecture.md`) — the human decides which.
  - `NO PATHS FOUND` is **not** a pass; confirm by hand.
  - Paste the `checked:` receipt line into the output. A silent hook is not evidence.
- **Then run, BLOCKING:** `.claude/scripts/validate-plan-facts.sh <plan file path>`
  - exit 2 → at least one task creating a new `.cs` file is missing `Callers:`/`Wiring:`, or a declared caller/module doesn't resolve on disk or in the plan. Do not print "Plan created". Show the violation and fix the plan — the human decides.
  - `NO TASKS FOUND` is **not** a pass — the script's own words are "this is NOT a pass"; confirm by hand.
  - `NO TASKS EXAMINED` is **not** a pass either — it means every task line found was `/Tests/`-exempt, so no rule ran against any of them.
  - **Expect `NO TASKS FOUND` for a plan written in the `/create-plan` narrative format.** The validator enumerates task subjects with the same matcher the write-time hook uses, which suppresses fenced (```` ``` ````) regions — a plan whose only checkbox lines are quoted *examples* inside code fences declares no tasks, correctly. That is exit 0 with a visible warning, not a block. It becomes a real check the moment the plan carries unfenced checkbox task lines with a backticked `.cs`/`.asmdef` subject.
  - Paste the receipt into the output. A silent hook is not evidence.
- Print: `Plan created: Docs/[plan file name]`

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
3. Spawn one **general-purpose** subagent (`model: sonnet` — implementer is worker-tier) per task in the same group simultaneously.
4. Wait for all tasks in the group to complete before starting the next group or sequential task.
5. If any task in a group fails → stop. Report all failures. Do not proceed until user resolves.
6. After all groups and sequential tasks complete → run reviewer + committer as normal.

**If no `parallel_group` annotations OR complexity < 0.4:** spawn a single **general-purpose** subagent (`model: sonnet`) with this prompt:

```
You are a senior C# Unity developer implementing a plan.

## Plan File
[INSERT HERE: the full plan file path e.g. Docs/PLAN_audio.md]

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

Each parallel task subagent uses this same prompt with its specific task ID and title scoped in.

After implementer finishes → spawn the **Reviewer** using priority order (codex:codex-rescue → claude) with:

```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review the implementation of the following plan for a Unity project.

## Plan File
[INSERT HERE: the full plan file path e.g. Docs/PLAN_audio.md]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The plan document and the orchestration ledger are NOT
under review and must never be reported as scope violations: `.claude/**`, `docs/**`,
`Docs/**`, `*.json`, `*.jsonl`, `*.md`.

## Files Changed
[INSERT HERE: the list of files modified by the Implementer agent]

## Review Criteria
1. Architecture — VContainer DI, no singletons, interfaces only across modules
2. Naming — PascalCase types, _camelCase private fields, SCREAMING_SNAKE_CASE constants
3. Namespace — must be in Layer.Module format (e.g. Game.Concretes.Audio)
4. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
5. Events — IEvent structs past-tense with Event suffix, published via IEventBus
6. UniTask — no async void outside lifecycle, CancellationToken on every async method
7. Unity null safety — no ?. or is null on UnityEngine objects
8. BLOCKED tasks were not implemented

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 8 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Criterion 8 (BLOCKED tasks were not
implemented) must name the BLOCKED task IDs you checked.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** See the measurement
> note in `orchestrate.md` Step 3.

If **CHANGES NEEDED** → spawn a **coder** subagent to fix each issue, then re-run the reviewer (max 2 fix passes). After 2 failed passes → show remaining issues to the user.

If **APPROVED** → spawn a **committer** subagent:

```
You are a release engineer. Commit the implementation of a plan for a Unity project.

## Plan Implemented
[INSERT HERE: the full plan file path e.g. Docs/PLAN_audio.md]

## Files Changed
[INSERT HERE: the list of files modified by the Implementer agent]

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
