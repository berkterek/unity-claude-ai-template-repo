---
name: game-plan
description: Game completion planner for Unity projects. Reads GDD.md, TDD.md, and PROGRESS.md from the docs/ folder, scans the existing codebase to understand what's been built vs what's stub or missing, then produces a docs/0_MasterPlan.md master tracking file plus numbered module plan files (docs/1_SlingshotPhysics.md, docs/2_VacuumCollection.md, etc.). Each module plan follows the same quality as /create-plan output: Tasks with real file paths, numbered steps with checkboxes, Code Skeleton, Test Type decision, Acceptance Criteria, and parallel_group annotations for /orchestrate. Use this skill whenever: the project architecture/skeleton is done and gameplay needs to be planned module by module, the user says "plan the game", "create module plans", "make a master plan", "plan the implementation", "complete the game with your steps", "extract modular plans", or when they need to track which game systems are complete vs pending.
---

# /game-plan — Game Completion Planner

Reads GDD + TDD + PROGRESS + codebase, then produces `0_MasterPlan.md` and numbered module plan files ready for `/orchestrate`.

## Usage

```
/game-plan
/game-plan docs/GDD.md    ← if GDD is at a non-default path
```

## Pipeline

```
[1] READER    → GDD + TDD + PROGRESS + .cs codebase scan
[2] ANALYZER  → gap analysis: done vs stub vs missing
[3] PLANNER   → 0_MasterPlan.md + numbered module plans (parallel, one agent per module)
[4] REVIEWER  → validates all plans
[5] SAVE      → writes all files to docs/
```

---

## Step 1 — Reader

**MANDATORY — do these two steps yourself before spawning any subagent:**

**Step A — Check graph age:**
```bash
python3 -c "import os,time; p='.claude/graph/graph.json'; print('missing' if not os.path.exists(p) else ('stale' if (time.time()-os.path.getmtime(p))/3600>24 else 'fresh'))"
```

**Step B — If fresh, extract graph data with python3:**
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

Keep this output in your active context — you will embed it into the Explore agent prompt below.

If the graph is missing or stale, skip Step B.

---

Now spawn an **Explore** subagent (`model: haiku`). Write the prompt yourself as prose, incorporating what you read from graph.json in Step B. The prompt must include:

```
You are a codebase analyst for a Unity project.

## Goal
Read the project's design documents and scan the code to understand what's done and what's missing.

## Documents to Read (in this order)
1. docs/GDD.md — full game design document
2. docs/TDD.md — technical design document
3. docs/PROGRESS.md — completed phases log
4. Run: git log --oneline -20

## Knowledge Graph Summary (pre-read by the orchestrator — use as primary inventory)
[INSERT HERE: a prose summary of what you read from graph.json — list class names, interfaces, events, installers. If graph was missing/stale, write "No graph data available."]

Use the graph summary above as the primary inventory. Cross-reference with the file scan below to determine STUB vs IMPLEMENTED (the graph has no explicit stub flag).

## Codebase Scan (always run; secondary if graph data present)
5. List all .cs files under Assets/_GameFolders/Scripts/Games/Concretes/
6. For each .cs file, read the **entire file** (not just the first 40 lines):
   - A file is IMPLEMENTED only if its public methods contain real logic (not just `throw new NotImplementedException()`, empty bodies, or single-line TODO returns)
   - A file is STUB if any core method is empty, returns a placeholder, or has a TODO comment
   - A file is PARTIAL if some methods are real and others are stubs — list which is which
7. Check Assets/_GameFolders/Prefabs/ folder structure
8. Check Assets/_GameFolders/Scripts/Games/Abstracts/ for interfaces

## Output Format — return exactly these sections:

### GDD: Core Gameplay Loop
Identify the ONE core gameplay loop from the GDD — the minimal sequence a player must complete to have a playable session. Example: "spawn → move → collect → score → end". This determines Module 1.

### GDD: All Systems
List every distinct gameplay system from the GDD (numbered), grouped:
- **Core loop systems** (required for any playable session)
- **Feature systems** (built on top of the core loop)
- **Polish/meta systems** (progression, monetization, analytics)

### DONE — Phases from PROGRESS.md
List phases marked complete. For each: what .cs files are IMPLEMENTED (confirmed by reading method bodies — not just class existence).

### STUB/PARTIAL — Code exists but incomplete
For each stub/partial file: filename + which specific methods are empty or placeholder.

### MISSING — No code at all
GDD systems (especially core loop systems) that have zero corresponding implementation.

### Module Breakdown Proposal
Group all stub/partial/missing work into modules. **MANDATORY ORDERING RULES:**

1. **Module 1 MUST deliver a playable core loop** — the minimal set of systems a player needs to complete one session. No feature modules before this exists.
2. **Each subsequent module must have all its dependencies in earlier modules** — if Module 3 needs a service from Module 2, that's fine; if it needs something from Module 5, reorder.
3. **Features that depend on core loop come after Module 1** — rockets, power-ups, skins, analytics are always later modules.
4. Order within a tier: by GDD priority / player-facing value (not alphabetically).

For each module:
- Number and name (e.g. "1. Core Movement & Collection")
- What GDD systems it covers
- Key files it will touch
- Dependencies: which earlier modules it requires
- Size: Small (1–3 tasks) | Medium (4–6) | Large (7+)

Report only. Do NOT write plan tasks or implementation code.
```

