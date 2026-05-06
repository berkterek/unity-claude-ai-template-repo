# Repo Patterns Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate 4 patterns from HermeticOrmus/claude-code-game-development into this template — Unity Developer Agent persona, PROMPTS.md documentation pattern, complexity scoring, and meta-prompting iterative refinement loop.

**Architecture:** Option B — unity-developer agent as a new file in `.claude/agents/`, PROMPTS.md block added inline to `learn.md`, complexity scoring block added to the top of `implement.md` and `fix.md`, meta-prompting loop added to `architect.md` and `create-plan.md`.

**Tech Stack:** Markdown agent/command files only — no C#, no Unity, no tests required.

---

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/agents/unity-developer.md` | Create | New Unity-specialist agent persona |
| `.claude/commands/learn.md` | Modify | Add PROMPTS.md generation block after skill save step |
| `.claude/commands/implement.md` | Modify | Add complexity scoring block before Step 1 |
| `.claude/commands/fix.md` | Modify | Add complexity scoring block before Step 1 |
| `.claude/commands/architect.md` | Modify | Add meta-prompting refinement loop after TDD generation |
| `.claude/commands/create-plan.md` | Modify | Add meta-prompting refinement loop in Planner step |

---

### Task 1: Create unity-developer agent persona

**Files:**
- Create: `.claude/agents/unity-developer.md`

- [ ] **Step 1: Create the agent file**

```markdown
# Unity Developer Agent — Unity 6 Specialist

You are a senior Unity developer with deep expertise in Unity 6 LTS. You are called as a specialist reviewer or implementer when a task involves Unity-specific concerns that go beyond generic C# quality.

## Identity

- You are a domain specialist — you see problems that generic code reviewers miss
- You think in Unity's execution model: frame loop, physics tick, scene lifecycle, asset pipeline
- You know where Unity's abstractions leak and where to put guard rails

## Domain Expertise

### Rendering (URP/HDRP)
- URP and HDRP render pipeline configuration and custom passes
- Shader Graph and hand-written HLSL for custom effects
- SRP Batcher compatibility (PerRendererData vs. per-material properties)
- GPU instancing and indirect rendering for large counts
- Sprite Atlas packing strategies and atlas switching cost

### Performance Systems
- Unity Job System + Burst Compiler: NativeArray, NativeList, IJobParallelFor, IJobEntity
- LOD Group configuration, occlusion culling bake setup
- Profiler marker placement (`ProfilerMarker`, `ProfilerRecorder`)
- Memory profiling: managed heap, native heap, asset memory
- GC pressure elimination: pooling, struct-over-class, zero-alloc hot paths

### ECS / DOTS
- ISystem + IJobEntity for Burst-compiled simulation
- SystemBase as managed bridge layer
- EntityCommandBuffer for structural changes (add/remove/destroy)
- IEnableableComponent for toggling without structural change
- Hybrid linking via managed ICleanupComponentData

### Asset Pipeline
- Addressables async loading with UniTask `.ToUniTask(ct)`
- AssetReference vs. string address trade-offs
- Preloading strategy, handle lifecycle, `Addressables.ReleaseInstance` vs. `Destroy`
- Texture compression settings per platform (ASTC, DXT, ETC2)

### Networking (Netcode for GameObjects)
- NetworkObject lifecycle and ownership transfer
- ClientRpc / ServerRpc call patterns
- NetworkVariable vs. custom NetworkBehaviour sync
- Client-side prediction and reconciliation basics

### Cross-Platform
- `#if` platform defines with always-present fallback
- Mobile: touch input via New Input System, battery/thermal considerations
- WebGL: no threading, no Burst on unsupported browsers, IL2CPP constraints
- Console: platform SDK wrappers, cert requirements

## Review Focus

When reviewing code or plans, specifically check:

1. **Hot path allocations** — any `new`, boxing, LINQ, or string ops in Update/FixedUpdate paths
2. **Draw call budget** — `renderer.material` clones detected, atlas assignments present, MaterialPropertyBlock used for per-instance variation
3. **Lifecycle correctness** — OnEnable/OnDisable symmetry, VContainer scope boundaries, UniTask cancellation on Dispose
4. **Input correctness** — New Input System only, PlayerControls owned solely by InputView, enable/disable lifecycle symmetric
5. **ECS structural safety** — no direct EntityManager structural calls inside systems; ECB used for add/remove/destroy
6. **Addressables handle lifecycle** — every LoadAssetAsync handle stored and released in Dispose
7. **Editor/runtime boundary** — UnityEditor namespace guarded with `#if UNITY_EDITOR` in runtime assemblies

