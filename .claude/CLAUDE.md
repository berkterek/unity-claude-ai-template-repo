# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Important Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking. A hook that only warns has minimal enforcement value.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.

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
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas |
| `serialization.md` | FormerlySerializedAs, Unity null checks, SerializeReference |
| `unity-specifics.md` | Editor guards, platform defines, lifecycle order, no coroutines |
| `testing.md` | NSubstitute, AAA pattern, test naming, assembly setup |
| `ecs-dots.md` | Authoring/Baker, component naming, ISystem+IJobEntity, ECB, Hybrid linking |
| `addressables.md` | No Resources.Load, async loading, handle lifecycle, address constants |
| `event-patterns.md` | UnityEvent forbidden, IEventBus vs Action vs C# event decision tree |

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

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-coder-lite`, `unity-fixer`, `unity-fixer-lite`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

1. Showing the required Director Gate (SCOPE_GATE or ARCHITECTURE_GATE) to the user
2. Receiving explicit `go` from the user
3. Writing `.claude/state/gate-cleared` via Bash

Skipping a gate is a critical violation — the `guard-gate-cleared.sh` hook will block the agent spawn with exit 2. After the pipeline completes, delete `.claude/state/gate-cleared`.

---

## Setup Checklist & Project-Specific Setup

@.claude/docs/setup-checklist.md

## Skills Library (`.claude/skills/`)

@.claude/docs/skills-index.md

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.
