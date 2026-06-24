# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Shell Commands (NON-NEGOTIABLE)

- **Use `tree` for directory listings** — `ls | grep`, `ls -la`, `find . -type f | grep` are forbidden for this purpose
- `tree -L 2` is sufficient in most cases; use `tree -L 3` or `tree --gitignore` when deeper traversal is needed
- `check-ls-grep.sh` blocks `ls | grep` patterns with exit 2

## Interaction Style

- Do NOT validate my ideas by default. No "great question", "good idea", "interesting approach" padding.
- If I present two conflicting options, you MUST pick one and justify it. "Both are good" is not an acceptable answer.
- Challenge my assumptions before agreeing. State the weaknesses, risks, and failure cases of any idea I propose — including my own.
- Be direct, not diplomatic. If an approach won't work, say "This won't work because X" instead of "Have you considered...".
- When I'm wrong, correct me. Do not change a correct answer just because I push back.

## What You Do NOT Do

- Do not call a flawed approach "interesting" or "clever".
- Do not agree first and critique later.
- Do not soften technical problems to spare my feelings.
- Do not add filler affirmations ("Sure!", "Absolutely!", "Of course!") at the start of responses.

## Important Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking. A hook that only warns has minimal enforcement value.
- **Hook profiles:** `UNITY_HOOK_PROFILE=minimal|standard|strict` (default: `standard`). `minimal` runs only 5 critical hooks; `standard` runs all standard-level hooks; `strict` adds heavy enforcement hooks. `DISABLE_UNITY_HOOKS=1` disables all hooks. `UNITY_HOOK_MODE=warn` downgrades blocking to warnings. Full profile docs: `.claude/docs/hook-profiles.md`.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- `.claude/agents/*.md` files define agent roles and provide prompt overlays for built-in FleetView agent types. The `subagent_type` value is always the agent's filename without `.md` (e.g. `unity-coder`, `lean-planner`). See `.claude/docs/agents-index.md` for the full mapping table.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.
- Claude's file tools (`Write`/`Edit`) cannot write `.unity` scene files — `block-scene-edit.sh` blocks this. **However, MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`) can create and wire scenes through the Unity Editor directly.** Always prefer MCP over listing manual Editor steps when MCP is connected.
- `.claude/graph/graph.json` is generated — never edit by hand. Use `/build-knowledge-graph` to refresh. **v1.3.0 partition architecture:** `scenes[]` and `prefabs[]` are stored in sibling files `scenes.json` and `prefabs.json` (same dir). `graph.json` holds `{"$partition": "scenes.json"}` refs. All three files are generated and committed together.
- Rule files under `.claude/rules/` start with a `## Cards` section (WHEN/WRONG/RIGHT/GOTCHA format). Read the cards first — the prose below each cards section is full reference detail.

## Knowledge Graph

@.claude/docs/knowledge-graph.md

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
| **Unity Knowledge Graph** | Built-in (`.claude/graph/`) | `graph` | Skip extractors and hooks. `/catch-up`, `/orchestrate`, `/context-prime`, `/architect` fall back to direct file-scan. |
| **Unity project subfolder** | — | `unity_project_folder` | Set to `"."` (default) when `Assets/` is at repo root. Set to e.g. `"HoleSphere"` when the Unity project lives in a subfolder. `graph-builder.py` reads this and prefixes all `Assets/` paths accordingly. Set once in `project-features.json` — never hardcode paths in scripts. |

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

Three layers: session model (launch alias), subagent model (agent `.md` frontmatter — Lead=Opus / Worker=Sonnet / Scanner=Haiku by role level), and skill `model-tier`. Every agent spawned inside a command must carry an explicit `model` (never inherit the session model). Full rule and agent list:

@.claude/docs/model-tiers.md

## Session Start

