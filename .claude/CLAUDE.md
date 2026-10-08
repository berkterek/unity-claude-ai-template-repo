# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

> This file is an index. Long root-cause narratives live in `docs/incidents/` (linked per rule). `@` imports here
> resolve relative to **this file's folder** (`.claude/`) — write `@docs/x.md`, never `@.claude/docs/x.md`, which
> silently loads nothing (measured 2026-10-08).

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

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created. New hook scripts must be `chmod +x`'d (the harness invokes them by path, so a missing exec bit makes the hook fail with exit 126 and silently become a no-op); `session-restore.sh` also self-heals any `.claude/hooks/*.sh` missing its exec bit at SessionStart as a safety net.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking. A hook that only warns has minimal enforcement value.
- **Never route around a blocking hook.** Every content hook is registered on `Edit|Write` and does not see a Bash command, so `cat > file.cs`, `tee`, `sed -i`, or `cp` into a project file skips all 20+ of them at once. `check-write-via-bash.sh` blocks that channel with exit 2 (`/tmp` scratch paths exempt). If `Write`/`Edit` was blocked, the block is the answer: fix the underlying issue, or surface the conflict at the gate and let the human decide. Silencing a check yourself is a critical violation even when the resulting file content is correct — the check existed to move a decision to a human, and switching tools cancels that, not the rule.
- **A green hook suite is NOT evidence about a prompt.** Editing a reviewer prompt → run `.claude/tests/reviewer-fixtures/`; editing pipeline step order → `.claude/tests/pipeline-dry-run/`; changing which rules load → `.claude/tests/rule-awareness-probe/`. Asmdef blocks → `validate-generated-asmdefs.py` + `.claude/tests/setup-compile-probe/`; FBX contract → `.claude/tests/blender-fbx-probe/`; `.claude/graph/` → `verify-graphify.sh`. → `docs/incidents/test-layers.md`
- **A silent hook is NOT a compliance check.** Only an explicit `checked: <rule>` receipt counts as evidence. → `docs/incidents/test-layers.md`
- **A `PreToolUse` content hook judges the effective post-edit content, never disk and never the `new_string` slice**, and its `Write` branch must be reachable (no file-exists guard above it). → `docs/incidents/pretooluse-effective-content.md`
- **Path rules and gateguard fact demands are validated at PLAN time** (`.claude/scripts/validate-plan-paths.sh`, `validate-plan-facts.sh`), single source of truth in `lib-path-rules.sh` / `lib-gateguard-facts.sh`; exceptions only via `.claude/path-allowlist.txt` + `rules/architecture.md`. Plan coverage releases the deny-then-allow gates; under `strict` it is game code's only door. → `docs/incidents/plan-time-gates.md`
- **Hook profiles:** `UNITY_HOOK_PROFILE=minimal|standard|strict` (default: `standard`). `minimal` runs only the 6 critical safety hooks (plus `check-ls-grep.sh`, which declares no level and therefore runs at every profile); `standard` runs all standard-level hooks; `strict` adds heavy enforcement hooks. `DISABLE_UNITY_HOOKS=1` disables all hooks. `UNITY_HOOK_MODE=warn` downgrades blocking to warnings. Full profile docs: `.claude/docs/hook-profiles.md`.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- `.claude/agents/*.md` files define agent roles and provide prompt overlays for built-in FleetView agent types. The `subagent_type` value is always the agent's filename without `.md` (e.g. `unity-coder`, `lean-planner`). See `.claude/docs/agents-index.md` for the full mapping table.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.
- **MCP tool list is frozen at session start** — restart for a missing bridge; never substitute Bash (Blender socket, `unity command eval`). → `docs/incidents/mcp-and-framework.md`
- **UI Toolkit is version-gated:** game UI on Unity 6 (6000.0)+, Editor tools only below. Read `ProjectSettings/ProjectVersion.txt` before choosing; routing per screen type in `rules/ui-toolkit-runtime.md`. Status and open blockers → `docs/incidents/ui-toolkit-status.md`
- Claude's file tools (`Write`/`Edit`) cannot write `.unity` scene files — `block-scene-edit.sh` blocks this. **However, MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`) can create and wire scenes through the Unity Editor directly.** Always prefer MCP over listing manual Editor steps when MCP is connected.
- **Prefab / ScriptableObject inspector references use the SerializedOps applier** (`Tools/Framework/Apply Serialized Ops`, read `Temp/serialized-ops-result.json`), never a throwaway Editor script. → `docs/incidents/mcp-and-framework.md`
- **The framework is a package; `packages/framework/` is its only source.** Never vendor it into `Assets/`; after editing it run `.claude/tests/setup-compile-probe/run-probe.sh`. → `docs/incidents/mcp-and-framework.md`
- **`.claude/graph/graph.json` is generated — never edit by hand** (`/build-knowledge-graph`). Read `parent_source`, `as_resolution` and `declaration_unresolved` before concluding; `parent: null` is "not resolved", `lifetime: ""` is not a lifetime. → `docs/incidents/knowledge-graph.md`
- Rule files under `.claude/rules/` start with a `## Cards` section (WHEN/WRONG/RIGHT/GOTCHA format). Read the cards first — the prose below each cards section is full reference detail.