---

## Step 2 — Analyzer

Read the Reader output. Extract:
- **Module list** with names, descriptions, and key files
- **Done summary** (for 0_MasterPlan context section)
- **Gap summary** (stubs + missing)

**Mandatory checks before finalizing the module list:**

1. **Core loop check:** Does Module 1 deliver a fully playable session on its own (spawn → play → end)? If not, merge or reorder until it does.
2. **Dependency check:** For each module, verify every system it depends on exists in an earlier module. Reorder if not.
3. **Feature-before-foundation check:** If any feature module (power-up, skin, analytics) appears before the core loop module, move it after Module 1.
4. **Stub accuracy check:** Cross-reference the Reader's IMPLEMENTED claims against the actual method bodies it read. If a file was assessed without reading method bodies, mark it as UNKNOWN and flag it for manual verification.

If the Reader missed obvious GDD systems (especially core loop systems), add them to the module list — place them in Module 1 if they are core loop, later modules if they are features.

---

## Step 3 — Master Planner

Spawn a **Plan** subagent (model: opus). Write the prompt yourself as prose — embed the Explore agent's full output and the module list inline where indicated:

```
You are a senior technical writer creating a master tracking plan for a Unity game project.

## Task
Create the content for docs/0_MasterPlan.md.

## Reader Findings
[INSERT HERE: the full output from the Step 1 Explore subagent — GDD systems, DONE, STUB/PARTIAL, MISSING, Module Breakdown]

## Module List
[INSERT HERE: the numbered module list from Step 2 — name, description, key files, size for each module]

## Required Format

---
# 0 — Master Plan: [Game Title]

> **Status:** In Progress
> **Last Updated:** [today's date]
> **GDD:** [GDD version or date]

## Game Overview
[2-3 sentences: genre, core fantasy, one-line game loop from GDD]

## Module Completion Status

| # | Module | Plan File | Status | Priority | Notes |
|---|--------|-----------|--------|----------|-------|
| 1 | [Name] | [1_Name.md](1_Name.md) | ⏳ Pending | High | [key dependency or risk] |
| 2 | [Name] | [2_Name.md](2_Name.md) | ⏳ Pending | High | |
...

**Status legend:** ⏳ Pending · 🔄 In Progress · ✅ Done · 🚫 Blocked

## Architecture Stack (from TDD)
[Table or list: DI framework, event system, async, key packages, input]

## Dependency Order
[Numbered list: which modules must be done before others, with reason]

## Out of Scope (MVP)
[Items from GDD "Not Doing" or "Nice to Have" sections]

## How to Use These Plans
1. Pick the next Pending module from the table
2. Open its plan file (e.g. docs/1_Name.md)
3. Run `/orchestrate docs/1_Name.md` to implement it
4. When done, update Status to ✅ Done in this file
---

Return the full 0_MasterPlan.md content. Nothing else.
```

---

## Step 4 — Module Planners (Parallel)

For each module in the module list, spawn a **Plan** subagent (model: opus) simultaneously. All module planners run at the same time.

