# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

> This file is an index — every rule is one line plus a pointer; long narratives live in `docs/incidents/`. `@`
> imports here resolve relative to **this file's folder** (`.claude/`) — write `@docs/x.md`, never
> `@.claude/docs/x.md`, which silently loads nothing (measured 2026-10-08).

## Shell Commands (NON-NEGOTIABLE)

- **Use `tree` for directory listings** — `ls | grep`, `ls -la`, `find . -type f | grep` are forbidden for this purpose
- `tree -L 2` is sufficient in most cases; use `tree -L 3` or `tree --gitignore` when deeper traversal is needed
- `check-ls-grep.sh` blocks `ls | grep` patterns with exit 2

## Important Constraints

- **`settings.json` cannot be edited by Claude** (`check-config-protection.sh`) — the user adds hook entries. New
  hook scripts must be `chmod +x` (a missing exec bit is exit 126 = silent no-op; `session-restore.sh` self-heals it).
- Hook exit 0 = warning only; exit 2 = blocking.
- **Never route around a blocking hook.** Content hooks run on `Edit|Write` only, so `cat >`, `tee`, `sed -i`, `cp`
  into a project file skips all of them — `check-write-via-bash.sh` blocks that (`/tmp` exempt). A block is the
  answer: fix the cause or surface the conflict at the gate. Silencing a check yourself is a critical violation even
  when the content is correct.
- **A green hook suite is NOT evidence about a prompt; a silent hook is NOT a compliance check** (only a
  `checked: <rule>` receipt is). Which probe proves which change: `docs/incidents/test-layers.md` — reviewer prompt →
  `tests/reviewer-fixtures/`, step order → `tests/pipeline-dry-run/`, which rules load → `tests/rule-awareness-probe/`.
- **A `PreToolUse` content hook judges the effective post-edit content**, never disk or the `new_string` slice, and
  its `Write` branch must be reachable. → `docs/incidents/pretooluse-effective-content.md`
- **Path rules and gateguard fact demands are validated at PLAN time** (`validate-plan-paths.sh`,
  `validate-plan-facts.sh`); exceptions only via `.claude/path-allowlist.txt` + `rules/architecture.md`.
  → `docs/incidents/plan-time-gates.md`
- **Token-cost changes are measured, not estimated** (`scripts/pipeline-breakdown.py`, module vs module). Measured
  2026-11-06: per-task `unity-verifier` catches real defects and confirms TDD RED — never move it to checkpoint-only;
  graph facts cover ~11% of planner discovery. → `docs/incidents/token-cost-agent-startup.md`
- **Hook profiles:** `UNITY_HOOK_PROFILE=minimal|standard|strict` (default `standard`); `DISABLE_UNITY_HOOKS=1`,
  `UNITY_HOOK_MODE=warn`. → `docs/hook-profiles.md`
- **MCP tool list is frozen at session start** — restart for a missing bridge; never substitute Bash (Blender socket,
  `unity command eval`). → `docs/incidents/mcp-and-framework.md`
- **Scenes:** `Write`/`Edit` cannot touch `.unity` (`block-scene-edit.sh`); MCP (`manage_scene`, `manage_gameobject`,
  `manage_components`, `manage_build`) can — prefer MCP over listing manual Editor steps when connected.
- **Prefab / SO inspector references use the SerializedOps applier** (`Tools/Framework/Apply Serialized Ops`), never
  a throwaway Editor script. **The framework is a package; `packages/framework/` is its only source** — never vendor
  it into `Assets/`; after editing run `tests/setup-compile-probe/run-probe.sh`. → `docs/incidents/mcp-and-framework.md`
- **UI Toolkit is version-gated** (game UI on Unity 6+, Editor only below; read `ProjectSettings/ProjectVersion.txt`).
  No screen is built before its mockup is approved at `docs/ui/mockups/<Screen>.html` — missing file → ask.
  → `rules/ui-toolkit-runtime.md`, `docs/incidents/ui-toolkit-status.md`
- **`.claude/graph/graph.json` is generated — never edit by hand.** `parent: null` is "not resolved", `lifetime: ""`
  is not a lifetime. → `docs/incidents/knowledge-graph.md`
- `subagent_type` = the agent's filename without `.md` → `docs/agents-index.md`.
- Rule files start with a `## Cards` section (WHEN/WRONG/RIGHT/GOTCHA) — read the cards first.

## Rules

Always loaded: `architecture`, `solid-oop`, `csharp-unity`, `bootstrap-pattern`. Every other rule in `.claude/rules/` is **path-scoped** (`paths:` frontmatter) and loads only when a matching file is Read/Edited — not on a new-file Write, not via MCP, and not after `/compact`.
`.claude/docs/rule-index.md` (injected at every SessionStart) says which rule to Read before which decision — **Read it before deciding in that area, even while only planning.** What each rule covers: `.claude/docs/rules-overview.md`.

## Required Stack