When starting a new conversation on this project, read these files first:
- `.claude/CLAUDE.md` (this file — already loaded)
- `.claude/rules/architecture.md` — module structure, VContainer, IEventBus patterns; same prefab hierarchy (root/child/grandchild) uses SerializeField not VContainer
- `.claude/rules/solid-oop.md` — SOLID & OOP kuralları (MonoBehaviour rol sınırları, SRP, OCP, DIP)
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide
- If `.claude/graph/graph.json` exists and `graph` feature is enabled: run `/knowledge-graph summary` — **this is the primary source of truth** for classes, interfaces, events, installers, scopes, prefabs, methods, and call edges. Do NOT manually scan source folders if the graph is available and fresh (< 24h).

**Graph query cheatsheet (use before touching any existing system):**
- "What interfaces exist?" → `/knowledge-graph implementers IAudioService`
- "Who publishes/subscribes to an event?" → `/knowledge-graph publishers RunStartedEvent`
- "What does an installer register?" → `/knowledge-graph registrations AudioService`
- "VContainer scope hierarchy?" → `/knowledge-graph scope-tree`
- "Any architecture violations?" → `/knowledge-graph violations`
- "What components does a prefab have?" → `/knowledge-graph prefab PlayerSphere`
- "Who calls this method?" → `/knowledge-graph callers AudioService.PlaySound`
- "What breaks if I change this class?" → `/knowledge-graph impact AudioService --hops 3`
- "How does X reach Y?" → `/knowledge-graph path AudioService.PlaySound UIManager.UpdateHUD`
- "Which classes are over-coupled?" → `/knowledge-graph god-nodes`

If the user asks to continue work on a specific module, also read its source files before making any changes.

Before modifying or implementing any existing system, check `skills-index.md` for a relevant skill first — do not read source files directly if a skill covers the system.

## Rules (auto-loaded)

Detailed coding standards in `.claude/rules/`:

| File | Covers |
|------|--------|
| `architecture.md` | VContainer DI, module structure, IEventBus, EventBusAccessor, Provider pattern, InputView, AppScope; one-caller overfitting rule; GameScope vs ModuleInstaller wiring boundary; same-prefab scripts wire via `[SerializeField]` not VContainer |
| `csharp-unity.md` | Naming, namespaces, #region, null checks, UniTask, encapsulation; interface contract documentation (precondition/postcondition/side-effect); namespace collision rule (`Game.Concretes.<Domain>` vs UnityEngine type aliases) |
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas; **material folder structure** (`Arts/Materials/<Domain>/`); **shader file structure** (`.shader`/`.shadergraph` → `_GameFolders/Arts/Shaders/`); shader authoring → `unity-shader-dev` agent (HLSL or ShaderGraph complexity router); particle VFX → `unity-particle-designer` agent |
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
| `bootstrap-pattern.md` | IInstaller → ModuleInstaller → [Module]Installer → AppInstaller → AppScope layer structure, EventBusInstaller requirement, GameScope scene-based wiring (SerializeField + RegisterComponent), new module addition flow |
| `solid-oop.md` | MonoBehaviour rol sınırları (View/Provider/Controller only, ~100 satır max); **suffix kuralı: `*View` yalnızca Canvas/UI, `*Controller` gameplay/karakter, `*Provider` Unity API soyutlaması**; SRP tek-cümle testi (AND içermemeli); OCP polymorphism kuralı; DIP constructor-interface kuralı |

## Hooks (auto-enforced on every Write/Edit)

@.claude/docs/hooks-blocking.md

### Warning (exit 0 — logs to stderr, does not block)

@.claude/docs/hooks-warning.md

### Subagent Lifecycle Hooks (SubagentStart / SubagentStop / TaskCompleted)

Three hooks produce persistent JSONL audit files in `.claude/state/` — they fire automatically when multi-agent pipelines run (`/implement`, `/fix`, `/orchestrate`):

| Hook | Event | Output |
|------|-------|--------|
| `agent-start-log.sh` | SubagentStart | `.claude/state/subagent-log.jsonl` — spawn record |
| `agent-stop-log.sh` | SubagentStop | `.claude/state/subagent-log.jsonl` — stop record + `duration_approx_s` |
| `task-completed-log.sh` | TaskCompleted | `.claude/state/task-log.jsonl` — success record |

