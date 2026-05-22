# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Important Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking. A hook that only warns has minimal enforcement value.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.
- Claude's file tools (`Write`/`Edit`) cannot write `.unity` scene files — `block-scene-edit.sh` blocks this. **However, MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`) can create and wire scenes through the Unity Editor directly.** Always prefer MCP over listing manual Editor steps when MCP is connected.

## Required Stack

| Package | Source | Purpose |
|---------|--------|---------|
| **VContainer** | openupm / Package Manager | Dependency injection — replaces all singletons |
| **UniTask** | openupm / Package Manager | Async/await — replaces all coroutines |
| **New Input System** | Package Manager (com.unity.inputsystem) | Input — legacy Input API is blocked |

## Optional Features

Selected during `/setup-project`. Choices are saved to `.claude/project-features.json`. Disabled features have their hooks removed from `settings.json` and their rules skipped per the `## Project Features` header in this file (written by setup).

| Package | Source | Feature flag | When disabled |
|---------|--------|--------------|---------------|
| **Addressables** | Package Manager (com.unity.addressables) | `addressables` | Addressables rules and skills skipped |
| **NSubstitute** | Manual DLL install | `testing` | Test folders, asmdefs, test hooks skipped |
| **Unity ECS DOTS** | Package Manager (optional) | `ecs` | ECS folder, asmdef, ECS hooks skipped |

## Optional Plugins

Optional Claude Code plugins. Each pipeline command checks for these at Step 0/0.5 Plugin Preflight.

| Plugin | Commands | Threshold |
|--------|----------|-----------|
| `superpowers:test-driven-development` | `/implement` | always |
| `superpowers:brainstorming` | `/implement` (score ≥ 0.7), `/scene-setup` (score ≥ 0.7), `/architect` | conditional |
| `superpowers:systematic-debugging` | `/fix` (score ≥ 0.4), `/fix-deep` (score ≥ 0.4), `/debug-session` | conditional |
| `superpowers:verification-before-completion` | `/architect`, `/orchestrate`, `/qa`, `/validate`, `/migrate` (score ≥ 0.7) | conditional |
| `code-simplifier` | `/implement` | always |
| `claude-md-management:revise-claude-md` | `/implement`, `/fix` | always |

## Quick Start

@.claude/docs/quick-start.md

## Model Tiers

@.claude/docs/model-tiers.md

## Session Start

When starting a new conversation on this project, read these files first:
- `.claude/CLAUDE.md` (this file — already loaded)
- `.claude/rules/architecture.md` — module structure, VContainer, IEventBus patterns
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide

If the user asks to continue work on a specific module, also read its source files before making any changes.

## Rules (auto-loaded)

Detailed coding standards in `.claude/rules/`:

| File | Covers |
|------|--------|
| `architecture.md` | VContainer DI, module structure, IEventBus, EventBusAccessor, Provider pattern, InputView, AppScope |
| `csharp-unity.md` | Naming, namespaces, #region, null checks, UniTask, encapsulation |
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas; **material folder structure** (`Arts/Materials/<Domain>/`); shader authoring → `unity-shader-dev` agent (HLSL veya ShaderGraph complexity router); particle VFX → `unity-particle-designer` agent |
| `serialization.md` | FormerlySerializedAs, Unity null checks, SerializeReference |
| `unity-lifecycle.md` | Editor guards, platform defines, lifecycle order, threading, Time, `.meta` files |
| `unity-async.md` | UniTask, no coroutines, CancellationToken, DontDestroyOnLoad |
| `unity-input.md` | New Input System, InputView pattern, action map switching |
| `unity-prefabs.md` | Prefab rules, new GameObject() forbidden, Destroy() rules, BaseCanvas pattern, Prefab Variants (Base+Variant decision table), folder structure, logic/visual separation |
| `testing.md` | Test type decision tree (EditMode / PlayMode-Programmatic / PlayMode-Scene / ECS / NoTest), NSubstitute, AAA pattern, assembly setup |
| `ecs-dots.md` | Authoring/Baker, component naming, ISystem+IJobEntity, ECB, Hybrid linking |
| `addressables.md` | No Resources.Load, async loading, handle lifecycle, address constants |
| `event-patterns.md` | UnityEvent forbidden, IEventBus vs Action vs C# event decision tree |
| `scene-hierarchy.md` | Standard 6-container scene hierarchy (`[Setup]`→`[VFX]`), classification table, prefab/container rules, enforcement |

## Hooks (auto-enforced on every Write/Edit)

