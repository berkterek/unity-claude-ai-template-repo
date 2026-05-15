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

1. Copy the `.claude/` folder into your Unity project root
2. Run `/setup-project` — it detects existing state, asks about optional features (Addressables / Testing / ECS), generates folder structure, .asmdef files, and base classes, then writes `.claude/project-features.json`
3. Complete the **Manual Setup Checklist** printed by `/setup-project`

For an existing project with legacy code, see **Adding to an Existing Project** below.

## Adding to an Existing Project

Copy `.claude/` into the project root. Most hooks warn only — four will **block** existing code:

| Hook | What it blocks | Migration path |
|------|---------------|----------------|
| `check-input-system.sh` | `Input.GetKey`, `Input.GetAxis` | Create `PlayerControls.inputactions`, wrap in `InputView` |
| `check-vcontainer-singleton.sh` | Static singletons | Replace with VContainer registration in scope |
| `guard-editor-runtime.sh` | Bare `using UnityEditor` in runtime | Wrap with `#if UNITY_EDITOR` |
| `check-pure-csharp.sh` | `using UnityEngine` in `_Framework/` | Move Unity calls to a Provider in `Concretes/` |

**Recommended migration order:**
1. Run `/setup-project` to scaffold the folder structure
2. Move existing scripts into the new structure without changing logic
3. Fix blocking hook violations one module at a time
4. Run `/migrate` for systematic pattern replacements (e.g. coroutine→UniTask)
5. Run `/validate` after each phase to confirm green state

## Model Tiers

Claude Code supports multiple models. Start your session with the right model for the task:

| Tier | Model | Alias | When to use |
|------|-------|-------|-------------|
| **light** | `claude-haiku-4-5` | `claude-light` | Quick tasks: `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | `claude-sonnet-4-6` | `claude-normal` | Balanced work: `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/performance-audit`, `/new-module`, `/check-portability`, `/clean-slop`, `/catch-up`, `/learn` |
| **heavy** | `claude-opus-4-7` | `claude-heavy` | Deep thinking: `/architect`, `/plan-workflow`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

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
| `check-vcontainer-singleton.sh` | Static singleton patterns outside of `EventBusAccessor` |
| `check-unity-event.sh` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` |
| `check-time-scale.sh` | `Time.timeScale =` assignment — use IEventBus + PauseService instead |
| `check-enum-byte-base.sh` | `enum` without `: byte` base in ECS component or IEvent files — use `ushort` if 255+ values needed |
| `guard-critical-files.sh` | Edits to `AppScope`, `InputView`, `*Installer`, `IEventBus`, `.asmdef` without investigation — **exception: files under `TestScopes/`, `EditModeTest/`, or `PlayModeTest/` paths** |
| `check-config-protection.sh` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` — **exception: test assemblies (`EditModeTest`, `PlayModeTest`)** |
| `gateguard.sh` (PreToolUse) | Edit/Write on any C# file that has not been read in the current session |
| `guard-reviewer-order.sh` | Codex installed and no `.claude/state/codex-reviewed` marker → blocks `unity-reviewer` agent spawn; Codex review required first. |

### Warning (exit 0 — logs to stderr, does not block)

@.claude/docs/hooks-warning.md

## Commands (slash commands)

### Pipelines (multi-agent)
- `/implement <task>` — **complexity score** → test writer → **unity-coder** → **unity-verifier** (compile + tests via MCP) → reviewer priority: **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → **silent failure audit** (changed files) → committer
- `/fix <bug>` — **complexity score** → Step 1: **unity-fixer** + **unity-scout** simultaneously (complexity ≥ 0.4) → test writer → **unity-coder** → **unity-verifier** (compile + tests via MCP) → reviewer priority: **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → **silent failure audit** (changed files) → committer
- `/fix-deep <bug>` — **complexity score** → **evidence-first pipeline**: log intake (file / text / MCP) → hypothesis → debug injection → Step 3: **unity-fixer** + **unity-scout** simultaneously (complexity ≥ 0.4) → **evidence gate** (proven / refuted / inconclusive) → fix only if proven → validator → reviewer → **silent failure audit** (changed files) → committer; refuses to fix if root cause cannot be proven
  - Use for: logic bugs, "sometimes happens" issues, wrong values at runtime, NullRef with unclear source
  - Use `/fix` when: stack trace clearly points to root cause
- `/scene-setup <description>` — **complexity score** → **unity-coder-lite** (Simple) / **unity-coder** (Medium/Complex) + unity-setup → **unity-verifier** → **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → committer
- `/migrate <pattern> in <scope>` — **complexity score** → [test guard if Medium/Complex] → **migrator** / **unity-migrator** → reviewer → [unity-developer if score ≥ 0.7] → committer
- `/create-plan <file> <what>` — researcher → **complexity-aware planner** (opus, assigns `parallel_group` to independent tasks) → reviewer → save → optional implementer (parallel spawn for grouped tasks if complexity ≥ 0.4)
- `/update-plan <file> <change>` — analyzer → planner (opus, updates `parallel_group` annotations) → reviewer → save → optional implementer (parallel spawn for grouped tasks if complexity ≥ 0.4)
- `/smart-commit` — analyze dirty working tree → group into logical commits → commit
- `/orchestrate` — **complexity score** → read WORKFLOW.md → check `parallel_group` annotations → per-task: **coder** (pure C#) / **unity-coder-lite** (Simple Unity) / **unity-coder** (Medium/Complex Unity) → **unity-verifier** → **Codex** → unity-reviewer → [unity-developer if score ≥ 0.7] → committer; tasks with same `parallel_group` run simultaneously (complexity ≥ 0.4); phase gate runs **ralph → silent-failure-hunt → validate** automatically before asking to proceed; emits `VERIFICATION_PASSED` event on success

> Reviewer priority: Codex → unity-reviewer (falls back to unity-reviewer if Codex is unavailable).

### Project Setup
- `/setup-project` — **Step 0:** detect existing state, compare against `project-features.json` (if any), offer sync-only mode on conflict. **Step 1:** ask feature questions (Addressables / Testing / ECS) + package gates. Generates folder structure, .asmdef files, base framework classes, and manual checklist. Writes `.claude/project-features.json`, removes disabled hooks from `settings.json`, adds `## Project Features` header to `CLAUDE.md`.
- `/create-prefab-scene` — **Legacy migration:** scan existing scenes for bare GameObjects, build a prefab inventory, create proper prefabs via MCP, review, commit. Use for scenes built before the prefab rules were in place.

