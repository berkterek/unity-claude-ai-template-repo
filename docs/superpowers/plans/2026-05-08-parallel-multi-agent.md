# Parallel Multi-Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add parallel agent execution to research phases (`search`, `fix`, `fix-deep`) and orchestrate task groups.

**Architecture:** Two independent parts — Part A restructures research phases to spawn Explore + unity-scout simultaneously (complexity ≥ 0.4), merging structured outputs before review. Part B adds `parallel_group` support to `orchestrate.md` so WORKFLOW.md-annotated tasks run simultaneously with conflict detection.

**Tech Stack:** Claude Code slash commands (`.claude/commands/`), existing agents (Explore, unity-scout, unity-fixer)

---

## File Map

| File | Status | Change |
|------|--------|--------|
| `.claude/commands/search.md` | Modify | Phase 1: restructure to true parallel spawn (Explore + unity-scout from main pipeline, not nested) |
| `.claude/commands/fix.md` | Modify | Step 1: add parallel Explore + unity-scout when complexity ≥ 0.4 |
| `.claude/commands/fix-deep.md` | Modify | Step 3: add parallel unity-scout alongside unity-fixer evidence collection when complexity ≥ 0.4 |
| `.claude/commands/orchestrate.md` | Modify | Task Execution: add parallel_group check, conflict detection, simultaneous spawn |

---

## Part A: Research Parallelism

---

### Task 1: `search.md` — True Parallel Phase 1

