# Unity Claude AI Template

A personal Claude Code configuration template for Unity 6 projects. Drop the `.claude/` folder into any Unity project to get automatic code quality enforcement, slash commands, and AI-assisted workflows — all following a consistent architecture.

---

## Table of Contents

- [What This Is](#what-this-is)
- [Quick Start](#quick-start)
- [Configuration File Map](#configuration-file-map)
- [Stack](#stack)
- [Usage Modes](#usage-modes)
- [Adding to an Existing Project](#adding-to-an-existing-project)
- [Building a Game from Scratch](#building-a-game-from-scratch)
- [Hooks — Auto-Enforced on Every Write](#hooks--auto-enforced-on-every-write)
- [Slash Commands](#slash-commands)
- [Agents](#agents)
- [Model Tiers](#model-tiers)
- [Recommended Plugins](#recommended-plugins)
- [Review Modes](#review-modes)
- [Director Gates](#director-gates)
- [Session State](#session-state)
- [Engine Version Reference](#engine-version-reference)
- [Built-In Skills](#built-in-skills)
- [Writing New Skills](#writing-new-skills)
- [Hook Audit Log](#hook-audit-log)
- [Manual Setup](#manual-setup-required-after-setup-project)
- [Architecture in a Nutshell](#architecture-in-a-nutshell)
- [Project-Specific Files](#project-specific-files-not-in-this-template)
- [License](#license)

---

## What This Is

Claude Code reads the `.claude/` folder when it opens a project. This template pre-loads it with:

- **Rules** — architecture, naming, testing, ECS, serialization, and Addressables standards that Claude follows automatically
- **Hooks** — shell scripts that run on every file write, blocking bad patterns before they land
- **Commands** — slash commands for common workflows (`/new-module`, `/setup-project`, `/debug-session`, etc.)
- **Agents** — specialized AI roles (`unity-coder`, `unity-fixer`, `unity-reviewer`, `unity-scout`, `committer`, and more)

---

## Quick Start

### Prerequisites

Install these packages in Unity Package Manager before running `/setup-project`:

| Package | Source | Package ID |
|---------|--------|-----------|
| **VContainer** | OpenUPM or git URL | `jp.hadashikick.vcontainer` |
| **UniTask** | OpenUPM or git URL | `com.cysharp.unitask` |
| **New Input System** | Package Manager | `com.unity.inputsystem` |

Optional packages are installed separately — see [Manual Setup](#manual-setup-required-after-setup-project).

### 1. Copy into your project

```
your-unity-project/
└── .claude/
    ├── CLAUDE.md
    ├── rules/
    ├── hooks/
    ├── commands/
    ├── agents/
    └── settings.json
```

### 2. Open with Claude Code

```bash
cd your-unity-project
claude
```

### 3. Run setup

```
/setup-project
```

This generates project-specific boilerplate: assembly definition files, base framework classes (`IEventBus`, `EventBus`, `EventBusAccessor`, `ModuleInstaller`, `AppInstaller`, `AppScope`). If MCP is connected, it also creates scenes, sets up AppScope in the Bootstrap scene, wires `AppInstaller`, and configures Build Settings — all through the Unity Editor automatically.

**Feature selection:** `/setup-project` asks about Addressables, Testing, and ECS DOTS. Based on your answers it writes `.claude/project-features.json`, skips irrelevant folders and asmdefs, removes disabled hooks from `settings.json`, and adds a `## Project Features` header to `CLAUDE.md`.

**Conflict detection (Step 0):** If `.claude/project-features.json` already exists, setup compares it against the actual project (folder presence, `manifest.json`) and reports any conflicts — useful after a partial or manual cleanup.

> **Package gating:** If VContainer/UniTask/Input System are missing, setup creates only the folder structure and stops. If NSubstitute DLL is missing (and Testing=yes), test `.asmdef` references and test templates are skipped. Re-run once packages are installed to continue.

---

## Configuration File Map

`CLAUDE.md` is the main entry point Claude Code reads at session start. It was split into multiple smaller files to avoid context/memory limits — the `@file` syntax includes them inline at load time.

### `.claude/CLAUDE.md` — Main entry point

Contains: stack requirements, session start instructions, hooks table (blocking), commands table, review modes, director gates, and session state. Includes three `@`-referenced sub-files:

| Referenced file | What it contains |
|-----------------|-----------------|
| `.claude/docs/hooks-warning.md` | Warning hooks (exit 0) — full table of non-blocking style/quality checks |
| `.claude/docs/agents-index.md` | All custom agents and their roles |
| `.claude/docs/skills-index.md` | Skills library index — core, platform, systems, third-party |

### `.claude/rules/` — Auto-loaded rule files

| File | Covers |
|------|--------|
| `architecture.md` | VContainer DI, module structure, IEventBus, EventBusAccessor, Provider pattern, InputView, AppScope |
| `csharp-unity.md` | Naming, namespaces, #region, null checks, UniTask, encapsulation |
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas |
| `serialization.md` | FormerlySerializedAs, Unity null checks, SerializeReference |
| `unity-specifics.md` | Editor guards, platform defines, lifecycle order, no coroutines |
| `testing.md` | Test type decision tree (EditMode / PlayMode-Programmatic / PlayMode-Scene / ECS / NoTest), NSubstitute, AAA pattern, assembly setup |
| `ecs-dots.md` | Authoring/Baker, component naming, ISystem+IJobEntity, ECB, Hybrid linking |
| `addressables.md` | No Resources.Load, async loading, handle lifecycle, address constants |
| `event-patterns.md` | UnityEvent forbidden, IEventBus vs Action vs C# event decision tree |
| `scene-hierarchy.md` | Standard 6-container scene hierarchy (`[Setup]` → `[Services]` → `[UI]` → `[Environment]` → `[Characters]` → `[VFX]`), classification table, prefab/container rules |

### `.claude/docs/` — Key reference docs (not loaded at startup)

| File | Purpose |
|------|---------|
| `hooks-blocking.md` | Blocking hooks table (`@`-included in CLAUDE.md) |
| `hooks-warning.md` | Warning hooks table (`@`-included in CLAUDE.md) |
| `agents-index.md` | Agent roster (`@`-included in CLAUDE.md) |
| `skills-index.md` | Skills library index (`@`-included in CLAUDE.md) |
| `commands.md` | Commands reference (`@`-included in CLAUDE.md) |
| `director-gates.md` | Full gate definitions (SCOPE, ARCHITECTURE, BREAKING, QUALITY, COMMIT) |
| `architecture-summary.md` | Key architecture rules summary |
| `context-management.md` | Review modes, compaction, checkpoint usage |
| `quick-start.md` | Quick start guide |
| `setup-checklist.md` | Manual post-setup steps |
| `model-tiers.md` | Model tier definitions and aliases |

### `docs/` — Human-readable project docs

| File | Purpose |
|------|---------|
| `ARCHITECTURE.md` | High-level system architecture diagram and pipeline flow |
| `SETUP.md` | Quick start, adding to existing project, hook audit log, model tiers |
| `WORKFLOW.md` | Full pipeline flows for `/implement`, `/fix`, `/orchestrate`, etc. |
| `CATCH_UP.md` | Auto-generated codebase guide (created by `/catch-up`, not committed) |

---

## Stack

### Required

| Package | Role |
|---------|------|
| **VContainer** | Dependency injection |
| **UniTask** | Async/await (replaces coroutines) |
| **New Input System** | Input handling |

### Optional (selected during `/setup-project`)

| Package | Role | When disabled |
|---------|------|---------------|
| **Addressables** | Runtime asset loading | Addressables rules and skills are skipped |
| **NSubstitute** | Test mocking (manual DLL install) | Test folders, asmdefs, and test hooks are skipped |
| **Unity ECS DOTS** | Data-oriented systems | ECS folder, asmdef, and ECS hooks are skipped |

`/setup-project` asks about each optional feature upfront and writes `.claude/project-features.json`. Hooks and commands automatically skip disabled features — no false warnings, no irrelevant rules.

---

## Usage Modes

| Mode | When to use |
|------|-------------|
| **New project** | Run `/setup-project` to generate the full folder structure, assembly definitions, and base classes from scratch |
| **Existing project** | Copy `.claude/` only — hooks and commands work immediately. Migrate code gradually, module by module |

---

## Adding to an Existing Project

You do **not** need to start from scratch. The `.claude/` folder is self-contained and can be dropped into any existing Unity project.

### What works immediately (zero migration needed)

- All slash commands (`/debug-session`, `/review-code`, `/performance-audit`, etc.)
- All warning hooks — they log issues but never block writes
- Rules — Claude follows the architecture standards when writing new code

### What will block existing code

The blocking hooks enforce patterns that legacy code likely violates. Before adding this template to an existing project, decide how to handle each:

| Hook | What it blocks | Migration path |
|------|---------------|----------------|
| `check-vcontainer-singleton` | Static singletons | Migrate to VContainer registration — or temporarily disable the hook |
| `check-input-system` | `Input.GetKey` / `Input.GetAxis` | Replace with New Input System + `InputView` |
| `check-unity-event` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` | Use `IEventBus`, `Action`/`Func`, or C# `event` keyword |
| `check-time-scale` | `Time.timeScale =` assignment | Use IEventBus + PauseService pattern |
| `check-pure-csharp` | `using UnityEngine` in `_Framework/` | Move Unity calls to provider classes |
| `guard-editor-runtime` | Unguarded `UnityEditor` in runtime code | Wrap with `#if UNITY_EDITOR` |

### Recommended migration approach

1. **Copy `.claude/` into your project** — commands and warnings are active immediately
2. **Temporarily disable blocking hooks** you're not ready for: comment out the relevant `[[hooks]]` entry in `.claude/settings.json`
3. **Run `/check-portability` on existing modules** to see what needs to change
4. **Migrate module by module** — new code follows the template, legacy code migrates on touch
5. **Re-enable hooks** as each area of the codebase is migrated

> **Note:** If VContainer, UniTask, or the New Input System are not yet installed, add them via Package Manager before enabling the hooks that depend on them.

---

## Building a Game from Scratch

### Phase 1 — Idea & Design

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/game-idea` | Manual — single step | Refines a raw idea into a GDD — surfaces assumptions, defines scope, creates a "Not Doing" list |
| `/architect` | Manual — single step | Converts the GDD into a TDD — `unity-critic` adversarially challenges the design before you review |
| `/grill-me [plan or file]` | Manual — single step | Stress-tests a plan or decision — one pointed question at a time, recommends an answer, ends with a Decision Record |

### Phase 2 — Planning

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/plan-workflow` | Manual — single step | Breaks the TDD into phases and tasks with agent types, inputs/outputs, and acceptance criteria → **WORKFLOW.md** |
| `/dry-run` | Manual — single step | *(optional)* Preview the orchestration plan without executing — shows agent assignments, phase count, risk points |

### Phase 3 — Project Setup

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/setup-project` | Manual — single step | Detects existing state → asks feature questions → generates folder structure, `.asmdef` files, and base framework classes |

### Phase 4 — Implementation

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/orchestrate` | Manual to start. **Within each phase:** tester → coder → verifier → reviewer → committer run **automatically**. **Between phases:** pauses and asks `Proceed?` | Executes `WORKFLOW.md` end-to-end, phase by phase |
| `/continue` | Manual — resumes interrupted orchestrate | Resumes an interrupted orchestration run from the event journal |

### Phase 5 — Quality

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/qa` | Manual to start. Inside: **ralph → silent-failure-hunt → validate** run **automatically** | Full quality pipeline — preferred entry point for Phase 5 |
| `/validate` | Manual — single step | Verifies exit criteria for a completed phase |
| `/review-code` | Manual — single step | Deep review of specific files via `unity-reviewer` |
| `/silent-failure-hunt` | Manual — single step | Audits for swallowed exceptions, async void, event leaks |
| `/performance-audit` | Manual — single step | Hot path allocation and draw call audit |
| `/ralph` | Manual to start. Inside: compile + test → fix loop (max 10 iterations) run **automatically** | Relentless verify-fix loop — refuses to stop until the project is clean |
| `/graphics-setup <mobile\|pc>` | Manual to start. Pauses for approval before creating assets | Tune or recreate URP quality tiers after gameplay is stable |
| `/audio-clip-setup [path]` | Manual to start. Pauses for commit confirmation at the end | Audit and fix AudioClip import settings before a build |

### Phase 6 — Documentation & Learning

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/learn` | Manual — single step | Extracts project-specific patterns into `.claude/skills/learned/` |
| `/catch-up` | Manual — single step | Generates a human-readable codebase guide at `docs/CATCH_UP.md` |
| `/adr <decision>` | Manual — single step | Records an Architecture Decision Record to `docs/decisions/` |
| `/create-changelog` | Manual — single step | Creates or updates `CHANGELOG.md` |
| `/update-claude-md` | Manual — single step | Syncs CLAUDE.md tables with actual project state (hooks, rules, commands, agents) |
| `/smart-commit` | Manual to start. Inside: analyze → group → commit run **automatically** | Groups dirty working tree into logical commits |

### Full Flow

Every command is **manually triggered** — there is no automatic chaining between phases.

```
/game-idea → /architect → /plan-workflow → /setup-project → /orchestrate
                                                                    ↓
                                                    /qa → /review-code → /performance-audit
                                                                    ↓
                                                         /learn → /smart-commit
```

#### When to run `/qa`

Run `/qa` after any implementation work outside of `/orchestrate` — e.g. after `/implement`, `/fix`, or any multi-file change. It is your pre-commit quality gate.

Skip `/qa` if you're inside an active `/orchestrate` run — the phase gate already covers it.

### Incremental Development (existing project or single feature)

| Command | How it runs | When to use |
|---------|------------|-------------|
| `/implement` | Manual to start. Inside: test writer → coder → verifier → reviewer → silent failure audit → committer run **automatically** | Implement a feature or task with full TDD pipeline |
| `/fix` | Manual to start. Inside: unity-fixer + unity-scout → test writer → coder → verifier → reviewer → silent failure audit → committer run **automatically** | Bug fix when stack trace clearly points to root cause |
| `/fix-deep` | Manual to start. Inside: log intake → hypothesis → debug injection → evidence gate → fix (only if proven) → committer run **automatically**. **Refuses to fix if root cause is unproven** | Logic bugs, intermittent issues, or any uncertain root cause |
| `/fix-smart` | Manual to start. Inside: context package → **Codex autonomous** (analyze + fix + verify) → Claude architecture review → [Codex revision loop max 3x] | Use when `/fix` or `/fix-deep` failed after 2+ attempts — Codex reads code directly without prior hypotheses |
| `/new-module` | Manual — single step | Scaffold a 5-file module (Interface, Service, Config, Installer, Events) |

> **`/fix` vs `/fix-deep` vs `/fix-smart`:** Use `/fix` when the stack trace clearly points to the root cause. Use `/fix-deep` for logic bugs, "sometimes happens" issues, or any case where the root cause is uncertain. Use `/fix-smart` when both have failed — Codex takes over autonomously, Claude reviews for architecture compliance.

---

## Hooks — Auto-Enforced on Every Write

Hooks run silently in the background every time Claude writes or edits a C# file.

### Blocking (exit 2 — stops the write)

| Hook | What it blocks |
|------|---------------|
| `block-git-push` | `git push` — Claude cannot push; user always pushes manually |
| `block-scene-edit` | Direct editing of `.unity`, `.prefab`, `.asset` YAML |
| `guard-editor-runtime` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-pure-csharp` | `_Framework/` referencing `_GameFolders` or other project folders |
| `check-input-system` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-unity-event` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` |
| `check-time-scale` | `Time.timeScale =` assignment |
| `check-vcontainer-singleton` | Static singleton patterns outside of `EventBusAccessor` |
| `guard-critical-files` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation — exception: test assemblies |
| `check-config-protection` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` — exception: test assemblies |
| `gateguard` (PreToolUse) | Edit/Write on any C# file that has not been read in the current session |
| `guard-reviewer-order` (PreToolUse) | `unity-reviewer` spawn if Codex CLI is installed but `codex:codex-rescue` has not reviewed the current pipeline pass |
| `check-no-runtime-instantiate` | `new GameObject()` — blocked outside `Pool/Factory/Spawner` files and test assemblies |
| `check-enum-byte-base` | `enum` without `: byte` base inside `IComponentData` or `IEvent` structs — use `: ushort` if 255+ values needed |

### Warnings (exit 0 — logged to stderr, does not block)

| Hook | What it warns |
|------|--------------|
| `check-no-linq-hotpath` | LINQ inside `Update` / `FixedUpdate` / `LateUpdate` |
| `check-no-hotpath-expensive-calls` | `GetComponent`, `Camera.main`, `FindObjectOfType`, bare `transform.`, `tag ==`, `SendMessage` in hot paths |
| `check-getcomponent-in-awake` | `GetComponent`/`GetComponentInChildren` in `Awake` — prefer `[SerializeField]` Inspector assignment |
| `check-no-runtime-instantiate` (Destroy) | `Destroy()` — use `pool.Return()` / `SetActive(false)` or `Addressables.ReleaseInstance()` instead |
| `check-test-exists` | Logic class with no matching test file |
| `warn-serialization` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `check-unused-code` | Unused private members and imports |
| `check-ecs-structural-changes` | `EntityManager.AddComponent/DestroyEntity` inside ECS system (use ECB) |
| `check-async-void` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation` | `async UniTask` methods missing `CancellationToken` parameter |
| `check-null-propagation` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |
| `check-test-scene-exists` (PostToolUse) | PlayMode test file references a scene not found in `_Scenes/TestScenes/` — suggests `/create-test` |
| `track-codex-review` (PostToolUse) | Creates `.claude/state/codex-reviewed` when `codex:codex-rescue` completes |
| `instinct-capture` (PostToolUse) | Captures tool-use observations for later distillation into instincts |
| `cost-tracker` (PostToolUse) | Logs every tool call with timestamp for cost auditing |
| `hook-logger` | Central audit logger — appends newline-delimited JSON to `~/.claude/hook-audit.log` |
| `instinct-distill` (Stop) | Distills captured observations into confidence-scored instincts |
| `session-restore` (SessionStart) | Restores session state from `.claude/state/` on session start |
| `session-save` (Stop) | Saves current session state to `.claude/state/` on stop |

---

## Slash Commands

### First-time project setup

| Command | How it runs | Description |
|---------|------------|-------------|
| `/setup-project` | Manual — single step | Detect existing state → ask feature questions → generate assembly definitions, base classes, and manual setup checklist |
| `/create-prefab-scene` | Manual — single step | **Legacy migration:** scan existing scenes for bare GameObjects, build a prefab inventory, create proper prefabs via MCP |

### Design

| Command | How it runs | Description |
|---------|------------|-------------|
| `/game-idea` | Manual — single step | Refine a raw idea into a GDD (assumption surfacing + "Not Doing" list) |
| `/architect` | Manual — single step | Create a Technical Design Document from a GDD (`unity-critic` adversarial challenge included) |
| `/grill-me [plan or file]` | Manual — single step | Stress-test a plan or decision — one pointed question at a time, produces a Decision Record on `/done` |
| `/refine-gdd` | Manual — single step | Iterate on an existing GDD |
| `/refine-tdd` | Manual — single step | Iterate on an existing TDD |
| `/plan-workflow` | Manual — single step | Create a phased execution plan from a TDD — assigns `parallel_group` numbers compatible with `/orchestrate` |

### Pipelines (multi-agent)

All pipeline commands are **manually triggered**. Once started, internal steps run automatically until done or blocked.

| Command | How it runs | Description |
|---------|------------|-------------|
| `/implement <task>` | Manual to start → test writer → coder → verifier → reviewer → silent failure audit → committer | TDD implementation pipeline for a single well-defined task |
| `/fix <bug>` | Manual to start → unity-fixer + unity-scout → test writer → coder → verifier → reviewer → committer | Bug fix pipeline — use when stack trace points to root cause |
| `/fix-deep <bug>` | Manual to start → log intake → hypothesis → debug injection → evidence gate → fix (only if proven) → committer. **Refuses to fix if root cause is unproven** | Evidence-first bug fix — use for logic bugs or intermittent issues |
| `/fix-smart <bug>` | Manual to start → context package → **Codex autonomous** (analyze + fix + verify) → Claude architecture review → [Codex revision loop max 3x] | Codex-first fix — escalate here when `/fix` or `/fix-deep` failed |
| `/migrate <pattern> in <scope>` | Manual to start → test guard → migrator → reviewer → committer | Legacy pattern migration (coroutine→UniTask, singleton→VContainer, etc.) |
| `/scene-setup <description>` | Manual to start → coder + unity-setup → verifier → reviewer → committer | Scene and prefab wiring pipeline |
| `/create-plan <file> <what>` | Manual to start → researcher → planner → reviewer loop → save → optional implementer | Create a phased WORKFLOW.md plan from a spec |
| `/update-plan <file> <change>` | Manual to start → analyzer → planner → reviewer loop → save → optional implementer | Update an existing plan |
| `/smart-commit` | Manual to start → analyze dirty tree → group commits → commit | Group working tree changes into logical semantic commits |
| `/orchestrate` | Manual to start. **Within each phase:** tester → coder → verifier → reviewer → committer. **Between phases:** pauses for `Proceed?` | Execute WORKFLOW.md end-to-end, phase by phase |

> Reviewer priority across all pipelines: Codex → unity-reviewer (falls back if Codex is unavailable). Review loops: CHANGES NEEDED → coder fixes → reviewer re-checks → repeat (max 3 passes).
>
> **Tester isolation:** The `tester` step in `/implement`, `/fix`, `/orchestrate`, and `/migrate` runs as an isolated `claude` subagent. It receives a clean context window and reads `tester.md` + `testing.md` directly — preventing implementation context from leaking into test decisions. The `committer` step runs inline since simple git operations don't benefit from isolation.

### Development

| Command | How it runs | Description |
|---------|------------|-------------|
| `/new-module` | Manual — single step | Generate the 5-file module structure (Interface, Service, Config, Installer, Events) |

### Quality

| Command | How it runs | Description |
|---------|------------|-------------|
| `/qa` | Manual to start → ralph → silent-failure-hunt → validate | Full quality pipeline — run after any implementation or before push |
| `/ralph` | Manual to start → compile + test → fix loop (max 10 iterations) | Relentless verify-fix loop — refuses to stop until green or stuck |
| `/validate` | Manual — single step | Validate a completed phase via unity-verifier |
| `/review-code` | Manual — single step | Deep code review on specific files via unity-reviewer |
| `/silent-failure-hunt` | Manual — single step | Audit files for swallowed exceptions and silent error patterns |
| `/performance-audit` | Manual — single step | Hot path allocation and draw call audit |
| `/debug-session` | Manual to start → root cause analysis → unity-fixer or unity-fixer-lite → learner skill | Structured root cause analysis session |
| `/clean-slop` | Manual — single step | Remove AI-generated bloat (dead code, useless abstractions) |
| `/check-portability` | Manual — single step | Audit a module for copy-paste portability to another project |
| `/learn` | Manual — single step | Extract project-specific patterns into `.claude/skills/learned/` |
| `/generate-tests` | Manual — single step | Write missing tests for an existing class |
| `/create-test <FeatureName>` | Manual — single step | Unified test generator — EditMode unit test, PlayMode-ECS, PlayMode-Programmatic (`new GameObject().AddComponent<>()`, no scene), or PlayMode-Scene (TestScope + TestInstaller + stub + scene via MCP + auto-adds scene to Build Settings) |
| `/graphics-setup <mobile\|pc>` | Manual to start. Pauses for approval before creating assets | Show tier plan, create URP Pipeline Assets + Renderer Data + URPQualityConfiguration via MCP |
| `/audio-clip-setup [path]` | Manual to start. Pauses for commit confirmation at the end | Scan AudioClip assets, categorize, apply optimized import settings via MCP |
| `/discover [--dry-run\|--write] [--only <pkg>]` | Manual — single step (`--dry-run` default) | Walk `Packages/manifest.json`, classify packages, write skill drafts, detect compliance violations |
| `/update-scene-hierarchy [scene]` | Manual — single step | Reorganize scene containers — moves misplaced GOs into correct `[Setup]`/`[Services]`/`[UI]`/`[Environment]`/`[Characters]`/`[VFX]` containers |
| `/unity-scene-update [scene]` | Manual — single step | Full scene audit — reorganizes containers AND converts bare GameObjects to prefabs |

### Session & Context

| Command | How it runs | Description |
|---------|------------|-------------|
| `/caveman` | Manual — mode toggle | Ultra-compressed communication mode (~75% fewer tokens). Exit with `/normal` |
| `/checkpoint` | Manual — saves file, then you run `/clear` | Save conversation summary to `.claude/state/checkpoint.md` for the next session |
| `/context-prime` | Manual — single step | Brief Claude on project context at the start of a session |
| `/search <query>` | Manual to start → Explore + unity-scout → reviewer loop (max 5) → findings → action router | Codebase investigation pipeline — presents findings and recommends a next command |
| `/dump` | Manual — single step | Save current session notes and decisions to `.claude/logs/` |
| `/five` | Manual — single step | 5 Whys root cause analysis |
| `/continue` | Manual — resumes orchestrate | Resume an interrupted `/orchestrate` run from the event journal |
| `/status` | Manual — single step | Report current pipeline stage: GDD → TDD → WORKFLOW progress summary |
| `/dry-run` | Manual — single step | Preview the orchestration plan for a WORKFLOW.md without executing |
| `/instincts` | Manual — single step | Manage instinct library: status, list, evolve, promote, export, import |

### Documentation

| Command | How it runs | Description |
|---------|------------|-------------|
| `/catch-up` | Manual — single step | Generate a human-readable codebase guide at `docs/CATCH_UP.md` |
| `/adr <decision>` | Manual — single step | Record an Architecture Decision — e.g. `/adr why VContainer over Zenject`; writes to `docs/decisions/NNN-topic.md` |
| `/create-changelog` | Manual — single step | Create or update `CHANGELOG.md` from recent git commits |
| `/mermaid` | Manual — single step | Generate a Mermaid architecture diagram for a module or system |
| `/update-claude-md [--section]` | Manual — single step | Sync CLAUDE.md tables with actual project state — hooks, rules, commands, agents. Shows diff before writing |

---

## Agents

Specialized AI roles invoked automatically by commands or directly by name.

| Agent | Role |
|-------|------|
| `coder` | **Pure C# only — no Unity API.** Used for `_Framework/`, `Abstracts/`, and pure C# targets in complexity-scored pipelines. |
| `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks. Spawned as an isolated `claude` subagent (clean context window) so test writing is not polluted by implementation context. |
| `reviewer` | Principal-level code review — architecture, naming, performance |
| `unity-developer` | Unity 6 specialist — second reviewer for complex tasks; checks hot paths, draw calls, ECS safety, Addressables lifecycle, prefab structure |
| `committer` | Smart phase commit manager — semantic git commits. Runs inline (not as subagent) — simple git ops don't benefit from context isolation. |
| `unity-setup` | Scene, prefab, ScriptableObject configuration via Unity MCP — enforces prefab rules |
| `debugger` | Root cause analysis — VContainer, ECS, UniTask, Input bug patterns |
| `migrator` | Legacy pattern migration — coroutine→UniTask, singleton→VContainer, legacy input |
| `silent-failure-hunter` | Swallowed exception audit — empty catch, `.Forget()` without handler, dangerous fallbacks |
| `package-analyzer` | Read-only analyst — walks `Packages/manifest.json` and resolved package directories, emits multi-file skill drafts under `.claude/skills/third-party/<pkg>/`. Detects prefabs, maps them to `_GameFolders/Prefabs/<Category>/` destinations, and scans for architecture violations. For singletons (all variants: `Instance`, `_instance`, `Current`/`Shared`/`Main`/`Default`, `GetInstance()`, `DontDestroyOnLoad`), generates Adapter pattern boilerplate + NSubstitute mock lines instead of generic fix notes. |
| `unity-critic` | Opus adversarial plan challenger — stress-tests architecture decisions before implementation |
| `unity-shader-dev` | URP shader authoring — ShaderGraph, HLSL, render passes |
| `unity-ui-builder` | UI Toolkit specialist — UXML, USS, runtime panel setup, data binding |
| `unity-optimizer` | Runtime performance — allocations, draw calls, ECS hot paths, profiler-guided fixes |
| `unity-scene-builder` | Scene composition via MCP — hierarchy, lighting, camera, volumes |
| `graphics-setup-agent` | Creates URP Pipeline Assets (Low/Medium/High) for mobile or PC, configures Renderer Data, wires Quality Settings via MCP |
| `audio-clip-agent` | Scans AudioClip assets, categorizes them, applies optimized import settings via temp Editor script + MCP |
| `unity-linter` | Static analysis pass — naming, regions, hook-rule compliance |
| `unity-security-reviewer` | Security audit — data exposure, serialization risks, network surface |
| `unity-build-runner` | CI/build pipeline — platform flags, build profiles, Addressables baking |
| `unity-coder` | **Primary Unity coder for medium/complex tasks.** Full Unity C# — MonoBehaviours, providers, installers, scene wiring. Used when complexity ≥ 0.4. |
| `unity-coder-lite` | Lightweight Unity coder for small isolated changes |
| `unity-fixer` | Bug fixer with full context — reads surrounding code before patching |
| `unity-fixer-lite` | Quick targeted fix for a single well-scoped defect |
| `unity-git-master` | Git workflow — branching strategy, conflict resolution, history rewrite |
| `unity-migrator` | Pattern migration specialist — coroutine→UniTask, singleton→VContainer, legacy input |
| `unity-network-dev` | Netcode for GameObjects / Unity Transport — lobby, relay, RPCs |
| `unity-prototyper` | Rapid prototype scaffolding — speed over correctness, clearly marked TODOs |
| `unity-reviewer` | Unity-specific code review — full checklist including ECS, Input, Addressables |
| `unity-scout` | Codebase explorer — maps dependencies, surfaces risks, no writes |
| `unity-test-runner` | Runs Edit/Play Mode tests via MCP and reports failures with context |
| `unity-test-builder` | Builds Play Mode test scenes — creates TestScope, TestInstaller, PlayMode test stub, wires TestBootstrap in scene via MCP, and adds the test scene to Build Settings automatically; used by `/create-test` |
| `unity-verifier` | Post-implementation verification — compile + test + prefab/scene integrity |

---

## Model Tiers

Different tasks need different models. Use the right tier to balance speed and cost:

| Tier | Model | Alias | Commands |
|------|-------|-------|----------|
| **light** | Haiku | `claude-light` | `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | Sonnet | `claude-normal` | `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/new-module`, `/performance-audit`, `/clean-slop`, `/catch-up` |
| **heavy** | Opus | `claude-heavy` | `/architect`, `/plan-workflow`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

### Setup

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/your-unity-project/.claude/aliases.sh
```

Or manually:

```bash
alias claude-light='claude --model claude-haiku-4-5'
alias claude-normal='claude --model claude-sonnet-4-6'
alias claude-heavy='claude --model claude-opus-4-7'
```

The alias file lives at `.claude/aliases.sh`.

---

## Recommended Plugins

These Claude Code plugins enhance the pipeline when installed. All are **optional** — every command falls back gracefully when a plugin is unavailable.

Install via `/plugin` in Claude Code:

| Plugin | Commands that use it | What it adds |
|--------|---------------------|--------------|
| `superpowers` | `/implement`, `/fix`, `/fix-deep`, `/debug-session`, `/migrate`, `/scene-setup`, `/architect`, `/orchestrate`, `/qa`, `/validate` | TDD discipline, brainstorming before complex features, systematic debugging, verification before completion |
| `skill-creator` | `/learn` | Structured skill drafting with description optimization |
| `code-simplifier` | `/clean-slop`, `/implement` (completion) | Post-implementation quality pass — reuse, efficiency, clarity |
| `claude-md-management` | `/implement`, `/fix` (completion) | Automatically updates CLAUDE.md with session learnings |
| `code-review` | `/review-code` | Additional review checklist layer on top of unity-reviewer |

**Availability check:** Each command that uses plugins prints a preflight status line before starting:
```
Plugins: superpowers:systematic-debugging [✓] | claude-md-management [✗]
```
`✓` = available and will be used · `✗` = not installed, fallback active

---

## Review Modes

Control pipeline depth by editing `production/review-mode.txt`:

| Mode | Effect | When to use |
|------|--------|-------------|
| `solo` | unity-coder → Committer only — no tests, no review | Prototypes, game jams |
| `lean` | Standard pipeline (default) | Regular solo development |
| `full` | Standard pipeline + unity-developer reviewer always active | Team review, learning sessions |

Change mode: `echo "full" > production/review-mode.txt`

---

## Director Gates

Human-pause checkpoints defined in `.claude/docs/director-gates.md`. Every pipeline command stops at the relevant gate and waits for `go` before spawning any agents. The `guard-gate-cleared.sh` hook enforces this at the tool level.

### Human-Pause Gates

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected, or always in `/new-module` | Approve proposed module structure |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED | Choose: `fix` / `skip` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |

### Automated Check Gates

| Gate | Checks |
|------|--------|
| `TD-ARCHITECTURE` | VContainer DI, interface-driven, IEventBus, Provider pattern, module boundaries |
| `TD-UNITY-RISK` | Post-cutoff API risk — reads `docs/engine-reference/unity/` before any architecture decision |
| `TD-PERFORMANCE` | Zero-alloc hot paths, draw call budget, ECS ECB usage, Addressables handle lifecycle |
| `TD-COMPILE` | Unity MCP compile + Edit Mode test pass — mandatory before reviewer |
| `CD-SCOPE` | YAGNI check — flags out-of-scope files, unnecessary abstractions, speculative features |

---

## Session State

### Structured State (`.claude/state/`)

| File | Contents |
|------|----------|
| `session.json` | Current branch, phase, modified files, active task, decisions |
| `learnings.jsonl` | Structured learning records accumulated across sessions |
| `instincts/` | Project-specific and global instinct library (confidence-scored patterns) |

- `session-restore.sh` (SessionStart hook) loads state at the start of every session
- `session-save.sh` (Stop hook) persists state when the session ends
- Use `/instincts` to view, evolve, promote, or export instincts

### Human-Readable Checkpoint

`production/session-state/active.md` is a living checkpoint updated after each milestone.

### Context Management with /checkpoint

When context is getting full (~70-80%), use `/checkpoint` instead of losing progress:

```
Context ~70-80% full
      ↓
/checkpoint
      ↓  Claude writes summary to .claude/state/checkpoint.md
/clear
      ↓  Context fully freed
Send: "read .claude/state/checkpoint.md"
      ↓  Claude reads file, resumes from where you left off, deletes the file
```

**Why not just `/compact`?** `/compact` summarizes in-memory — context shrinks but doesn't fully clear. `/checkpoint` + `/clear` fully resets context for maximum token recovery while preserving all progress in a file.

---

## Engine Version Reference

`docs/engine-reference/unity/` contains Unity 6 LTS risk assessments:

| File | Contents |
|------|----------|
| `VERSION.md` | Risk levels per system area (ECS, UI Toolkit, Netcode, etc.) |
| `breaking-changes.md` | HIGH/MEDIUM risk API changes with migrations |
| `deprecated-apis.md` | Forbidden APIs and their replacements |
| `current-best-practices.md` | VContainer, UniTask, ECS, Input, Addressables, Rendering patterns |

`/architect` reads these automatically and stamps TDD sections that touch risky areas.

---

## Built-In Skills

Skills live under `.claude/skills/` and are loaded automatically by commands. They are read-only reference files that inform Claude's decisions — they do not execute code. The `/learn` command writes project-specific patterns to `skills/learned/`.

### Core (`skills/core/`)

| Skill | Covers |
|-------|--------|
| `model-routing` | Automatic model selection heuristics — file count, complexity, risk factors |
| `deep-interview` | 5-dimension ambiguity gating before implementation starts |
| `learner` | Post-debug insight extraction — writes findings to CLAUDE.md Project Learnings |
| `unity-instincts` | Instinct system for learned Unity patterns — capture, score, promote, apply |
| `assembly-definitions` | .asmdef authoring — references, platforms, define constraints |
| `source-driven-development` | Fetch official Unity docs before writing API calls — cites sources, flags deprecated APIs |
| `documentation-and-adrs` | ADR creation — `/adr` command writes to `docs/decisions/`, lifecycle management |
| `planning-and-task-breakdown` | Vertical slice decomposition + per-task acceptance criteria |
| `code-simplification` | Chesterton's Fence discipline for `/clean-slop` — understand before removing |
| `commit-trailers` | Conventional commit trailers — co-author, ticket links, sign-off |
| `event-systems` | IEventBus patterns — pub/sub, struct events, subscribe/unsubscribe lifecycle |
| `event-bus` | Project-specific IEventBus implementation — location, namespace, and code examples |
| `logging` | Project-specific DLog pattern — logging implementation, location, and usage |
| `save-load` | Project-specific SaveLoadSystem pattern — location, namespace, and usage |
| `tdd-nsubstitute` | Project-specific TDD pattern — assembly structure, test templates, and mock rules |
| `hud-statusline` | In-session status line rendering for pipeline progress |
| `object-pooling` | ObjectPool<T> setup, return-to-pool patterns, warm-up |
| `scriptable-objects` | ScriptableObject config authoring, CreateAssetMenu, validation |
| `serialization-safety` | FormerlySerializedAs, SerializeReference, Unity null semantics |
| `unity-mcp-patterns` | MCP tool call patterns for scene/prefab/asset operations |
| `playmode-scene-testing` | Play Mode scene test pattern — TestBootstrap prefab, TestScope, UnityTest patterns |
| `mcp-preflight` | 3-state MCP availability check — connected / disconnected / not installed |
| `test-type-router` | Determines test type (EditMode / PlayMode-ECS / PlayMode-Programmatic / PlayMode-Scene / NoTest) from class name or file path |

### Platform (`skills/platform/`)

| Skill | Covers |
|-------|--------|
| `mobile` | Touch input, safe area, haptics, app lifecycle |

### Systems (`skills/systems/`)

| Skill | Covers |
|-------|--------|
| `addressables` | Loading, handle lifecycle, label groups, preload |
| `animation` | Animator parameters, state machine behaviours, blend trees |
| `audio` | AudioMixer groups, snapshots, pooled AudioSource, spatial audio, beat sync, procedural SFX |
| `audio-mixer` | AudioMixer routing, exposed parameters, send/receive buses, ducking (sidechain), snapshot transitions |
| `audio-settings` | Audio settings UI, volume persistence via PlayerPrefs, IAudioSettingsService + VContainer wiring |
| `audio-clip-settings` | AudioClip import settings — PCM/ADPCM/Vorbis format selection, load type, platform overrides |
| `cinemachine` | Virtual cameras, blends, impulse, follow targets |
| `navmesh` | NavMeshAgent setup, dynamic obstacles, off-mesh links |
| `physics` | Layer matrix, non-alloc queries, trigger vs collision |
| `shader-graph` | URP shader nodes, property exposure, keyword variants |
| `ui-toolkit` | USS, UXML, data binding, runtime panel setup |
| `urp-pipeline` | Renderer features, camera stacking, custom render passes, SRP Batcher, Forward+ |
| `urp-quality-settings` | URP quality tiers (Low/Medium/High/Ultra), runtime asset swap, auto-detect, adaptive performance |
| `urp-lighting-shadows` | Directional/point/spot lights, shadow cascades, bias tuning, light layers, reflection probes |
| `urp-post-processing` | Bloom, DOF, Motion Blur, SSAO, Tonemapping, Color Grading, Vignette — setup, values, runtime control |
| `audio-mixer-mcp` | AudioMixer exposed parameters, AudioSource routing — configuration via MCP execute_code |
| `srp-batcher-mcp` | SRP Batcher enable/verify, UI Raycast Target audit, post-processing Volume cleanup via MCP |

### Third-Party (`skills/third-party/` and `skills/plugins/`)

Static pre-built skills. `skills/third-party/` holds folder-based skills (with subdirectories); `skills/plugins/` holds flat `.md` skills plus any skills generated by `/discover`.

**`skills/third-party/`**

| Skill | Covers |
|-------|--------|
| `dotween` | Tween creation, sequences, callbacks, memory management |
| `nsubstitute` | NSubstitute mock setup, argument matchers, received verification |
| `odin-inspector` | Custom attributes, validators, group drawers |
| `textmeshpro` | Font assets, rich text, SDF materials, localization |
| `unitask` | Async patterns, cancellation, `Forget()`, UniTaskVoid |
| `vcontainer` | Scope hierarchy, registration patterns, `IInitializable`/`IDisposable` lifecycle, DI failure diagnosis |

**`skills/plugins/`** (flat `.md` skills + `/discover` output)

| Skill | Covers |
|-------|--------|
| `odin-inspector` | Custom attributes, validators, group drawers |
| `primetween` | PrimeTween setup, tween API, sequences, and UniTask integration |
| `r3` | R3 (Cysharp) Observable, Subject, ReactiveProperty, and UniTask integration |
| `unitask` | Async patterns, cancellation, `Forget()`, UniTaskVoid |
| `unity-asmdef` | Assembly definition authoring, references, define constraints |
| `unity-editor-tools` | Custom Editor windows, PropertyDrawers, EditorUtility patterns |
| `unity-uitoolkit` | UI Toolkit runtime panels, UXML, USS, data binding |
| `vcontainer` | VContainer registration patterns, scope hierarchy, lifecycle |

#### Discovered Package Skills (`skills/third-party/<pkg>/`)

Generated by `/discover --write`. Each package folder contains `SKILL.md` plus optional split files for large packages:

| File | Covers |
|------|--------|
| `SKILL.md` | Trigger file — When to use, Key APIs summary, links to other files |
| `api.md` | Full API reference + idiomatic code examples |
| `prefabs.md` | Complete prefab list with duplication targets |
| `integration.md` | VContainer / UniTask / IEventBus bridge patterns + Prefab setup workflow |
| `test-strategy.md` | PlayMode test requirements, minimum scene setup, mock strategy |
| `samples.md` | Demo scene analysis — real GameObject/component hierarchy |
| `compliance.md` | Rule violations in the package + recommended fixes — **only written when violations exist** |
| `test-strategy.md` | PlayMode test requirements, minimum scene setup — includes **Mock Requirements** section when singletons detected |

Small packages (< 10 prefabs) use a single `SKILL.md`. Medium packages add `prefabs.md`. Large packages (50+) use the full split.

**Compliance severities:** `MUST-FIX` (blocking hooks will fire), `SHOULD-FIX` (architecture rules), `CONSIDER` (good practice).

**Singleton detection:** `/discover` catches all common singleton variants — `Instance`/`_instance` field, `Current`/`Shared`/`Main`/`Default` static properties, `GetInstance()`, `static readonly new`, and `DontDestroyOnLoad`. Since package code cannot be modified, every singleton finding generates an **Adapter pattern** boilerplate (interface + adapter class + AppScope registration + NSubstitute mock line) rather than a generic "register as IService" note. The `test-strategy.md` `Mock Requirements` section lists exactly which interfaces to mock in PlayMode tests.

---

## Writing New Skills

When adding a new skill under `.claude/skills/`, always include `model-tier` in the frontmatter:

```markdown
---
name: my-skill
description: What this skill does
user-invocable: true
model-tier: light   # light | normal | heavy
---
```

| Tier | Model | Use when |
|------|-------|----------|
| `light` | Haiku | Read-only tasks, formatting, quick summaries |
| `normal` | Sonnet | Code generation, review, debugging |
| `heavy` | Opus | Architecture, planning, creative design |

---

## Hook Audit Log

Every hook execution is logged to `~/.claude/hook-audit.log` as newline-delimited JSON:

```jsonc
{"ts":"2026-05-04T10:22:01Z","hook":"check-vcontainer-singleton","status":"BLOCKED","file":"Games/Concretes/GameManager.cs","project":"my-game"}
{"ts":"2026-05-04T10:22:02Z","hook":"warn-serialization","status":"OK","file":"Games/Concretes/GameManager.cs","project":"my-game"}
```

**Status values:** `OK` — passed · `BLOCKED` — write was stopped (exit 2) · `WARN` — warning logged (exit 0 with output)

```bash
# See all blocked writes today
grep BLOCKED ~/.claude/hook-audit.log | tail -20

# See which hooks fired on a specific file
grep "GameManager.cs" ~/.claude/hook-audit.log

# Count blocks per hook (which rule fires most)
grep BLOCKED ~/.claude/hook-audit.log | jq -r '.hook' | sort | uniq -c | sort -rn
```

The log is capped at 5000 lines and rotates automatically. It is global across all projects — the `project` field identifies which project each entry came from.

---

## Manual Setup (Required After `/setup-project`)

`/setup-project` handles most Unity Editor work automatically via MCP (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`). Only the following steps require manual action:

**NSubstitute** _(only if Testing=yes)_
1. Download `NSubstitute.dll` from [NuGet](https://www.nuget.org/packages/NSubstitute) — rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from `lib/`
2. Place at `Assets/Plugins/NSubstitute/NSubstitute.dll`
3. The `.asmdef` files generated by `/setup-project` already reference it via `precompiledReferences`

**New Input System — Project Settings**
1. Install via Package Manager: `com.unity.inputsystem`
2. Edit → Project Settings → Player → Active Input Handling → `Input System Package (New)` _(Unity restarts — cannot be set via MCP)_
3. Create `Assets/_GameFolders/Input/[ProjectName]Controls.inputactions`
4. Enable "Generate C# Class" in the `.inputactions` inspector

**settings.json hook entries** — Claude cannot edit `settings.json` (blocked by `check-config-protection.sh`). Add manually — see `.claude/docs/setup-checklist.md` for the exact JSON blocks:
- `check-test-scene-exists.sh` (PostToolUse, Write|Edit matcher)
- `guard-reviewer-order.sh` (PreToolUse, Agent matcher)
- `track-codex-review.sh` (PostToolUse, Agent matcher)

> **MCP unavailable?** If Unity Editor is not open or MCP is disconnected when `/setup-project` runs, Step 5d is skipped and a manual checklist is printed for scene creation, AppScope wiring, and Build Settings.

---

## Architecture in a Nutshell

> Full architecture diagrams (pipeline flow, agent pipeline, VContainer scope hierarchy, layer dependencies, hook flow): **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

> Architecture summary (key rules at a glance): **[.claude/docs/architecture-summary.md](.claude/docs/architecture-summary.md)**

```
_Framework/                  ← Never references _GameFolders or other project folders (may use UnityEngine internally)
  Events/                    ← IEventBus, IEvent
  Logging/
  SaveLoadSystems/

_GameFolders/Scripts/Games/
  Abstracts/                 ← interfaces, abstract classes
  Concretes/                 ← implementations, providers
    Audio/                   ← BasicAudioProvider, AudioRoot (Unity API here)
    Store/
  Ecs/                       ← DOTS: Authorings, Components, Systems
```

**Key rules:**
- VContainer for DI — no singletons, no service locators
- Each module is 5 files: `IService`, `Service`, `Configuration`, `Installer`, `Events`
- `AppScope` never changes — add modules via `AppInstaller.asset`
- `IEventBus` for cross-module communication — no direct cross-module calls
- `EventBusAccessor` static bridge for ECS ↔ Mono communication (only approved static accessor)
- Provider pattern — Unity API stays in `Concretes/<Module>/`, never in service classes
- Every scene GO is a prefab instance; root=logic components, `Body` child=visual components
- All prefabs under `_GameFolders/Prefabs/<Domain>/`; shared-base objects use Prefab Variants
- New Input System only — `InputView` owns `PlayerControls`
- UniTask everywhere — no coroutines, no `async void`, always pass `CancellationToken`
- Addressables for all runtime asset loading — no `Resources.Load`
- NSubstitute + AAA pattern for tests — only interfaces mocked

---

## Project-Specific Files (Not in This Template)

These are generated per-project and should NOT be committed back to this template:

```
.claude/skills/learned/    ← patterns extracted from your specific project
docs/CATCH_UP.md           ← auto-generated codebase guide (/catch-up)
docs/decisions/            ← ADRs specific to your game
docs/GDD.md                ← game design document (/game-idea)
docs/TDD.md                ← technical design document (/architect)
docs/WORKFLOW.md           ← phased execution plan (/plan-workflow)
```

Note: `docs/ARCHITECTURE.md`, `docs/SETUP.md`, and `docs/engine-reference/` are part of the template and should be kept.

---

## License

Copyright (c) 2026 Berk Terek — All rights reserved.