### Design & Architecture
- `/game-idea` — Refine a raw game idea into a GDD (includes assumption surfacing + "Not Doing" list)
- `/architect` — Create a Technical Design Document from a GDD (auto-runs Phase 7 self-critique → **unity-critic** adversarial challenge → developer review)
- `/grill-me [plan or file]` — Stress-test a plan or design decision — asks one pointed question at a time, offers a recommended answer, resolves every branch; ends with a Decision Record
- `/refine-gdd` — Iterate on an existing GDD
- `/refine-tdd` — Iterate on an existing TDD

### Development
- `/plan-workflow` — Create a phased execution plan from a TDD — assigns integer `parallel_group` numbers (1, 2, `—`) compatible with `/orchestrate`; compile-time type dependencies force sequential even across different files
- `/new-module` — Generate the 5-file module structure (Interface, Service, Config, Installer, Events)

### Quality
- `/review-code` — Code review on specific files via **unity-reviewer**
- `/validate` — Validate a completed phase; **unity-verifier** via MCP tried first, dotnet CLI fallback
- `/check-portability` — Audit a module for copy-paste portability
- `/clean-slop` — Remove AI-generated bloat (dead code, useless abstractions)
- `/learn` — Extract project-specific patterns into `.claude/skills/learned/` + generates `PROMPTS.md` documenting the workflow
- `/discover [--dry-run|--write] [--only <pkg>]` — Walk `Packages/manifest.json`, summarize each Unity package, and emit per-package skill drafts to `.claude/skills/third-party/<pkg>/`. Small packages produce a single `SKILL.md`; large packages (50+ prefabs) produce a multi-file folder (`SKILL.md`, `api.md`, `prefabs.md`, `integration.md`, `test-strategy.md`, `samples.md`). Supports `--dry-run` (default), `--write`, `--only <pkg>`, `--include-assets-plugins`.
- `/generate-tests` — Write missing tests for an existing class
- `/create-test <FeatureName>` — Unified test generator: runs test-type-router to determine EditMode / PlayMode-ECS / PlayMode-Scene, then generates the full test infrastructure for the chosen type. EditMode → NSubstitute unit test. PlayMode-ECS → isolated World test. PlayMode-Scene → TestScope + TestInstaller + test stub + scene via MCP.
- `/graphics-setup <mobile|pc>` — Show tier plan (Low/Medium/High), await approval, create URP Pipeline Assets + Renderer Data + URPQualityConfiguration via MCP, wire into Quality Settings, commit option
- `/audio-clip-setup [path]` — Scan AudioClip assets, categorize (Music/SFX/UI/Voice), apply optimized import settings via temp Editor script + MCP; reports per-clip changes + summary + commit option
- `/performance-audit` — Audit files for allocations and hot-path violations
- `/debug-session` — Structured root cause analysis; routes to **unity-fixer** (complex) or **unity-fixer-lite** (scoped) after root cause; **learner** skill runs on completion
- `/silent-failure-hunt` — Audit files for swallowed exceptions and silent error patterns
- `/ralph` — Relentless verify-fix loop (max 10 outer iterations) — refuses to stop until compile and tests are green or stuck is detected
- `/qa` — Full quality pipeline: **ralph** (compile + tests) → **silent-failure-hunt** → **validate** — run after any implementation, accepts `--phase N` and `--files <path>`

