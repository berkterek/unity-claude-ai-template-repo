# Unity Claude AI Template

A personal Claude Code configuration template for Unity 6 projects. Drop the `.claude/` folder into any Unity project to get automatic code quality enforcement, slash commands, and AI-assisted workflows — all following a consistent architecture.

---

## What This Is

Claude Code reads the `.claude/` folder when it opens a project. This template pre-loads it with:

- **Rules** — architecture, naming, testing, ECS, serialization, addressables standards that Claude follows automatically
- **Hooks** — shell scripts that run on every file write, blocking bad patterns before they land
- **Commands** — slash commands for common workflows (`/new-module`, `/setup-project`, `/debug-session`, etc.)
- **Agents** — specialized AI agent roles (coder, tester, reviewer, unity-developer, debugger, migrator, silent-failure-hunter, unity-setup)

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

## Usage Modes

This template works in two modes:

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
| `check-pure-csharp` | `using UnityEngine` in `_Framework/` | Move Unity calls to provider classes |
| `guard-editor-runtime` | Unguarded `UnityEditor` in runtime code | Wrap with `#if UNITY_EDITOR` |

### Recommended migration approach

1. **Copy `.claude/` into your project** — commands and warnings are active immediately
2. **Temporarily disable blocking hooks** you're not ready for: comment out the relevant `[[hooks]]` entry in `.claude/settings.json`
3. **Run `/check-portability` on existing modules** to see what needs to change
4. **Migrate module by module** — new code follows the template, legacy code migrates on touch
5. **Re-enable hooks** as each area of the codebase is migrated

> **Note:** If VContainer, UniTask, or the New Input System are not yet installed, add them via Package Manager before enabling the hooks that depend on them. The hooks will block writes that use the old patterns, but Claude will still help you write the migration code correctly.

---

## Model Tiers

Different tasks need different models. Use the right tier to balance speed and cost:

| Tier | Model | Alias | Commands |
|------|-------|-------|----------|
| **light** | Haiku | `claude-light` | `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | Sonnet | `claude-normal` | `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/new-module`, `/performance-audit`, `/clean-slop`, `/catch-up` |
| **heavy** | Opus | `claude-heavy` | `/architect`, `/plan-workflow`, `/game-idea`, `/add-feature`, `/refine-gdd`, `/refine-tdd` |

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

Then open Claude for the right task:

```bash
claude-light   # quick logs, diagrams, changelogs
claude-normal  # code review, debugging, module generation
claude-heavy   # architecture, planning, game design
```

The alias file lives at `.claude/aliases.sh`.

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
| `block-git-push` | `git push` — Claude cannot push; user always pushes manually |
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
| `/game-idea` | Refine a raw idea into a GDD (assumption surfacing + "Not Doing" list included) |
| `/architect` | Create a Technical Design Document from a GDD (auto-runs Phase 7 self-critique before review) |
| `/refine-gdd` | Iterate on an existing GDD |
| `/refine-tdd` | Iterate on an existing TDD |
| `/plan-workflow` | Create a phased execution plan from a TDD |

### Pipelines (multi-agent)
| Command | Description |
|---------|-------------|
| `/implement <task>` | **Complexity score** → Test Writer → Coder → **Unity Validator** (compile + tests via MCP) → Reviewer (loop) → [Unity Developer reviewer if complex] → Committer |
| `/fix <bug>` | **Complexity score** → Debugger → Test Writer → Coder → **Unity Validator** (compile + tests via MCP) → Reviewer (loop) → [Unity Developer reviewer if complex] → Committer |
| `/migrate <pattern> in <scope>` | Migrator → Reviewer (loop) → Committer — coroutine→UniTask, singleton→VContainer, etc. |
| `/scene-setup <description>` | Coder + Unity-Setup → Reviewer (loop) → Committer — scripts and scene wiring together |
| `/create-plan <file> <what>` | Researcher → **Complexity-aware Planner** → Reviewer (loop) → Save → optional Implementer — create a new plan file from scratch |
| `/update-plan <file> <change>` | Analyzer → Planner → Reviewer (loop) → Save → optional Implementer — extend an existing plan |
| `/smart-commit` | Analyze dirty working tree → group into logical atomic commits → commit |
| `/orchestrate` | Read `WORKFLOW.md` → execute every task automatically (coder → reviewer loop → committer per task), phase gate between phases |

> All pipeline reviewer steps loop automatically: CHANGES NEEDED → coder fixes → reviewer re-checks → repeat until APPROVED (max 3 passes). Only asks the user if 3 passes fail.

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
| `/learn` | Extract project-specific patterns into `.claude/skills/learned/` + generates `PROMPTS.md` documenting the workflow |
| `/catch-up` | Generate a human-readable codebase guide |
| `/generate-tests` | Write missing tests for an existing class |
| `/performance-audit` | Audit files for allocations and hot-path violations |
| `/debug-session` | Structured root cause analysis for a bug |
| `/silent-failure-hunt` | Audit files for swallowed exceptions and silent error patterns |

### Session & Context
| Command | Description |
|---------|-------------|
| `/context-prime` | Brief Claude on project context at the start of a session (reads git log + key files) |
| `/dump` | Save current session notes and decisions to `.claude/logs/` as markdown |
| `/five` | 5 Whys root cause analysis — drill down from symptom to root cause |

### Changelog & Diagrams
| Command | Description |
|---------|-------------|
| `/create-changelog` | Create or update `CHANGELOG.md` from recent git commits |
| `/mermaid` | Generate a Mermaid architecture diagram for a module or system |

---

## Agents

Specialized AI roles invoked automatically by commands or directly by name.

| Agent | Role |
|-------|------|
| `coder` | Pure C# implementation — follows TDD spec exactly |
| `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks |
| `reviewer` | Principal-level code review — architecture, naming, performance |
| `unity-developer` | Unity 6 specialist — second reviewer for complex tasks (score ≥ 0.7); checks hot paths, draw calls, ECS safety, Addressables lifecycle |
| `committer` | Smart phase commit manager — semantic git commits |
| `unity-setup` | Scene, prefab, ScriptableObject configuration via Unity MCP |
| `debugger` | Root cause analysis — VContainer, ECS, UniTask, Input bug patterns |
| `migrator` | Legacy pattern migration — coroutine→UniTask, singleton→VContainer, legacy input |
| `silent-failure-hunter` | Swallowed exception audit — empty catch, `.Forget()` without handler, dangerous fallbacks |

