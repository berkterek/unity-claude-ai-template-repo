# Unity Claude AI Template

A personal Claude Code configuration template for Unity 6 projects. Drop the `.claude/` folder into any Unity project to get automatic code quality enforcement, slash commands, and AI-assisted workflows — all following a consistent architecture.

---

## What This Is

Claude Code reads the `.claude/` folder when it opens a project. This template pre-loads it with:

- **Rules** — architecture, naming, testing, ECS, serialization, addressables standards that Claude follows automatically
- **Hooks** — shell scripts that run on every file write, blocking bad patterns before they land
- **Commands** — slash commands for common workflows (`/new-module`, `/setup-project`, `/debug-session`, etc.)
- **Agents** — specialized AI agent roles (coder, tester, reviewer, debugger, migrator, silent-failure-hunter, unity-setup)

---

## Stack

This template assumes the following packages are (or will be) installed in your Unity project:

| Package | Role |
|---------|------|
| **VContainer** | Dependency injection |
| **UniTask** | Async/await (replaces coroutines) |
| **New Input System** | Input handling |
| **Addressables** | Runtime asset loading (Resources.Load forbidden) |
| **NSubstitute** | Test mocking (manual DLL install) |
| **Unity ECS DOTS** | Optional — hooks and rules are active if you use it |

---

## Quick Start

### 1. Copy into your project

```
your-unity-project/
└── .claude/          ← copy this folder here
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

This generates project-specific boilerplate: assembly definition files (with your project name), base framework classes (`IEventBus`, `ModuleInstaller`, `AppScope`), NSubstitute test assembly config, and a manual setup checklist.

---

## Hooks — Auto-Enforced on Every Write

Hooks run silently in the background every time Claude writes or edits a C# file.

### Blocking (stops the write, runs before write)

| Hook | What it blocks |
|------|---------------|
| `block-scene-edit` | Direct editing of `.unity`, `.prefab`, `.asset` YAML |
| `guard-editor-runtime` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-pure-csharp` | `using UnityEngine` inside `_Framework/` or service classes in `Abstracts/Concretes/` |
| `check-input-system` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-vcontainer-singleton` | Static singleton patterns outside of `EventBusAccessor` |
| `guard-critical-files` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation |
| `check-config-protection` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` |

### Warnings (logged to stderr, does not block)

| Hook | What it warns |
|------|--------------|
| `check-naming-conventions` | Wrong field/type naming (underscore, PascalCase rules) |
| `check-no-linq-hotpath` | LINQ inside `Update` / `FixedUpdate` / `LateUpdate` |
| `check-no-runtime-instantiate` | `new GameObject()`, `Instantiate()`, `Destroy()` |
| `check-test-exists` | Logic class with no matching test file |
| `check-compile` | Basic C# syntax errors |
| `warn-serialization` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `warn-filename` | C# filename doesn't match primary class name |
| `check-unused-code` | Unused private members and imports |
| `check-namespace-format` | Namespace not in `Layer.Module` format (e.g. `Game.Concretes`) |
| `check-event-naming` | `IEvent` struct without `Event` suffix or not past tense |
| `check-ecs-structural-changes` | `EntityManager.AddComponent/DestroyEntity` inside ECS system (use ECB) |
| `check-async-void` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation` | `async UniTask` methods missing `CancellationToken` parameter |
| `check-null-propagation` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |

---

## Slash Commands

### First-time project setup
| Command | Description |
|---------|-------------|
| `/setup-project` | Generate assembly definitions, base classes, NSubstitute config, and manual setup checklist |

### Design
| Command | Description |
|---------|-------------|
| `/game-idea` | Refine a raw idea into a Game Design Document |
| `/architect` | Create a Technical Design Document from a GDD |
| `/refine-gdd` | Iterate on an existing GDD |
| `/refine-tdd` | Iterate on an existing TDD |
| `/plan-workflow` | Create a phased execution plan from a TDD |

### Development
| Command | Description |
|---------|-------------|
| `/new-module` | Generate the 5-file module structure (Interface, Service, Config, Installer, Events) |
| `/add-feature` | Incrementally extend an existing game |

### Quality
| Command | Description |
|---------|-------------|
| `/review-code` | Code review on specific files |
| `/validate` | Validate a completed phase |
| `/check-portability` | Audit a module for copy-paste portability to another project |
| `/clean-slop` | Remove AI-generated bloat (dead code, useless abstractions) |
| `/learn` | Extract project-specific patterns into `.claude/skills/learned/` |
| `/catch-up` | Generate a human-readable codebase guide |
| `/generate-tests` | Write missing tests for an existing class |
| `/performance-audit` | Audit files for allocations and hot-path violations |
| `/debug-session` | Structured root cause analysis for a bug |
| `/silent-failure-hunt` | Audit files for swallowed exceptions and silent error patterns |

---

## Agents

Specialized AI roles invoked automatically by commands or directly by name.

| Agent | Role |
|-------|------|
| `coder` | Pure C# implementation — follows TDD spec exactly |
| `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks |
| `reviewer` | Principal-level code review — architecture, naming, performance |
| `committer` | Smart phase commit manager — semantic git commits |
| `unity-setup` | Scene, prefab, ScriptableObject configuration via Unity MCP |
| `debugger` | Root cause analysis — VContainer, ECS, UniTask, Input bug patterns |
| `migrator` | Legacy pattern migration — coroutine→UniTask, singleton→VContainer, legacy input |
| `silent-failure-hunter` | Swallowed exception audit — empty catch, `.Forget()` without handler, dangerous fallbacks |

---

## Architecture in a Nutshell

The rules enforce this structure across all projects:

```
_Framework/                  ← Pure C#, no Unity dependency
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
- New Input System only — `InputView` owns `PlayerControls`
- UniTask everywhere — no coroutines, no `async void`, always pass `CancellationToken`
- Addressables for all runtime asset loading — no `Resources.Load`
- NSubstitute + AAA pattern for tests — only interfaces mocked

---

## Manual Setup (Required After `/setup-project`)

Some things Claude cannot do inside Unity Editor — you do these once per project:

**NSubstitute**
1. Download `NSubstitute.dll` from the [NSubstitute releases page](https://github.com/nsubstitute/NSubstitute/releases)
2. Place in `Assets/_GameFolders/Plugins/NSubstitute/NSubstitute.dll`
3. The `.asmdef` files generated by `/setup-project` already reference it

**VContainer**
Install via Unity Package Manager — add by git URL from the VContainer repository.

**UniTask**
Install via Unity Package Manager — add by git URL from the UniTask repository.

**New Input System**
1. Install via Package Manager: `com.unity.inputsystem`
2. Edit → Project Settings → Player → Active Input Handling → `Input System Package (New)`
3. Create `Assets/Input/[ProjectName]Controls.inputactions`
4. Enable "Generate C# Class" in the `.inputactions` inspector

**Addressables**
1. Install via Package Manager: `com.unity.addressables`
2. Mark runtime assets as Addressable in the Inspector
3. Use `AssetAddresses` constants class for address strings — no hardcoded strings

**AppScope (Bootstrap scene)**
1. Create a `Bootstrap` scene (Build index 0)
2. Add `AppScope` component to an empty GameObject
3. Create `AppInstaller.asset` → `Assets/Configs/`
4. Assign to `AppScope._appInstaller` in Inspector

---

## Project-Specific Files (Not in This Template)

These are generated per-project and should NOT be committed back to this template:

```
.claude/skills/learned/    ← patterns extracted from your specific project
docs/                      ← GDD, TDD, WORKFLOW, PROGRESS (generated by commands)
```

---

## License

MIT
