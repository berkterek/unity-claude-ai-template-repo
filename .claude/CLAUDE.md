# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

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

### Project Setup
- `/setup-project` — Initialize a new project: folder structure, .asmdef files, base framework classes, NSubstitute setup, manual checklist

### Design & Architecture
- `/game-idea` — Refine a raw game idea into a GDD
- `/architect` — Create a Technical Design Document from a GDD
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
- `/learn` — Extract project-specific patterns into `.claude/skills/learned/`
- `/generate-tests` — Write missing tests for an existing class
- `/performance-audit` — Audit files for allocations and hot-path violations
- `/debug-session` — Structured root cause analysis for a bug
- `/silent-failure-hunt` — Audit files for swallowed exceptions and silent error patterns

### Documentation
- `/catch-up` — Generate a human-readable codebase guide (`docs/CATCH_UP.md`)

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