---

## Review Modes

Control pipeline depth by editing `production/review-mode.txt`:

| Mode | Effect | When to use |
|------|--------|-------------|
| `solo` | Coder → Committer only — no tests, no review | Prototypes, game jams |
| `lean` | Standard pipeline (default) | Regular solo development |
| `full` | Standard pipeline + unity-developer reviewer always active | Team review, learning sessions |

Change mode: `echo "full" > production/review-mode.txt`

---

## Director Gates

Named review prompts in `.claude/docs/director-gates.md` — referenced by ID across all pipeline commands to prevent prompt drift:

| Gate | Checks |
|------|--------|
| `TD-ARCHITECTURE` | VContainer DI, interface-driven, IEventBus, Provider pattern, module boundaries |
| `TD-UNITY-RISK` | Post-cutoff API risk — reads `docs/engine-reference/unity/` before any architecture decision |
| `TD-PERFORMANCE` | Zero-alloc hot paths, draw call budget, ECS ECB usage, Addressables handle lifecycle |
| `TD-COMPILE` | Unity MCP compile + Edit Mode test pass — mandatory before reviewer |
| `CD-SCOPE` | YAGNI check — flags out-of-scope files, unnecessary abstractions, speculative features |

---

## Engine Version Reference

`docs/engine-reference/unity/` contains Unity 6 LTS risk assessments:

- `VERSION.md` — risk levels per system area (ECS, UI Toolkit, Netcode, etc.)
- `breaking-changes.md` — HIGH/MEDIUM risk API changes with migrations
- `deprecated-apis.md` — forbidden APIs and their replacements
- `current-best-practices.md` — VContainer, UniTask, ECS, Input, Addressables, Rendering patterns

`/architect` reads these automatically and stamps TDD sections that touch risky areas.

---

## Session State

`production/session-state/active.md` is a living checkpoint updated after each milestone.

- **On session start** — `session-start.sh` hook previews the active task automatically
- **On stop** — `pre-compact.sh` hook reminds Claude to save state before context is lost
- **To resume** — read `production/session-state/active.md`, then continue from where you left off

Compact context **proactively at ~60-70% usage** — not reactively when it runs out.

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

## Hook Audit Log

Every hook execution is logged to `~/.claude/hook-audit.log` as newline-delimited JSON. Use this to see what was blocked, warned, or passed on any file.

```jsonc
{"ts":"2026-05-04T10:22:01Z","hook":"check-vcontainer-singleton","status":"BLOCKED","file":"Games/Concretes/GameManager.cs","project":"my-game"}
{"ts":"2026-05-04T10:22:02Z","hook":"check-naming-conventions","status":"OK","file":"Games/Concretes/GameManager.cs","project":"my-game"}
```

**Status values:** `OK` — passed, `BLOCKED` — write was stopped (exit 2), `WARN` — warning logged (exit 0 with output)

**Useful queries:**

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

## Built-In Skills

Skills in `.claude/skills/third-party/` are loaded automatically and cover setup and diagnosis for third-party tools:

| Skill | Covers |
|-------|--------|
| `unity-asmdef` | Assembly definition setup, reference wiring, CS0246/CS0234 diagnosis, test assembly configuration |
| `nsubstitute` | NSubstitute DLL installation, `overrideReferences` configuration, mock patterns, runtime error diagnosis |
| `vcontainer` | Scope hierarchy, registration patterns, `IInitializable`/`IDisposable` lifecycle, DI failure diagnosis |

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

This keeps the tier system consistent across all project skills and makes it easy to pick the right `claude-light` / `claude-normal` / `claude-heavy` alias when opening a session.

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
