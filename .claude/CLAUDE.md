# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Important Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.

## Required Stack

| Package | Source | Purpose |
|---------|--------|---------|
| **VContainer** | openupm / Package Manager | Dependency injection — replaces all singletons |
| **UniTask** | openupm / Package Manager | Async/await — replaces all coroutines |
| **New Input System** | Package Manager (com.unity.inputsystem) | Input — legacy Input API is blocked |

## Optional Features

Selected during `/setup-project`. Choices saved to `.claude/project-features.json`. Disabled features have hooks removed and rules skipped.

| Package | Feature flag | When disabled |
|---------|--------------|---------------|
| **Addressables** | `addressables` | Addressables rules and skills skipped |
| **NSubstitute** | `testing` | Test folders, asmdefs, test hooks skipped |
| **Unity ECS DOTS** | `ecs` | ECS folder, asmdef, ECS hooks skipped |

## Optional Plugins (Claude Code)

| Plugin | What it adds |
|--------|--------------|
| `superpowers` | brainstorming (≥0.7), TDD setup, systematic-debugging (≥0.4), verification-before-completion |
| `skill-creator` | Structured skill drafting |
| `code-simplifier` | Post-implementation quality pass |
| `claude-md-management` | Auto-updates CLAUDE.md with learnings |
| `code-review` | Extra review checklist layer |

Each pipeline command prints a preflight status line: `Plugins: superpowers:systematic-debugging [✓] | claude-md-management [✗]`

## Session Start

When starting a new conversation, read these files first:
- `.claude/rules/architecture.md` — module structure, VContainer, IEventBus patterns
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide

## Rules (auto-loaded)

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

### Blocking (exit 2 — stops the write)

| Hook | Blocks |
|------|--------|
| `block-git-push.sh` | `git push` — Claude cannot push; user always pushes manually |
| `block-scene-edit.sh` | Direct editing of `.unity`, `.prefab`, `.asset` files |
| `guard-editor-runtime.sh` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-pure-csharp.sh` | `using UnityEngine` in `_Framework/` or `Games/Abstracts/` / `Games/Concretes/` (non-provider) |
| `check-input-system.sh` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-unity-event.sh` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` |
| `check-time-scale.sh` | `Time.timeScale =` assignment — use IEventBus + PauseService instead |
| `check-enum-byte-base.sh` | `enum` without `: byte` base in ECS component or IEvent files |
| `check-vcontainer-singleton.sh` | Static singleton patterns outside of `EventBusAccessor` |
| `guard-critical-files.sh` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation — **exception: `TestScopes/`, `EditModeTest/`, `PlayModeTest/`** |
| `check-config-protection.sh` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` — **exception: test assemblies** |
| `gateguard.sh` (PreToolUse) | Edit/Write on any C# file that has not been read in the current session |
| `guard-reviewer-order.sh` (PreToolUse) | `unity-reviewer` spawn if Codex CLI is installed but `codex:codex-rescue` has not reviewed the current pipeline pass; bypass: `touch .claude/state/codex-reviewed` |

### Warning (exit 0 — logs to stderr, does not block)

@.claude/docs/hooks-warning.md

## Commands (slash commands)

Full pipeline flows: see `docs/WORKFLOW.md`.

### Pipelines
| Command | What it does |
|---------|-------------|
| `/implement <task>` | Full implementation pipeline with tests, review, commit |
| `/fix <bug>` | Bug fix pipeline — scout + fixer + verifier + review + commit |
| `/fix-deep <bug>` | Evidence-first pipeline — refuses to fix without proven root cause |
| `/scene-setup <desc>` | Build/configure a Unity scene via MCP |
| `/migrate <pattern> in <scope>` | Systematic pattern replacement across files |
| `/orchestrate` | Execute WORKFLOW.md phase by phase with parallel task support |
| `/create-plan <file> <what>` | Research → plan with parallel_group annotations → optional implement |
| `/update-plan <file> <change>` | Update existing plan and re-run implementer |
| `/smart-commit` | Analyze dirty tree → group into logical commits → commit |

### Project Setup
| Command | What it does |
|---------|-------------|
| `/setup-project` | Scaffold folder structure, asmdefs, base classes, feature flags |
| `/create-prefab-scene` | Migrate legacy bare GameObjects to proper prefabs |

### Design & Architecture
| Command | What it does |
|---------|-------------|
| `/game-idea` | Refine raw idea into GDD |
| `/architect` | Create TDD from GDD with adversarial review |
| `/grill-me [plan]` | Stress-test a plan — one pointed question at a time |
| `/refine-gdd` | Iterate on an existing GDD |
| `/refine-tdd` | Iterate on an existing TDD |

### Development
| Command | What it does |
|---------|-------------|
| `/plan-workflow` | Create phased WORKFLOW.md from TDD with parallel_group numbers |
| `/new-module` | Generate 5-file module structure |

