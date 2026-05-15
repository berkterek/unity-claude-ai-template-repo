# Complexity Scoring Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add complexity scoring + coder/unity-coder routing to the `orchestrate`, `scene-setup`, `migrate`, and `add-feature` commands.

**Architecture:** A `## Step 0 — Complexity Scoring` block is prepended to each command. Existing step numbers are not shifted — scoring is added as Step 0, continuing from Step 1 onward. Each command adjusts agent selection based on complexity score and target code type.

**Tech Stack:** Claude Code slash commands (`.claude/commands/`), existing scoring pattern borrowed from `implement.md` / `fix.md`.

---

## File Map

| File | Status | Change |
|------|--------|--------|
| `.claude/commands/orchestrate.md` | Modify | Add Step 0 scoring + agent routing |
| `.claude/commands/scene-setup.md` | Modify | Add Step 0 scoring + unity-coder-lite/unity-coder routing |
| `.claude/commands/migrate.md` | Modify | Add Step 0 scoring + test guard and unity-developer conditions |
| `.claude/commands/add-feature.md` | Modify | Add Step 0 scoring + interview length + coder routing |

---

## Task 1: `orchestrate.md` — Add Complexity Scoring

**Files:**
- Modify: `.claude/commands/orchestrate.md`

- [ ] **Step 1: Read the file**

```bash
cat .claude/commands/orchestrate.md | head -20
```

Expected: starts with `# Orchestrate — Automated WORKFLOW.md Executor`.

- [ ] **Step 2: Insert Step 0 block before the Initialization section**

Insert the following block immediately before the `## Initialization` line:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder/unity-coder → committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before executing any task, score the overall workflow complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Pure C# target → **coder** / Unity target → **unity-coder-lite** |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Pure C# target → **coder** / Unity target → **unity-coder** + unity-developer review after each task |

**Agent routing per task — decide before spawning:**

| Target location | Simple | Medium/Complex |
|-----------------|--------|----------------|
| `_Framework/`, `Abstracts/`, pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring | **unity-coder-lite** | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder-lite** | **unity-coder** |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [coder | unity-coder-lite | unity-coder] (per task)
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after the standard unity-reviewer step passes for each task, spawn a **unity-developer** subagent review pass before the committer.

---
```

- [ ] **Step 3: Update the coder spawn line in the Task Execution section**

In `### Task Execution`, find the prompt that spawns the coder agent. Add the following note immediately above the spawn prompt, replacing the hardcoded agent name with a score-based selection:

```markdown
**Coder agent:** Determine from Step 0 score and task target location (see routing table above).
```

- [ ] **Step 4: Verify the file**

```bash
grep -n "Step 0\|Complexity Scoring\|unity-coder-lite\|Agent routing" .claude/commands/orchestrate.md | head -10
```

Expected: Step 0 lines are visible.

---

## Task 2: `scene-setup.md` — Add Complexity Scoring

**Files:**
- Modify: `.claude/commands/scene-setup.md`

- [ ] **Step 1: Read the file**

```bash
cat .claude/commands/scene-setup.md | head -20
```

Expected: starts with `# /scene-setup`.

- [ ] **Step 2: Insert Step 0 block before the Pipeline section**

Insert the following block immediately before the `## Pipeline` line:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — unity-coder/unity-coder-lite → unity-setup → committer only. |
| `lean` | Standard pipeline. |
| `full` | Standard pipeline + unity-developer second reviewer always active. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the task complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single MonoBehaviour, no new interfaces, no DI wiring | **unity-coder-lite** |
| 0.4–0.6 | **Medium** | 2–4 scripts, new interface, or LifetimeScope installer | **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS, or Addressables | **unity-coder** + unity-developer review |

Scene setup always targets Unity/Mixed code — `coder` agent is never used here.

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single MonoBehaviour with no dependencies? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [unity-coder-lite | unity-coder]
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after unity-reviewer APPROVED, spawn a **unity-developer** subagent review pass before the committer.

---
```

- [ ] **Step 3: Update Step 1a — Coder spawn line**

Under `## Step 1a — Coder`, change the existing `Spawn a **coder** subagent` line to:

```markdown
Spawn the coder agent determined in Step 0 (**unity-coder-lite** for Simple, **unity-coder** for Medium/Complex) with this prompt:
```

- [ ] **Step 4: Verify the file**

```bash
grep -n "Step 0\|Complexity Scoring\|unity-coder-lite\|Review Mode" .claude/commands/scene-setup.md | head -10
```

Expected: Step 0 lines are visible.

---

## Task 3: `migrate.md` — Add Complexity Scoring

**Files:**
- Modify: `.claude/commands/migrate.md`

- [ ] **Step 1: Read the file**

```bash
cat .claude/commands/migrate.md | head -20
```

Expected: starts with `# /migrate`.

- [ ] **Step 2: Insert Step 0 block before the Pipeline section**

Insert the following block immediately before the `## Pipeline` line:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No test guard or unity-developer — migrator → committer only. |
| `lean` | Standard pipeline. |
| `full` | Standard pipeline + unity-developer second reviewer always active. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the migration complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Pipeline variant |
|-------|-------|---------|-----------------|
| 0.0–0.3 | **Simple** | Single file, mechanical substitution (e.g. one coroutine) | migrator/unity-migrator → reviewer → committer |
| 0.4–0.6 | **Medium** | Multiple files, interface changes, or VContainer rewiring | test guard → migrator/unity-migrator → reviewer → committer |
| 0.7–1.0 | **Complex** | Cross-module migration, ECS involvement, or Addressables | test guard → migrator/unity-migrator → unity-reviewer → unity-developer → committer |