## Rules

Always loaded: `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`. Every other rule in `.claude/rules/` is **path-scoped** (`paths:` frontmatter) and loads only when a matching file is Read/Edited — not on a new-file Write, not via MCP, and not after `/compact`.
`.claude/docs/rule-index.md` (injected at every SessionStart) says which rule to Read before which decision — **Read it before deciding in that area, even while only planning.** What each rule covers: `.claude/docs/rules-overview.md`.

## Required Stack

| Package | Source | Purpose |
|---------|--------|---------|
| **`com.berkterek.framework`** | Git URL (this repo, `?path=/packages/framework#framework/vX.Y.Z`) | This template's framework: `IEventBus`, `DLog`, the `ISaveLoadService`/`ISaveLoadDal` chain, and the SerializedOps Editor applier. Installed by `/setup-project` **Step 2b**, before Step 3 — every game-side asmdef references `FrameworkEvents` / `FrameworkLogging` / `FrameworkSaveLoadSystems` by name |
| **VContainer** | openupm / Package Manager | Dependency injection — replaces all singletons |
| **UniTask** | openupm / Package Manager | Async/await — replaces all coroutines |
| **New Input System** | Package Manager (com.unity.inputsystem) | Input — legacy Input API is blocked |
| **Newtonsoft Json** | Package Manager (com.unity.nuget.newtonsoft-json) | Save/load serialization — `LocalSaveLoadDal` will not compile without it |
| **R3** | Git URL (`com.cysharp.r3`) | Reactive state — `ReactiveProperty` for observable values a View renders, `Observable` for owner-less streams. See `skills/plugins/r3.md`; boundary vs `IEventBus` in `rules/event-patterns.md` |

## Optional Features

Selected during `/setup-project`. Choices are saved to `.claude/project-features.json`. Disabled features have their hooks removed from `settings.json` and their rules skipped per the `## Project Features` header in this file (written by setup).

| Package | Source | Feature flag | When disabled |
|---------|--------|--------------|---------------|
| **Addressables** | Package Manager (com.unity.addressables) | `addressables` | Addressables rules and skills skipped |
| **NSubstitute** | Manual DLL install | `testing` | Test folders, asmdefs, test hooks skipped |
| **Unity ECS DOTS** | Package Manager (optional) | `ecs` | ECS folder, asmdef, ECS hooks skipped |
| **Unity Knowledge Graph** | Built-in (`.claude/graph/`) | `graph` | Skip extractors and hooks. All graph-aware commands (planning, implementation, fix/debug, investigation, migration, and audit/review pipelines) fall back to direct file-scan. |
| **Unity project subfolder** | — | `unity_project_folder` | Set to `"."` (default) when `Assets/` is at repo root. Set to e.g. `"MyGame"` when the Unity project lives in a subfolder. `graph-builder.py` reads this and prefixes all `Assets/` paths accordingly. Set once in `project-features.json` — never hardcode paths in scripts. |

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

**Unity official plugin (`unity:*`):** this repo's rules win on every conflict; `unity command eval` is forbidden;
`unity:new-unity-project` never replaces `/setup-project`; `unity:ui-ugui` / `unity:ui-uitk` output is reshaped to our
rules before it lands. → `docs/incidents/mcp-and-framework.md`

## Model Tiers

Agent frontmatter and session aliases use `opus` / `sonnet` / `haiku`, **never a pinned model ID** (only fallback
aliases stay pinned). Every agent spawned inside a command carries an explicit `model`. There is no automatic model
fallback — switch manually with `/model`. Details: `.claude/docs/model-tiers.md`; history → `docs/incidents/model-tiers.md`

## Session Start