### Session & Context
- `/caveman` — Ultra-compressed communication mode (~75% fewer tokens). Drops filler, keeps technical accuracy. Exit with `/normal`.
- `/checkpoint` — Save current conversation summary to `.claude/state/checkpoint.md`, then run `/clear` to free context; next session auto-reads the checkpoint and resumes
- `/context-prime` — Brief Claude on project context at the start of a session
- `/search <query>` — **complexity score** → Phase 1: **Explore** + **unity-scout** simultaneously (complexity ≥ 0.4) → write findings to `.claude/state/search-findings.md` → Phase 2: reviewer validates **completeness** (COMPLETE / INCOMPLETE / REJECT, max 5 iter) → Phase 3: present findings to user → Phase 4: **action router** recommends next command (`/fix`, `/fix-deep`, `/implement`, `/create-plan`, `/update-plan`, or no action) — never executes automatically
- `/dump` — Save current session notes to `.claude/logs/` as markdown
- `/five` — 5 Whys root cause analysis for a bug or architectural problem
- `/continue` — Resume an interrupted orchestration run from the event journal (picks up where it left off)
- `/status` — Report current pipeline stage: GDD → TDD → WORKFLOW progress summary
- `/dry-run` — Preview the orchestration plan for a WORKFLOW.md without executing any tasks
- `/instincts` — Manage instinct library: status, list, evolve, promote, export, import

### Changelog
- `/create-changelog` — Create or update `CHANGELOG.md` with recent changes

### Diagrams
- `/mermaid` — Generate a Mermaid architecture diagram for a module or system

### Documentation
- `/catch-up` — Generate a human-readable codebase guide (`docs/CATCH_UP.md`)
- `/adr <decision>` — Record an Architecture Decision (e.g. `/adr why VContainer over Zenject`); writes to `docs/decisions/NNN-topic.md`
- `/update-claude-md [--section hooks|rules|commands|agents]` — Sync CLAUDE.md tables with actual project state (settings.json hooks, rules/ files, commands/ files, agents/ files). Shows diff, waits for confirmation before writing.

## Agents (`.claude/agents/`)

@.claude/docs/agents-index.md

## Context Management

### Context Getting Full? Use /checkpoint

When context reaches ~70-80%, use `/checkpoint` to save progress and fully reset:

```
/checkpoint  →  Claude writes summary to .claude/state/checkpoint.md
/clear       →  Context fully freed
Send: "read .claude/state/checkpoint.md"  →  Claude resumes from where you left off
```

The checkpoint file is at `.claude/state/checkpoint.md` and is deleted after it is read. This is the preferred approach over `/compact` when you need maximum token recovery.

**`/compact` vs `/checkpoint` + `/clear`:**
- `/compact` — shrinks context in-place, you continue immediately, some tokens remain
- `/checkpoint` + `/clear` — full reset, maximum token recovery, resumes via file on next message

### Session Resume

After a context reset or new session:
1. `session-restore.sh` runs automatically — shows checkpoint (if any) + prior session state
2. Read `.claude/CLAUDE.md` and `.claude/rules/architecture.md`
3. Read the source files for the module being worked on

### Session State Persistence (`.claude/state/`)

Structured state written and restored automatically by hooks across sessions:

| File | Contents |
|------|----------|
| `session.json` | Current branch, phase, modified files, active task, decisions |
| `learnings.jsonl` | Structured learning records accumulated across sessions |
| `instincts/` | Project-specific and global instinct library (confidence-scored patterns) |

- `session-restore.sh` (SessionStart hook) loads state at the start of every session
- `session-save.sh` (Stop hook) persists state when the session ends
- Use `/instincts` to view, evolve, promote, or export instincts

## Review Modes

Control pipeline depth by prefixing any pipeline command:

| Mode | Trigger | Pipeline |
|------|---------|---------|
| **solo** | `/solo /implement …` | unity-coder only — no reviewer, no committer |
| **lean** | `/lean /implement …` | unity-coder → unity-reviewer → committer |
| **full** | `/full /implement …` (default) | unity-coder → Codex → unity-reviewer → committer |

Use `solo` for exploratory spikes, `lean` for low-risk changes, `full` for production features.

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

## Key Architecture Rules (summary)

- **No singletons** — VContainer only. Register in AppScope (global) or scene scopes.
- **No GameContext / service locator** — each class declares only its own dependencies.
- **No coroutines** — UniTask everywhere. `async UniTask`, not `async void`.
- **No legacy Input** — New Input System only. InputView owns PlayerControls.
- **No concrete cross-module deps** — only interfaces consumed across modules.
- **No UnityEngine in services** — Provider pattern. Unity API lives in `Concretes/<Module>/`.
- **No direct EntityManager structural changes** — use `EntityCommandBuffer` in ECS systems.
- **Tests are mandatory** — NSubstitute + AAA. Only interfaces mocked. Test file per class.

### Folder Structure

```
_Framework/              ← Pure C# — no Unity dependency
  Events/                ← IEventBus, IEvent, EventBusAccessor
  Logging/
  SaveLoadSystems/

_GameFolders/
  Scripts/
    Games/
      Abstracts/         ← Interfaces, abstract classes
      Concretes/         ← Unity providers, MonoBehaviours
      Ecs/               ← Authorings, Components, Systems
    Tests/
      [ProjectName]EditModeTest/    ← Edit Mode (NUnit + NSubstitute)
      [ProjectName]PlayModeTest/    ← Play Mode (ECS World integration)
  Prefabs/
    Enemies/
    UI/
    VFX/
    Environment/
```

### Building a Game from Scratch

| Phase | Commands | What happens |
|-------|---------|--------------|
| 1 — Idea & Design | `/game-idea`, `/architect` | GDD → TDD with adversarial review |
| 2 — Planning | `/plan-workflow`, `/dry-run` | WORKFLOW.md phases, preview without execution |
| 3 — Project Setup | `/setup-project` | Folder structure, .asmdefs, base classes, URP quality tiers, audio import settings |
| 4 — Implementation | `/orchestrate`, `/continue` | Execute WORKFLOW.md phase by phase |
| 5 — Quality | `/validate`, `/review-code`, `/ralph`, `/performance-audit` | Compile + tests green, code review, fix loops, hot path audit |
| 6 — Documentation | `/learn`, `/catch-up`, `/adr`, `/smart-commit` | Extract patterns, generate CATCH_UP.md, record decisions, commit |