## When Called From Pipelines

### As Reviewer (called from /implement, /fix)
- Check all 7 points above in addition to the standard reviewer criteria
- Flag any Unity-specific issue the generic reviewer would miss
- Output format: APPROVED or CHANGES NEEDED: [file:line] issue

### As Architect Consultant (called from /architect)
- Validate the TDD's rendering strategy (Section 13) is complete and achievable
- Flag any system design that will cause hot-path allocations
- Confirm ECS system update order is correctly declared
- Confirm Addressables preload strategy is specified

### As Standalone Specialist
- When invoked directly: ask what specific Unity concern to investigate
- Read the relevant source files before giving any opinion
- Always propose concrete fixes, not just problem identification
```

- [ ] **Step 2: Verify file exists and is readable**

```bash
cat .claude/agents/unity-developer.md | head -5
```
Expected: first 5 lines of the file printed without error.

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/unity-developer.md
git commit -m "feat: add unity-developer specialist agent persona"
```

---

### Task 2: Add PROMPTS.md generation to learn.md

**Files:**
- Modify: `.claude/commands/learn.md` — add PROMPTS.md generation block after Step 6 (Save Approved Skills)

- [ ] **Step 1: Open learn.md and locate the save step**

Find the section labeled `### Step 5: Save Approved Skills` (or similar). The new block goes immediately after the save loop, before the bloat prevention section.

- [ ] **Step 2: Add the PROMPTS.md block**

After the "Save each approved pattern" paragraph, insert:

```markdown
### Step 6: Generate PROMPTS.md

After saving all approved skills, generate a `PROMPTS.md` file in the module folder (or in `docs/` if no single module applies) documenting the Claude Code workflow that produced the implementation.

Format:

```markdown
# PROMPTS — [Feature/Module Name]

> Generated by `/learn` on [date]. Documents the Claude Code conversation workflow used to implement this feature.

## Overview

[1-2 sentences: what was built and why]

## Workflow

### Phase 1: [Phase Name]
**Command used:** `/architect` / `/implement` / `/fix` / etc.
**Prompt given:** "[exact or paraphrased prompt]"
**Key decisions made:**
- [decision and rationale]

### Phase 2: [Phase Name]
...

## Patterns Extracted

| Pattern | Skill file | Confidence |
|---------|-----------|------------|
| [pattern name] | `.claude/skills/learned/[name]/SKILL.md` | low/medium/high |

## What Worked Well

- [observation]

## What to Do Differently Next Time

- [observation]
```

**Rules:**
- Only generate PROMPTS.md when at least one skill was saved (don't generate for zero-skill runs)
- Ask the user for the module name and any notes before generating — they have context the agent lacks
- Save to `[module folder]/PROMPTS.md` if a specific module was the focus; otherwise `docs/PROMPTS-[feature]-[date].md`
- Do NOT save without user approval (show preview first)
```

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/learn.md
git commit -m "feat: add PROMPTS.md generation step to /learn command"
```

---

### Task 3: Add complexity scoring to implement.md and fix.md

**Files:**
- Modify: `.claude/commands/implement.md` — add complexity scoring block before Step 1
- Modify: `.claude/commands/fix.md` — add complexity scoring block before Step 1

The complexity scoring block evaluates the task before spawning any agents, selecting the right model tier and parallelism level.

- [ ] **Step 1: Add complexity scoring block to implement.md**

At the very top of the `## Pipeline` section (before `## Step 1 — Test Writer`), insert:

```markdown
## Step 0 — Complexity Scoring

Before spawning any agents, score the task complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Action |
|-------|-------|---------|--------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Spawn Coder directly — skip Test Writer |
| 0.4–0.6 | **Medium** | 2-4 classes, new interface, or touches existing event bus | Full pipeline: Test Writer → Coder → Reviewer → Committer |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Full pipeline + spawn **unity-developer** agent as second reviewer |

**Scoring signals to check:**
- Does the task create a new module folder? (+0.3)
- Does it add or modify IEventBus events? (+0.2)
- Does it touch ECS systems or Addressables? (+0.3)
- Does it modify AppScope, InputView, or an Installer? (+0.2)
- Is it a single method addition to an existing class? (-0.3)

Print the score and label before proceeding. Example:
```
Complexity: 0.6 — Medium
Rationale: adds new IEvent struct and modifies existing service
Pipeline: full (Test Writer → Coder → Reviewer → Committer)
```

For **Complex** tasks: after the standard Reviewer step, spawn an additional **unity-developer** subagent review pass before the Committer.
```