When starting a new conversation on this project, read these files first:
- `.claude/CLAUDE.md` (this file — already loaded)
- `.claude/rules/architecture.md` — module structure, VContainer, IEventBus patterns; same prefab hierarchy (root/child/grandchild) uses SerializeField not VContainer; domain folder convention (first folder under `Games/Abstracts|Concretes/` is a domain, never a layer or catch-all) and the `Concretes/<Domain>/ARCHITECTURE.md` intent contract
- `.claude/rules/solid-oop.md` — SOLID & OOP rules (MonoBehaviour role boundaries, SRP, OCP, DIP)
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide
- `docs/ROADMAP.md` if it exists — **which milestone is `← OPEN` and which of its modules are still Pending.** Read this before agreeing to work on any module: outside the open milestone the default answer is "not yet", and the rule (`rules/roadmap-milestones.md`) has no hook behind it, so this file plus SCOPE_GATE are the whole enforcement
- If `.claude/graph/graph.json` exists and `graph` feature is enabled: run `/knowledge-graph summary` — **this is the primary source of truth** for classes, interfaces, events, installers, scopes, prefabs, methods, and call edges. Do NOT manually scan source folders if the graph is available and fresh (< 24h).

**Graph query cheatsheet (use before touching any existing system):** `/knowledge-graph` + `implementers IAudioService` · `publishers LevelStartedEvent` · `registrations AudioService` · `scope-tree` (read `parent_source`; an `(unresolved: …)` parent is not a root scope) · `violations` · `prefab Player` · `callers AudioService.PlaySound` · `impact AudioService --hops 3` · `path AudioService.PlaySound HUDView.UpdateHUD` · `god-nodes`.

- Before modifying any injectable class: apply Card 0 (solid-oop.md) — if no `[SerializeField]` and no Unity callbacks needed, make it pure C#.
- If the user asks to continue work on a specific module, also read its source files before making any changes.
- Before modifying or implementing any existing system, check `skills-index.md` for a relevant skill first — do not read source files directly if a skill covers the system.

## Reference (read on demand — not loaded at launch)

All under `.claude/docs/`: `rule-index.md` (which rule before which decision; also injected at SessionStart) ·
`rules-overview.md` (what each rule covers) · `knowledge-graph.md` (querying/rebuilding the graph) · `quick-start.md`
(setup, hook wiring) · `model-tiers.md` · `hooks-blocking.md` / `hooks-warning.md` (a hook blocked or warned) ·
`commands.md` / `agents-index.md` (picking a command or agent) · `architecture-summary.md` · `context-management.md`
(review modes) · `director-gates.md` (**before showing any gate**) · `setup-checklist.md` · `skills-index.md` /
`auto-loaded-skills.md` (finding a skill; the latter is also injected at SessionStart).

## Director Gates

Named prompts that pause the pipeline and wait for human approval before continuing. Full definitions in `.claude/docs/director-gates.md` — **Read it before showing any gate.**

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect. Its block prints a `Milestone:` line when the work maps to a module; this gate is the **only** enforcement point `rules/roadmap-milestones.md` has |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected (+0.3 signal), or always in `/new-module` | Approve proposed module structure (interface/service/installer/scope) |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `BREAKING_REVISION_GATE` | `/create-plan`, `/update-plan` | When reviewer classifies a plan revision as BREAKING (structural change, contradicts prior decision) | Choose: `re-research` / `accept` / `stop` — prevents cascading fix cycles |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED, while the fix budget still has passes left | Choose: `fix` / `skip` / `stop`, plus display-only `list` |
| `EXHAUSTION_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/qa`, `/create-prefab-scene`, `/create-plan`, `/update-plan` (13 sites) | A bounded retry loop spent its budget and the work still fails | Ship the known-bad state or abandon the run: `skip` / `stop`. **`fix` is deliberately absent** — the loop already spent it |
| `EVIDENCE_GATE` | `/fix-deep` | Automated reproduction produced no debug logs | Supply the evidence yourself: `retry` / `manual: <text>` / `stop` |
| `HYPOTHESIS_GATE` | `/fix-deep` | Evidence refuted the hypothesis (bound: 2 revision cycles) | Spend another investigation cycle or stop: `retry` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |
| `SPARC_GATE` | `/implement`, `/orchestrate`, `/fix` (≥ 0.4) | Before coder spawn, after SCOPE_GATE | Approve Specification + Architecture (how it will be built) |

