# PLAN — Model Tier Redesign

> **Version:** v3 — 2026-06-19
> **Status:** Active
> **Scope:** Agent frontmatter model fields, model-routing SKILL.md, command files (--heavy flag, --lite flag), commands.md docs, deletion of fix-lite/implement-lite commands and lite agents, reference cleanup across codebase

> **Revision v2:** Added Task 10 (--lite flag for fix-lite.md) and Task 11 (--lite flag for implement-lite.md). Updated Task 9 to also add --lite row to commands.md. Updated Status table and File Map accordingly.

> **Revision v3:** Tasks 10 and 11 replaced entirely. The /fix-lite, /implement-lite commands and their lite agents (unity-fixer-lite, unity-coder-lite) are deleted rather than extended. Instead, --lite flag is added directly to fix.md and implement.md. New Task 10 deletes 4 files. New Task 11 adds --lite to fix.md. New Task 12 adds --lite to implement.md. New Task 13 cleans up all references across CLAUDE.md, agents-index.md, hooks-blocking.md, debug-session.md, scene-setup.md, orchestrate.md, create-test.md, and model-routing/SKILL.md. Task 9 scope updated to document --lite on /fix and /implement (not /fix-lite and /implement-lite), and to remove /fix-lite and /implement-lite command entries from commands.md.

## Context

The current model tier assignment treats implementation agents (unity-coder, coder, unity-fixer, etc.) as opus-tier, which is wasteful. These agents perform mechanical, well-defined work — they receive a spec and write code — not the kind of deep reasoning that justifies opus cost. Meanwhile, `lean-planner` runs on sonnet despite doing architectural decomposition that directly shapes implementation quality.

The redesign applies a simple rule: **analysis/planning/review → opus, implementation → sonnet, lightweight inspection → haiku**. Debugger, reviewer, unity-developer, and unity-critic stay at opus because they perform root-cause analysis and adversarial code review — their output quality degrades measurably on sonnet. Lean-planner is upgraded to opus because it produces the execution plan that all downstream agents follow.

A `--heavy` escape hatch is added to `/implement`, `/fix`, `/fix-deep`, and `/orchestrate`. When the flag is present, the implementation agent is forced to opus regardless of the tier routing, allowing the user to opt in to higher quality for genuinely difficult tasks without changing the default.

A `--lite` escape hatch is added to `/implement` and `/fix`. When the flag is present, the implementation agent is forced to haiku tier — maximum speed and minimum cost for trivial single-file changes. The standalone `/fix-lite` and `/implement-lite` commands and their dedicated lite agents (`unity-fixer-lite`, `unity-coder-lite`) are removed entirely; --lite on the main commands replaces them.

## Goals

