# Unity Claude AI Template

A personal Claude Code configuration template for Unity 6 projects. Drop the `.claude/` folder into any Unity project to get automatic code quality enforcement, slash commands, and AI-assisted workflows — all following a consistent architecture.

---

## Table of Contents

- [What This Is](#what-this-is)
- [Quick Start](#quick-start)
- [Configuration File Map](#configuration-file-map)
- [Stack](#stack)
- [Knowledge Graph](#knowledge-graph)
- [Usage Modes](#usage-modes)
- [Adding to an Existing Project](#adding-to-an-existing-project)
- [Building a Game from Scratch](#building-a-game-from-scratch)
- [Hooks — Auto-Enforced on Every Write](#hooks--auto-enforced-on-every-write)
- [Slash Commands](#slash-commands)
- [Agents](#agents)
- [Model Tiers](#model-tiers)
- [Recommended Plugins](#recommended-plugins)
- [Review Modes](#review-modes)
- [Director Gates](#director-gates)
- [Session State](#session-state)
- [Engine Version Reference](#engine-version-reference)
- [Built-In Skills](#built-in-skills)
- [Writing New Skills](#writing-new-skills)
- [Hook Audit Log](#hook-audit-log)
- [Manual Setup](#manual-setup-required-after-setup-project)
- [Architecture in a Nutshell](#architecture-in-a-nutshell)
- [Distribution as a Claude Code Plugin](#distribution-as-a-claude-code-plugin)
- [CI Integration — GitHub Actions](#ci-integration--github-actions)
- [Project-Specific Files](#project-specific-files-not-in-this-template)
- [License](#license)

---

## What This Is

Claude Code reads the `.claude/` folder when it opens a project. This template pre-loads it with:

- **Rules** — architecture, naming, SOLID/OOP, testing, ECS, serialization, and Addressables standards that Claude follows automatically
- **Hooks** — shell scripts that run on every file write, blocking bad patterns before they land
- **Commands** — slash commands for common workflows (`/new-module`, `/setup-project`, `/debug-session`, etc.)
- **Agents** — specialized AI roles (`unity-coder`, `unity-fixer`, `unity-reviewer`, `unity-scout`, `committer`, and more)

---

## Quick Start

### Prerequisites

Install these packages in Unity Package Manager before running `/setup-project`:

| Package | Source | Package ID |
|---------|--------|-----------|
| **VContainer** | OpenUPM or git URL | `jp.hadashikick.vcontainer` |
| **UniTask** | OpenUPM or git URL | `com.cysharp.unitask` |
| **New Input System** | Package Manager | `com.unity.inputsystem` |

Optional packages are installed separately — see [Manual Setup](#manual-setup-required-after-setup-project).

### 1. Install into your project

**Option A — bootstrap script (recommended):**

```bash
# From within your Unity project root (must have a .git directory)
bash /path/to/unity-claude-ai-template-repo/install.sh

# Force overwrite an existing .claude/ folder
bash /path/to/unity-claude-ai-template-repo/install.sh --force

# Or install into a specific target
bash /path/to/unity-claude-ai-template-repo/install.sh /path/to/your-project
```

The script copies `.claude/`, `.claudeignore`, and `.claude-plugin/`; makes all hook scripts executable; clears ephemeral session state; and prints a NEXT STEPS block.

**Option B — manual copy:**

```
your-unity-project/
└── .claude/
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

This generates project-specific boilerplate: assembly definition files, base framework classes (`IEventBus`, `EventBus`, `EventBusAccessor`, `AppModules`, `AppScope`, `ConfigCatalog`, `EventBusModule`). If MCP is connected, it also creates scenes, sets up AppScope in the Bootstrap scene, and configures Build Settings — all through the Unity Editor automatically.

**Feature selection:** `/setup-project` asks about Addressables, Testing, and ECS DOTS. Based on your answers it writes `.claude/project-features.json`, skips irrelevant folders and asmdefs, removes disabled hooks from `settings.json`, and adds a `## Project Features` header to `CLAUDE.md`.

**Conflict detection (Step 0):** If `.claude/project-features.json` already exists, setup compares it against the actual project (folder presence, `manifest.json`) and reports any conflicts — useful after a partial or manual cleanup.

> **Package gating:** If VContainer/UniTask/Input System are missing, setup creates only the folder structure and stops. If NSubstitute DLL is missing (and Testing=yes), test `.asmdef` references and test templates are skipped. Re-run once packages are installed to continue.

---

## Global Claude Configuration (`~/.claude/CLAUDE.md`)

The global `~/.claude/CLAUDE.md` file applies to every Claude Code session across all projects. Use it for personal interaction preferences that are not project-specific.

The anti-sycophancy block is already included in `.claude/CLAUDE.md` — it ships with the template and applies to every project that installs it. If you want the same behavior globally (across all your projects), copy the block to `~/.claude/CLAUDE.md` as well:

```markdown
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
```

> **Why this matters:** Claude's default behavior includes sycophantic affirmations and agreement-first patterns that reduce usefulness during technical work. These rules suppress that behavior globally. See [GitHub issue #14759](https://github.com/anthropics/claude-code/issues/14759) for background.

---

## Configuration File Map

`CLAUDE.md` is the main entry point Claude Code reads at session start. It was split into multiple smaller files to avoid context/memory limits — the `@file` syntax includes them inline at load time.

### `.claude/CLAUDE.md` — Main entry point

Contains: stack requirements, session start instructions, hooks table (blocking), commands table, review modes, director gates, and session state. Includes `@`-referenced sub-files loaded inline at session start:

| Referenced file | What it contains |
|-----------------|-----------------|
| `.claude/docs/knowledge-graph.md` | Knowledge graph query cheatsheet and session-start graph instructions |
| `.claude/docs/quick-start.md` | Quick start guide |
| `.claude/docs/model-tiers.md` | Model tier definitions and aliases |
| `.claude/docs/hooks-blocking.md` | Blocking hooks table (exit 2) |
| `.claude/docs/hooks-warning.md` | Warning hooks (exit 0) — full table of non-blocking style/quality checks |
| `.claude/docs/commands.md` | Full slash commands reference |
| `.claude/docs/agents-index.md` | All custom agents and their roles |
| `.claude/docs/architecture-summary.md` | Key architecture rules summary |
| `.claude/docs/context-management.md` | Review modes, compaction, checkpoint usage |
| `.claude/docs/director-gates.md` | Full gate definitions (SCOPE, ARCHITECTURE, BREAKING, QUALITY, COMMIT) |
| `.claude/docs/orchestrate-rules.md` | NON-NEGOTIABLE /orchestrate execution rules |
| `.claude/docs/setup-checklist.md` | Manual post-setup steps |
| `.claude/docs/skills-index.md` | Skills library index — core, platform, systems, third-party |
| `.claude/docs/auto-loaded-skills.md` | Auto-managed @-references for third-party/plugin/learned/platform skills |

### `.claude/graph/` — Knowledge graph

| File | Purpose |
|------|---------|
| `schema.json` | JSON-Schema (draft-07) for `graph.json` — v1.3.0 |
| `graph.json` (generated) | Living index of the codebase — do not edit by hand. Stores `{"$partition": "..."}` refs for scenes/prefabs |
| `scenes.json` (generated) | Partition file — full `scenes[]` array, written atomically alongside `graph.json` |
| `prefabs.json` (generated) | Partition file — full `prefabs[]` array, written atomically alongside `graph.json` |
| `extractors/asmdef-extractor.sh` | Parses every `*.asmdef` |
| `extractors/csharp-extractor.sh` | Regex extractor — emits `methods[]` + `partial_calls[]` (confidence: INFERRED) |
| `extractors/csharp_extractor.py` | tree-sitter AST extractor — higher accuracy (confidence: EXTRACTED). Optional — see [C# Extractor](#c-extractor-tree-sitter-optional) |
| `extractors/mcp-extractor.md` | MCP scene/prefab extraction skill |
| `graph-builder.py` | Top-level orchestrator + SHA256 cache + call edge merge (Python stdlib, no jq) |
| `graph-traversal.py` | BFS traversal — impact, callers, path, god-nodes, --finalize-calls. Imports `graph_bfs_core` for shared logic |
| `graph_bfs_core.py` | Shared pure BFS module — no file I/O, no CLI. Imported by both `graph-traversal.py` and `graph-mcp-server.py` |
| `graph-mcp-server.py` | stdio MCP server — loads graph partitions into RAM, exposes callers/impact/path/god-nodes as `mcp__graph_mcp__*` tools. Used when `hybrid_graph: true` |
| `graph-validator.sh` | Architecture invariant checks (R1–R6) |
| `graph_cluster.py` | Community detection — groups related classes into modules. Uses Louvain (`networkx`) when available; falls back to stdlib greedy. Install `pip install networkx` for better results on sparse codebases. |
| `graph_analyze.py` | Surprising connections + enhanced god-nodes (cross-boundary edge analysis) |
| `graph_validate.py` | Two-mode validator. **Default (consistency):** internal graph integrity — orphan events, dangling call edges, missing installer classes (skips `unresolved:true` registrations). No source files read. **`--accuracy` flag:** re-extracts a sample via `csharp_extractor.py` (tree-sitter) and compares against graph — run manually or in CI |
| `graph-viz.py` | `graph.html` generator — resolves `$partition` refs, builds a class/interface/event node model with calls/implements/publish/subscribe/registers edges, emits one HTML file with inline CSS + a vis-network force-directed layout. Offline, no CDN, no build step; references a vendored `vis-network.min.js` (pinned 9.1.6). See [Visualizer](#visualizer-graphhtml) |
| `codex-validator.md` | Codex accuracy spot-check prompt |
| `graph-watch.sh` | Optional fswatch/inotifywait watch loop |

### `.claude/rules/` — Auto-loaded rule files

Each rule file begins with a `## Cards` section containing WHEN/WRONG/RIGHT/GOTCHA cards — quick-scan summaries of the most important rules. The prose reference follows below the cards. Read the cards first; consult the prose for full context.

| File | Covers |
|------|--------|
| `architecture.md` | VContainer DI, module structure, IEventBus, EventBusAccessor, Provider pattern, InputView, AppScope |
| `csharp-unity.md` | Naming, namespaces, #region, null checks, UniTask, encapsulation; namespace collision rule (`Game.Concretes.<Domain>` vs UnityEngine aliases) |
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas; material folder structure (`Arts/Materials/<Domain>/`); shader file structure (`_GameFolders/Arts/Shaders/`); URP shader rule (Standard forbidden) |
| `serialization.md` | FormerlySerializedAs, Unity null checks, SerializeReference |
| `unity-lifecycle.md` | Editor guards, platform defines, lifecycle order, threading, Time, `.meta` files |
| `unity-async.md` | UniTask, no coroutines, CancellationToken, DontDestroyOnLoad |
| `unity-input.md` | New Input System, InputService (ITickable) + InputHandler (per-prefab), action map switching |
| `unity-prefabs.md` | Prefab rules, new GameObject() forbidden, Destroy() rules, BaseCanvas pattern, Prefab Variants (Base+Variant decision table), folder structure, logic/visual separation |
| `testing.md` | Test type decision tree (EditMode / PlayMode-Programmatic / PlayMode-Scene / ECS / NoTest), NSubstitute, AAA pattern, assembly setup |
| `ecs-dots.md` | Authoring/Baker, component naming, ISystem+IJobEntity, ECB, Hybrid linking |
| `addressables.md` | No Resources.Load, async loading, handle lifecycle, address constants |
| `event-patterns.md` | UnityEvent forbidden, IEventBus vs Action vs C# event decision tree |
| `scene-hierarchy.md` | Standard 6-container scene hierarchy (`[Setup]` → `[Services]` → `[UI]` → `[Environment]` → `[Characters]` → `[VFX]`), classification table, prefab/container rules |
| `bootstrap-pattern.md` | Code-first static Module pattern: `[X]Module` static class → `AppModules.cs` → `AppScope`. ConfigCatalog, SceneModules, new module addition flow (one line in AppModules, no Editor asset) |
| `solid-oop.md` | MonoBehaviour rol sınırları (View/Provider/Controller only, ~100 satır max); **suffix kuralı: `*View` yalnızca Canvas/UI, `*Controller` gameplay/karakter, `*Provider` Unity API soyutlaması**; SRP tek-cümle testi (AND içermemeli); OCP polymorphism kuralı; DIP constructor-interface kuralı |

### `.claude/docs/` — Key reference docs (not loaded at startup)

| File | Purpose |
|------|---------|
| `hooks-blocking.md` | Blocking hooks table (`@`-included in CLAUDE.md) |
| `hooks-warning.md` | Warning hooks table (`@`-included in CLAUDE.md) |
| `agents-index.md` | Agent roster (`@`-included in CLAUDE.md) |
| `skills-index.md` | Skills library index (`@`-included in CLAUDE.md) |
| `auto-loaded-skills.md` | Auto-managed `@`-references for all third-party/plugin/learned/platform skills — updated by `auto-load-skills.sh` hook |
| `commands.md` | Commands reference (`@`-included in CLAUDE.md) |
| `director-gates.md` | Full gate definitions (SCOPE, ARCHITECTURE, BREAKING, QUALITY, COMMIT) |
| `architecture-summary.md` | Key architecture rules summary |
| `context-management.md` | Review modes, compaction, checkpoint usage |
| `quick-start.md` | Quick start guide |
| `setup-checklist.md` | Manual post-setup steps |
| `model-tiers.md` | Model tier definitions and aliases |
| `knowledge-graph.md` | Knowledge graph query cheatsheet and session-start instructions |
| `orchestrate-rules.md` | NON-NEGOTIABLE /orchestrate execution rules |

### `docs/` — Human-readable project docs

| File | Purpose |
|------|---------|
| `ARCHITECTURE.md` | High-level system architecture diagram and pipeline flow |
| `SETUP.md` | Quick start, adding to existing project, hook audit log, model tiers |
| `ROADMAP.md` | Module roadmap table — status rollup for all modules (`/roadmap` creates it) |
| `modules/<n>-<name>/` | Per-module vertical slices: `spec.md`, `design.md`, `tasks.md` (`/plan-module <n>` creates them) |
| `CATCH_UP.md` | Auto-generated codebase guide (created by `/catch-up`, not committed) |
| `archive/WORKFLOW.md` | Archived — old horizontal phase-based pipeline (replaced by modules/ system) |

---

## Knowledge Graph

`.claude/graph/` ships a Graphify-inspired Unity-specific knowledge graph (v1.3.0). When enabled (default in
`/setup-project`), the graph indexes every class, interface, event, installer, scope, asmdef, scene,
prefab, **method**, and **call edge**. Graph-aware commands across planning, implementation,
fix/debug, investigation, migration, and audit/review pipelines run a Step 0 graph preload —
reading this graph instead of scanning files from scratch, and falling back to a file scan only
when the graph is stale (> 24h), empty, or disabled.

**v1.3.0 partition architecture:** `scenes[]` and `prefabs[]` live in sibling files `scenes.json` and `prefabs.json`. `graph.json` stores `{"$partition": "..."}` references — keeping the main artifact slim regardless of scene/prefab count. All three files are generated and committed together.

### Quick commands

| Command | Purpose |
|---------|---------|
| `/build-knowledge-graph [--full\|--incremental]` | Build/refresh the graph |
| `/build-knowledge-graph --validate-with-codex` | Spot-check graph accuracy with Codex |
| `/knowledge-graph summary` | One-screen project overview |
| `/knowledge-graph implementers <I>` | List concrete classes implementing an interface |
| `/knowledge-graph publishers <E>` | List event publishers |
| `/knowledge-graph subscribers <E>` | List event subscribers |
| `/knowledge-graph registrations <T>` | Which installer registers a type |
| `/knowledge-graph scope-tree` | Full VContainer scope hierarchy |
| `/knowledge-graph prefab <P>` | Prefab components and variant status |
| `/knowledge-graph violations` | Print architecture errors and warnings |
| `/knowledge-graph diff` | Compare current graph with last backup |
| `/knowledge-graph callers <Class.Method>` | All direct callers of a method |
| `/knowledge-graph impact <ClassName> [--hops N]` | Blast radius — upstream + downstream affected nodes |
| `/knowledge-graph path <A> <B>` | Shortest call-graph path between two nodes |
| `/knowledge-graph god-nodes [--top N]` | Most-connected classes (over-coupling candidates) — shows `community_id` + `severity` after v1.2.0 build |
| `/knowledge-graph communities [--scope S]` | List class community groups detected from call edges |
| `/knowledge-graph surprising [--severity warning\|info]` | Cross-scope/assembly edges that indicate architectural drift |

### Triggers (kept in sync automatically)

- Every Write/Edit → PostToolUse `graph-auto-update.sh` (incremental, background, ~1–2s)
- Every `git commit` → post-commit hook (incremental rebuild, preserves MCP cache)
- Manual: `/build-knowledge-graph`

### What the extractor captures

| Data | Detail |
|------|--------|
| Classes / interfaces | Name, namespace, file, base types, `implements[]`, `is_mono_behaviour`, `has_static_instance` |
| Methods | Per-class: name, signature, line, accessibility, `is_async`, `is_static`, return type |
| Call edges | `calls[]` — `ClassName.MethodName → callee`, file, line, confidence; resolution fields `callee_class` / `callee_file` / `method_match` / `callee_kind` (`internal` \| `external` \| `unresolved`) set by the builder's global pass |
| Events | Publishers + subscribers via `_eventBus.Publish<T>()` / `.Publish(new T())` and `Subscribe<T>()` |
| VContainer registrations | `Register<T>`, `RegisterInstance`, `RegisterComponent` — including `.As<IFoo>()`, `.AsImplementedInterfaces()`, and real `Lifetime` (Singleton/Transient/Scoped) |
| VContainer scopes | `LifetimeScope` subclasses; parent resolved from `[ParentScope(typeof(X))]` in C# code **or** from `LifetimeScope.parentReference` Inspector field via MCP (MCP wins on conflict) |
| Prefabs (MCP) | Component list, variant status, full child GO hierarchy. Optional: scalar Inspector field values (`int`, `float`, `string`, `bool`, `enum`) via `execute_code` + `SerializedObject` — shown by `/knowledge-graph prefab <Name>` |
| Assemblies | Name, file, references, platforms, `allowUnsafeCode` |

### Nested Unity project support

For Unity projects nested under a sub-folder (e.g. `MyGame/Assets/`), set `unity_project_folder` in `.claude/project-features.json` (e.g. `"MyGame"`). The builder, extractors, and watcher all read it and prefix `Assets/` accordingly — never hardcode a project path.

```bash
# Explicit override (takes precedence over config)
bash .claude/graph/extractors/csharp-extractor.sh --root MyGame/Assets
bash .claude/graph/extractors/asmdef-extractor.sh --root MyGame/Assets

# Or set env var for graph-watch
GRAPH_WATCH_ROOT=MyGame/Assets bash .claude/graph/graph-watch.sh
```

With no `--root`/env override, the scan root is resolved from `unity_project_folder` (`"."` → `Assets/`).

### C# Extractor — tree-sitter (optional)

By default the C# extractor uses **regex** (confidence: `INFERRED`). For higher-accuracy AST-based extraction (confidence: `EXTRACTED`), install the tree-sitter Python bindings:

```bash
pip install tree-sitter tree-sitter-c-sharp
```

Once installed, `graph-builder.py` automatically uses `csharp_extractor.py` instead of the regex pipeline — no config change needed. Without it, the build falls back to regex and emits a loud `FALLBACK_EXTRACTOR` warning to both `validation.warnings[]` (in `graph.json`) and stderr — so a degraded build is never silent.

The AST extractor correctly handles:
- `base_list` named child lookup (tree-sitter-c-sharp grammar quirk — field-based lookup returns nothing)
- **Type-inferred event pub/sub** — not just the generic form `Publish<T>()`/`Subscribe<T>()`, but also `Publish(new GoldChangedEvent())` where the event type comes from the argument's `object_creation_expression`. This is walked on the AST per member (fields + method params + method-local `var`), so scoped symbols never leak across methods
- `RegisterInstance<T>`, `RegisterComponent<T>`, `RegisterEntryPoint<T>` VContainer registration variants **plus** type-inferred `RegisterInstance(config)` — the registered type is resolved from the argument identifier against fields and method-local variables
- Null-conditional calls — `_eventBus?.Publish(...)` (via `conditional_access_expression` / `member_binding_expression`)
- **Unresolved registrations are marked, never dropped** — when a registered type can't be resolved (e.g. a mystery local), the entry is emitted as `{"unresolved": true, "confidence": "AMBIGUOUS"}` for human review; consistency validation and the visualizer skip these rather than fabricating a false edge
- `struct_declaration` — `IEvent` structs are added to `events[]`
- VContainer `Installer` / `LifetimeScope` detection for `vcontainer.installers` and `vcontainer.scopes`

> **Known limitation:** a `Publish`/`Subscribe` on an arbitrary receiver (`foo.Publish<X>()`) is detected by method name alone — the extractor does not verify the receiver is an `IEventBus`. This matches the previous regex behaviour (no regression) and is documented in `.claude/docs/knowledge-graph.md`.

> **Recommended** if your project has 50+ classes or complex generics/multi-line declarations. Not required for the graph to function.

### Visualizer (graph.html)

`graph-viz.py` turns `graph.json` into a `graph.html` — inline CSS, an inline JSON data island, and inline glue JS driving a **vis-network** force-directed layout. Offline and build-free (no CDN, no external fonts/images), it opens in any browser — but it is **not** fully self-contained: it references a vendored `vis-network.min.js` (pinned 9.1.6) that must sit in the same directory.

```bash
python3 .claude/graph/graph-viz.py                 # graph.json → graph.html (defaults)
python3 .claude/graph/graph-viz.py --graph path/to/graph.json --out /tmp/graph.html
```

- Nodes: class (MonoBehaviour = blue, plain C# = purple), interface (green square), event (orange)
- Edges: `calls` (grey), `implements` (green), `publish` (orange), `subscribe` (blue dashed), `registers` (purple dotted)
- Interaction: hover for a tooltip (name · type · namespace), drag to reposition, scroll to zoom, drag empty space to pan
- `$partition` refs (`scenes.json` / `prefabs.json`) are resolved recursively; a missing partition **fails fast** rather than rendering a partial graph
- `unresolved:true` registrations are skipped — no fabricated `registers` edge
- Graphs over 800 nodes still render fully, with an on-screen "layout may be dense" note (no silent truncation)

`graph.html` is **generated** and `.gitignore`d — reproducible from `graph.json` via `/build-knowledge-graph --viz`. The vendored `vis-network.min.js` it loads **is** committed; that one file is the only tracked viz artifact.

> This is the one piece taken from [Graphify](https://github.com/Graphify-Labs/graphify) (the force-directed viz idea), rebuilt standalone — our own generator over `graph.json`, rendering with a single vendored, pinned `vis-network.min.js` (no CDN, no build step). Graphify itself was evaluated and **not** adopted as a backend — the fragile layer is the Unity-semantic detection, which is inherently ours to maintain.

### Hybrid MCP backend (optional, off by default)

`hybrid_graph` in `project-features.json` (default `false`) routes the four call-graph queries (`callers`, `impact`, `path`, `god-nodes`) through a custom in-process MCP server (`graph-mcp-server.py`) backed by a shared BFS core (`graph_bfs_core.py`). The eleven Unity-semantic queries (`summary`, `implementers`, `publishers`, etc.) are unaffected — they stay on `jq`.

When `hybrid_graph` is `false` (default), behaviour is **byte-for-byte identical to today** — no stderr output, no pip probe, no MCP dependency.

**To enable:** Run `/setup-project` with `graph=true` — Step 5.6 handles everything automatically:

1. Checks if the `mcp` Python package is importable; installs it if not.
2. Registers `graph-mcp-server.py` as a project-scoped MCP server (`claude mcp add --scope project`), creating `.mcp.json` in the repo root (gitignored — machine-specific).
3. Writes `hybrid_graph: true` to `.claude/project-features.json`.
4. Restart Claude Code. If `mcp__graph_mcp__*` tools appear in the session, the server is running.

**Manual enable (if not using `/setup-project`):**
```bash
pip install mcp                   # or: pipx install mcp
claude mcp add --scope project graph-mcp python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
# then set "hybrid_graph": true in .claude/project-features.json
```

**Fallback:** If the MCP server is unavailable while `hybrid_graph` is `true`, call-graph queries automatically fall back to `graph-traversal.py` and emit a warning on stderr.

> **Recommendation:** Leave this off until you have verified that the graph works correctly in your project with the default backend. The hybrid backend produces identical results — the benefit is reduced subprocess overhead on large projects.

### Regression test harness

`.claude/graph/test/verify-graphify.sh` runs a self-contained test suite against the graph pipeline — no Unity Editor required.

```bash
bash .claude/graph/test/verify-graphify.sh
# Expected: 29 PASS, 0 FAIL (template mode — C#-dependent tests skip until source files exist)
```

Tests cover: builder flags (`--full`, `--incremental`, `--skip-mcp`, `--output`, `--quiet`), all six validator rules (R1–R6), MCP prefab merge, `/knowledge-graph` subcommands, PostToolUse and post-commit triggers, v1.2.0 modules (cluster/analyze/validate/csharp_extractor). Sandbox backup/restore ensures the live `graph.json` is never corrupted by a test run.

### Confidence levels

`EXTRACTED` (tree-sitter AST), `INFERRED` (regex-mode or call-graph guess), `AMBIGUOUS` (needs human review).

---

## Stack

### Required

| Package | Role |
|---------|------|
| **VContainer** | Dependency injection |
| **UniTask** | Async/await (replaces coroutines) |
| **New Input System** | Input handling |

### Optional (selected during `/setup-project`)

| Package | Role | When disabled |
|---------|------|---------------|
| **Addressables** | Runtime asset loading | Addressables rules and skills are skipped |
| **NSubstitute** | Test mocking (manual DLL install) | Test folders, asmdefs, and test hooks are skipped |
| **Unity ECS DOTS** | Data-oriented systems | ECS folder, asmdef, and ECS hooks are skipped |

`/setup-project` asks about each optional feature upfront and writes `.claude/project-features.json`. Hooks and commands automatically skip disabled features — no false warnings, no irrelevant rules.

---

## Usage Modes

| Mode | When to use |
|------|-------------|
| **New project** | Run `/setup-project` to generate the full folder structure, assembly definitions, and base classes from scratch |
| **Existing project** | Copy `.claude/` only — hooks and commands work immediately. Migrate code gradually, module by module |

---

## Adding to an Existing Project

You do **not** need to start from scratch. The `.claude/` folder is self-contained and can be dropped into any existing Unity project.

### `.claudeignore`

Copy `.claudeignore` from this repo to your project root alongside `.gitignore`. It tells Claude Code to skip Unity build artifacts, IDE temp files, and large binary assets — preventing them from being read into context and wasting tokens.

```bash
cp .claudeignore /path/to/your/project/.claudeignore
```

Key exclusions: `Library/`, `Temp/`, `Logs/`, `Build/`, `*.fbx`, `*.psd`, `*.wav`, `*.mp4`, `.claude/state/*.jsonl`.

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
| `check-unity-event` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` | Use `IEventBus`, `Action`/`Func`, or C# `event` keyword |
| `check-time-scale` | `Time.timeScale =` assignment | Use IEventBus + PauseService pattern |
| `check-no-monobehaviour-in-services` | `class FooService : MonoBehaviour/ScriptableObject` in `_Framework/` / `Games/Abstracts/` / `Games/Concretes/` | Make it a Provider, View, or Controller instead — `using UnityEngine` for math types is allowed |
| `guard-editor-runtime` | Unguarded `UnityEditor` in runtime code | Wrap with `#if UNITY_EDITOR` |

### Recommended migration approach

1. **Copy `.claude/` into your project** — commands and warnings are active immediately
2. **Temporarily disable blocking hooks** you're not ready for: comment out the relevant `[[hooks]]` entry in `.claude/settings.json`
3. **Run `/check-portability` on existing modules** to see what needs to change
4. **Migrate module by module** — new code follows the template, legacy code migrates on touch
5. **Re-enable hooks** as each area of the codebase is migrated

> **Note:** If VContainer, UniTask, or the New Input System are not yet installed, add them via Package Manager before enabling the hooks that depend on them.

---

## Building a Game from Scratch

### Phase 1 — Idea & Design

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/game-idea` | Manual — single step | Refines a raw idea into a GDD — surfaces assumptions, defines scope, creates a "Not Doing" list |
| `/architect` | Manual — single step | Converts the GDD into a TDD — `unity-critic` adversarially challenges the design before you review |
| `/grill-me [plan or file]` | Manual — single step | Stress-tests a plan or decision — one pointed question at a time, recommends an answer, ends with a Decision Record. Auto-delegates to Opus (heavy tier) regardless of current session model. **Next:** if the plan changed, run `/update-plan` to reflect the decisions; skip if the plan was only confirmed. |

### Phase 2 — Planning

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/roadmap` | Manual — single step | Reads GDD + TDD + existing `docs/modules/` → produces `docs/ROADMAP.md` module table with gap analysis. Creates the list of modules to build; shows done vs. missing. Run once after TDD is approved. |
| `/plan-module <n>` | Manual — single step | Just-in-time planner for a single module. ARCHITECTURE_GATE fires before spawning agents. Produces `docs/modules/<n>-<name>/spec.md`, `design.md`, and `tasks.md`. Run immediately before you orchestrate that module. |
| `/dry-run` | Manual — single step | *(optional)* Preview pending tasks in a `tasks.md` without executing |
| `/plan-summary <file>` | Manual — single step | *(optional)* Reads a plan file and produces a 3-section human-readable summary — what we're doing, how, and what you'll see at the end. |

### Phase 3 — Project Setup

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/setup-project` | Manual — single step | Detects existing state → asks feature questions → generates folder structure, `.asmdef` files, and base framework classes |

### Phase 4 — Implementation

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/orchestrate docs/modules/<n>/tasks.md` | Manual to start. **Within each task:** tester → coder → verifier → reviewer → committer run **automatically**. **Checkpoint lines** pause for `Proceed?`. | Executes a module's `tasks.md` end-to-end; marks `- [ ]` → `- [x]` and updates `ROADMAP.md` on completion |
| `/continue docs/modules/<n>/tasks.md` | Manual — resumes interrupted orchestrate | Resumes an interrupted orchestration run from the EVENTS.jsonl journal |

### Phase 5 — Quality

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/qa` | Manual to start. Inside: **ralph → silent-failure-hunt → validate** run **automatically** | Full quality pipeline — preferred entry point for Phase 5 |
| `/validate` | Manual — single step | Verifies exit criteria for a completed phase |
| `/review-code` | Manual — single step | Deep review of specific files via `unity-reviewer` |
| `/silent-failure-hunt` | Manual — single step | Audits for swallowed exceptions, async void, event leaks |
| `/performance-audit` | Manual — single step | Hot path allocation and draw call audit |
| `/ralph` | Manual to start. Inside: compile + test → fix loop (max 10 iterations) run **automatically** | Relentless verify-fix loop — refuses to stop until the project is clean |
| `/graphics-setup <mobile\|pc>` | Manual to start. Pauses for approval before creating assets | Tune or recreate URP quality tiers after gameplay is stable |
| `/audio-clip-setup [path]` | Manual to start. Pauses for commit confirmation at the end | Audit and fix AudioClip import settings before a build |

### Phase 6 — Documentation & Learning

| Command | How it runs | What it does |
|---------|------------|-------------|
| `/learn` | Manual — single step | Extracts project-specific patterns into `.claude/skills/learned/` and updates `skills-index.md` |
| `/catch-up` | Manual — single step | Generates a human-readable codebase guide at `docs/CATCH_UP.md` |
| `/adr <decision>` | Manual — single step | Records an Architecture Decision Record to `docs/decisions/` |
| `/create-changelog` | Manual — single step | Creates or updates `CHANGELOG.md` |
| `/update-claude-md` | Manual — single step | Syncs CLAUDE.md tables with actual project state (hooks, rules, commands, agents) |
| `/smart-commit` | Manual to start. Inside: analyze → group → commit run **automatically** | Groups dirty working tree into logical commits |
| `/smart-commit-selected` | Manual to start. Inside: analyze → plan groups → **multiSelect checklist** → commit selected only | Commit only chosen groups from dirty working tree |

### Full Flow

Every command is **manually triggered** — there is no automatic chaining between phases.

```
/game-idea → /architect → /roadmap → /setup-project
                                           ↓
                              /plan-module 1 → /orchestrate docs/modules/1-*/tasks.md
                              /plan-module 2 → /orchestrate docs/modules/2-*/tasks.md
                                          …
                              /plan-module N → /orchestrate docs/modules/N-*/tasks.md
                                           ↓
                                /qa → /review-code → /performance-audit
                                           ↓
                                  /learn → /smart-commit
```

#### When to run `/qa`

Run `/qa` after any implementation work outside of `/orchestrate` — e.g. after `/implement`, `/fix`, or any multi-file change. It is your pre-commit quality gate.

Skip `/qa` if you're inside an active `/orchestrate` run — the phase gate already covers it.

### Incremental Development (existing project or single feature)

| Command | How it runs | When to use |
|---------|------------|-------------|
| `/implement` | Manual to start. Inside: flag detection (`--heavy`/`--lite`) → complexity score → test-type-router → [tester if not NoTest] → coder (sonnet; opus if `--heavy`, haiku if `--lite`) → verifier → reviewer → silent failure audit → committer run **automatically** | Implement a feature or task with full TDD pipeline |
| `/fix` | Manual to start. Inside: flag detection (`--heavy`/`--lite`) → unity-fixer + unity-scout → test-type-router → [tester (regression) if not NoTest] → coder (sonnet; opus if `--heavy`, haiku if `--lite`) → verifier → reviewer → silent failure audit → committer run **automatically** | Bug fix when stack trace clearly points to root cause |
| `/fix-deep` | Manual to start. Inside: log intake → hypothesis → debug injection → evidence gate → fix (only if proven) → committer run **automatically**. **Refuses to fix if root cause is unproven** | Logic bugs, intermittent issues, or any uncertain root cause |
| `/fix-codex` | Manual to start. Inside: **Codex Analysis** (fresh eyes) → **Human Gate** → **Codex Implementation** → **Claude Review** → loop back to Codex if NEEDS REVISION (max 2x) → committer | Legacy/large codebase (2000+ line files) or stuck 30+ min — Codex analyzes and implements, Claude reviews |
| `/new-module` | Manual — single step | Scaffold a 5-file module (Interface, Service, Config, Installer, Events) |

> **`/implement` flags:** Use `--lite` (haiku tier) for trivial single-file changes where speed matters. Use `--heavy` (opus tier) for unusually complex tasks. Default is sonnet tier. `/implement` and `/fix` auto-suggest the right flag from the complexity score — `--lite` on Simple (< 0.3), `--heavy` on Complex (≥ 0.7); the suggestion is non-blocking and you choose whether to re-run with it.

> **`/fix` vs `/fix-deep` vs `/fix-codex`:** Use `/fix` when the stack trace points to root cause (add `--lite` for obvious one-liners). Use `/fix-deep` for logic bugs or intermittent issues. Use `/fix-codex` for legacy/large codebases or when stuck 30+ minutes — Codex analyzes and implements with fresh eyes, Claude reviews the result.

---

## Hooks — Auto-Enforced on Every Write

Hooks run silently in the background every time Claude writes or edits a C# file.

### Hook Profiles

Control which hooks are active via `UNITY_HOOK_PROFILE`:

| Profile | What runs | When to use |
|---------|-----------|-------------|
| `minimal` | Only 5 critical safety hooks (`block-git-push`, `block-scene-edit`, `block-projectsettings`, `check-config-protection`, `guard-critical-files`) | Prototypes, game jams, legacy migration |
| `standard` | All hooks except strict-only enforcement hooks (default) | Regular development |
| `strict` | All hooks, including heavy enforcement (gate guards, skill enforcer, codex review order) | Team projects, CI, shared repos |

```bash
# Set for one session
UNITY_HOOK_PROFILE=minimal claude

# Disable all hooks entirely (kill switch)
DISABLE_UNITY_HOOKS=1 claude

# Downgrade a single blocking hook to warn mode
UNITY_HOOK_MODE=warn claude

# Disable one specific hook
DISABLE_HOOK_CHECK_PURE_CSHARP=1 claude
```

Full profile documentation: `.claude/docs/hook-profiles.md`

### Hook Self-Tests

The hook suite has automated bats-core tests at `.claude/hooks/tests/`:

```bash
# Run all hook tests (requires bats-core)
./.claude/hooks/tests/run-tests.sh

# Install bats-core
brew install bats-core   # macOS
npm install -g bats      # Linux
```

12 test files cover every blocking hook with happy path, blocking trigger, profile skip, and warn-mode scenarios.

### Blocking (exit 2 — stops the write)

| Hook | What it blocks |
|------|---------------|
| `block-git-push` | `git push` — Claude cannot push; user always pushes manually |
| `block-scene-edit` | Direct editing of `.unity`, `.prefab`, `.asset` YAML |
| `guard-editor-runtime` | `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `check-no-monobehaviour-in-services` | `class FooService : MonoBehaviour` or `: ScriptableObject` in service/domain files — inheritance blocked, `using UnityEngine` allowed; exempts `*Provider`, `*View`, `*Controller`, `*Root`, `*Panel`, `*Button`, `*Events`, and ScriptableObject configs (`*Configuration`/`*Config`/`*Catalog`/`*Definition`) |
| `check-input-system` | Legacy `Input.GetKey` / `Input.GetAxis` API |
| `check-unity-event` | `UnityEvent`, `UnityEvent<T>`, `using UnityEngine.Events` |
| `check-time-scale` | `Time.timeScale =` assignment |
| `check-vcontainer-singleton` | Static singleton patterns outside of `EventBusAccessor` |
| `guard-critical-files` | Edits to `AppScope`, `InputService`, `*Installer`, `EventBus`, `AppModules`, `ConfigCatalog`, `.asmdef` — deny-then-allow gate: first edit attempt per file blocks and demands investigation, retry passes; creating a brand-new file is never blocked |
| `check-config-protection` | Modifications to `.asmdef`, `.claude/settings.json`, `.inputactions`, `manifest.json` — exception: test assemblies |
| `guard-gate-cleared` (PreToolUse) | Edit/Write on any C# file that has not been read in the current session |
| `guard-pipeline-direct-work` (PreToolUse Edit\|MultiEdit\|Write\|Bash) | Blocks direct `Edit`/`Write` to `_GameFolders/Scripts/**/*.cs` and direct `git commit` while a Director Gate is open (`gate-cleared` exists) but no subagent is currently running (`subagent-depth` == 0) — closes the "gate was shown but pipeline agent was never spawned" loophole. Escape valve: `.claude/state/pipeline-override` for explicit user-approved bypasses |
| `guard-reviewer-order` (PreToolUse) | `unity-reviewer` spawn if Codex CLI is installed but `codex:codex-rescue` has not reviewed the current pipeline pass |
| `check-no-runtime-instantiate` | `new GameObject()` — blocked everywhere in runtime code; use `Instantiate(prefab)` or `Addressables.InstantiateAsync()` |
| `check-enum-byte-base` | `enum` without `: byte` base inside `IComponentData` or `IEvent` structs — use `: ushort` if 255+ values needed |
| `block-graph-direct-read` (PreToolUse Read) | Direct `Read` of `graph.json`, `scenes.json`, or `prefabs.json` when `hybrid_graph: true` — use `/knowledge-graph` subcommands or `mcp__graph_mcp__*` tools instead |

### Warnings (exit 0 — logged to stderr, does not block)

| Hook | What it warns |
|------|--------------|
| `check-no-linq-hotpath` | LINQ inside `Update` / `FixedUpdate` / `LateUpdate` |
| `check-no-hotpath-expensive-calls` | `GetComponent`, `Camera.main`, `FindObjectOfType`, bare `transform.`, `tag ==`, `SendMessage` in hot paths |
| `check-getcomponent-in-awake` | `GetComponent`/`GetComponentInChildren` in `Awake` — prefer `[SerializeField]` Inspector assignment |
| `check-no-runtime-instantiate` (Destroy) | `Destroy()` outside Pool/Manager/Spawner files — use `pool.Return()` / `SetActive(false)` instead; Pool/Manager/Spawner may call `Destroy()` for capacity trim or manager shutdown |
| `warn-serialization` | Renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `check-ecs-structural-changes` | `EntityManager.AddComponent/DestroyEntity` inside ECS system (use ECB) |
| `check-async-void` | `async void` outside Unity lifecycle methods (swallows exceptions) |
| `check-unitask-cancellation` | `async UniTask` methods missing `CancellationToken` parameter |
| `check-null-propagation` | `?.` or `is null` on Unity objects (bypasses destroyed-object detection) |
| `check-test-scene-exists` (PostToolUse) | PlayMode test file references a scene not found in `_Scenes/TestScenes/` — suggests `/create-test` |
| `track-read` (PostToolUse Read) | Records every `Read` tool call into `gateguard-reads.txt` — required for `gateguard.sh` Stage 1 (`unity_was_read()`) to pass. Without this, every edit is blocked even after reading the file. |
| `track-codex-review` (PostToolUse) | Creates `.claude/state/codex-reviewed` when `codex:codex-rescue` completes |
| `track-skill-invocations` (PostToolUse Skill) | Records every `Skill` tool invocation to `skills-invoked.txt` — required by `enforce-skill-for-keywords.sh` to know which skills are already loaded this session. Also injects `additionalContext` after every invocation to force Claude to read and follow the skill content before proceeding. |
| `auto-load-skills` (PostToolUse) | Adds `@`-reference to `.claude/docs/auto-loaded-skills.md` whenever a skill is written to `third-party/`, `plugins/`, `learned/`, or `platform/` |
| `enforce-skill-for-keywords` (UserPromptSubmit) | Detects third-party package keywords in every prompt. Skips enforcement if the skill is auto-loaded via `auto-loaded-skills.md` (already in context) or already invoked via `Skill` tool this session — otherwise injects a blocking context message |
| `instinct-capture` (PostToolUse) | Captures tool-use observations for later distillation into instincts |
| `cost-tracker` (PostToolUse) | Logs every tool call with timestamp for cost auditing |
| `hook-logger` | Central audit logger — appends newline-delimited JSON to `~/.claude/hook-audit.log` |
| `instinct-distill` (Stop) | Distills captured observations into confidence-scored instincts |
| `session-restore` (SessionStart) | Restores session state from `.claude/state/` on session start |
| `session-save` (Stop) | Saves current session state to `.claude/state/` on stop. Also **auto-expires ephemeral gate files** (`gate-cleared`, `sparc-approved`, `codex-reviewed`, etc.) so they never leak into the next session. Subagent counters are read only when log files exist — prevents `0\n0` jq parse error on sessions without subagents |
| `stop-verify` (Stop) | Drains the edit accumulator at session end — runs batch verifiers (shell syntax, JSON validity, one `dotnet build` for all `.cs` files written this session). ECC pattern: catches subagent writes whose PostToolUse hooks never fired in the main session. Must be listed after `session-save` in the Stop array. |
| `notify` (Notification) | OS-level notification when Claude finishes a task — macOS via `osascript`, Linux via `notify-send`. Persists last notification to `.claude/state/last-notify.json` for `/catch-up` |
| `pre-compact` (PreCompact) | Snapshots branch, recent commits, and edited files to `.claude/state/precompact-state.md` before `/compact` discards conversation history — consumed by `session-restore.sh` and `/catch-up` |
| `block-projectsettings` (PreToolUse Edit\|Write) | Blocks direct edits to `ProjectSettings/*.asset`, `Packages/manifest.json`, and `packages-lock.json` — these files must be changed through the Unity Editor or Package Manager, not raw text edits **[MANUAL: add to settings.json]** |
| `check-ls-grep` (PreToolUse Bash) | Blocks `ls \| grep/awk/sed` patterns used for directory listing — forces use of `tree` instead |
| `graph-auto-update` (PostToolUse Write\|Edit) | Incremental graph rebuild in background on file change — never blocks. Warns once per session when `scanned_files == 0` (empty graph) |
| `verify-after-write` (PostToolUse Write\|Edit) | Runs `dotnet build` after each `.cs` write — prints WARNING to stderr if compile errors found; never blocks (exit 0). Reads `unity_project_folder` from `project-features.json` to locate `.sln`. MCP unavailable in bash hooks — dotnet CLI only. |
| `agent-start-log` (SubagentStart) | Appends spawn record to `.claude/state/subagent-log.jsonl` — `agent_type`, `agent_id`, `session_id`, `started_at`. Advisory only (exit 2 not honoured on SubagentStart). |
| `agent-stop-log` (SubagentStop) | Appends stop record with approximate duration to `.claude/state/subagent-log.jsonl`. Duration computed from matching SubagentStart timestamp; `-1` when no match. No `exit_code` in payload — pure audit trail. |
| `task-completed-log` (TaskCompleted) | Appends success record to `.claude/state/task-log.jsonl` — `task_id`, `task_title`, `task_subject`, `team_name`. Fires on success only (no `status` field). |

### Subagent Audit Trail

`agent-start-log`, `agent-stop-log`, and `task-completed-log` together give visibility into multi-agent pipeline runs (`/implement`, `/fix`, `/orchestrate`):

```bash
# Which agents ran this session
jq -rs '[.[] | select(.event=="SubagentStart") | .agent_type] | unique[]' .claude/state/subagent-log.jsonl

# Slow agents (> 120 s)
jq -s '[.[] | select(.event=="SubagentStop" and .duration_approx_s > 120)]' .claude/state/subagent-log.jsonl

# Completed tasks
jq -rs '[.[] | "\(.task_title) [\(.task_subject)]"] | .[]' .claude/state/task-log.jsonl
```

`session-save.sh` embeds totals into `session.json` on every Stop:
```json
"subagent_summary": { "spawned": 12, "stopped": 11, "tasks_completed": 5 }
```

Both JSONL files are persistent (not auto-expired) and gitignored. See `.claude/docs/hooks-warning.md → Subagent Audit Trail` for full field reference.

---

## Slash Commands

### Knowledge Graph

| Command | How it runs | Description |
|---------|------------|-------------|
| `/build-knowledge-graph [flags]` | Manual or auto (hook + git) | Build the knowledge graph; `--full` rebuilds from scratch; `--validate-with-codex` cross-checks accuracy |
| `/knowledge-graph <sub> [args]` | Manual | Query the knowledge graph: `summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff` |

### First-time project setup

| Command | How it runs | Description |
|---------|------------|-------------|
| `/setup-project` | Manual — single step | Detect existing state → ask feature questions → generate assembly definitions, base classes, and manual setup checklist |
| `/create-prefab-scene` | Manual — single step | **Legacy migration:** scan existing scenes for bare GameObjects, build a prefab inventory, create proper prefabs via MCP |

### Design

| Command | How it runs | Description |
|---------|------------|-------------|
| `/game-idea` | Manual — single step | Refine a raw idea into a GDD (assumption surfacing + "Not Doing" list) |
| `/architect` | Manual — single step | Create a Technical Design Document from a GDD (`unity-critic` adversarial challenge included) |
| `/grill-me [plan or file]` | Manual — single step | Stress-test a plan or decision — one pointed question at a time, produces a Decision Record on `/done`. Auto-delegates to Opus (heavy tier) regardless of current session model. **Next:** if the plan changed, run `/update-plan` to reflect the decisions; skip if the plan was only confirmed. |
| `/refine-gdd` | Manual — single step | Iterate on an existing GDD |
| `/refine-tdd` | Manual — single step | Iterate on an existing TDD |
| `/roadmap` | Manual — single step | Read GDD + TDD + existing modules → produce `docs/ROADMAP.md` module table with gap analysis. Run once after TDD is approved. |
| `/plan-module <n>` | Manual — single step | Just-in-time module planner: ARCHITECTURE_GATE → lean-planner + reviewer → writes `docs/modules/<n>-<name>/spec.md`, `design.md`, `tasks.md` → updates ROADMAP.md. Run immediately before orchestrating that module. |

### Pipelines (multi-agent)

All pipeline commands are **manually triggered**. Once started, internal steps run automatically until done or blocked.

| Command | How it runs | Description |
|---------|------------|-------------|
| `/implement <task>` | Manual to start → flag detection (`--heavy`/`--lite`) → complexity score → test-type-router → [tester if not NoTest] → coder (sonnet by default) → verifier → reviewer → silent failure audit → committer | TDD implementation pipeline. `--lite` forces haiku, `--heavy` forces opus. |
| `/fix <bug>` | Manual to start → flag detection (`--heavy`/`--lite`) → unity-fixer + unity-scout → test-type-router → [tester (regression) if not NoTest] → coder (sonnet by default) → verifier → reviewer → committer | Bug fix pipeline. `--lite` for trivial one-liners, `--heavy` for complex root causes. |
| `/fix-deep <bug>` | Manual to start → log intake → hypothesis → debug injection → evidence gate → fix (only if proven) → committer. **Refuses to fix if root cause is unproven** | Evidence-first bug fix — use for logic bugs or intermittent issues |
| `/fix-codex [--files f1,f2] <bug>` | Manual to start → **Codex Analysis** (fresh eyes, no hypotheses) → Human Gate → **Codex Implementation** → **Claude Review** → loop back to Codex if NEEDS REVISION (max 2x) → committer | Legacy/large codebase or when stuck 30+ min — Codex analyzes and implements, Claude reviews |
| `/migrate <pattern> in <scope>` | Manual to start → test guard → migrator → reviewer → committer | Legacy pattern migration (coroutine→UniTask, singleton→VContainer, etc.) |
| `/scene-setup <description>` | Manual to start → coder + unity-setup → verifier → reviewer → committer | Scene and prefab wiring pipeline |
| `/create-plan <file> <what>` | Manual to start → researcher (reads existing Modify files + scene/prefab pre-scan via graph) → planner (Opus) → reviewer loop (BREAKING revisions pause for user) → save → optional implementer | Create a phased plan from a spec |
| `/create-plan --lean <file> <what>` | Manual to start → researcher → **lean-planner** (Sonnet) → reviewer → save. No implementer auto-spawn. | Compact 3-5 task table plan — faster for small tasks. |
| `/update-plan <file> <change>` | Manual to start → analyzer → planner (Opus) → reviewer loop → save → optional implementer | Update an existing plan |
| `/update-plan --lean <file> <change>` | analyzer → **lean-planner** (Sonnet) → reviewer → save. No implementer auto-spawn. | Small plan changes — task add/remove, file path fix. |
| `/smart-commit` | Manual to start → analyze dirty tree → group commits → commit | Group working tree changes into logical semantic commits |
| `/smart-commit-selected` | Manual to start → analyze → plan groups → multiSelect checklist → commit selected | Commit only user-selected groups from working tree |
| `/orchestrate docs/modules/<n>/tasks.md` | Manual to start. **Within each task:** tester → coder → verifier (compile + assembly error check + Play Mode entry + VContainerException scan — **blocking**) → reviewer → committer. **Checkpoint lines** pause for `Proceed?` | Execute a module's `tasks.md` end-to-end; marks checkboxes and updates ROADMAP.md on completion |

> Reviewer priority across all pipelines: Codex → unity-reviewer (falls back if Codex is unavailable). Review loops: CHANGES NEEDED → coder fixes → reviewer re-checks → repeat (max 3 passes).
>
> **Tester isolation:** The `tester` step in `/implement`, `/fix`, `/orchestrate`, and `/migrate` runs as an isolated `claude` subagent. It receives a clean context window and reads `tester.md` + `testing.md` directly — preventing implementation context from leaking into test decisions. The `committer` step runs inline since simple git operations don't benefit from isolation.

### Development

| Command | How it runs | Description |
|---------|------------|-------------|
| `/new-module` | Manual — single step | Generate the 5-file module structure (Interface, Service, Config, Installer, Events) |

### Quality

| Command | How it runs | Description |
|---------|------------|-------------|
| `/qa` | Manual to start → ralph → silent-failure-hunt → validate | Full quality pipeline — run after any implementation or before push |
| `/ralph` | Manual to start → compile + test → fix loop (max 10 iterations) | Relentless verify-fix loop — refuses to stop until green or stuck |
| `/validate` | Manual — single step | Validate a completed phase via unity-verifier |
| `/review-code` | Manual — single step | Deep code review on specific files via unity-reviewer |
| `/silent-failure-hunt` | Manual — single step | Audit files for swallowed exceptions and silent error patterns |
| `/performance-audit` | Manual — single step | Hot path allocation and draw call audit |
| `/debug-session` | Manual to start → root cause analysis → unity-fixer → learner skill | Structured root cause analysis session |
| `/clean-slop` | Manual — single step | Remove AI-generated bloat (dead code, useless abstractions) |
| `/check-portability` | Manual — single step | Audit a module for copy-paste portability to another project |
| `/learn` | Manual — single step | Extract project-specific patterns into `.claude/skills/learned/` and update `skills-index.md` |
| `/generate-tests` | Manual — single step | Write missing tests for an existing class |
| `/create-test <FeatureName>` | Manual — single step | Unified test generator — EditMode unit test, PlayMode-ECS, PlayMode-Programmatic (`new GameObject().AddComponent<>()`, no scene), or PlayMode-Scene (TestScope + TestInstaller + stub + scene via MCP + auto-adds scene to Build Settings) |
| `/graphics-setup <mobile\|pc>` | Manual to start. Pauses for approval before creating assets | Show tier plan, create URP Pipeline Assets + Renderer Data + URPQualityConfiguration via MCP |
| `/audio-clip-setup [path]` | Manual to start. Pauses for commit confirmation at the end | Scan AudioClip assets, categorize, apply optimized import settings via MCP |
| `/discover [--dry-run\|--write] [--only <pkg>]` | Manual — single step (`--dry-run` default) | Walk `Packages/manifest.json`, classify packages, write skill drafts, detect compliance violations; `--write` also updates `skills-index.md` |
| `/update-scene-hierarchy [scene]` | Manual — single step | Reorganize scene containers — moves misplaced GOs into correct `[Setup]`/`[Services]`/`[UI]`/`[Environment]`/`[Characters]`/`[VFX]` containers |
| `/unity-scene-update [scene]` | Manual — single step | Full scene audit — reorganizes containers AND converts bare GameObjects to prefabs |

### Session & Context

| Command | How it runs | Description |
|---------|------------|-------------|
| `/caveman` | Manual — mode toggle | Ultra-compressed communication mode (~75% fewer tokens). Exit with `/normal` |
| `/checkpoint` | Manual — saves file, then you run `/clear` | Save conversation summary to `.claude/state/checkpoint.md` for the next session |
| `/context-prime` | Manual — single step | Brief Claude on project context at the start of a session |
| `/search <query>` | Manual to start → Explore + unity-scout → reviewer loop (max 5) → findings → action router | Codebase investigation pipeline — presents findings and recommends a next command |
| `/dump` | Manual — single step | Save current session notes and decisions to `.claude/logs/` |
| `/five` | Manual — single step | 5 Whys root cause analysis |
| `/continue docs/modules/<n>/tasks.md` | Manual — resumes orchestrate | Resume an interrupted `/orchestrate` run from the EVENTS.jsonl journal |
| `/status` | Manual — single step | Report current pipeline stage: GDD → TDD → ROADMAP → module plans → checkbox progress |
| `/dry-run docs/modules/<n>/tasks.md` | Manual — single step | Preview pending tasks in a `tasks.md` without executing |
| `/instincts` | Manual — single step | Manage instinct library: status, list, evolve, promote, export, import |

### Documentation

| Command | How it runs | Description |
|---------|------------|-------------|
| `/catch-up` | Manual — single step | Generate a human-readable codebase guide at `docs/CATCH_UP.md` |
| `/adr <decision>` | Manual — single step | Record an Architecture Decision — e.g. `/adr why VContainer over Zenject`; writes to `docs/decisions/NNN-topic.md` |
| `/create-changelog` | Manual — single step | Create or update `CHANGELOG.md` from recent git commits |
| `/mermaid` | Manual — single step | Generate a Mermaid architecture diagram for a module or system |
| `/update-claude-md [--section]` | Manual — single step | Sync CLAUDE.md tables with actual project state — hooks, rules, commands, agents. Shows diff before writing |

---

## Agents

Specialized AI roles invoked automatically by commands or directly by name.

| Agent | Role |
|-------|------|
| `coder` | **Pure C# only — no Unity API.** Used for `_Framework/`, `Games/Abstracts/`, and pure C# targets in `Games/Concretes/` in complexity-scored pipelines. |
| `tester` | NUnit + NSubstitute test writer — AAA pattern, interface-only mocks. Spawned as an isolated `claude` subagent (clean context window) so test writing is not polluted by implementation context. |
| `reviewer` | Principal-level code review — architecture, naming, performance |
| `unity-developer` | Unity 6 specialist — second reviewer for complex tasks; checks hot paths, draw calls, ECS safety, Addressables lifecycle, prefab structure |
| `committer` | Smart phase commit manager — semantic git commits. Runs inline (not as subagent) — simple git ops don't benefit from context isolation. |
| `unity-setup` | Scene, prefab, ScriptableObject configuration via Unity MCP — enforces prefab rules |
| `debugger` | Root cause analysis — VContainer, ECS, UniTask, Input bug patterns |
| `migrator` | Legacy pattern migration — coroutine→UniTask, singleton→VContainer, legacy input |
| `silent-failure-hunter` | Swallowed exception audit — empty catch, `.Forget()` without handler, dangerous fallbacks |
| `package-analyzer` | Read-only analyst — walks `Packages/manifest.json` and resolved package directories, emits multi-file skill drafts under `.claude/skills/third-party/<pkg>/`. Detects prefabs, maps them to `_GameFolders/Prefabs/<Category>/` destinations, and scans for architecture violations. For singletons (all variants: `Instance`, `_instance`, `Current`/`Shared`/`Main`/`Default`, `GetInstance()`, `DontDestroyOnLoad`), generates Adapter pattern boilerplate + NSubstitute mock lines instead of generic fix notes. |
| `unity-critic` | Opus adversarial plan challenger — stress-tests architecture decisions before implementation |
| `unity-shader-dev` | URP shader authoring — complexity router: simple effects use HLSL (.shader), complex/visual effects use ShaderGraph (.shadergraph JSON output + material assigned via MCP) |
| `unity-ui-builder` | Runtime UGUI specialist — Canvas hierarchy via MCP, MonoBehaviour view scripts, TextMeshPro, safe area, responsive layout, Canvas split strategy |
| `unity-ui-toolkit-builder` | Editor UI Toolkit specialist — UXML layouts, USS stylesheets, custom inspectors, EditorWindows, SerializedObject data binding (Editor-only; runtime UI uses UGUI) |
| `unity-optimizer` | Runtime performance — allocations, draw calls, ECS hot paths, profiler-guided fixes |
| `unity-scene-builder` | Scene composition via MCP — hierarchy, lighting, camera, volumes |
| `graphics-setup-agent` | Creates URP Pipeline Assets (Low/Medium/High) for mobile or PC, configures Renderer Data, wires Quality Settings via MCP |
| `audio-clip-agent` | Scans AudioClip assets, categorizes them, applies optimized import settings via temp Editor script + MCP |
| `unity-particle-designer` | VFX specialist — creates ParticleSystem prefabs, URP particle materials, pooled VFX services, and wires event-driven playback via MCP |
| `unity-linter` | Static analysis pass — naming, regions, hook-rule compliance |
| `unity-security-reviewer` | Security audit — data exposure, serialization risks, network surface |
| `unity-build-runner` | CI/build pipeline — platform flags, build profiles, Addressables baking |
| `unity-coder` | Unity coder for all complexity levels (sonnet tier by default; use `--heavy` for opus, `--lite` for haiku). Full Unity C# — MonoBehaviours, providers, installers, scene wiring. |
| `unity-fixer` | Bug fixer with full context — reads surrounding code before patching (sonnet tier by default; use `--heavy`/`--lite` flags on `/fix`) |
| `unity-git-master` | Git workflow — branching strategy, conflict resolution, history rewrite |
| `unity-migrator` | Pattern migration specialist — coroutine→UniTask, singleton→VContainer, legacy input |
| `unity-network-dev` | Netcode for GameObjects / Unity Transport — lobby, relay, RPCs. VContainer DI integration for NetworkBehaviour via `[Inject]` method injection and `container.Inject(go)` for runtime-spawned network objects |
| `unity-prototyper` | Rapid prototype scaffolding — speed over correctness, clearly marked TODOs |
| `unity-reviewer` | Unity-specific code review (Opus — lead-tier reviewer) — full checklist including ECS, Input, Addressables |
| `unity-scout` | Codebase explorer — maps dependencies, surfaces risks, no writes |
| `unity-test-runner` | Runs Edit/Play Mode tests via MCP and reports failures with context |
| `unity-test-builder` | Builds Play Mode test scenes — creates TestScope, TestInstaller, PlayMode test stub, wires TestBootstrap in scene via MCP, and adds the test scene to Build Settings automatically; used by `/create-test` |
| `unity-verifier` | Post-implementation verification — compile + test + prefab/scene integrity |

---

## Model Tiers

Model selection has **three independent layers**: (1) **session model** — the alias you launch with (table below); (2) **subagent model** — each agent's `model:` frontmatter, set by role level (Lead=Opus / Worker=Sonnet / Scanner=Haiku — see `.claude/docs/model-tiers.md`); (3) **skill model-tier** — skill frontmatter. The table below is layer 1 only.

Different tasks need different models. Use the right tier to balance speed and cost:

| Tier | Model | Alias | Commands |
|------|-------|-------|----------|
| **light** | Haiku | `claude-light` | `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | Sonnet | `claude-normal` | `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/new-module`, `/performance-audit`, `/clean-slop`, `/catch-up`, `/search` |
| **heavy** | Opus | `claude-heavy` | `/architect`, `/roadmap`, `/plan-module`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

### Setup

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
source /path/to/your-unity-project/.claude/aliases.sh
```

Or manually:

```bash
alias claude-light='claude --model claude-haiku-4-5'
alias claude-normal='claude --model claude-sonnet-4-6'
alias claude-heavy='claude --model claude-opus-4-8'
```

The alias file lives at `.claude/aliases.sh`.

---

## Recommended Plugins

These Claude Code plugins enhance the pipeline when installed. All are **optional** — every command falls back gracefully when a plugin is unavailable.

Install via `/plugin` in Claude Code:

| Plugin | Commands that use it | What it adds |
|--------|---------------------|--------------|
| `superpowers` | `/implement`, `/fix`, `/fix-deep`, `/debug-session`, `/migrate`, `/scene-setup`, `/architect`, `/orchestrate`, `/qa`, `/validate` | TDD discipline, brainstorming before complex features, systematic debugging, verification before completion |
| `skill-creator` | `/learn` | Structured skill drafting with description optimization |
| `code-simplifier` | `/clean-slop`, `/implement` (completion) | Post-implementation quality pass — reuse, efficiency, clarity |
| `claude-md-management` | `/implement`, `/fix` (completion) | Automatically updates CLAUDE.md with session learnings |
| `code-review` | `/review-code` | Additional review checklist layer on top of unity-reviewer |

**Availability check:** Each command that uses plugins prints a preflight status line before starting:
```
Plugins: superpowers:systematic-debugging [✓] | claude-md-management [✗]
```
`✓` = available and will be used · `✗` = not installed, fallback active

---

## Review Modes

Control pipeline depth by editing `production/review-mode.txt`:

| Mode | Effect | When to use |
|------|--------|-------------|
| `solo` | unity-coder → Committer only — no tests, no review | Prototypes, game jams |
| `lean` | Standard pipeline (default) | Regular solo development |
| `full` | Standard pipeline + unity-developer reviewer always active | Team review, learning sessions |

Change mode: `echo "full" > production/review-mode.txt`

---

## Director Gates

Human-pause checkpoints defined in `.claude/docs/director-gates.md`. Every pipeline command stops at the relevant gate and waits for `go` before spawning any agents. The `guard-gate-cleared.sh` hook enforces this at the tool level.

### Human-Pause Gates

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected, or always in `/new-module` | Approve proposed module structure |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `BREAKING_REVISION_GATE` | `/create-plan`, `/update-plan` | When reviewer classifies a plan revision as BREAKING (structural change, contradicts prior decision) | `re-research` / `accept` / `stop` — prevents cascading fix cycles from bad plans |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED | Choose: `fix` / `skip` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |

### Hook-Enforced Gates

Automatically blocked by a PreToolUse hook — no mid-run pause, the hook exits 2 if the approval file is missing.

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SPARC_GATE` | `/implement`, `/orchestrate`, `/fix` (complexity ≥ 0.4) | Before `coder` / `unity-coder` spawn, after SCOPE_GATE | Approve Specification + Architecture (how it will be built — files, interfaces, data flow) |

State file: `.claude/state/sparc-approved` (independent of `gate-cleared`). Written after "go", deleted after the gated agent completes. Guard hook: `guard-sparc-approved.sh`.

### Gate TTL

`gate-cleared` expires after **45 minutes** (2700 s). If a pipeline is abandoned mid-flight (QUALITY_GATE "stop", error, user interruption), the approval remains valid until the TTL elapses — a later pipeline can still run within that window without re-showing the gate. To force-expire immediately after stopping a pipeline:

```bash
rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

### Automated Check Gates

| Gate | Checks |
|------|--------|
| `TD-ARCHITECTURE` | VContainer DI, interface-driven, IEventBus, Provider pattern, module boundaries |
| `TD-UNITY-RISK` | Post-cutoff API risk — reads `docs/engine-reference/unity/` before any architecture decision |
| `TD-PERFORMANCE` | Zero-alloc hot paths, draw call budget, ECS ECB usage, Addressables handle lifecycle |
| `TD-COMPILE` | Unity MCP compile + Edit Mode test pass — mandatory before reviewer |
| `CD-SCOPE` | YAGNI check — flags out-of-scope files, unnecessary abstractions, speculative features |

---

## Session State

### Structured State (`.claude/state/`)

| File | Contents |
|------|----------|
| `session.json` | Current branch, phase, modified files, active task, decisions |
| `learnings.jsonl` | Structured learning records accumulated across sessions |
| `instincts/` | Project-specific and global instinct library (confidence-scored patterns) |

- `session-restore.sh` (SessionStart hook) loads state at the start of every session
- `session-save.sh` (Stop hook) persists state when the session ends and **auto-expires** ephemeral gate files (`gate-cleared`, `sparc-approved`, `codex-reviewed`, `graph-empty-warned`, etc.) — these must never persist across sessions
- Use `/instincts` to view, evolve, promote, or export instincts

### Human-Readable Checkpoint

`production/session-state/active.md` is a living checkpoint updated after each milestone.

### Context Management with /checkpoint

When context is getting full (~70-80%), use `/checkpoint` instead of losing progress:

```
Context ~70-80% full
      ↓
/checkpoint
      ↓  Claude writes summary to .claude/state/checkpoint.md
/clear
      ↓  Context fully freed
Send: "read .claude/state/checkpoint.md"
      ↓  Claude reads file, resumes from where you left off, deletes the file
```

**Why not just `/compact`?** `/compact` summarizes in-memory — context shrinks but doesn't fully clear. `/checkpoint` + `/clear` fully resets context for maximum token recovery while preserving all progress in a file.

---

## Engine Version Reference

`docs/engine-reference/unity/` contains Unity 6 LTS risk assessments:

| File | Contents |
|------|----------|
| `VERSION.md` | Risk levels per system area (ECS, UI Toolkit, Netcode, etc.) |
| `breaking-changes.md` | HIGH/MEDIUM risk API changes with migrations |
| `deprecated-apis.md` | Forbidden APIs and their replacements |
| `current-best-practices.md` | VContainer, UniTask, ECS, Input, Addressables, Rendering patterns |

`/architect` reads these automatically and stamps TDD sections that touch risky areas.

---

## Built-In Skills

Skills live under `.claude/skills/` and are loaded automatically by commands. They are read-only reference files that inform Claude's decisions — they do not execute code. The `/learn` command writes project-specific patterns to `skills/learned/` and automatically adds entries to `skills-index.md`. The `/discover --write` command writes third-party package skills to `skills/third-party/<pkg>/` and also updates `skills-index.md`.

**Auto-loading:** Skills in `third-party/`, `plugins/`, `learned/`, and `platform/` are referenced via `@`-includes in `.claude/docs/auto-loaded-skills.md`, which is linked from CLAUDE.md. The `auto-load-skills.sh` PostToolUse hook keeps this file current — new skill files are added automatically on write.

### Core (`skills/core/`)

| Skill | Covers |
|-------|--------|
| `model-routing` | Automatic model selection heuristics — file count, complexity, risk factors |
| `deep-interview` | 5-dimension ambiguity gating before implementation starts |
| `learner` | Post-debug insight extraction — writes findings to CLAUDE.md Project Learnings |
| `unity-instincts` | Instinct system for learned Unity patterns — capture, score, promote, apply |
| `source-driven-development` | Fetch official Unity docs before writing API calls — cites sources, flags deprecated APIs |
| `documentation-and-adrs` | ADR creation — `/adr` command writes to `docs/decisions/`, lifecycle management |
| `planning-and-task-breakdown` | Vertical slice decomposition + per-task acceptance criteria |
| `code-simplification` | Chesterton's Fence discipline for `/clean-slop` — understand before removing |
| `commit-trailers` | Conventional commit trailers — co-author, ticket links, sign-off |
| `event-systems` | IEventBus patterns — pub/sub, struct events, subscribe/unsubscribe lifecycle |
| `event-bus` | Project-specific IEventBus implementation — location, namespace, and code examples |
| `logging` | Project-specific DLog pattern — logging implementation, location, and usage |
| `save-load` | Project-specific SaveLoadSystem pattern — location, namespace, and usage |
| `tdd-nsubstitute` | Project-specific TDD pattern — assembly structure, test templates, and mock rules |
| `hud-statusline` | In-session status line rendering for pipeline progress |
| `object-pooling` | ObjectPool<T> setup, return-to-pool patterns, warm-up |
| `scriptable-objects` | ScriptableObject config authoring, CreateAssetMenu, validation |
| `serialization-safety` | FormerlySerializedAs, SerializeReference, Unity null semantics |
| `unity-mcp-patterns` | MCP tool call patterns for scene/prefab/asset operations |
| `playmode-scene-testing` | Play Mode scene test pattern — TestBootstrap prefab, TestScope, UnityTest patterns |
| `mcp-preflight` | 3-state MCP availability check — connected / disconnected / not installed |
| `test-type-router` | Determines test type (EditMode / PlayMode-ECS / PlayMode-Programmatic / PlayMode-Scene / NoTest) from class name or file path |
| `unity-ugui` | Runtime UGUI implementation — View scripts, Canvas/MCP setup, HUD, Popup/Dialog, Scroll View pool, safe area, Canvas split strategy, performance rules |
| `unity-git` | Unity git conventions — .meta hygiene, .gitattributes (YAML merge / binary), LFS patterns, conventional commits, commit grouping by dependency order; loaded by `committer` and `unity-git-master` agents |

### Platform (`skills/platform/`)

| Skill | Covers |
|-------|--------|
| `mobile` | Touch input, safe area, haptics, app lifecycle |

### Systems (`skills/systems/`)

| Skill | Covers |
|-------|--------|
| `addressables` | Loading, handle lifecycle, label groups, preload |
| `animation` | Animator parameters, state machine behaviours, blend trees |
| `audio` | AudioMixer groups, snapshots, pooled AudioSource, spatial audio, beat sync, procedural SFX |
| `audio-mixer` | AudioMixer routing, exposed parameters, send/receive buses, ducking (sidechain), snapshot transitions |
| `audio-settings` | Audio settings UI, volume persistence via PlayerPrefs, IAudioSettingsService + VContainer wiring |
| `audio-clip-settings` | AudioClip import settings — PCM/ADPCM/Vorbis format selection, load type, platform overrides |
| `cinemachine` | Virtual cameras, blends, impulse, follow targets |
| `navmesh` | NavMeshAgent setup, dynamic obstacles, off-mesh links |
| `physics` | Layer matrix, non-alloc queries, trigger vs collision |
| `shader-graph` | ShaderGraph JSON format guide — node templates, edge wiring, UUID rules, Dissolve/Rim/Scroll/Toon effect recipes, MCP integration |
| `ui-toolkit` | USS, UXML, data binding, runtime panel setup |
| `urp-pipeline` | Renderer features, camera stacking, custom render passes, SRP Batcher, Forward+ |
| `urp-quality-settings` | URP quality tiers (Low/Medium/High/Ultra), runtime asset swap, auto-detect, adaptive performance |
| `urp-lighting-shadows` | Directional/point/spot lights, shadow cascades, bias tuning, light layers, reflection probes |
| `urp-post-processing` | Bloom, DOF, Motion Blur, SSAO, Tonemapping, Color Grading, Vignette — setup, values, runtime control |
| `audio-mixer-mcp` | AudioMixer exposed parameters, AudioSource routing — configuration via MCP execute_code |
| `srp-batcher-mcp` | SRP Batcher enable/verify, UI Raycast Target audit, post-processing Volume cleanup via MCP |
| `particle-vfx` | ParticleSystem module config, URP particle shaders, VFX pool, VContainer wiring, event-driven playback |
| `urp-volume` | URP Volume MCP skill — `manage_graphics` volume_* actions, global/local Volume setup, VolumeProfile, effect overrides |

### Third-Party (`skills/third-party/` and `skills/plugins/`)

Static pre-built skills. `skills/third-party/` holds folder-based skills (with subdirectories); `skills/plugins/` holds flat `.md` skills plus any skills generated by `/discover`.

All skills under `skills/third-party/`, `skills/plugins/`, `skills/learned/`, and `skills/platform/` are **automatically loaded into every session** via `@`-references managed by `auto-loaded-skills.md`. The `auto-load-skills.sh` PostToolUse hook keeps this file in sync — whenever `/discover` or `/learn` writes a new skill file, the reference is added automatically. No manual CLAUDE.md edits needed.

**`skills/third-party/`**

| Skill | Covers |
|-------|--------|
| `dotween` | Tween creation, sequences, callbacks, memory management — includes PITFALLS (30+ traps) and LIFETIME (kill strategies) |
| `nsubstitute` | NSubstitute mock setup, argument matchers, received verification |
| `odin-inspector` | Custom attributes, validators, group drawers |
| `textmeshpro` | Font assets, rich text, SDF materials, localization |
| `unitask` | Async patterns, cancellation, `Forget()`, UniTaskVoid — includes PITFALLS (30 traps with source anchors) and CANCELLATION patterns |
| `unity-asmdef` | Assembly definition authoring, references, define constraints |
| `unity-editor-tools` | Custom Editor windows, PropertyDrawers, EditorUtility patterns |
| `unity-uitoolkit` | Editor-only UI Toolkit — EditorWindow, custom Inspector, PropertyDrawer, UXML/USS (NOT runtime UI) |
| `netcode` | NGO 2.x — NetworkBehaviour, RPC, NetworkVariable, Spawn/Despawn, Scene management, VContainer + UniTask integration — 7 sub-docs |
| `probuilder` | In-editor mesh modeling — shape generation, face/edge/vertex ops, UV unwrapping, Boolean ops, bake-to-asset workflow — api.md + integration.md |
| `vcontainer` | Scope hierarchy, registration patterns, `IInitializable`/`IDisposable` lifecycle, DI failure diagnosis |

**`skills/plugins/`** (flat `.md` skills + `/discover` output)

| Skill | Covers |
|-------|--------|
| `primetween` | PrimeTween setup, tween API, sequences, and UniTask integration |
| `r3` | R3 (Cysharp) Observable, Subject, ReactiveProperty, and UniTask integration |

#### Discovered Package Skills (`skills/third-party/<pkg>/`)

Generated by `/discover --write`. Each package folder contains `SKILL.md` plus optional split files for large packages. After writing, `/discover` automatically adds/updates the package row in the `## Discovered Packages` table in `skills-index.md` — so future sessions can see what was discovered without re-running the scan.

| File | Covers |
|------|--------|
| `SKILL.md` | Trigger file — When to use, Key APIs summary, links to other files |
| `api.md` | Full API reference + idiomatic code examples |
| `prefabs.md` | Complete prefab list with duplication targets |
| `integration.md` | VContainer / UniTask / IEventBus bridge patterns + Prefab setup workflow |
| `test-strategy.md` | PlayMode test requirements, minimum scene setup, mock strategy |
| `samples.md` | Demo scene analysis — real GameObject/component hierarchy |
| `compliance.md` | Rule violations in the package + recommended fixes — **only written when violations exist** |
| `test-strategy.md` | PlayMode test requirements, minimum scene setup — includes **Mock Requirements** section when singletons detected |

Small packages (< 10 prefabs) use a single `SKILL.md`. Medium packages add `prefabs.md`. Large packages (50+) use the full split.

**Compliance severities:** `MUST-FIX` (blocking hooks will fire), `SHOULD-FIX` (architecture rules), `CONSIDER` (good practice).

**Singleton detection:** `/discover` catches all common singleton variants — `Instance`/`_instance` field, `Current`/`Shared`/`Main`/`Default` static properties, `GetInstance()`, `static readonly new`, and `DontDestroyOnLoad`. Since package code cannot be modified, every singleton finding generates an **Adapter pattern** boilerplate (interface + adapter class + AppScope registration + NSubstitute mock line) rather than a generic "register as IService" note. The `test-strategy.md` `Mock Requirements` section lists exactly which interfaces to mock in PlayMode tests.

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

---

## Hook Audit Log

Every hook execution is logged to `~/.claude/hook-audit.log` as newline-delimited JSON:

```jsonc
{"ts":"2026-05-04T10:22:01Z","hook":"check-vcontainer-singleton","status":"BLOCKED","file":"Games/Concretes/GameManager.cs","project":"my-game"}
{"ts":"2026-05-04T10:22:02Z","hook":"warn-serialization","status":"OK","file":"Games/Concretes/GameManager.cs","project":"my-game"}
```

**Status values:** `OK` — passed · `BLOCKED` — write was stopped (exit 2) · `WARN` — warning logged (exit 0 with output)

```bash
# See all blocked writes today
grep BLOCKED ~/.claude/hook-audit.log | tail -20

# See which hooks fired on a specific file
grep "GameManager.cs" ~/.claude/hook-audit.log

# Count blocks per hook (which rule fires most)
grep BLOCKED ~/.claude/hook-audit.log | jq -r '.hook' | sort | uniq -c | sort -rn
```

The log is capped at 500 lines and rotates automatically. It is global across all projects — the `project` field identifies which project each entry came from.

---

## Manual Setup (Required After `/setup-project`)

`/setup-project` handles most Unity Editor work automatically via MCP (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`). Only the following steps require manual action:

**NSubstitute** _(only if Testing=yes)_
1. Download `NSubstitute.dll` from [NuGet](https://www.nuget.org/packages/NSubstitute) — rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from `lib/`
2. Place at `Assets/Plugins/NSubstitute/NSubstitute.dll`
3. The `.asmdef` files generated by `/setup-project` already reference it via `precompiledReferences`

**New Input System — Project Settings**
1. Install via Package Manager: `com.unity.inputsystem`
2. Edit → Project Settings → Player → Active Input Handling → `Input System Package (New)` _(Unity restarts — cannot be set via MCP)_
3. Create `Assets/_GameFolders/Input/[ProjectName]Controls.inputactions`
4. Enable "Generate C# Class" in the `.inputactions` inspector

**settings.json hook entries** — Claude cannot edit `settings.json` (blocked by `check-config-protection.sh`). Add manually — see `.claude/docs/setup-checklist.md` for the exact JSON blocks:
- `check-test-scene-exists.sh` (PostToolUse, Write|Edit matcher)
- `guard-reviewer-order.sh` (PreToolUse, Agent matcher)
- `track-codex-review.sh` (PostToolUse, Agent matcher)

> **MCP unavailable?** If Unity Editor is not open or MCP is disconnected when `/setup-project` runs, Step 5d is skipped and a manual checklist is printed for scene creation, AppScope wiring, and Build Settings.

---

## Architecture in a Nutshell

> Full architecture diagrams (pipeline flow, agent pipeline, VContainer scope hierarchy, layer dependencies, hook flow): **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**

> Architecture summary (key rules at a glance): **[.claude/docs/architecture-summary.md](.claude/docs/architecture-summary.md)**

```
_Framework/                              ← Never references _GameFolders or other project folders
  Events/FrameworkEventBus.asmdef       ← each subfolder has its OWN .asmdef (never a single root-level one)
  Logging/FrameworkLogging.asmdef
  SaveLoadSystems/FrameworkSaveLoadSystems.asmdef
  Editors/FrameworkEditor.asmdef

_GameFolders/Scripts/
  Games/
    Abstracts/               ← interfaces and abstract base classes, organized by domain
      Players/
      Enemies/
      ...
    Concretes/               ← ALL concrete classes (pure C# or MonoBehaviour), organized by domain
      Players/
      Enemies/
      Audio/
      ...
    Ecs/                     ← DOTS: Authorings, Components, Systems (if ECS enabled)
  Tests/
    [Project]EditModeTest/
    [Project]PlayModeTest/
  Editors/                   ← Editor-only tools

Arts/
  Materials/               ← all .mat files, organized by domain (never inside Prefabs/)
    Items/
    Environment/
    Characters/
    VFX/
  Shaders/                 ← all .shader and .shadergraph files
  Textures/                ← textures by domain
```

**Key rules:**
- VContainer for DI — no singletons, no service locators
- Each module is a static `[X]Module` class + `IService`, `Service`, `Configuration`, `Events` — no ScriptableObject installers
- `AppScope` never changes — add modules via one line in `AppModules.Install()`
- `IEventBus` for cross-module communication — no direct cross-module calls
- `EventBusAccessor` static bridge for ECS ↔ Mono communication (only approved static accessor)
- Provider pattern — Unity API stays in providers inside `Games/Concretes/<Domain>/`, never in service classes
- Every scene GO is a prefab instance; root=logic components, `Body` child=visual components
- `Games/Abstracts/` = interfaces and abstract base classes ONLY — no concrete implementations
- `Games/Concretes/` = ALL concrete classes, both pure C# (MoveHandler, DamageHandler) and MonoBehaviours — organized by domain (Players/, Enemies/, Audio/…), never by layer
- Only valid top-level folders under `Scripts/`: `Games/`, `Tests/`, `Editors/` — never create `Config/`, `GameUnity/`, `Game/` or other folders alongside `Games/`
- Every `_Framework` subfolder has its own `.asmdef` — never a single root-level assembly covering all subfolders
- All prefabs under `_GameFolders/Prefabs/<Domain>/` (`Bootstrap/`, `CoreObjects/`, `Enemies/`, `UI/Canvases/`, `VFX/`, `Environment/`…); shared-base objects use Prefab Variants; all Canvas prefabs are Prefab Variants of `BaseCanvas`
- All material assets (.mat) under `Arts/Materials/<Domain>/` — never inside `Prefabs/`; shader files (.shader / .shadergraph) under `_GameFolders/Arts/Shaders/`; never use Built-in Standard shader in a URP project — use the `unity-shader-dev` agent for shader authoring (automatically routes to HLSL or ShaderGraph based on complexity); use the `unity-particle-designer` agent for particle VFX (`Arts/Materials/VFX/` + `_GameFolders/Prefabs/VFX/` + pooling)
- `AppScope` saved as `Prefabs/Bootstrap/AppScope.prefab`; `EventSystem` and `MainCamera` saved as `Prefabs/CoreObjects/` prefabs — same prefab instance reused across all scenes
- New Input System only — `InputService` (pure C#, `ITickable`) owns `PlayerControls`; per-prefab `InputHandler` routes actions
- UniTask everywhere — no coroutines, no `async void`, always pass `CancellationToken`
- Addressables for all runtime asset loading — no `Resources.Load`
- NSubstitute + AAA pattern for tests — only interfaces mocked

---

## Distribution as a Claude Code Plugin

This template ships a `.claude-plugin/plugin.json` manifest, making it installable as a Claude Code plugin:

```bash
claude plugin install github:berkterek/unity-claude-ai-template-repo
```

The manifest declares all skills, commands, hooks, and agents so Claude Code discovers them automatically on install. See `.claude-plugin/README.md` for full installation details.

---

## CI Integration — GitHub Actions

Three workflows live under `.github/workflows/` (all on `actions/checkout@v5` / `actions/setup-python@v6`, Node 24). See `.github/workflows/README.md` for full details.

### claude-pr-review.yml — automatic PR review

Runs automatic Claude code review on every pull request that touches Unity source files (`Assets/**`, `.claude/**`, `_GameFolders/**`, `_Framework/**`).

**Setup:**

1. Add your Anthropic API key as a repository secret named `ANTHROPIC_API_KEY`
2. The workflow triggers automatically on PRs — no other configuration required

The reviewer checks architecture rules (VContainer DI, no singletons, IEventBus cross-module communication), Unity-specific patterns (UniTask, New Input System, null safety), and naming conventions.

### hook-tests.yml — hook regression gate

Runs the bats-core suite (`.claude/hooks/tests/`) plus `shellcheck` on every change under `.claude/hooks/` (and on changes to its own YAML; `workflow_dispatch` for manual runs). Installs bats with `sudo npm install -g bats` — the runner's `/usr/local` global prefix is not writable by the unprivileged `runner` user, so a plain `npm install -g` fails with `EACCES` (exit 243). A broken or over-broad hook turns the check red instead of silently shipping.

### graph-tests.yml — knowledge-graph harness

Runs `.claude/graph/test/verify-graphify.sh` (jq + Python 3.12) on every change under `.claude/graph/` (and its own YAML; `workflow_dispatch`). The harness hard-requires a committed `graph.json` — it does not build one, and `actions/checkout` only delivers tracked files. `.claude/graph/graph.json` is therefore committed alongside `scenes.json` / `prefabs.json`, **not** gitignored.

---

## Project-Specific Files (Not in This Template)

These are generated per-project and should NOT be committed back to this template:

```
.claude/skills/learned/          ← patterns extracted from your specific project
docs/CATCH_UP.md                 ← auto-generated codebase guide (/catch-up)
docs/decisions/                  ← ADRs specific to your game
docs/GDD.md                      ← game design document (/game-idea)
docs/TDD.md                      ← technical design document (/architect)
docs/ROADMAP.md                  ← module roadmap table (/roadmap)
docs/modules/<n>-<name>/         ← per-module plans (/plan-module <n>)
  spec.md                        ← player stories + acceptance criteria
  design.md                      ← contracts, events, file map, risks
  tasks.md                       ← /orchestrate-ready task list with checkboxes
```

Note: `docs/ARCHITECTURE.md`, `docs/SETUP.md`, and `docs/engine-reference/` are part of the template and should be kept.

---

## License

Copyright (c) 2026 Berk Terek — All rights reserved.