Gate markers (`gate-cleared`, `sparc-approved`, `codex-reviewed`) are bounded by a 45-minute TTL and cleared at
SessionStart — except `source=compact`, which keeps them. `UNITY_GATE_TTL` is not an input. → `docs/incidents/gate-markers.md`

### Automated Check Gates

Five gates decide nothing and pause nothing: `TD-ARCHITECTURE`, `TD-UNITY-RISK`, `TD-PERFORMANCE`, `CD-SCOPE` ride the reviewer spawn as named criteria; `TD-COMPILE` rides the validator step (compile + **stale-assembly probe** + Edit Mode tests — a clean console after a failed compile describes the *previous* build). Full definitions and where each is applied: `.claude/docs/director-gates.md` → "Automated Check Gates".

## NON-NEGOTIABLE: /orchestrate Rules

@docs/orchestrate-rules.md

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-fixer`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

1. Showing the required Director Gate (SCOPE_GATE or ARCHITECTURE_GATE) to the user
2. Receiving explicit `go` from the user
3. Writing `$(git rev-parse --show-toplevel)/.claude/state/gate-cleared` via Bash

Skipping a gate is a critical violation — the `guard-gate-cleared.sh` hook will block the agent spawn with exit 2. After the pipeline completes, delete `$(git rev-parse --show-toplevel)/.claude/state/gate-cleared`.

- **Gate-cleared ≠ pipeline-executed.** While a gate is open, doing the work yourself instead of spawning the pipeline agent is a violation; `guard-pipeline-direct-work.sh` blocks direct `_GameFolders/Scripts/**/*.cs` writes and `git commit` at subagent depth 0. The only escape valve is a one-line reason in `.claude/state/pipeline-override` **after the user explicitly approved skipping the pipeline** — never speculatively. → `docs/incidents/gate-markers.md`
- **`subagent-depth` is a hint, never fact.** If a leaked count locks you out, clear the counter and its queue together: `printf 0 > "$CLAUDE_PROJECT_DIR"/.claude/state/subagent-depth && rm -f "$CLAUDE_PROJECT_DIR"/.claude/state/subagent-depth-pending.jsonl` — and say what you changed. → `docs/incidents/subagent-depth.md`

## Project Features

Configured by `/setup-project`. Source of truth: `.claude/project-features.json`.

| Feature | Status | Effect when disabled |
|---------|--------|----------------------|
| `addressables` | **DISABLED** | Skip `rules/addressables.md`, Addressables hooks, and address-constant checks |
| `testing` | **ENABLED** | Enforce `rules/testing.md`, NSubstitute rules, test-folder/asmdef requirements, and test hooks |
| `ecs` | **DISABLED** | Skip `rules/ecs-dots.md`, ECS structural-change hook (`check-ecs-structural-changes.sh`), and enum-byte-base hook (`check-enum-byte-base.sh`) |
| `graph` | **ENABLED** | `graph.json` is the primary source of truth. Graph-aware commands run a Step 0 graph preload — planning (`/create-plan`, `/update-plan`, `/plan-module`, `/new-module`), implementation (`/implement`, `/orchestrate`), fix/debug (`/fix`, `/fix-deep`, `/fix-codex`, `/debug-session`), investigation (`/search`, `/catch-up`, `/context-prime`, `/architect`), migration (`/migrate`), audit/review (`/qa`, `/validate`, `/review-code`, `/performance-audit`, `/check-portability`) — query graph first and fall back to file-scan only if graph is stale (> 24h), empty, or disabled. |
| `hybrid_graph` | **DISABLED** | Route call-graph queries (`callers`, `impact`, `path`, `god-nodes`) via `graph-mcp-server.py` MCP tools (backed by `graph_bfs_core.py`) with Bash-emitted stderr warning and lazy pip probe on fallback. When disabled: all queries use `graph-traversal.py`/`jq` (current behaviour), zero stderr output, no pip probe. |

> When a feature is DISABLED, Claude must not enforce its rules or suggest its patterns.

## Skills Library (`.claude/skills/`)

`skills-index.md` is the live index of all skills. `/discover --write` and `/learn` keep its tables current.
Reference skills under `third-party/`, `plugins/`, `learned/`, `platform/` are listed with descriptions in
`.claude/docs/auto-loaded-skills.md` — injected at SessionStart, not `@`-imported; Read a skill when its description
matches the work. Agents read that list at Step 0. `enforce-skill-for-keywords.sh` (strict profile) demands a
package skill before code when its keyword appears. → `docs/incidents/skills-loading.md`

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.