- [ ] Downgrade 10 implementation agent frontmatter fields from `opus` to `sonnet`
- [ ] Upgrade `lean-planner` frontmatter from `claude-sonnet-4-6` to `opus`
- [ ] Update `model-routing/SKILL.md` tier tables to reflect new reality
- [ ] Add `--heavy` flag to `/implement`, `/fix`, `/fix-deep`, `/orchestrate` commands
- [ ] Delete `/fix-lite`, `/implement-lite` commands and `unity-fixer-lite`, `unity-coder-lite` agents
- [ ] Add `--lite` flag to `/fix` and `/implement` (forces haiku tier on implementation agent)
- [ ] Clean up all references to lite commands and lite agents across the codebase
- [ ] Document `--heavy` and `--lite` flags in `commands.md`

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Downgrade implementation agents (batch A: unity-coder, coder, unity-fixer, unity-verifier, unity-setup) | Pending | A |
| 1 | Task 2 — Downgrade implementation agents (batch B: unity-scene-builder, unity-optimizer, unity-shader-dev, unity-network-dev, unity-prototyper) | Pending | A |
| 1 | Task 3 — Upgrade lean-planner to opus | Pending | A |
| 1 | Task 10 — Delete fix-lite.md, implement-lite.md, unity-fixer-lite.md, unity-coder-lite.md | Pending | A |
| 2 | Task 4 — Update model-routing/SKILL.md | Pending | B |
| 2 | Task 5 — Add --heavy flag to implement.md | Pending | B |
| 2 | Task 6 — Add --heavy flag to fix.md | Pending | B |
| 2 | Task 7 — Add --heavy flag to fix-deep.md | Pending | B |
| 2 | Task 8 — Add --heavy flag to orchestrate.md | Pending | B |
| 2 | Task 11 — Add --lite flag to fix.md | Pending | B |
| 2 | Task 12 — Add --lite flag to implement.md | Pending | B |
| 2 | Task 13 — Reference cleanup (CLAUDE.md, agents-index.md, hooks-blocking.md, debug-session.md, scene-setup.md, orchestrate.md, create-test.md, model-routing/SKILL.md) | Pending | B |
| 3 | Task 9 — Document --heavy and --lite flags in commands.md; remove /fix-lite and /implement-lite entries | Pending | C |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/agents/unity-coder.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/coder.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-fixer.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-verifier.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-setup.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-scene-builder.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-optimizer.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-shader-dev.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-network-dev.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/unity-prototyper.md` | Edit | `model: opus` → `model: sonnet` |
| `.claude/agents/lean-planner.md` | Edit | `model: claude-sonnet-4-6` → `model: opus` |
| `.claude/agents/unity-fixer-lite.md` | **Delete** | Lite agent removed; --lite flag on fix.md replaces it |
| `.claude/agents/unity-coder-lite.md` | **Delete** | Lite agent removed; --lite flag on implement.md replaces it |
| `.claude/commands/fix-lite.md` | **Delete** | Command removed; use `/fix --lite` instead |
| `.claude/commands/implement-lite.md` | **Delete** | Command removed; use `/implement --lite` instead |
| `.claude/skills/core/model-routing/SKILL.md` | Edit | Update Opus and Sonnet tier agent lists; remove lite agents from Sonnet Tier |
| `.claude/commands/implement.md` | Edit | Add --heavy flag detection and routing logic; add --lite flag; remove routing to /implement-lite |
| `.claude/commands/fix.md` | Edit | Add --heavy flag detection and routing logic; add --lite flag; remove routing to /fix-lite |
| `.claude/commands/fix-deep.md` | Edit | Add --heavy flag detection and routing logic |
| `.claude/commands/orchestrate.md` | Edit | Add --heavy flag detection and routing logic; remove unity-coder-lite from routing tables |
| `.claude/commands/debug-session.md` | Edit | Change unity-fixer-lite reference to unity-fixer |
| `.claude/commands/scene-setup.md` | Edit | Remove unity-coder-lite references |
| `.claude/commands/create-test.md` | Edit | Remove unity-coder-lite reference |
| `.claude/docs/commands.md` | Edit | Add --heavy and --lite rows to flag table; remove /fix-lite and /implement-lite command entries; clean up references in scene-setup and orchestrate descriptions |
| `.claude/docs/agents-index.md` | Edit | Remove rows for unity-fixer-lite and unity-coder-lite |
| `.claude/docs/hooks-blocking.md` | Edit | Remove unity-coder-lite from SPARC gate protected list |
| `.claude/CLAUDE.md` | Edit | Remove unity-fixer-lite and unity-coder-lite from NON-NEGOTIABLE agent list |

---

## Task 1 — Downgrade Implementation Agents Batch A

**Files:**
- `.claude/agents/unity-coder.md`
- `.claude/agents/coder.md`
- `.claude/agents/unity-fixer.md`
- `.claude/agents/unity-verifier.md`
- `.claude/agents/unity-setup.md`

**Steps:**
- [ ] 1. Open `.claude/agents/unity-coder.md`. In the YAML frontmatter (between `---` delimiters), find the line `model: opus` and change it to `model: sonnet`.
- [ ] 2. Open `.claude/agents/coder.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 3. Open `.claude/agents/unity-fixer.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 4. Open `.claude/agents/unity-verifier.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 5. Open `.claude/agents/unity-setup.md`. Change `model: opus` → `model: sonnet` in frontmatter.

**Test Type:** NoTest

**Acceptance Criteria:**
- Each of the five files has `model: sonnet` on line 4 (or wherever the model field appears in frontmatter).
- No other frontmatter fields are modified.
- The body of each agent file is unchanged.