`com.berkterek.framework` (Git URL, `?path=/packages/framework#framework/vX.Y.Z` — `IEventBus`, `DLog`, the
`ISaveLoadService`/`ISaveLoadDal` chain, SerializedOps; installed by `/setup-project` Step 2b, before any game asmdef)
· **VContainer** (DI, replaces singletons) · **UniTask** (replaces coroutines) · **New Input System** (legacy Input
blocked) · **Newtonsoft Json** (`LocalSaveLoadDal` needs it) · **R3** (`ReactiveProperty` / `Observable`; boundary vs
`IEventBus` in `rules/event-patterns.md`).

## Optional Features & Plugins

Chosen in `/setup-project`, saved to `.claude/project-features.json`: `addressables`, `testing` (NSubstitute), `ecs`,
`graph`, `hybrid_graph`, `unity_project_folder` (`"."` when `Assets/` is at repo root, else the subfolder — set once,
never hardcode paths). Status: **Project Features** below. Optional plugins per command (superpowers,
`code-simplifier`, `claude-md-management`) and the `unity:*` plugin rules: `docs/optional-plugins.md` — the
`unity` CLI live-Editor code channel (`unity command`/`eval`, `unity run --command`, `unity shell`) is forbidden
(`check-unity-cli.sh`); this repo's rules win on every conflict.

## Model Tiers

Agent frontmatter and session aliases use `opus` / `sonnet` / `haiku`, **never a pinned model ID**. Every agent
spawned inside a command carries an explicit `model`; no automatic fallback. → `docs/model-tiers.md`

## Session Start

When starting a new conversation on this project, read these files first:
- `.claude/rules/architecture.md`, `.claude/rules/solid-oop.md` (already loaded)
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide
- `docs/ROADMAP.md` if it exists — **which milestone is `← OPEN` and which of its modules are Pending.** Outside the
  open milestone the default answer is "not yet"; this file plus SCOPE_GATE are the whole enforcement
  (`rules/roadmap-milestones.md`)
- If `graph` is enabled and `graph.json` is fresh (< 24h): `/knowledge-graph summary` before scanning source folders;
  query cheatsheet in `docs/knowledge-graph.md`.

- Before modifying any injectable class: apply Card 0 (solid-oop.md) — no `[SerializeField]` and no Unity callbacks → pure C#.
- If the user asks to continue work on a specific module, read its source files before making any changes.
- Before modifying an existing system, check `skills-index.md` for a relevant skill first.

## Reference (read on demand — not loaded at launch)

All under `.claude/docs/`: `rule-index.md` · `rules-overview.md` · `knowledge-graph.md` · `quick-start.md` ·
`model-tiers.md` · `hooks-blocking.md` / `hooks-warning.md` (a hook blocked or warned) · `commands.md` /
`agents-index.md` · `architecture-summary.md` · `context-management.md` · `director-gates.md` (**before showing any
gate**) · `optional-plugins.md` · `orchestrate-rules.md` · `setup-checklist.md` · `skills-index.md` /
`auto-loaded-skills.md`.

## Director Gates

Named prompts (`SCOPE_GATE`, `ARCHITECTURE_GATE`, `COMMIT_GATE`, … plus automated `TD-*` / `CD-SCOPE`) that pause
the pipeline for human approval. The full list, which command shows which, and the allowed answers:
`.claude/docs/director-gates.md` — **Read it before showing any gate.** SCOPE_GATE prints a `Milestone:` line (the
only enforcement point of `rules/roadmap-milestones.md`). Gate markers: 45-minute TTL, cleared at SessionStart except
`source=compact` → `docs/incidents/gate-markers.md`.

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

| Feature | Status | Effect |
|---------|--------|--------|
| `addressables` | **DISABLED** | Skip `rules/addressables.md`, Addressables hooks and address-constant checks |
| `testing` | **ENABLED** | Enforce `rules/testing.md`, NSubstitute, test-folder/asmdef requirements and test hooks |
| `ecs` | **DISABLED** | Skip `rules/ecs-dots.md`, `check-ecs-structural-changes.sh`, `check-enum-byte-base.sh` |
| `graph` | **ENABLED** | `graph.json` is the primary source of truth; graph-aware commands query it first → `docs/knowledge-graph.md` |
| `hybrid_graph` | **DISABLED** | Call-graph queries use `graph-traversal.py`/`jq`, not the MCP server → `docs/knowledge-graph.md` |

> When a feature is DISABLED, Claude must not enforce its rules or suggest its patterns.

## Skills Library (`.claude/skills/`)

`skills-index.md` is the live index of all skills (`/discover --write` and `/learn` keep it current). Reference skills
under `third-party/`, `plugins/`, `learned/`, `platform/` are listed in `.claude/docs/auto-loaded-skills.md` —
injected at SessionStart; Read a skill when its description matches the work. → `docs/incidents/skills-loading.md`

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.