@.claude/docs/hooks-blocking.md

### Warning (exit 0 — logs to stderr, does not block)

@.claude/docs/hooks-warning.md

## Commands (slash commands)

@.claude/docs/commands.md

## Agents (`.claude/agents/`)

@.claude/docs/agents-index.md

## Key Architecture Rules (summary)

@.claude/docs/architecture-summary.md

## Context Management & Review Modes

@.claude/docs/context-management.md

## Director Gates

Named prompts that pause the pipeline and wait for human approval before continuing. Full definitions in `.claude/docs/director-gates.md`.

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected (+0.3 signal), or always in `/new-module` | Approve proposed module structure (interface/service/installer/scope) |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED | Choose: `fix` / `skip` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |

## NON-NEGOTIABLE: Pre-Implementation Codebase Scan (/orchestrate only)

`/orchestrate` performs a mandatory pre-scan during Initialization (Step 5) before any agent is spawned:

1. **Check `_Framework/`** — list all subfolders, `.asmdef` names, and existing interfaces/services. Never re-implement infrastructure that already exists.
2. **Check `_GameFolders/Scripts/Games/Abstracts/`** — list existing interfaces. If an interface already exists for a WORKFLOW.md target, use it — do not create a duplicate.
3. **Check `_GameFolders/Scripts/Games/Concretes/`** — list existing classes. If a target class already exists, read it and verify it follows architecture rules before deciding to modify or re-implement.
4. **Print a Pre-Scan Report** — what exists, what is missing, any conflicts with WORKFLOW.md outputs, any architecture violations in existing files.
5. **Flag already-implemented tasks** — if a WORKFLOW.md output file already exists and is correct, ask the developer whether to skip or re-implement before proceeding.

This scan is part of `/orchestrate` Initialization. It does not apply to `/implement` (which handles simpler, scoped tasks).

## NON-NEGOTIABLE: Assembly Error Blocking (/orchestrate)

`/orchestrate` Step 3.5 (Bounded Verification) and Phase Gate Step 1 (Ralph) both perform an explicit compile check **before** committing or advancing. If any assembly or compile error is detected, the pipeline **stops** — the committer is never spawned.

Detected error patterns: `error CS`, `Assembly ... error/failed`, `has compiler errors`, `Scripts have compiler errors`, `is not allowed to reference`.

The verifier reads `get_logs` after `refresh_assets` and searches for these patterns explicitly. Errors are not silently ignored — they surface as `⛔ BLOCKED` with file path and line number.

---

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-coder-lite`, `unity-fixer`, `unity-fixer-lite`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

1. Showing the required Director Gate (SCOPE_GATE or ARCHITECTURE_GATE) to the user
2. Receiving explicit `go` from the user
3. Writing `.claude/state/gate-cleared` via Bash

Skipping a gate is a critical violation — the `guard-gate-cleared.sh` hook will block the agent spawn with exit 2. After the pipeline completes, delete `.claude/state/gate-cleared`.

---

## Project Features

Configured by `/setup-project`. Source of truth: `.claude/project-features.json`.

| Feature | Status | Effect when disabled |
|---------|--------|----------------------|
| `addressables` | **DISABLED** | Skip `rules/addressables.md`, Addressables hooks, and address-constant checks |
| `testing` | **DISABLED** | Skip `rules/testing.md`, NSubstitute rules, test-folder/asmdef requirements, and test hooks |
| `ecs` | **DISABLED** | Skip `rules/ecs-dots.md`, ECS structural-change hook (`check-ecs-structural-changes.sh`), and enum-byte-base hook (`check-enum-byte-base.sh`) |

> When a feature is DISABLED, Claude must not enforce its rules or suggest its patterns.

---

## Setup Checklist & Project-Specific Setup

@.claude/docs/setup-checklist.md

## Skills Library (`.claude/skills/`)

`skills-index.md` is the live index of all skills. It is updated automatically:
- `/discover --write` adds/updates rows in the `## Discovered Packages` table after writing package skills
- `/learn` adds/updates rows in the `## Learned Skills` table after saving approved patterns

Skills under `third-party/`, `plugins/`, `learned/`, and `platform/` are auto-loaded into every session via `@`-references in `auto-loaded-skills.md`. The `auto-load-skills.sh` PostToolUse hook keeps that file in sync — whenever a skill file is written, the reference is added automatically.

@.claude/docs/skills-index.md

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.

@.claude/docs/auto-loaded-skills.md