**Migrator agent routing — decide before spawning:**

| Migration type | Agent |
|----------------|-------|
| Pure C# pattern (no Unity API: data classes, interfaces, services) | **migrator** |
| Unity-specific (coroutine→UniTask, singleton→VContainer, Input.GetKey→New Input System) | **unity-migrator** |

**Scoring signals:**
- Touches more than 5 files? +0.3
- Changes a public interface or adds IEventBus events? +0.2
- Involves ECS systems or Addressables? +0.3
- Single file, single pattern? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Migrator Agent: [migrator | unity-migrator]
Pipeline: [which variant]
Review Mode: [solo | lean | full]
```

---
```

- [ ] **Step 3: Make the test guard conditional for Simple mode**

Add the following note before the `## Step 1 — Test Guard` heading:

```markdown
> **Skip this step if complexity score is Simple (0.0–0.3) and review mode is not `full`.**
```

- [ ] **Step 4: Add the unity-developer step for Complex mode**

After the APPROVED log at the end of `## Step 3 — Reviewer`, add the following block:

```markdown
### unity-developer Pass (Complex only)

If complexity score ≥ 0.7 and review mode is `lean` or `full`: after unity-reviewer reports APPROVED, spawn a **unity-developer** subagent with this prompt:

```
Review this migration for Unity-specific correctness.

## Migration Task
$MIGRATION_DESCRIPTION

## Files Changed
$MIGRATOR_OUTPUT

## Review Criteria (from .claude/agents/unity-developer.md)
- Hot-path allocations introduced?
- Draw call regressions?
- ECS safety (structural changes via ECB)?
- Addressables handle lifecycle correct?
- Prefab structure intact (root=logic / Body=visual)?

## Output Format
APPROVED — migration is correct.

CHANGES NEEDED:
- [file:line] Issue and fix.
```

If CHANGES NEEDED → spawn **unity-migrator** to fix, then re-run unity-developer (max 2 passes).
```

- [ ] **Step 5: Verify the file**

```bash
grep -n "Step 0\|Complexity Scoring\|unity-migrator\|Skip this step" .claude/commands/migrate.md | head -10
```

Expected: Step 0 and migrator routing lines are visible.

---

## Task 4: `add-feature.md` — Add Complexity Scoring

**Files:**
- Modify: `.claude/commands/add-feature.md`

- [ ] **Step 1: Read the file**

```bash
cat .claude/commands/add-feature.md | head -20
```

Expected: starts with `# Add Feature Agent`.

- [ ] **Step 2: Insert Step 0 block before the Initialization section**

Insert the following block immediately before the `## Initialization` line:

```markdown
## Step 0 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder/unity-coder → committer only. |
| `lean` | Standard pipeline. |
| `full` | Standard pipeline + unity-developer second reviewer always active. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Score the feature complexity on a 0.0–1.0 scale **after** reading GDD/TDD/WORKFLOW in Initialization:

| Score | Label | Signals | Interview | Coder Agent |
|-------|-------|---------|-----------|-------------|
| 0.0–0.3 | **Simple** | Single class addition, no new interfaces, no events | 3 targeted questions | Pure C# → **coder** / Unity → **unity-coder-lite** |
| 0.4–0.6 | **Medium** | New interface, event bus change, or 2–4 classes | deep-interview (full) | Pure C# → **coder** / Unity → **unity-coder** |
| 0.7–1.0 | **Complex** | New module, ECS, Addressables, cross-system events | deep-interview (full) | Pure C# → **coder** / Unity → **unity-coder** + unity-developer |

**Agent routing — decide before spawning:**

| Target location | Simple | Medium/Complex |
|-----------------|--------|----------------|
| `_Framework/`, `Abstracts/`, pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring | **unity-coder-lite** | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder-lite** | **unity-coder** |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Interview: [3 questions | deep-interview]
Coder Agent: [coder | unity-coder-lite | unity-coder]
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after unity-reviewer APPROVED, spawn a **unity-developer** subagent review pass before the committer.

---
```

- [ ] **Step 3: Update the interview condition in Step 1**

In `### Step 1: Understand the Feature`, replace the deep-interview call with:

```markdown
> **Interview depth from Step 0:**
> - Simple (0.0–0.3): Ask only 3 targeted questions (mechanics, edge cases, acceptance criteria).
> - Medium/Complex (0.4–1.0): Invoke the **deep-interview** skill — gates requirements through 5 dimensions, requires score 6/10 before implementation.
```

- [ ] **Step 4: Verify the file**

```bash
grep -n "Step 0\|Complexity Scoring\|unity-coder-lite\|Interview depth" .claude/commands/add-feature.md | head -10
```

Expected: Step 0 and Interview lines are visible.

---

## Self-Review Checklist

- [x] Spec coverage: orchestrate ✓, scene-setup ✓, migrate ✓, add-feature ✓
- [x] Coder/unity-coder routing table present for all 4 commands
- [x] Test guard skip condition present in migrate (Simple mode)
- [x] unity-developer pass present in migrate (Complex mode)
- [x] Interview length tied to scoring in add-feature
- [x] No placeholders — all steps contain concrete content
- [x] Scoring signals consistent across all commands