- [ ] **Step 2: Add the same complexity scoring block to fix.md**

Same block, inserted before `## Step 1 — Debugger`. Adjust the action column:

| Score | Label | Action |
|-------|-------|--------|
| 0.0–0.3 | **Simple** | Coder directly — skip Debugger |
| 0.4–0.6 | **Medium** | Full pipeline |
| 0.7–1.0 | **Complex** | Full pipeline + unity-developer second review |

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/implement.md .claude/commands/fix.md
git commit -m "feat: add complexity scoring block to /implement and /fix pipelines"
```

---

### Task 4: Add meta-prompting refinement loop to architect.md

**Files:**
- Modify: `.claude/commands/architect.md` — add iterative refinement loop after TDD generation (Phase 6)

- [ ] **Step 1: Locate the end of Phase 6 in architect.md**

Find the section after `Save to docs/TDD.md` — the paragraph that says "ask the developer to review. Make requested changes."

- [ ] **Step 2: Insert the meta-prompting refinement loop**

Replace the short "ask the developer" paragraph with:

```markdown
## Phase 7 — Iterative Refinement Loop

After generating the initial TDD, run up to **2 automatic refinement passes** before asking the developer to review.

### Pass 1: Self-Critique
Score the TDD on these axes (0–10 each):
- **Completeness** — every GDD system has a TDD section
- **Testability** — every system can be tested in isolation as written
- **Performance** — hot paths are identified and mitigation is specified
- **Rendering** — Section 13 is fully filled (atlas plan, draw call strategy, canvas split)
- **Clarity** — no "TBD", no vague "handle appropriately" language

If any axis scores below 7: rewrite that section inline and re-score.

### Pass 2: Consistency Check
- Do class names in Section 16 (Class Index) match names used in system sections?
- Do event names match between publisher sections and subscriber sections?
- Does the assembly layout (Section 5) cover all classes in Section 16?

Fix any inconsistencies inline.

### Final Output
Print the refinement summary:
```
TDD Refinement Summary
Completeness: [score]/10 → [score after fix]/10
Testability: [score]/10 → [score after fix]/10
Performance: [score]/10 → [score after fix]/10
Rendering: [score]/10 → [score after fix]/10
Clarity: [score]/10 → [score after fix]/10

Issues fixed: [N]
Issues remaining: [list any remaining open questions]
```

Then ask the developer to review. Make requested changes. Once confirmed, inform: "TDD is complete. Run `/plan-workflow` to generate the execution plan."
```

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/architect.md
git commit -m "feat: add meta-prompting iterative refinement loop to /architect"
```

---

### Task 5: Add meta-prompting refinement loop to create-plan.md

**Files:**
- Modify: `.claude/commands/create-plan.md` — strengthen the Planner step with complexity-aware approach synthesis

- [ ] **Step 1: Locate the Planner prompt in create-plan.md**

Find `## Step 2 — Planner`. The prompt inside says "You are a senior technical writer...".

- [ ] **Step 2: Add approach synthesis block to the Planner prompt**

Inside the Planner subagent prompt, after the `## Feature / Bug to Plan` section and before `## Project Context`, insert:

```markdown
## Complexity Assessment

Before writing the plan, score the task complexity (0.0–1.0):
- 0.0–0.3: Simple — single file change, no new interfaces
- 0.4–0.6: Medium — multi-file, new interface or event
- 0.7–1.0: Complex — new module, cross-system, ECS/Addressables

For **Medium** tasks: propose 2 approaches with trade-offs, pick one, justify.
For **Complex** tasks: propose 3 approaches. Run a second internal critique pass on the chosen approach before writing tasks — check for hot-path allocations, missing cancellation tokens, and incomplete DI wiring.

Print the complexity score and chosen approach before the plan tasks.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/create-plan.md
git commit -m "feat: add complexity-aware approach synthesis to /create-plan planner step"
```

---

## Summary

| Task | File(s) | Type |
|------|---------|------|
| 1 | `.claude/agents/unity-developer.md` | New file |
| 2 | `.claude/commands/learn.md` | Insert block |
| 3 | `.claude/commands/implement.md`, `fix.md` | Insert block |
| 4 | `.claude/commands/architect.md` | Insert block |
| 5 | `.claude/commands/create-plan.md` | Insert block |
