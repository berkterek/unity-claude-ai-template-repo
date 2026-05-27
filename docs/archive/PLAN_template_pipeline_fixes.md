# PLAN — Template Pipeline Structural Fixes (F1–F5)

> **Version:** v1 — 2026-05-23
> **Status:** Active
> **Scope:** `.claude/commands/plan-workflow.md`, `.claude/commands/orchestrate.md` (template repo only — no C# code touched)

## Context

The Nile Hole Sphere game was built end-to-end through the `/plan-workflow` → `/orchestrate` pipeline in this template. All six phases of the generated `WORKFLOW.md` were marked complete by the pipeline, yet the game still required ~50 follow-up fix commits before it actually ran. A post-mortem traced every one of those follow-ups back to **structural gaps in the pipeline commands themselves**, not to coder/reviewer mistakes.

Five gaps were identified:

- **F1 — No cycle detection** in `plan-workflow.md` Step 1 (Dependency Graph). The planner emits dependency graphs with cycles; downstream phases then deadlock or get silently linearized.
- **F2 — No Play Mode entry / VContainerException scan** in `orchestrate.md` Step 3.5 Step C (Bounded Verification). The current text says "Quick scan" and never enters Play Mode, so DI-binding-missing runtime errors slip past the green checkmark.
- **F3 — No architecture drift / ADR rule** in `orchestrate.md` Step 2 Coder Rules and Step 3 Reviewer Criteria. Coders silently add new singletons, event channels, or folder layouts that contradict the TDD.
- **F4 — No task atomicity gate** in `plan-workflow.md` Step 3 (Task Specification). XL tasks slip through without being split; one agent then runs out of context mid-task.
- **F5 — No testing-capability preflight** in `plan-workflow.md` Initialization. When tests are disabled in the project, the pipeline scaffolds test tasks that go nowhere and removes the only safety net that catches the other four bugs.

This plan applies five **additive, surgical text insertions** to the two existing command files. No restructuring, no behaviour changes outside the new gates. Each gate is labelled **BLOCKING** (pipeline must stop) or **WARNING** (pipeline continues but logs) so downstream agents know how to react.

## Goals

- [ ] F1 — Add a BLOCKING cycle-detection gate to `plan-workflow.md` Step 1 right after "Identify the critical path".
- [ ] F2 — Replace the "Quick scan" sentence in `orchestrate.md` Step 3.5 Step C with explicit Play Mode entry plus a `VContainerException` / `NullReferenceException` console-error pattern check.
- [ ] F3a — Add a BLOCKING architecture-drift rule to `orchestrate.md` Step 2 Coder Rules block.
- [ ] F3b — Add a matching architecture-drift criterion (#10) to `orchestrate.md` Step 3 Reviewer Criteria list.
- [ ] F4 — Add a Task Atomicity Gate to `plan-workflow.md` Step 3 right after the task spec field list.
- [ ] F5 — Add a testing-capability preflight step between current Initialization step 4 (read CLAUDE.md) and step 5 (Codebase Pre-Scan) in `plan-workflow.md` — renumber old 5→6, old 6→7.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | F1 — cycle detection gate in `plan-workflow.md` Step 1 | ⏳ Pending | A |
| 1 | F2 — Play Mode + error scan in `orchestrate.md` Step 3.5 Step C | ⏳ Pending | B |
| 2 | F3a — architecture-drift rule in `orchestrate.md` Step 2 Coder Rules | ⏳ Pending | — |
| 2 | F3b — architecture-drift criterion #10 in `orchestrate.md` Step 3 Reviewer | ⏳ Pending | — |
| 3 | F4 — Task Atomicity Gate in `plan-workflow.md` Step 3 | ⏳ Pending | — |
| 3 | F5 — testing-capability preflight in `plan-workflow.md` Initialization | ⏳ Pending | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/commands/plan-workflow.md` | Edit (additive) | Three insertions: F1 (after Step 1 critical-path bullet), F4 (after Step 3 field list), F5 (between Initialization step 4 and step 5) |
| `.claude/commands/orchestrate.md` | Edit (additive) | Three insertions: F2 (replace Step 3.5 Step C "Quick scan" line), F3a (append to Step 2 Coder Rules), F3b (append to Step 3 Reviewer Criteria) |
| `Docs/PLAN_template_pipeline_fixes.md` | Create | This plan file. |

---

## Task F1 — Add Cycle Detection Gate to plan-workflow.md Step 1

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/plan-workflow.md`

**Insertion Point:**
Section `### Step 1: Dependency Graph`. Immediately **after** the bullet:
`- Identify the critical path (longest chain of sequential dependencies)`

**Steps:**
1. [ ] Open `plan-workflow.md`.
2. [ ] Locate the exact line `- Identify the critical path (longest chain of sequential dependencies)` in `### Step 1: Dependency Graph`.
3. [ ] Insert the following block immediately after that line (preserve the leading blank line):

```markdown

**Cycle Detection (BLOCKING).** After building the dependency graph and before defining phases, run a cycle check:

1. Treat every deliverable as a node and every dependency as a directed edge.
2. Run a depth-first traversal from each unvisited node, tracking the current path stack.
3. If any edge points to a node already on the path stack → a cycle exists.

If one or more cycles are found:
- List every cycle as `A → B → C → A`.
- Print:
  ```
  ⛔ BLOCKED at Step 1 (Dependency Graph): cycles detected.
  [paste cycle list]
  Resolve by inverting one dependency per cycle (extract an interface, hoist shared types into a lower assembly, or split a class) before continuing.
  ```
- **Do NOT proceed to Step 2.** The user must restructure the TDD or task list.

If zero cycles are found, log:
```
Cycle check: 0 cycles across N nodes / M edges — OK.
```
and continue to Step 2.
```

4. [ ] Save. Confirm `### Step 2: Phase Definition` still starts immediately after the new block.

**Test Type:** NoTest

**Acceptance Criteria:**
- The phrase `**Cycle Detection (BLOCKING).**` appears exactly once in `plan-workflow.md`.
- The string `⛔ BLOCKED at Step 1 (Dependency Graph): cycles detected.` appears exactly once.
- The original line `- Identify the critical path (longest chain of sequential dependencies)` is still present and unchanged.
- `### Step 2: Phase Definition` heading still follows the new block.
- `git diff` shows additions only (zero deletions) on this file for this task.

---

## Task F2 — Replace "Quick scan" in orchestrate.md Step 3.5 Step C

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/orchestrate.md`

**Insertion Point:**
Inside `Step 3.5 — Bounded Verification`, sub-section `### Step C — Unity-Specific Issues (only if Steps A and B pass)`.
**Replace** the single line:
`7. Quick scan for Unity-specific issues (null refs, missing SerializeField, event leaks).`

**Steps:**
1. [ ] Open `orchestrate.md`.
2. [ ] Locate the exact line `7. Quick scan for Unity-specific issues (null refs, missing SerializeField, event leaks).` inside Step 3.5 Step C.
3. [ ] Replace **only that line** with the following block:

```markdown
7. **Play Mode entry (BLOCKING).** Use MCP `manage_editor` to enter Play Mode. Wait up to 10 s for `editor_state.isPlaying == true`. If Play Mode never engages → report ISSUES FOUND with reason "PlayMode failed to start".
8. **Console error pattern scan (BLOCKING).** While in Play Mode for at least 2 frames, then exit Play Mode and call `read_console`. Search the full console output for ANY of:
   - `VContainerException` — DI binding missing
   - `NullReferenceException` originating from `_GameFolders/` or `_Framework/`
   - `MissingReferenceException`
   - `MissingComponentException`
   - Any log line at level `Error` containing `Installer`, `Resolve`, or `Bind`
9. If ANY of the patterns above appear:
   - Attempt to fix (max 2 attempts), re-enter Play Mode, re-scan.
   - If still present → Report: ISSUES FOUND with the full matching log lines.
   - Do NOT report VERIFIED while any pattern persists.
10. Quick scan for the remaining Unity-specific issues (missing SerializeField, event leaks, leftover Debug.Log spam). These are WARNING-level — list them but do not block.
```

4. [ ] Save. Verify that `Report: VERIFIED or ISSUES FOUND with details.` (the closing line of the verifier prompt) is still present and unchanged.

**Test Type:** NoTest

**Acceptance Criteria:**
- The string `7. Quick scan for Unity-specific issues` no longer appears anywhere in `orchestrate.md`.
- The strings `Play Mode entry (BLOCKING)`, `VContainerException`, and `Console error pattern scan (BLOCKING)` each appear exactly once.
- The line `Report: VERIFIED or ISSUES FOUND with details.` is still present and unchanged.
- Step A (Compile & Assembly Check) and Step B (Test Run) blocks in Step 3.5 are unchanged.
- `git diff` shows one deletion (old line) and the new 4-step block as additions.

---

## Task F3a — Add Architecture-Drift Rule to orchestrate.md Step 2 Coder Rules

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/orchestrate.md`

**Insertion Point:**
Inside the Coder prompt template, `## Project Rules` block.
Immediately **after** the last bullet:
`- #region tags required in _GameFolders/Scripts/`
And **before** the `## When Done` heading.

**Steps:**
1. [ ] Open `orchestrate.md`.
2. [ ] Locate the bullet `- #region tags required in _GameFolders/Scripts/` inside the Coder prompt `## Project Rules` block.
3. [ ] Append the following block immediately after that bullet:

```markdown
- **Architecture Drift (BLOCKING).** Before introducing any new pattern, scan for an existing one:
  - New service / manager → check `_Framework/` and `Games/Abstracts/` for an interface to implement; if one exists, use it instead of inventing a parallel system.
  - New event → check existing `IEvent` structs under `_GameFolders/Scripts/Games/Concretes/Events/`; reuse before creating.
  - New folder under `_GameFolders/Scripts/` → forbidden unless the TDD explicitly lists it. Stop and report BLOCKED with reason "ADR required: new folder `<path>` not in TDD".
  - New singleton, ServiceLocator, static manager, or `Object.FindObjectOfType` call → forbidden. VContainer only.
  - If the task description requires a pattern that contradicts the TDD → stop and report BLOCKED with reason "ADR required: `<conflict>`. Pause for human decision before proceeding."
```

4. [ ] Save. Confirm `## When Done` heading inside the Coder prompt still follows immediately after the new bullet.

**Test Type:** NoTest

**Acceptance Criteria:**
- The phrase `**Architecture Drift (BLOCKING).**` appears exactly once in `orchestrate.md`.
- The new bullet appears inside the Coder prompt fenced code block (between the opening triple backticks and the closing triple backticks that wraps the coder prompt).
- The original bullets in `## Project Rules` are still present, in original order.
- `## When Done` heading inside the Coder prompt is unchanged.
- `git diff` shows additions only on this file for this task.

---

## Task F3b — Add Architecture-Drift Criterion #10 to orchestrate.md Reviewer Criteria

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/orchestrate.md`

**Insertion Point:**
Inside the Reviewer prompt template, `## Review Criteria` block.
Immediately **after** criterion:
`9. Serialization — FormerlySerializedAs on any renamed [SerializeField]`
And **before** the `## Output Format` heading.

**Steps:**
1. [ ] Open `orchestrate.md`.
2. [ ] Locate the line `9. Serialization — FormerlySerializedAs on any renamed [SerializeField]` in the Reviewer prompt `## Review Criteria` block.
3. [ ] Append the following line immediately after criterion 9:

```markdown
10. **Architecture drift (BLOCKING)** — implementation must match the TDD: no new singletons, no `ServiceLocator`, no `FindObjectOfType`, no new folders under `_GameFolders/Scripts/` that aren't in the TDD, and no new event structs when an existing `IEvent` covers the case. If the diff introduces any of these without a paired ADR entry, the review must return **CHANGES NEEDED** with reason "Architecture drift: `<specific drift>` — open an ADR or revert."
```

4. [ ] Save. Confirm `## Output Format` heading still follows criterion 10.

**Test Type:** NoTest

**Acceptance Criteria:**
- The Reviewer `## Review Criteria` block contains exactly 10 numbered criteria (1 through 10).
- Criterion 10 starts with `**Architecture drift (BLOCKING)**`.
- Criteria 1–9 remain unchanged.
- `## Output Format` heading directly follows criterion 10.
- `git diff` shows additions only on this file for this task.

---

## Task F4 — Add Task Atomicity Gate to plan-workflow.md Step 3

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/plan-workflow.md`

**Insertion Point:**
Section `### Step 3: Task Specification`.
Immediately **after** the last field bullet:
`- **parallel_group**: Integer (1, 2, 3…) if this task can run simultaneously with other tasks in the same group; — if sequential. See Parallel Group Rules below.`
And **before** `### Step 4: Agent Team Plan`.

**Steps:**
1. [ ] Open `plan-workflow.md`.
2. [ ] Locate the `- **parallel_group**: Integer (1, 2, 3…)...` bullet (last bullet of Step 3's field list).
3. [ ] Insert the following block immediately after that bullet (preserve the leading blank line):

```markdown

**Task Atomicity Gate (BLOCKING).** Before locking the task in the plan, verify it is small enough for a single agent session:

1. Estimated complexity must be `S` or `M`. If the honest estimate is `L` → flag for review. If `XL` → **must split**, do not emit the task as-is.
2. Outputs list must contain **≤ 3 files**. If the task produces more than 3 files, split it along the natural seam (interface + implementation + test = three separate tasks at minimum).
3. Description must reference **≤ 1 TDD section**. If the task spans multiple TDD sections, split it per section.
4. Acceptance criteria must be **≤ 6 bullets**. More than 6 → the task is doing too much.

For each violation, print:
```
⛔ BLOCKED at Step 3 (Task Specification): task `<TaskID>` violates atomicity gate.
Reason: <which of the four rules failed>
Split into: <propose 2+ smaller task IDs>
```
and refuse to emit the WORKFLOW.md until the user splits or accepts an override (`override-atomicity: <reason>` in the answer to Step 6 Verification Questions).
```

4. [ ] Save. Confirm `### Step 4: Agent Team Plan` still begins on the next non-blank line.

**Test Type:** NoTest

**Acceptance Criteria:**
- The phrase `**Task Atomicity Gate (BLOCKING).**` appears exactly once in `plan-workflow.md`.
- The four numbered atomicity rules (S/M complexity cap, ≤ 3 files, ≤ 1 TDD section, ≤ 6 bullets) are all present in that order.
- The original `- **parallel_group**: ...` bullet is unchanged.
- `### Step 4: Agent Team Plan` heading still exists immediately after the new block.
- `git diff` shows additions only on this file for this task.

---

## Task F5 — Add Testing-Capability Preflight to plan-workflow.md Initialization

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claire/commands/plan-workflow.md`

**Files:**
- `/Users/berkterek/Desktop/Github/unity-claude-ai-template-repo/.claude/commands/plan-workflow.md`

**Insertion Point:**
Section `## Initialization`.
Insert as new **step 5** between:
- `4. Read CLAUDE.md for project constraints.`
- `5. **Codebase Pre-Scan** — before planning any tasks, scan what already exists:`

Then renumber old step 5 → 6 and old step 6 → 7.

**Steps:**
1. [ ] Open `plan-workflow.md`.
2. [ ] Locate `4. Read \`CLAUDE.md\` for project constraints.` in `## Initialization`.
3. [ ] Insert the following block as new step 5 immediately after that line:

```markdown
5. **Testing capability preflight (BLOCKING/WARNING).** Determine whether tests can actually run in this project:
   - Check for `Packages/manifest.json` containing `"com.unity.test-framework"` → records `tests_available: true|false`.
   - Check for at least one `*.Tests.asmdef` under `_GameFolders/Scripts/` or `_Framework/` → records `test_asmdefs_present: true|false`.
   - Check `.claude/CLAUDE.md` or `production/review-mode.txt` for an explicit `testing: disabled` flag → records `testing_disabled_by_config: true|false`.

   Decision matrix:

   | tests_available | test_asmdefs_present | testing_disabled_by_config | Action |
   |-----------------|----------------------|-----------------------------|--------|
   | true            | true                 | false                       | Continue normally. Generate test tasks as usual. |
   | true            | false                | false                       | WARNING. Continue, but mark Phase 3 (Unit Tests) entry criterion as "create at least one `*.Tests.asmdef` first". |
   | any             | any                  | true                        | WARNING. Skip tester tasks. Compensate: (a) extra reviewer pass after every phase, (b) manual smoke-test acceptance criterion on every task that produces a MonoBehaviour or Installer, (c) require Step 3.5 Bounded Verification to be non-skippable in `/orchestrate`. |
   | false           | any                  | false                       | BLOCKING. Print: `⛔ BLOCKED at Initialization step 5: tests are referenced by the plan but com.unity.test-framework is missing from manifest.json. Either install the package or set testing: disabled in CLAUDE.md.` Exit. |

   Print the resolved row before continuing:
   ```
   Testing Preflight: tests_available=<bool>, test_asmdefs_present=<bool>, testing_disabled_by_config=<bool> → <Action label>
   ```
```

4. [ ] Renumber the existing `5. **Codebase Pre-Scan**...` → `6. **Codebase Pre-Scan**...` (change only the leading digit).
5. [ ] Renumber the existing `6. Analyze every system, class, and dependency in the TDD.` → `7. Analyze every system, class, and dependency in the TDD.` (change only the leading digit).
6. [ ] Do **not** touch any sub-bullet text inside the Codebase Pre-Scan block — only the leading number changes.
7. [ ] Save.

**Test Type:** NoTest

**Acceptance Criteria:**
- The `## Initialization` section contains exactly 7 numbered top-level steps (1 through 7).
- Step 5 is the new `**Testing capability preflight (BLOCKING/WARNING).**` block.
- Step 6 is the original Codebase Pre-Scan block with all its sub-bullets, only the leading number changed from `5.` to `6.`.
- Step 7 is the original `Analyze every system, class, and dependency in the TDD.`, only the leading number changed from `6.` to `7.`.
- The decision matrix table has exactly 4 data rows.
- The strings `Testing capability preflight (BLOCKING/WARNING)`, `tests_available`, `test_asmdefs_present`, and `testing_disabled_by_config` each appear exactly once.
- `git diff` shows the insertion plus the two single-digit renumbering edits — no other changes on this file.

---

## Implementation Order Notes

- **Phase 1 (parallel):** F1 and F2 touch different files — run concurrently.
- **Phase 2 (sequential):** F3a then F3b — both edit `orchestrate.md`; F3b must wait for F3a to avoid line-number drift inside the reviewer prompt block.
- **Phase 3 (sequential):** F4 then F5 — both edit `plan-workflow.md`; execute F4 first (Step 3 area), then F5 (Initialization area above it).

After all six tasks land, do a final read-through of both files end-to-end to confirm:
- Every fenced code block (triple backtick pairs) still balances.
- Every numbered list is still contiguous.
- No accidental edits outside the listed insertion points.

These are Markdown command files — no C# compilation, no Unity Editor refresh, no test run needed. Changes take effect the next time `/plan-workflow` or `/orchestrate` is invoked.
