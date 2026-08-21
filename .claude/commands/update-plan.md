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
[0] Knowledge Graph Preload → [1] ANALYZER → [2] PLANNER → [3] REVIEWER → [4] SAVE → [5] IMPLEMENTER
```

---

## Step 0 — Knowledge Graph Preload

Before spawning the Analyzer, check whether the knowledge graph can accelerate this update.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, proceed to Step 1 (file-scan behavior, unchanged).

If it is a candidate, verify the graph is **usable** (fresh AND non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, fall back to file scan. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated update. Falling back to file scan.
  ```
- Otherwise (fresh AND non-empty) → build `GRAPH_CONTEXT` from the graph inventory:

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

Keep this output in your active context as `GRAPH_CONTEXT`. You will embed it into the Step 1 Analyzer subagent prompt below. When `GRAPH_CONTEXT` is empty, the analysis phase behaves exactly as before — no regression.

---

## Step 1 — Analyzer

Spawn an **Explore** subagent (`model: haiku`) with this prompt:

```
You are a codebase analyst for this Unity project.

## Goal
Analyze the existing plan and relevant source files to understand:
1. What is already implemented (match plan tasks to actual code)
2. What is missing or broken (gaps between plan and code)
3. Concrete technical findings the planner needs to write precise tasks

## Plan File
[INSERT HERE: the plan file path from the /update-plan argument]

## Change Request
[INSERT HERE: the change description from the /update-plan argument]

## Knowledge Graph (class/interface/event/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0 — if empty, write "No usable graph — scan source files directly."]

## What to Read
1. The plan file listed above
2. Recent git log: `git log --oneline -10`
3. Source files relevant to the change request — **read every file the change request implies modifying, before anything else**
4. Any relevant .claude/skills/learned/ files

## Graph-First Instruction
If a knowledge graph inventory is provided above (non-empty), use it FIRST — do not re-scan folders for what it already answers:
- "who implements interface X" → the graph's implements/interfaces data
- "who publishes/subscribes to event E" → the graph's pub/sub data
- "what does installer I register" / "what is class C's blast radius" → the graph's registrations / dependencies
Only read source files for the specific detail (exact line, logic body) the graph cannot provide. If the graph inventory is empty (or absent), fall back to scanning the codebase for files, classes, and patterns relevant to the change request exactly as below.

## Modify Pre-Read (MANDATORY)
From the plan's File Map and the change request, identify every existing file that will be modified.
Read each of those files now. Note:
- Current method signatures the planner will call or override
- Existing field names (avoid renaming without `[FormerlySerializedAs]`)
- Subscribe/Unsubscribe pairs already in place
- Namespace collision risk: does the domain name match a UnityEngine type? (Camera, Random, Object, Input, Physics…)

## Scene & Prefab Pre-Scan (if change touches UI, scene objects, or VContainer registration)
Graph age check: read `.claude/graph/graph.json` → `metadata.generated_at`. If < 24h:
- Read `codebase.scenes[].gameobjects[]` — flag any `active: false` GO that a VContainer registration depends on
- Read `codebase.prefabs[]` — check components and isVariant for affected prefabs
- Flag any `duplicate: true` GO entries

If graph is stale → note "unverified — rebuild graph with Unity Editor open" in Technical Notes.

## Output Format
### Already Implemented
- List tasks/steps from the plan that are confirmed in code

### Scene / Prefab State (if applicable)
- `active: false` GOs relevant to VContainer registrations
- Duplicate GOs found
- Prefab variants affected

### Gaps Found
- For each gap: what is missing, which file it belongs to, why it matters

### Technical Notes for Planner
- Concrete findings (method signatures, field names, patterns) the planner needs
- Constraints or gotchas discovered in the code
- VContainer scene preconditions: for every `RegisterComponentInHierarchy<T>()` the update will add, state: "GO must be active at registration time"

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
[INSERT HERE: the plan file path from the /update-plan argument]

## Change Request
[INSERT HERE: the change description from the /update-plan argument]

## Analyzer Findings
[INSERT HERE: the full output from the Analyzer agent]

## Test Type Decision Matrix

For each new task, apply this decision matrix to its **primary file** to fill the `**Test Type:**` field:

**Path-based (fastest):**
| Path contains | Decision |
|---------------|----------|
| `Games/Abstracts/` or `Games/Concretes/` | **EditMode** |
| `Games/Ecs/Systems/` | **PlayMode-ECS** |
| `Games/Ecs/Components/` or `Games/Ecs/Authorings/` | **NoTest** |
| `_Framework/` | **EditMode** |
| `Editor/` | **NoTest** |

**Class type fallback:**
| Class type | Decision |
|------------|----------|
| Extends `LifetimeScope` | **NoTest** |
| `MonoBehaviour` with no logic (thin adapter) | **NoTest** |
| `MonoBehaviour` WITH logic | **PlayMode-Scene** |
| `ISystem` or `SystemBase` | **PlayMode-ECS** |
| `IComponentData` struct or `Baker<T>` | **NoTest** |
| Pure C# service/model/util | **EditMode** |
| `ScriptableObject` config | **NoTest** |

## Parallel Group Assignment

After writing all new tasks, analyze dependencies across ALL tasks (existing + new) and update the `parallel_group` column in the Status table:

**Rules:**
1. **Compile-time dependency (most important):** If Task B's code references a type, interface, or method that Task A *introduces* (even in a different file), Task B MUST be sequential after Task A. Different files ≠ safe to parallelize when there is a type dependency.
   - Example: Task A creates `IGameFlowService.cs`, Task B creates `PauseInputHandler.cs` that calls `IGameFlowService.ResumeGame()` → Task B is sequential after Task A.
2. **File write conflict:** If two tasks write to the same file → they MUST be sequential.
3. **Independent:** If two tasks write to entirely different files AND neither references types introduced by the other → assign the same `parallel_group` number.
4. Tasks with no parallel candidate get `—` (sequential by default).
- If the Status table has no `parallel_group` column yet, add it.

**When orchestrate runs this plan:** tasks in the same `parallel_group` will spawn simultaneously (complexity ≥ 0.4). Tasks with `—` run sequentially.

## Instructions
1. Read the existing plan file carefully
2. Add a new revision note at the top (vN+1 format, today's date)
3. Update the status table if any phases changed status (add `parallel_group` column if missing)
4. Add new Task sections at the bottom (Task N+1, Task N+2, etc.) with:
   - Files to modify (exact paths)
   - Numbered steps with [ ] checkboxes
   - **Test Type:** field — apply the decision matrix below to the primary file for each new task (EditMode | PlayMode-ECS | PlayMode-Scene | NoTest)
   - Code snippets showing method signatures and key logic (not full implementations)
   - Clear acceptance criteria
5. Keep existing tasks and content untouched — only append

## Output
Return the FULL updated plan file content.
Do NOT truncate existing content.
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

Review the following plan update for a Unity project.

## Plan File
[INSERT HERE: the plan file path from the /update-plan argument]

## Change Request
[INSERT HERE: the change description from the /update-plan argument]

## Updated Plan Content
[INSERT HERE: the full updated plan content from the Planner agent]

## Review Criteria
1. Scope — do new tasks stay within the intended boundaries?
2. File paths — are all referenced files real paths in the project?
3. Task completeness — do steps have clear acceptance criteria?
4. No duplicates — do new tasks overlap with already-implemented work?
5. Revision note — is it present and correctly formatted?

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 5 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <plan section, or file:line for criterion 2> | <evidence>

Criterion 2 (file paths are real) may only be CONFIRMED after you have actually
verified each path exists on disk — state how you checked. Criterion 4 (no duplicates)
must cite what you searched, not an assumption.

Then, for a plan that has any GAP:

CHANGES NEEDED:
- [section] Issue and fix.

Revision classification (add one line after CHANGES NEEDED):
REVISION_TYPE: INCREMENTAL   ← small fixes, no structural changes
REVISION_TYPE: BREAKING      ← removes/renames existing tasks, changes module structure, or contradicts a previous plan decision
```