For each module, write the prompt yourself as prose — fill in the module's actual number, name, description, key files, and the relevant excerpt from the Reader output inline:

```
You are a senior technical writer creating a module execution plan for a Unity project.

## Module
[INSERT HERE: the module's number, name, description, key files, and size from the Step 2 module list]

## Reader Findings (relevant to this module)
[INSERT HERE: the portion of the Step 1 Explore output that relates to this module — relevant stubs, missing files, GDD systems it covers]

## Architecture Rules (non-negotiable)
- VContainer DI — no singletons. New services → ModuleInstaller → AppInstaller.asset
- IEventBus only for cross-module events — readonly struct + Event suffix + past tense
- UniTask — no coroutines. Every async method takes CancellationToken
- New Input System — InputView pattern. No legacy Input.GetKey/GetAxis
- sealed classes by default
- No new GameObject() anywhere in runtime code — instantiate from prefab only
- Zero heap allocation in Update/FixedUpdate

## Required File Format

---
# [module number] — [module name]

> **Version:** v1 — [today's date]
> **Status:** ⏳ Pending
> **Master Plan:** [0_MasterPlan.md](0_MasterPlan.md)
> **Scope:** [systems and files affected]

## Context
[2–3 paragraphs: what this module delivers, why it matters for the core game loop,
current state (what exists as stub, what's completely missing)]

## Goals
- [ ] Goal 1
- [ ] Goal 2

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task title | ⏳ Pending | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| path/to/File.cs | Add / Modify | what changes |

---

## Task 1 — [Title]

**Files:**
- `path/to/File.cs`

**Steps:**
1. [ ] Specific step
2. [ ] Specific step

**Test Type:** [see matrix below]

**Code Skeleton:**
```csharp
// Key method signatures and logic outline — not full implementation
// Use real class names from the codebase
```

**Acceptance Criteria:**
- Specific, testable criterion
- Another criterion

---
[repeat Task section for each task]

## Test Type Decision Matrix
Apply to the primary file for each task:

| Class type | Test Type |
|------------|-----------|
| Pure C# service (no UnityEngine) | EditMode |
| MonoBehaviour (no lifecycle needed) | EditMode |
| MonoBehaviour (needs Awake/OnEnable/Update) | PlayMode-Programmatic |
| Requires VContainer scope / scene wiring | PlayMode-Scene |
| LifetimeScope, ScriptableObject config, thin adapter | NoTest |

## Parallel Group Rules
- Tasks with no compile-time dependency on each other AND different output files → same parallel_group number
- If Task B references a type/interface introduced by Task A → Task B gets "—" (sequential after A)
- Tasks writing to the same file → always sequential ("—")

Return the full plan file content ONLY. No preamble or explanation.
```

---

## Step 5 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

After all planners complete, spawn the reviewer. Write the prompt yourself — embed the full content of every generated plan file inline where indicated:

```
Review these Unity project plan files for a game completion project.

## All Plan Files
[INSERT HERE: the full content of 0_MasterPlan.md followed by each module plan file, separated by "---"]

## Review Criteria
1. 0_MasterPlan: lists all modules? status table links match real filenames?
2. Module plans: every task has file path, numbered steps, code skeleton, test type, acceptance criteria?
3. Architecture: do proposed changes respect VContainer DI, IEventBus, UniTask, sealed class rules?
4. Coverage: does the module set together cover all GDD gameplay systems?
5. Ordering: no module plan references types or interfaces introduced by a later module?
6. Parallel groups: are they assigned correctly (no compile-time dependency within a group)?

Output: APPROVED — or — CHANGES NEEDED: [list each issue as: module file → what to fix]
```

If **CHANGES NEEDED** → fix only the flagged sections in the affected plan files. Re-review (max 2 passes).

---

## Step 6 — Save

Write all files:
- `docs/0_MasterPlan.md`
- `docs/1_[ModuleName].md` through `docs/N_[ModuleName].md`

Print:

```
## ✓ Game Plan Created

docs/0_MasterPlan.md  ← master tracking file

Module Plans:
  docs/1_[Name].md   — [one-line description]
  docs/2_[Name].md   — [one-line description]
  ...

Total: [N] module plans

To start implementing:
  /orchestrate docs/1_[FirstModule].md
```

$ARGUMENTS