Currently unity-scout is spawned as an instruction *inside* the Explore agent prompt (instruction #2). This makes it nested, not truly parallel. Restructure to spawn both agents from the main pipeline simultaneously.

**Files:**
- Modify: `.claude/commands/search.md`

- [ ] **Step 1: Read current Phase 1 section**

```bash
grep -n "Phase 1\|Spawn an\|unity-scout\|Capture output" .claude/commands/search.md
```

Expected: lines ~26-68 show Explore spawn with unity-scout as nested instruction #2.

- [ ] **Step 2: Replace Phase 1 with parallel spawn pattern**

Replace the entire `## Phase 1 — Research` section (from `## Phase 1 — Research` to `Capture output as...`) with:

```markdown
## Phase 1 — Research

**If complexity score ≥ 0.4 (Medium/Complex):** Spawn **Explore** and **unity-scout** simultaneously. Proceed once both complete.

**If complexity score < 0.4 (Simple):** Spawn Explore only — skip unity-scout.

### Explore Agent Prompt

```
You are a research agent investigating a query in a Unity project.

QUERY: $QUERY
ITERATION: $ITERATION / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK

## Instructions

1. Search the codebase for files, classes, and patterns relevant to the query.
   - Use file reads, grep patterns, and directory listings.
   - Focus on: .claude/rules/, _Framework/, _GameFolders/Scripts/Games/
2. If the query mentions a Unity API, package name, or error message → use web search for Unity documentation or known issues.
3. If PREVIOUS_REVIEWER_FEEDBACK is not empty → specifically address the gap flagged. Don't repeat the same evidence.

## Output Format (REQUIRED)

CODEBASE_FINDINGS:
- [file path or pattern] — [how it supports the query]
- [...]

PROPOSED_SOLUTION:
[Concrete steps. Reference specific files and classes. No vague language.]

CONFIDENCE: low | medium | high
```

### unity-scout Agent Prompt (complexity ≥ 0.4 only)

```
You are a Unity risk analyst. Scan the project for Unity-specific issues related to the following query.

QUERY: $QUERY

## Instructions

Investigate for Unity-specific risks:
- VContainer registration gaps or missing .As<IInterface>() calls
- UniTask async methods missing CancellationToken
- Input System lifecycle violations (missing Enable/Disable in OnEnable/OnDisable)
- ECS structural changes outside EntityCommandBuffer
- Addressables handles not released in Dispose()
- Unity null check violations (?. or is null on UnityEngine objects)

## Output Format (REQUIRED)

UNITY_RISKS:
- [risk type] — [file:line] — [description]
OR: UNITY_RISKS: none
```

### Merge (after both agents complete)

Synthesize into unified research output:

```
COMBINED_ROOT_CAUSE: [one sentence — synthesize CODEBASE_FINDINGS + UNITY_RISKS]

EVIDENCE:
- [from CODEBASE_FINDINGS]
- [from UNITY_RISKS if any]

PROPOSED_SOLUTION: [from Explore, refined with any Unity risk findings]

CONFIDENCE: [take the lower of the two if they differ]
```

Capture as `$ROOT_CAUSE`, `$EVIDENCE`, `$PROPOSED_SOLUTION`, `$CONFIDENCE`.

---
```

- [ ] **Step 3: Verify the change**

```bash
grep -n "simultaneously\|CODEBASE_FINDINGS\|UNITY_RISKS\|Merge\|complexity ≥ 0.4" .claude/commands/search.md | head -10
```

Expected: all four terms appear.

---

### Task 2: `fix.md` — Parallel Research in Step 1

Step 1 (Debugger) currently spawns only unity-fixer. When complexity ≥ 0.4, also spawn unity-scout in parallel to catch Unity-specific risks the debugger might miss.

**Files:**
- Modify: `.claude/commands/fix.md`

- [ ] **Step 1: Read current Step 1 section**

```bash
sed -n '62,100p' .claude/commands/fix.md
```

Expected: `## Step 1 — Debugger` spawns unity-fixer with root cause analysis prompt.

- [ ] **Step 2: Add parallel unity-scout note after the Step 1 heading**

Find `## Step 1 — Debugger` and insert immediately after the heading:

```markdown
**If complexity score ≥ 0.4:** Spawn **unity-fixer** and **unity-scout** simultaneously. Proceed once both complete.

**If complexity score < 0.4 (Simple):** Spawn unity-fixer only — skip to Step 2 if Simple bypasses debugger.
```

- [ ] **Step 3: Add unity-scout prompt after the unity-fixer prompt block**

After the unity-fixer prompt's closing ` ``` ` and before `Show the debugger output to the user`, insert:

```markdown
### unity-scout Agent Prompt (complexity ≥ 0.4 only)

```
You are a Unity risk analyst. While the debugger investigates the bug, scan in parallel for Unity-specific risk patterns.

BUG: $BUG_DESCRIPTION

## Instructions

Scan for Unity-specific patterns that could cause or contribute to this bug:
- VContainer registration gaps or scope hierarchy issues
- UniTask async methods missing CancellationToken or using async void
- Input System lifecycle violations (missing Enable/Disable)
- ECS structural changes outside EntityCommandBuffer
- Addressables handles not released
- Unity null check violations (?. or is null on UnityEngine objects)
- Missing [Inject] Construct() methods on MonoBehaviours

## Output Format (REQUIRED)

UNITY_RISKS:
- [risk type] — [file:line] — [description]
OR: UNITY_RISKS: none
```

### Merge (after both agents complete)

Combine into unified debugger output before showing to user:

```
ROOT CAUSE: [from unity-fixer]

AFFECTED FILES:
- [from unity-fixer]

REPRODUCTION PATH:
[from unity-fixer]

UNITY_RISKS (parallel scan):
[from unity-scout, or "none"]
```
```

- [ ] **Step 4: Verify the change**

```bash
grep -n "simultaneously\|UNITY_RISKS\|parallel scan\|unity-scout" .claude/commands/fix.md | head -10
```

Expected: all terms appear.

---

### Task 3: `fix-deep.md` — Parallel unity-scout in Step 3

Step 3 (Evidence Collection) spawns unity-fixer for MCP log reading. Add parallel unity-scout for static risk scan — runs while unity-fixer waits for log output.

**Files:**
- Modify: `.claude/commands/fix-deep.md`

- [ ] **Step 1: Find Step 3 heading line number**

```bash
grep -n "Step 3 — Evidence Collection\|Then spawn a \*\*unity-fixer" .claude/commands/fix-deep.md | head -5
```

Note the line numbers.

- [ ] **Step 2: Add parallel spawn note after Step 3 heading**

After `## Step 3 — Evidence Collection (Post-Injection)` and the print/wait block, before `Then spawn a **unity-fixer** subagent`, insert:

```markdown
**If complexity score ≥ 0.4:** Spawn **unity-fixer** (MCP log collection) and **unity-scout** (static risk scan) simultaneously. Both complete before proceeding to Step 4.

**If complexity score < 0.4:** Spawn unity-fixer only.
```

- [ ] **Step 3: Add unity-scout prompt after the unity-fixer prompt block in Step 3**

After the unity-fixer prompt's closing ` ``` ` and before the `If **NO_EVIDENCE**` block, insert:

```markdown
### unity-scout Agent Prompt (complexity ≥ 0.4 only, runs in parallel with unity-fixer)

```
You are a Unity risk analyst. While evidence logs are being collected, scan the codebase for Unity-specific patterns related to this bug hypothesis.

HYPOTHESIS: $HYPOTHESIS

## Instructions

Scan for patterns that could confirm or refute the hypothesis:
- VContainer registration and scope hierarchy
- UniTask cancellation and lifecycle
- ECS structural change patterns
- Input System Enable/Disable lifecycle
- Addressables handle management
- Unity null semantics (?. vs == null)

## Output Format (REQUIRED)

STATIC_EVIDENCE:
- [file:line] — [how this supports or refutes the hypothesis]
OR: STATIC_EVIDENCE: none
```

After both agents complete, append unity-scout findings to the evidence:
```
EVIDENCE LOGS: [from unity-fixer]
STATIC_EVIDENCE: [from unity-scout]
```
Pass both to Step 4 — Evidence Gate.
```

- [ ] **Step 4: Verify the change**

```bash
grep -n "simultaneously\|STATIC_EVIDENCE\|unity-scout\|parallel" .claude/commands/fix-deep.md | head -10
```

Expected: all terms appear.

---

## Part B: Orchestrate Task Parallelism

---

### Task 4: `orchestrate.md` — parallel_group Support

**Files:**
- Modify: `.claude/commands/orchestrate.md`

- [ ] **Step 1: Find Task Execution section**

```bash
grep -n "Task Execution\|for each task\|in order\|parallel_group" .claude/commands/orchestrate.md | head -10
```

Expected: `### Task Execution (for each task in the phase, in order)` around line 97.

- [ ] **Step 2: Replace "for each task in the phase, in order" heading with parallel-aware version**

Change:

```markdown
### Task Execution (for each task in the phase, in order)
```

To:

```markdown
### Task Execution

Before executing tasks in a phase, check for `parallel_group` annotations in WORKFLOW.md:

**If no tasks have `parallel_group`:** Execute all tasks sequentially (existing behavior).

**If tasks have `parallel_group` AND complexity score ≥ 0.4:**
1. Group tasks by their `parallel_group` number. Tasks without a group number are sequential.
2. **Conflict check:** For each group, read each task's `outputs` field. If two tasks in the same group list the same output file → demote the later task to sequential and warn:
   ```
   ⚠ PARALLEL CONFLICT: [T1] and [T2] both write to [file]
   [T2] demoted to sequential. Running [T1] first.
   ```
3. Execute tasks in the same group simultaneously. Each spawns its own full pipeline (test-writer → coder → verifier → reviewer).
4. Wait for all tasks in the group to complete before starting the next group or sequential task.
5. If any task in a group fails → stop the entire group. Report all failures. Do not proceed until user resolves.
6. Commit all group outputs in a single commit after the group completes.

**If complexity score < 0.4:** Ignore `parallel_group` — run all tasks sequentially.

---

#### Sequential Task Execution (for each task without parallel_group, in order)
```

- [ ] **Step 3: Add parallel_group field to the task announce block**

Find the `**Announce the task:**` block and update it to show parallel_group if present:

```markdown
**Announce the task:**
```
### [P{phase}.T{task}] [Task Title]
Type: [type] | Agent: [agent type] | Complexity: [S/M/L/XL] | Group: [parallel_group or "sequential"]
Inputs: [list]
Outputs: [list]
```
```

- [ ] **Step 4: Verify the change**

```bash
grep -n "parallel_group\|Conflict check\|simultaneously\|demoted\|Group:" .claude/commands/orchestrate.md | head -10
```

Expected: all terms appear.

---

## Self-Review Checklist

- [x] Spec coverage: Research parallelism (search ✓, fix ✓, fix-deep ✓), orchestrate parallel_group ✓, conflict detection ✓, complexity gate ✓, merge format ✓
- [x] No placeholders — all prompt blocks are complete
- [x] Consistent terminology: `CODEBASE_FINDINGS`, `UNITY_RISKS`, `STATIC_EVIDENCE`, `parallel_group` used consistently across all tasks
- [x] Complexity gate (≥ 0.4) applied in all 4 tasks