For incremental feature work on an existing game: `/implement <description>` (complexity scored, full pipeline).

## Skills Library (`.claude/skills/`)

@.claude/docs/skills-index.md

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.

## Hook Audit Log

Every hook execution is logged. Query logs to audit what was blocked or warned:

```bash
# All hook events from the current session
cat .claude/logs/hooks-$(date +%Y-%m-%d).log

# Only blocking events (exit code 2)
grep '"exit":2' .claude/logs/hooks-*.log

# Cost tracker summary
cat .claude/logs/cost-tracker.log | tail -50
```

Logs rotate daily and are stored in `.claude/logs/`.

## Manual Setup Checklist

After running `/setup-project`, complete these steps manually (Claude cannot do them):

- [ ] **NSubstitute DLL** — Download from [NuGet](https://www.nuget.org/packages/NSubstitute): click "Download package", rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from the `lib/` folder, place in `Assets/Plugins/NSubstitute/`
- [ ] **VContainer** — Install via Package Manager or openupm (`jp.hadashikick.vcontainer`)
- [ ] **UniTask** — Install via Package Manager or openupm (`com.cysharp.unitask`)
- [ ] **New Input System** — Install via Package Manager (`com.unity.inputsystem`); set active input handling to "Input System Package (New)" in Project Settings → Player
- [ ] **Addressables** — Install via Package Manager (`com.unity.addressables`); initialize via Window → Asset Management → Addressables → Groups
- [ ] **AppScope scene** — Create a Bootstrap scene (Build index 0), add `AppScope` component, wire `AppInstaller`
- [ ] **Build settings** — Add Bootstrap scene as index 0; add Menu and Game scenes
- [ ] **`check-test-scene-exists.sh` hook** — Add to `.claude/settings.json` PostToolUse section (Claude cannot edit settings.json due to config-protection hook):
  ```json
  {
    "matcher": "Write|Edit",
    "hooks": [{ "type": "command", "command": ".claude/hooks/check-test-scene-exists.sh", "timeout": 5000, "statusMessage": "Checking test scene exists..." }]
  }
  ```
- [ ] **`guard-reviewer-order.sh` hook** — Add to `.claude/settings.json` **PreToolUse** `Agent` matcher (alongside `guard-gate-cleared.sh`):
  ```json
  {
    "type": "command",
    "command": ".claude/hooks/guard-reviewer-order.sh",
    "timeout": 3000,
    "statusMessage": "Checking reviewer order (Codex first)..."
  }
  ```
  Full entry in `hooks.PreToolUse` where `"matcher": "Agent"` already exists — add as a second hook in that hooks array.
- [ ] **`track-codex-review.sh` hook** — Add to `.claude/settings.json` **PostToolUse** section as a new entry:
  ```json
  {
    "matcher": "Agent",
    "hooks": [{ "type": "command", "command": ".claude/hooks/track-codex-review.sh", "timeout": 3000, "statusMessage": "Tracking Codex review..." }]
  }
  ```

## Project-Specific Setup

When first adding this template to a new project, run `/setup-project`. It:

1. **Detects existing state** — checks folder structure and `manifest.json`, compares against `project-features.json` if it exists, reports conflicts and offers sync-only mode
2. **Asks feature questions** — Addressables (yes/no), Testing (yes/no), ECS (yes/no) — with detected signals as defaults
3. **Writes `.claude/project-features.json`** — hooks and commands read this to skip disabled features
4. **Generates** assembly definitions, base framework classes (`IEventBus`, `EventBus`, `EventBusAccessor`, `ModuleInstaller`, `AppInstaller`, `AppScope`), and test templates (if Testing=yes + NSubstitute present)
5. **Cleans settings.json** — removes hooks for disabled features
6. **Updates CLAUDE.md** — prepends `## Project Features` section listing enabled/disabled features

Then follow the **Manual Setup Checklist** it prints. **Note:** `.unity` scene files must be created manually in Unity Editor — Claude cannot write scene files (`block-scene-edit.sh` blocks all `.unity` writes).
