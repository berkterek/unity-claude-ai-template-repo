---
name: game-plan
description: Game completion planner for Unity projects. Reads GDD.md, TDD.md, and PROGRESS.md from the docs/ folder, scans the existing codebase to understand what's been built vs what's stub or missing, then produces a docs/0_MasterPlan.md master tracking file plus numbered module plan files (docs/1_SlingshotPhysics.md, docs/2_VacuumCollection.md, etc.). Each module plan follows the same quality as /create-plan output: Tasks with real file paths, numbered steps with checkboxes, Code Skeleton, Test Type decision, Acceptance Criteria, and parallel_group annotations for /orchestrate. Use this skill whenever: the project architecture/skeleton is done and gameplay needs to be planned module by module, the user says "plan the game", "create module plans", "make a master plan", "plan the implementation", "oyunu tamamla adimlarinla planla", "modüler planlar çıkar", or when they need to track which game systems are complete vs pending.
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

Spawn an **Explore** subagent:

```
You are a codebase analyst for a Unity project.

## Goal
Read the project's design documents and scan the code to understand what's done and what's missing.

## Documents to Read (in this order)
1. $GDD_PATH (default: docs/GDD.md) — full game design document
2. docs/TDD.md — technical design document
3. docs/PROGRESS.md — completed phases log
4. Run: git log --oneline -20

## Codebase Scan

**Step A — Graph check (primary source when available):**
Check if `.claude/graph/graph.json` exists:
- If YES and file modified within 24h → run these graph queries first (skip to Step B with graph as primary):
  - `cat .claude/graph/graph.json | python3 -c "import sys,json; g=json.load(sys.stdin); [print(n['id'],n.get('type',''),n.get('status','')) for n in g.get('nodes',[])]"` — list all classes with type/status
  - Look for nodes with status STUB, PARTIAL, or TODO comments
  - Extract all interfaces (type: Interface) from graph
  - Extract all events (type: Event) from graph
  - Extract all installers (type: Installer) and their registered services
  - Note: graph data supplements steps 5–8 below — use it to fill DONE/STUB/MISSING sections directly
- If NO or stale (> 24h) → skip to Step B using direct file scan only

**Step B — Direct file scan (always run; use as secondary if graph available):**
5. List all .cs files under Assets/_GameFolders/Scripts/Games/Concretes/
6. For each .cs file, read the first 40 lines (class declaration, fields, constructor, first method bodies)
   — assess: IMPLEMENTED (has real logic) | STUB (empty methods, TODO, placeholder returns) | PARTIAL (some logic, some stubs)
7. Check Assets/_GameFolders/Prefabs/ folder structure
8. Check Assets/_GameFolders/Scripts/Games/Abstracts/ for interfaces

## Output Format — return exactly these sections:

### GDD: Core Systems
List every distinct gameplay system from the GDD (numbered). Examples:
1. Slingshot mechanic
2. Vacuum collection
3. Combo system
...

### DONE — Phases from PROGRESS.md
List phases marked complete. For each: what .cs files are IMPLEMENTED (not stub).

### STUB/PARTIAL — Code exists but not working
For each stub file: filename, which methods are empty or placeholder.

### MISSING — No code at all
GDD systems that have zero corresponding implementation.

### Module Breakdown Proposal
Group all stub/partial/missing work into 6–10 logical modules. Order by dependency.
Each module:
- Number and name (e.g. "3. Combo System")  
- What GDD systems it covers
- Key files it will touch
- Size: Small (1–3 tasks) | Medium (4–6) | Large (7+)

Report only. Do NOT write plan tasks or implementation code.
```

---

## Step 2 — Analyzer

Read the Reader output. Extract:
- **Module list** with names, descriptions, and key files
- **Done summary** (for 0_MasterPlan context section)
- **Gap summary** (stubs + missing)

If the Reader missed obvious GDD systems, add them to the module list.

---

## Step 3 — Master Planner

Spawn a **Plan** subagent (model: opus):

```
You are a senior technical writer creating a master tracking plan for a Unity game project.

## Task
Create the content for docs/0_MasterPlan.md.

## Reader Findings
$READER_OUTPUT

## Module List
$MODULE_LIST

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

Each subagent gets this prompt (fill in the module-specific fields):

```
You are a senior technical writer creating a module execution plan for a Unity project.

## Module
Number: $MODULE_NUMBER
Name: $MODULE_NAME
Description: $MODULE_DESCRIPTION
Key files: $MODULE_KEY_FILES

## Reader Findings (relevant to this module)
$READER_FINDINGS_EXCERPT

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
# $MODULE_NUMBER — $MODULE_NAME

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

After all planners complete, spawn the reviewer:

```
Review these Unity project plan files for a game completion project.

## All Plan Files
$ALL_PLAN_CONTENTS

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