If Codex is unavailable → fall back to a **general-purpose** subagent (`model: opus` — plan review is lead-tier) with the same prompt.

If reviewer reports **CHANGES NEEDED**:

- **REVISION_TYPE: INCREMENTAL** → automatically re-run the pipeline (no user prompt):
  1. Re-spawn the **Analyzer** with original change request + reviewer feedback appended.
  2. Re-spawn the **Planner** (opus) with original inputs + analyzer output + reviewer feedback.
  3. Re-spawn the **Reviewer** on the new planner output.

- **REVISION_TYPE: BREAKING** → stop immediately and show **BREAKING_REVISION_GATE**.

  Show the BREAKING_REVISION_GATE block from `.claude/docs/director-gates.md`, passing the plan version as `v[N]` and the full CHANGES NEEDED list. Wait for user input before continuing.

  This command's branches:
  - `re-research` → re-spawn the **Analyzer** with expanded scope, then re-plan and re-review
  - `accept` → proceed with the breaking revision (user accepts risk)
  - `stop` → abort, do not save

Repeat INCREMENTAL passes up to **2 more times** (3 total reviewer passes).

After 3 failed INCREMENTAL passes → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`) with
`$WHAT_WAS_RETRIED` = the plan reviewer loop, `$N` = 3, `$PASS_TYPE` = reviewer, and all
accumulated feedback listed. Fill `Skipping ships:` from that feedback — `skip` saves a plan
carrying known defects, and every task downstream of a wrong path inherits it. `skip` saves
the last planner output as-is; `stop` saves nothing.

---

## Step 4 — Save

After APPROVED → write the updated content to `[INSERT HERE: the plan file path from the /update-plan argument]`.

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
[INSERT HERE: the plan file path from the /update-plan argument]

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

After implementer finishes → spawn the **Reviewer** using priority order (codex:codex-rescue → claude) with:

```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review the implementation of the following plan.

## Plan File
[INSERT HERE: the plan file path from the /update-plan argument]

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
2. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
3. UniTask — no async void outside lifecycle, CancellationToken on every async method
4. Unity null safety — no ?. or is null on UnityEngine objects
5. BLOCKED tasks were not implemented

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 5 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Criterion 5 (BLOCKED tasks were not
implemented) must name the BLOCKED task IDs you checked.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** See the measurement
> note in `orchestrate.md` Step 3.

If **CHANGES NEEDED** → spawn a **coder** subagent to fix each issue, then re-run the reviewer (max 3 fix passes — reviewer-verdict bound, see `.claude/docs/director-gates.md` → Retry and Pass Limits). After 3 failed passes → show remaining issues to the user at QUALITY_GATE.

If **APPROVED** → spawn a **committer** subagent:

```
You are a release engineer. Commit the implementation of a plan.

## Plan Implemented
[INSERT HERE: the plan file path from the /update-plan argument]

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
## ✓ Plan Updated & Implemented
File: [plan file path]
Changes: [one-line summary]
Reviewer: [Codex | Claude] — APPROVED
Commit: [hash] — [message]   (only if implemented)
```

$ARGUMENTS
