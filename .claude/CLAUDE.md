# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Model Tiers

Claude Code supports multiple models. Start your session with the right model for the task:

| Tier | Model | Alias | When to use |
|------|-------|-------|-------------|
| **light** | `claude-haiku-4-5` | `claude-light` | Quick tasks: `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | `claude-sonnet-4-6` | `claude-normal` | Balanced work: `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/performance-audit`, `/new-module`, `/check-portability`, `/clean-slop`, `/catch-up`, `/learn` |
| **heavy** | `claude-opus-4-7` | `claude-heavy` | Deep thinking: `/architect`, `/plan-workflow`, `/game-idea`, `/add-feature`, `/refine-gdd`, `/refine-tdd` |

Setup aliases once in your shell profile — see `.claude/aliases.sh`.

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

## Hooks (auto-enforced on every Write/Edit)

### Blocking (exit 2 — stops the write)

| Hook | Blocks |
|------|--------|
| `block-git-push.sh` | `git push` — Claude cannot push; user always pushes manually |
| `block-scene-edit.sh` | Direct editing of `.unity`, `.prefab`, `.asset` files |
| `guard-editor-runtime.sh` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-pure-csharp.sh` | `using UnityEngine` in `_Framework/` or `Games/Abstracts/` / `Games/Concretes/` (non-provider) |
| `check-input-system.sh` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-vcontainer-singleton.sh` | Static singleton patterns outside of `EventBusAccessor` |
| `guard-critical-files.sh` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation |
| `check-config-protection.sh` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` |

### Warning (exit 0 — logs to stderr, does not block)

| Hook | Warns |
|------|-------|
| `check-naming-conventions.sh` | Non-PascalCase types, wrong field naming |
| `check-no-linq-hotpath.sh` | LINQ in Update/FixedUpdate/LateUpdate |
| `check-no-runtime-instantiate.sh` | `Instantiate()`, `new GameObject()`, `Destroy()` |
| `check-test-exists.sh` | Logic class with no corresponding test file |
| `check-compile.sh` | Basic C# syntax (braces, namespace, type declaration) |
| `warn-serialization.sh` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `warn-filename.sh` | C# filename doesn't match primary class name |
| `check-unused-code.sh` | Unused private members, unused imports |
| `check-namespace-format.sh` | Namespace not in `Layer.Module` format |
| `check-event-naming.sh` | `IEvent` struct without `Event` suffix or not past tense |
| `check-ecs-structural-changes.sh` | `EntityManager.AddComponent/RemoveComponent/DestroyEntity` inside ECS system (use ECB) |
| `check-async-void.sh` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation.sh` | `async UniTask` methods without `CancellationToken` parameter |
| `check-null-propagation.sh` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |

## Commands (slash commands)

### Pipelines (multi-agent)
- `/implement <task>` — **complexity score** → test writer → coder → unity validator (compile + tests via MCP) → reviewer → [unity-developer reviewer if score ≥ 0.7] → committer
- `/fix <bug>` — **complexity score** → debugger → test writer → coder → unity validator (compile + tests via MCP) → reviewer → [unity-developer reviewer if score ≥ 0.7] → committer
- `/scene-setup <description>` — coder + unity-setup → reviewer → committer
- `/migrate <pattern> in <scope>` — test guard → migrator → reviewer → committer
- `/create-plan <file> <what>` — researcher → **complexity-aware planner** (opus) → reviewer → save → optional implementer
- `/update-plan <file> <change>` — analyzer → planner (opus) → reviewer → save
- `/smart-commit` — analyze dirty working tree → group into logical commits → commit

> Reviewer tries Codex first; falls back to Claude reviewer agent if unavailable.

### Project Setup
- `/setup-project` — Initialize a new project: folder structure, .asmdef files, base framework classes, NSubstitute setup, manual checklist

### Design & Architecture
- `/game-idea` — Refine a raw game idea into a GDD
- `/architect` — Create a Technical Design Document from a GDD (auto-runs Phase 7 self-critique before asking for review)
- `/refine-gdd` — Iterate on an existing GDD
- `/refine-tdd` — Iterate on an existing TDD

### Development
- `/plan-workflow` — Create a phased execution plan from a TDD
- `/new-module` — Generate the 5-file module structure (Interface, Service, Config, Installer, Events)
- `/add-feature` — Incrementally extend an existing game

### Quality
- `/review-code` — Code review on specific files
- `/validate` — Validate a completed phase
- `/check-portability` — Audit a module for copy-paste portability
- `/clean-slop` — Remove AI-generated bloat (dead code, useless abstractions)
- `/learn` — Extract project-specific patterns into `.claude/skills/learned/` + generates `PROMPTS.md` documenting the workflow
- `/generate-tests` — Write missing tests for an existing class
- `/performance-audit` — Audit files for allocations and hot-path violations
- `/debug-session` — Structured root cause analysis for a bug
- `/silent-failure-hunt` — Audit files for swallowed exceptions and silent error patterns

### Session & Context
- `/context-prime` — Brief Claude on project context at the start of a session
- `/dump` — Save current session notes to `.claude/logs/` as markdown
- `/five` — 5 Whys root cause analysis for a bug or architectural problem

### Changelog
- `/create-changelog` — Create or update `CHANGELOG.md` with recent changes

### Diagrams
- `/mermaid` — Generate a Mermaid architecture diagram for a module or system

### Documentation
- `/catch-up` — Generate a human-readable codebase guide (`docs/CATCH_UP.md`)

## Agents (`.claude/agents/`)

| Agent | Role |
|-------|------|
| `coder` | Pure C# implementation — no Unity API |
| `tester` | Test writer — NSubstitute + AAA |
| `reviewer` | General code review |
| `unity-developer` | Unity 6 specialist — second reviewer for complex tasks (score ≥ 0.7) |
| `unity-setup` | Unity Editor setup steps |
| `committer` | Staged changes → commit |
| `debugger` | Root cause analysis |
| `migrator` | Pattern migration |

## Context Management

### Proactive Compaction

Compact context **before** it runs out — at ~60-70% usage, not reactively:
- Update `production/session-state/active.md` with current task and decisions
- Use `/clear` between unrelated tasks
- Natural compaction points: after committing, after completing a task, after writing a document section

### Session Resume

After a context reset or new session:
1. Read `production/session-state/active.md` — the `session-start` hook previews it automatically
2. Read `.claude/CLAUDE.md` and `.claude/rules/architecture.md`
3. Read the source files for the module being worked on

## Key Architecture Rules (summary)

- **No singletons** — VContainer only. Register in AppScope (global) or scene scopes.
- **No GameContext / service locator** — each class declares only its own dependencies.
- **No coroutines** — UniTask everywhere. `async UniTask`, not `async void`.
- **No legacy Input** — New Input System only. InputView owns PlayerControls.
- **No concrete cross-module deps** — only interfaces consumed across modules.
- **No UnityEngine in services** — Provider pattern. Unity API lives in `Concretes/<Module>/`.
- **No direct EntityManager structural changes** — use `EntityCommandBuffer` in ECS systems.
- **Tests are mandatory** — NSubstitute + AAA. Only interfaces mocked. Test file per class.

## Project-Specific Setup

When first adding this template to a new project, run `/setup-project` to generate:
- Assembly definition files with correct project name
- Base framework classes (IEventBus, ModuleInstaller, AppScope)
- NSubstitute test assembly configuration
- Sample test templates

Then follow the **Manual Setup Checklist** it prints (NSubstitute DLL, VContainer, UniTask, Input System, AppScope scene wiring).