### Quality
| Command | What it does |
|---------|-------------|
| `/review-code` | Code review via unity-reviewer |
| `/validate` | Compile + test validation via MCP or dotnet CLI |
| `/check-portability` | Audit module for copy-paste portability |
| `/clean-slop` | Remove AI-generated bloat |
| `/learn` | Extract project patterns into `.claude/skills/learned/` |
| `/discover [--dry-run\|--write]` | Emit per-package skill drafts from manifest.json — classifies packages as `unity-native` (prefabs/scenes → direct skill write) or `logic` (pure C# → recommends `/skill-creator` post-write) |
| `/generate-tests` | Write missing tests for an existing class |
| `/create-test <Feature>` | Full test infrastructure: EditMode / PlayMode-ECS / PlayMode-Scene |
| `/graphics-setup <mobile\|pc>` | Create URP Pipeline Assets and wire into Quality Settings |
| `/audio-clip-setup [path]` | Optimize AudioClip import settings |
| `/performance-audit` | Audit files for allocations and hot-path violations |
| `/debug-session` | Structured root cause analysis |
| `/silent-failure-hunt` | Audit for swallowed exceptions |
| `/ralph` | Relentless verify-fix loop until compile + tests are green |
| `/qa` | Full quality pipeline: ralph → silent-failure-hunt → validate |

### Session & Context
| Command | What it does |
|---------|-------------|
| `/caveman` | Ultra-compressed mode (~75% fewer tokens). Exit with `/normal` |
| `/checkpoint` | Save summary to `.claude/state/checkpoint.md` then `/clear` |
| `/context-prime` | Brief Claude on project context |
| `/search <query>` | Research pipeline → findings → action recommendation |
| `/dump` | Save session notes to `.claude/logs/` |
| `/five` | 5 Whys root cause analysis |
| `/continue` | Resume interrupted orchestration from event journal |
| `/status` | GDD → TDD → WORKFLOW progress summary |
| `/dry-run` | Preview orchestration plan without executing |
| `/instincts` | Manage instinct library: status, list, evolve, promote, export, import |
| `/create-changelog` | Create or update `CHANGELOG.md` |
| `/update-claude-md` | Sync CLAUDE.md tables with actual project state |
| `/mermaid` | Generate Mermaid architecture diagram |
| `/catch-up` | Generate `docs/CATCH_UP.md` codebase guide |
| `/adr <decision>` | Record an Architecture Decision |

## Agents (`.claude/agents/`)

@.claude/docs/agents-index.md

## Review Modes

| Mode | Trigger | Pipeline |
|------|---------|---------|
| **solo** | `/solo /implement …` | unity-coder only — no reviewer, no committer |
| **lean** | `/lean /implement …` | unity-coder → unity-reviewer → committer |
| **full** | `/full /implement …` (default) | unity-coder → Codex → unity-reviewer → committer |

## Director Gates

Full definitions: `.claude/docs/director-gates.md`.

| Gate | When it fires | What you decide |
|------|--------------|-----------------|
| `SCOPE_GATE` | After complexity scoring, before any agent spawns | Confirm scope — type `go` or redirect |
| `ARCHITECTURE_GATE` | New module detected, or always in `/new-module` | Approve module structure |
| `BREAKING_GATE` | Fix >3 files or migrate >5 files | Confirm wide blast radius |
| `QUALITY_GATE` | Reviewer returns CHANGES NEEDED | Choose: `fix` / `skip` / `stop` |
| `COMMIT_GATE` | After verification, before committer | Final sign-off — type `go` or `stop` |

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-coder-lite`, `unity-fixer`, `unity-fixer-lite`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

1. Showing the required Director Gate (SCOPE_GATE or ARCHITECTURE_GATE) to the user
2. Receiving explicit `go` from the user
3. Writing `.claude/state/gate-cleared` via Bash

Skipping a gate is a critical violation — the `guard-gate-cleared.sh` hook will block the agent spawn with exit 2. After the pipeline completes, delete `.claude/state/gate-cleared`.

## Session State Persistence (`.claude/state/`)

| File | Contents |
|------|----------|
| `session.json` | Current branch, phase, modified files, active task, decisions |
| `learnings.jsonl` | Structured learning records accumulated across sessions |
| `instincts/` | Project-specific and global instinct library (confidence-scored patterns) |

- `session-restore.sh` (SessionStart hook) loads state at session start
- `session-save.sh` (Stop hook) persists state when session ends

## Context Management

When context reaches ~70-80%, use `/checkpoint` to save progress and reset:
```
/checkpoint → saves to .claude/state/checkpoint.md
/clear      → frees context
```
Next session: send `"read .claude/state/checkpoint.md"` to resume.

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`.

## Skills Library (`.claude/skills/`)

@.claude/docs/skills-index.md

## Setup & Onboarding

See `docs/SETUP.md` for: Quick Start, Adding to Existing Project, Manual Setup Checklist, Building a Game from Scratch, Hook Audit Log, Model Tiers.