`session-save.sh` embeds all-time totals on every Stop: `session.json → subagent_summary.{spawned, stopped, tasks_completed}`.
Payload note: SubagentStop carries **no `exit_code`**; TaskCompleted carries **no `status`** field — all three hooks are pure audit trail (exit 0 always).
Full field reference and jq queries: `.claude/docs/hooks-warning.md → ## Subagent Audit Trail`.

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

@.claude/docs/director-gates.md

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected (+0.3 signal), or always in `/new-module` | Approve proposed module structure (interface/service/installer/scope) |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `BREAKING_REVISION_GATE` | `/create-plan`, `/update-plan` | When reviewer classifies a plan revision as BREAKING (structural change, contradicts prior decision) | Choose: `re-research` / `accept` / `stop` — prevents cascading fix cycles |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED | Choose: `fix` / `skip` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |
| `SPARC_GATE` | `/implement`, `/orchestrate`, `/fix` (≥ 0.4) | Before coder spawn, after SCOPE_GATE | Approve Specification + Architecture (how it will be built) |

## NON-NEGOTIABLE: /orchestrate Rules

@.claude/docs/orchestrate-rules.md

---

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-fixer`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

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
| `testing` | **ENABLED** | Enforce `rules/testing.md`, NSubstitute rules, test-folder/asmdef requirements, and test hooks |
| `ecs` | **DISABLED** | Skip `rules/ecs-dots.md`, ECS structural-change hook (`check-ecs-structural-changes.sh`), and enum-byte-base hook (`check-enum-byte-base.sh`) |
| `graph` | **ENABLED** | `graph.json` is the primary source of truth. `/orchestrate` pre-scan reads graph instead of scanning folders. `/catch-up`, `/context-prime`, `/architect` query graph first; fall back to file-scan only if graph is stale (> 24h) or disabled. |
| `hybrid_graph` | **DISABLED** | Route call-graph queries (`callers`, `impact`, `path`, `god-nodes`) via `graph-mcp-server.py` MCP tools (backed by `graph_bfs_core.py`) with Bash-emitted stderr warning and lazy pip probe on fallback. When disabled: all queries use `graph-traversal.py`/`jq` (current behaviour), zero stderr output, no pip probe. |

> When a feature is DISABLED, Claude must not enforce its rules or suggest its patterns.

---

## Setup Checklist & Project-Specific Setup

@.claude/docs/setup-checklist.md

## Skills Library (`.claude/skills/`)

`skills-index.md` is the live index of all skills. It is updated automatically:
- `/discover --write` adds/updates rows in the `## Discovered Packages` table after writing package skills
- `/learn` adds/updates rows in the `## Learned Skills` table after saving approved patterns

Skills under `third-party/`, `plugins/`, `learned/`, and `platform/` are auto-loaded into every session via `@`-references in `auto-loaded-skills.md`. The `auto-load-skills.sh` PostToolUse hook keeps that file in sync — whenever a skill file is written, the reference is added automatically.

**Agent-side skill loading:** All code-writing, review, and exploration agents (`unity-coder`, `coder`, `tester`, `reviewer`, `unity-fixer`, `debugger`, `unity-scout`, and 20+ others) include a **Step 0** that reads `auto-loaded-skills.md` and then loads every relevant skill before starting work. This ensures subagents — which do not receive the parent session's `@`-includes — still have access to project-specific conventions. Subagents that handle git operations (`committer`, `unity-git-master`) read `.claude/skills/core/unity-git.md` specifically at Step 0.

**Skill enforcement (NON-NEGOTIABLE):** `enforce-skill-for-keywords.sh` (UserPromptSubmit hook) detects third-party package keywords in every prompt. Enforcement is skipped when the skill is already available — either auto-loaded via `auto-loaded-skills.md` (already in context) or previously invoked via the `Skill` tool this session. Otherwise it injects a blocking context message — you MUST invoke the skill before writing code, giving advice, or calling MCP tools. `track-skill-invocations.sh` (PostToolUse/Skill hook) records each Skill tool invocation. To add a new keyword mapping, edit the `KEYWORD_MAP` array in `.claude/hooks/enforce-skill-for-keywords.sh`.

@.claude/docs/skills-index.md

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.

@.claude/docs/auto-loaded-skills.md