---

## Task 2 — Downgrade Implementation Agents Batch B

**Files:**
- `.claude/agents/unity-scene-builder.md`
- `.claude/agents/unity-optimizer.md`
- `.claude/agents/unity-shader-dev.md`
- `.claude/agents/unity-network-dev.md`
- `.claude/agents/unity-prototyper.md`

**Steps:**
- [ ] 1. Open `.claude/agents/unity-scene-builder.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 2. Open `.claude/agents/unity-optimizer.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 3. Open `.claude/agents/unity-shader-dev.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 4. Open `.claude/agents/unity-network-dev.md`. Change `model: opus` → `model: sonnet` in frontmatter.
- [ ] 5. Open `.claude/agents/unity-prototyper.md`. Change `model: opus` → `model: sonnet` in frontmatter.

**Test Type:** NoTest

**Acceptance Criteria:**
- Each of the five files has `model: sonnet` in frontmatter.
- No other frontmatter fields are modified.
- The body of each agent file is unchanged.

---

## Task 3 — Upgrade lean-planner to Opus

**Files:**
- `.claude/agents/lean-planner.md`

**Steps:**
- [ ] 1. Open `.claude/agents/lean-planner.md`. In the YAML frontmatter, find `model: claude-sonnet-4-6` and change it to `model: opus`.

**Test Type:** NoTest

**Acceptance Criteria:**
- `lean-planner.md` frontmatter contains `model: opus`.
- No other frontmatter fields are modified.
- The body of the agent file is unchanged.

---

## Task 4 — Update model-routing/SKILL.md Tier Tables

**Files:**
- `.claude/skills/core/model-routing/SKILL.md`

**Steps:**
- [ ] 1. Read the file to locate the Opus Tier and Sonnet Tier agent lists.
- [ ] 2. Update the **Opus Tier** section:
  - Remove from the list: `unity-coder`, `coder`, `unity-fixer`, `unity-verifier`, `unity-setup`, `unity-scene-builder`, `unity-optimizer`, `unity-shader-dev`, `unity-network-dev`, `unity-prototyper`
  - Ensure the following remain in Opus Tier: `lean-planner` (add if not present), `debugger`, `reviewer`, `unity-developer`, `unity-critic`
  - Update description: Opus Tier = planners + analyzers/reviewers. Examples: plan authors (Plan built-in, lean-planner), root-cause analysts (debugger), code reviewers (reviewer, unity-developer, unity-critic).
- [ ] 3. Update the **Sonnet Tier** section:
  - Add all 10 downgraded agents to the Sonnet Tier list: `unity-coder`, `coder`, `unity-fixer`, `unity-verifier`, `unity-setup`, `unity-scene-builder`, `unity-optimizer`, `unity-shader-dev`, `unity-network-dev`, `unity-prototyper`
  - Remove `unity-fixer-lite` and `unity-coder-lite` from the Sonnet Tier list if present (these agents are deleted).
  - Update description: Sonnet Tier = implementors. Agents that receive a spec and produce code or scene changes.
- [ ] 4. Verify the **Haiku Tier** section is unchanged: `unity-scout`, `unity-linter`. Remove any mention of lite agents if present.
- [ ] 5. Add a section or note documenting both flags: "When `--heavy` is passed to a command, the implementation agent for that run is forced to opus tier regardless of this routing table. When `--lite` is passed to `/fix` or `/implement`, the implementation agent is forced to haiku tier."

**Test Type:** NoTest

**Acceptance Criteria:**
- Opus Tier lists: `lean-planner`, `debugger`, `reviewer`, `unity-developer`, `unity-critic` (and any other existing opus agents not touched by this plan).
- Sonnet Tier lists all 10 implementation agents plus any previously-sonnet agents. Does not list `unity-fixer-lite` or `unity-coder-lite`.
- Haiku Tier is unchanged (no lite agents).
- Both `--heavy` and `--lite` flag concepts are documented.

---

## Task 5 — Add --heavy Flag to implement.md

**Files:**
- `.claude/commands/implement.md`

**Steps:**
- [ ] 1. Read `.claude/commands/implement.md` and locate Step 0 (or the earliest argument-parsing step).
- [ ] 2. Add `--heavy` flag detection immediately after the existing `$ARGUMENTS` check. Pattern:
  ```
  Check $ARGUMENTS for --heavy flag → set FORCE_OPUS_TIER=true
  ```
- [ ] 3. Locate the coder routing step (where the command decides which agent to spawn based on complexity score). Add a branch:
  ```
  If FORCE_OPUS_TIER == true → always use opus-tier agent (e.g. coder at opus, not sonnet)
  ```
- [ ] 4. Verify the change does not alter any other routing logic or flag handling.

**Test Type:** NoTest

**Acceptance Criteria:**
- `implement.md` checks for `--heavy` in `$ARGUMENTS` early in the pipeline.
- When `--heavy` is set, the implementation agent runs at opus tier.
- All other routing (complexity score, SCOPE_GATE, SPARC_GATE) is unchanged.

---

## Task 6 — Add --heavy Flag to fix.md

**Files:**
- `.claude/commands/fix.md`

**Steps:**
- [ ] 1. Read `.claude/commands/fix.md` and locate Step 0 / argument-parsing section.
- [ ] 2. Add `--heavy` flag detection. Pattern identical to Task 5:
  ```
  Check $ARGUMENTS for --heavy → set FORCE_OPUS_TIER=true
  ```
- [ ] 3. In the fixer/coder routing step, add branch: if FORCE_OPUS_TIER == true → use opus-tier fixer agent.
- [ ] 4. Verify no other logic is altered.

**Test Type:** NoTest

**Acceptance Criteria:**
- `fix.md` detects `--heavy` flag.
- Fixer agent is forced to opus when flag is present.
- All other fix routing unchanged.

---

## Task 7 — Add --heavy Flag to fix-deep.md

**Files:**
- `.claude/commands/fix-deep.md`

**Steps:**
- [ ] 1. Read `.claude/commands/fix-deep.md` and locate Step 0 / argument-parsing section.
- [ ] 2. Add `--heavy` flag detection (same pattern as Tasks 5–6).
- [ ] 3. In the agent routing step, add branch: if FORCE_OPUS_TIER == true → force opus-tier implementation agent.
- [ ] 4. Verify no other logic is altered.

**Test Type:** NoTest

**Acceptance Criteria:**
- `fix-deep.md` detects `--heavy` flag.
- Implementation agent is forced to opus when flag is present.
- All other fix-deep routing unchanged.

---

## Task 8 — Add --heavy Flag to orchestrate.md

**Files:**
- `.claude/commands/orchestrate.md`

**Steps:**
- [ ] 1. Read `.claude/commands/orchestrate.md` and locate Step 0 / argument-parsing section.
- [ ] 2. Add `--heavy` flag detection (same pattern as Tasks 5–7).
- [ ] 3. In the worker agent spawning step, add branch: if FORCE_OPUS_TIER == true → all spawned implementation agents use opus tier for this run.
- [ ] 4. Verify no other orchestrate logic is altered (parallel_group handling, graph pre-scan, gate logic all unchanged).

**Test Type:** NoTest

**Acceptance Criteria:**
- `orchestrate.md` detects `--heavy` flag.
- All implementation agents spawned by orchestrate use opus when flag is present.
- Orchestrate's parallel dispatch, graph pre-scan, and gate logic are unchanged.

---

## Task 9 — Document --heavy and --lite Flags in commands.md; Remove Lite Command Entries

**Files:**
- `.claude/docs/commands.md`

**Steps:**
- [ ] 1. Read `.claude/docs/commands.md` and locate the flags table or section where `--lean` is documented.
- [ ] 2. Add `--heavy` to the same table/section, immediately after `--lean`, using identical formatting style. Content:
  ```
  | `--heavy` | `/implement`, `/fix`, `/fix-deep`, `/orchestrate` | Forces implementation agent to opus tier for this run, regardless of complexity score. Use for unusually difficult tasks where sonnet output quality is insufficient. |
  ```
- [ ] 3. Add `--lite` to the same table/section, immediately after `--heavy`. Content:
  ```
  | `--lite` | `/fix`, `/implement` | Forces implementation agent to haiku tier for this run. Use for trivial single-file changes where maximum speed and minimum cost are the priority. |
  ```
- [ ] 4. Locate the command entries for `/fix-lite` and `/implement-lite` and remove them entirely.
- [ ] 5. In any description for `/scene-setup` or `/orchestrate` that references `unity-coder-lite`, remove or replace those references.
- [ ] 6. Verify the `--heavy` and `--lite` entries are consistent with the existing table column structure. Verify no remaining references to `/fix-lite`, `/implement-lite`, `unity-coder-lite`, or `unity-fixer-lite` remain.

**Test Type:** NoTest

**Acceptance Criteria:**
- `commands.md` contains a `--heavy` row listing the four affected commands.
- `commands.md` contains a `--lite` row listing `/fix` and `/implement` (not `/fix-lite` or `/implement-lite`).
- Both rows explain the tier-override behavior.
- `/fix-lite` and `/implement-lite` command entries are removed.
- No references to lite commands or lite agents remain in commands.md.

---

## Task 10 — Delete Lite Command Files and Lite Agent Files

**Files (to delete):**
- `.claude/commands/fix-lite.md`
- `.claude/commands/implement-lite.md`
- `.claude/agents/unity-fixer-lite.md`
- `.claude/agents/unity-coder-lite.md`

**Steps:**
- [ ] 1. Delete `.claude/commands/fix-lite.md`.
- [ ] 2. Delete `.claude/commands/implement-lite.md`.
- [ ] 3. Delete `.claude/agents/unity-fixer-lite.md`.
- [ ] 4. Delete `.claude/agents/unity-coder-lite.md`.

**Test Type:** NoTest

**Acceptance Criteria:**
- All four files no longer exist on disk.
- No other files are modified by this task.

---

## Task 11 — Add --lite Flag to fix.md

**Files:**
- `.claude/commands/fix.md`

**Steps:**
- [ ] 1. Read `.claude/commands/fix.md` and locate the earliest argument-parsing step (Step 0 or equivalent, before SCOPE_GATE).
- [ ] 2. Add `--lite` flag detection alongside the `--heavy` detection added in Task 6. Pattern:
  ```
  Check $ARGUMENTS for --lite flag → set FORCE_HAIKU_TIER=true
  ```
- [ ] 3. Locate the fixer agent routing step. Add a branch:
  ```
  If FORCE_HAIKU_TIER == true → spawn unity-fixer subagent (model: haiku)
  Else if FORCE_OPUS_TIER == true → spawn unity-fixer subagent (model: opus)
  Else → spawn unity-fixer subagent (default sonnet tier)
  ```
  The model override is specified inline in the spawn instruction text — no new agent file is needed.
- [ ] 4. Remove any existing routing logic that routes low-complexity fixes to `/fix-lite` (complexity < 0.3 branch or similar). The --lite flag on fix.md is the new mechanism.
- [ ] 5. Verify no other pipeline steps are altered (SCOPE_GATE, BREAKING_GATE, QUALITY_GATE, COMMIT_GATE all unchanged).

**Test Type:** NoTest

**Acceptance Criteria:**
- `fix.md` checks for `--lite` in `$ARGUMENTS` before SCOPE_GATE.
- When `--lite` is set, the spawn instruction for `unity-fixer` explicitly specifies `model: haiku`.
- When `--heavy` is set, unity-fixer uses opus.
- When neither flag is set, unity-fixer uses the default sonnet tier.
- Any routing to `/fix-lite` is removed.
- All other pipeline steps are unmodified.

---

## Task 12 — Add --lite Flag to implement.md

**Files:**
- `.claude/commands/implement.md`

**Steps:**
- [ ] 1. Read `.claude/commands/implement.md` and locate the earliest argument-parsing step (Step 0 or equivalent, before SCOPE_GATE).
- [ ] 2. Add `--lite` flag detection alongside the `--heavy` detection added in Task 5. Pattern:
  ```
  Check $ARGUMENTS for --lite flag → set FORCE_HAIKU_TIER=true
  ```
- [ ] 3. Locate the coder agent routing step. Add a branch:
  ```
  If FORCE_HAIKU_TIER == true → spawn unity-coder subagent (model: haiku)
  Else if FORCE_OPUS_TIER == true → spawn unity-coder subagent (model: opus)
  Else → spawn unity-coder subagent (default sonnet tier)
  ```
  The model override is specified inline in the spawn instruction text — no new agent file is needed.
- [ ] 4. Remove any existing routing logic that routes low-complexity tasks to `/implement-lite` (complexity < 0.3 branch or similar). The --lite flag on implement.md is the new mechanism.
- [ ] 5. Verify no other pipeline steps are altered (SCOPE_GATE, SPARC_GATE, ARCHITECTURE_GATE, QUALITY_GATE, COMMIT_GATE all unchanged).

**Test Type:** NoTest

**Acceptance Criteria:**
- `implement.md` checks for `--lite` in `$ARGUMENTS` before SCOPE_GATE.
- When `--lite` is set, the spawn instruction for `unity-coder` explicitly specifies `model: haiku`.
- When `--heavy` is set, unity-coder uses opus.
- When neither flag is set, unity-coder uses the default sonnet tier.
- Any routing to `/implement-lite` is removed.
- All other pipeline steps are unmodified.

---

## Task 13 — Reference Cleanup Across Codebase

**Files:**
- `.claude/CLAUDE.md`
- `.claude/docs/agents-index.md`
- `.claude/docs/hooks-blocking.md`
- `.claude/commands/debug-session.md`
- `.claude/commands/scene-setup.md`
- `.claude/commands/orchestrate.md`
- `.claude/commands/create-test.md`
- `.claude/skills/core/model-routing/SKILL.md`

**Steps:**
- [ ] 1. **`.claude/CLAUDE.md`** — Locate the NON-NEGOTIABLE section that lists agent types (the gate rule: "NEVER spawn a `tester`, `coder`, `unity-coder`, …"). Remove `unity-fixer-lite` and `unity-coder-lite` from that list.
- [ ] 2. **`.claude/docs/agents-index.md`** — Locate the agents table. Remove the rows for `unity-fixer-lite` and `unity-coder-lite` entirely.
- [ ] 3. **`.claude/docs/hooks-blocking.md`** — Locate the SPARC gate protected agent list. Remove `unity-coder-lite` from that list.
- [ ] 4. **`.claude/commands/debug-session.md`** — Find any reference to `unity-fixer-lite` and replace it with `unity-fixer`.
- [ ] 5. **`.claude/commands/scene-setup.md`** — Find all references to `unity-coder-lite` and remove or replace them. If unity-coder-lite was used as a routing option for low-complexity scene tasks, route those to `unity-coder` (sonnet tier) instead.
- [ ] 6. **`.claude/commands/orchestrate.md`** — Find all references to `unity-coder-lite` in routing tables or agent selection logic and remove them. Low-complexity tasks that previously routed to unity-coder-lite should now route to unity-coder (sonnet tier).
- [ ] 7. **`.claude/commands/create-test.md`** — Find the reference to `unity-coder-lite` and replace it with `unity-coder`.
- [ ] 8. **`.claude/skills/core/model-routing/SKILL.md`** — This is also edited by Task 4. Confirm that after Task 4 completes, no references to `unity-fixer-lite` or `unity-coder-lite` remain in the file. If Task 4 and Task 13 run in parallel, coordinate so both sets of edits are applied without conflict (apply Task 4 edits first, then verify Task 13 cleanup on this file).

**Test Type:** NoTest

**Acceptance Criteria:**
- `CLAUDE.md` NON-NEGOTIABLE agent list contains no reference to `unity-fixer-lite` or `unity-coder-lite`.
- `agents-index.md` contains no rows for lite agents.
- `hooks-blocking.md` SPARC gate list contains no reference to `unity-coder-lite`.
- `debug-session.md` references `unity-fixer`, not `unity-fixer-lite`.
- `scene-setup.md` contains no references to `unity-coder-lite`.
- `orchestrate.md` routing tables contain no references to `unity-coder-lite`.
- `create-test.md` references `unity-coder`, not `unity-coder-lite`.
- `model-routing/SKILL.md` contains no references to lite agents anywhere.
- No other content in any of these files is altered beyond the targeted removals and replacements.
