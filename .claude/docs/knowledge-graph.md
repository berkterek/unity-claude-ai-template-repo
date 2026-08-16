# Knowledge Graph

The template ships with a Graphify-inspired knowledge graph at `.claude/graph/graph.json` (schema v1.2.0).
Opt-in via `project-features.json` (`"graph": true`). When enabled, it is the single source of truth
for `/catch-up`, `/orchestrate` pre-scan, and `/context-prime`.

**Pipeline:** detect → extract (C# / asmdef / MCP) → build → finalize-calls → analyze → report → export

**Commands:**
- `/build-knowledge-graph [--full|--incremental] [--skip-mcp] [--validate] [--validate-with-codex] [--viz]`
- `/knowledge-graph <summary|implementers|publishers|subscribers|registrations|scope-tree|prefab|violations|diff|callers|impact|path|god-nodes>`

**Triggers (kept in sync automatically):**
- Every Write/Edit → PostToolUse `graph-auto-update.sh` (incremental, background, non-blocking, one rebuild at a time)
- Every `git commit` → `.git/hooks/post-commit` (incremental rebuild, background — preserves MCP cache)
- Manual → `/build-knowledge-graph`

**Manual settings.json entry** (Claude cannot edit settings.json — add this yourself):
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/graph-auto-update.sh" }
        ]
      }
    ]
  }
}
```
Add this entry under your existing PostToolUse hooks. Then run `bash .claude/hooks/install-git-hooks.sh` once to install the git post-commit hook.

---

## Extractor Reliability Notes

Lessons from live testing — read before debugging graph output.

### csharp-extractor.sh

- **Multi-line class declarations** (`class Foo\n  : IBar`) are handled by a python3 parser that joins up to 6 lines. Single-line and multi-line declarations both produce correct `base_types[]` and `implements[]`.
- **Fully qualified interface names** (`Game.Abstracts.IFoo`) are reduced to their last segment (`IFoo`) before being stored. Both short and qualified names produce correct `implements[]`.
- **methods[] extraction** — every public/private/protected method is captured per class (name, signature, line, is_async, is_static, return_type). Confidence: `INFERRED` (regex mode).
- **partial_calls[] extraction** — call sites are extracted per file and merged into `codebase.calls[]` by `graph-builder.py`. BCL types (`Debug`, `Mathf`, `Vector3`…) and C# keywords are filtered out. Confidence: `INFERRED`.
- **Stale MCP cache** — when `mcp-extract.json` is older than 60 minutes, `graph-builder.py` retains prefabs and scenes from the existing `graph.json` instead of dropping them. Run `/build-knowledge-graph` with Unity Editor open to refresh MCP data. `--full` always invalidates the MCP cache regardless of age — retained prefabs are cross-checked against disk and stale paths emit `STALE_PREFAB_PATH` warnings in `validation.warnings[]`.
- **Missing scripts** — null component entries (`"null"` in `comps=(...)`) during MCP extraction set `has_missing_scripts: true` on the GO/prefab. `graph-builder.py` collects these into `MISSING_SCRIPT` warnings in `validation.warnings[]`. Surface with `/knowledge-graph violations`.
- **Python JSON passing** — both `STALE_PATH_WARNINGS` and `MISSING_SCRIPT_WARNINGS` blocks pass data via env vars (`MCP_PREFABS_JSON`, `MISSING_INPUT_JSON`) + `json.loads(os.environ[...])`, not `echo | python3 -`. Bash heredoc overrides stdin so the pipe pattern silently delivers empty input to Python.
- **Subfolder layout (UNITY_FOLDER)** — `STALE_PATH_WARNINGS` passes `UNITY_FOLDER` to Python and prepends it to the `Assets/...` path before `os.path.exists()`. Without this, every prefab appears stale on projects where `Assets/` is not at repo root.
- **gameObjects key casing** — MISSING_SCRIPT detection reads `scene.get("gameObjects", scene.get("gameobjects", []))` to handle both camelCase (MCP cache output) and lowercase (older extractions).

### csharp_extractor.py — pub/sub + registration detection is AST-based (not regex)

`_detect_vcontainer` in `csharp_extractor.py` (tree-sitter path) walks the real
`invocation_expression` AST per-method — it is **not** a text regex. This replaces a prior
regex approach that only matched the generic `Publish<T>(...)` form and silently missed the
common non-generic form `_eventBus.Publish(new SettingsClosedEvent())`, and that skipped
`builder.RegisterInstance(config)` registrations entirely. Both gaps are closed:

- **Publish/Subscribe/Unsubscribe** are detected whether written generically (`Publish<T>(...)`)
  or via type inference from the argument (`Publish(new T())`, including `_eventBus?.Publish(...)`
  null-conditional call sites) — no double-count when both forms are present on the same call.
- **Registrations** (`Register<T>()`, `RegisterInstance(var)`, `RegisterComponent`,
  `RegisterEntryPoint`, `RegisterComponentInHierarchy`) are matched the same way. `RegisterInstance(var)`
  resolves `var`'s type from a bounded local symbol table (class fields + the enclosing
  method/constructor's own parameters). When the type cannot be resolved (e.g. `var x = Build(); builder.RegisterInstance(x);`),
  the registration is **still recorded** — never silently dropped — tagged `"unresolved": true, "confidence": "AMBIGUOUS"`.
- Chained calls (`builder.Register<T>(Lifetime.Singleton).AsImplementedInterfaces()`) resolve to
  exactly one registration; the outer `.AsImplementedInterfaces()` invocation is not itself a
  pub/sub or registration method and is ignored.
- Regression tests pinning both patterns live in `.claude/graph/test/test_extractor_pubsub.py`
  (stdlib-only, no pytest) and are run by `verify-graphify.sh`; the harness prints `SKIP` rather
  than failing when tree-sitter is unavailable (the regex-fallback `.sh` path — see next bullet
  — is unaffected by this AST rewrite and is out of scope for it).
- **Regex-fallback path (`csharp-extractor.sh`) still under-reports.** If tree-sitter is
  unavailable at build time, `graph-builder.py` falls back to the shell/regex extractor, which
  has the same non-generic-form blind spot the AST walk fixes. When this happens, the build
  appends a `FALLBACK_EXTRACTOR` entry to `validation.warnings[]` and echoes the same warning to
  stderr — surfaced via `/knowledge-graph violations`. Treat pub/sub and registration data as
  **low confidence** for any build that shows this warning.
- **Known limitation (unchanged from the prior regex approach — not a new regression):**
  pub/sub detection matches any `x.Publish<T>()` / `x.Publish(new T())` call by **method name
  alone** — it does not verify that `x` resolves to an `IEventBus` instance (that would require
  full type resolution across the project, which tree-sitter alone does not provide). A class
  with an unrelated method also named `Publish` and a generic/`new`-argument call shape is a
  possible false positive. This has always been true of the extraction approach and is
  explicitly documented here rather than silently accepted.

### graph-builder.py call edge merge

- **Full build (`--full`):** discards retained call edges, uses only freshly extracted `partial_calls[]`.
- **Incremental with changed files:** retains edges from unchanged files, replaces edges for changed files only.
- **Incremental with no changed files:** retains all existing call edges unchanged (no re-extraction needed).
- After assembly, `graph-traversal.py --finalize-calls` deduplicates edges and promotes `EXTRACTED` over `INFERRED` for the same caller+callee+file+line.

**Callee resolution (global pass, `resolve_call_targets`):** every edge is resolved against all project types and tagged `callee_kind`:
- `internal` — head linked to a project class/interface (`callee_class` / `callee_file` set).
- `external` — head is a resolved non-project type (Unity/BCL/3rd-party, e.g. `Transform`) — a **correct** null, not a miss.
- `unresolved` — bare variable the extractor could not type, or an ambiguous same-name project type — the genuine miss.

When the head is a variable, the pass walks the caller class's own **+ inherited** `field_types` map across base classes and links **only** when the resolved type actually declares the method (`method_match: true`), so fluent-chain tails never fabricate false edges. `method_match` is recomputed every build and never touches `confidence`.

### graph-traversal.py

New in v1.1.0. Pure Python 3 stdlib — no pip install needed.

| Subcommand | What it does |
|---|---|
| `impact <Node> [--hops N]` | BFS forward (downstream) + reverse (upstream) from node, default 3 hops |
| `callers <Class.Method>` | One-hop reverse lookup — direct callers only |
| `path <A> <B>` | BFS shortest path on forward call graph; exits 1 if no path |
| `god-nodes [--top N]` | Rank nodes by in+out degree; `is_god_node: true` when total > 20 |
| `--finalize-calls` | Sort + dedupe + promote confidence in `calls[]`; atomically rewrites `graph.json` |

### MCP Extraction (mcp-extractor.md)

These MCP tool behaviors were discovered during live Editor testing — they differ from what the tool documentation implies:

| Tool / Pattern | Actual behavior |
|----------------|----------------|
| `manage_scene get_hierarchy` with `target` param | **target is ignored** — always returns full root list. Use `execute_code` recursive delegate for deep traversal. |
| `manage_components` | **No `get` action.** Only `add`, `remove`, `set_property` exist. Use `execute_code` + `SerializedObject` for reading. |
| `manage_prefabs get_hierarchy` | Works correctly for root component list. Does **not** return child GO hierarchy — use `execute_code` + `AssetDatabase` recursive walk for children. |
| `execute_code` compiler | **Roslyn not available** in most Unity projects. Always use `compiler: "codedom"` (C# 6 — no local functions, no string interpolation with complex expressions). |
| `VContainer.Unity.ParentReference` | Is a **struct** — `!= null` won't compile in CodeDom. Use `.TypeName` (string) field; empty string = no parent. |

Full working code snippets for all patterns: see `.claude/graph/extractors/mcp-extractor.md`.


## v1.2.0 Fields (new in Graph Module v2)

| Field | jq path | Description |
|-------|---------|-------------|
| Communities | `.codebase.communities` | Class community groups from `graph_cluster.py` |
| Surprising connections | `.analysis.surprising_connections` | Cross-scope/assembly/community call edges |
| Enhanced god-nodes | `.analysis.enhanced_god_nodes` | God-nodes enriched with `community_id` and `severity` |
| Accuracy report | `.validation.accuracy` | Extraction accuracy spot-check vs source files |

### graph_cluster.py

New in v1.2.0. Detects class communities from call edges using greedy modularity (stdlib) or Louvain (via optional `networkx`). Writes `codebase.communities[]`.

- `algorithm: "greedy-modularity-stdlib"` — default, no pip install needed. Works on all graphs but produces coarser clusters on sparse codebases.
- `algorithm: "louvain-networkx"` — higher quality, recommended for projects with > 30 classes; requires `pip install networkx`

> **Recommendation:** Run `pip install networkx` once after setup. On sparse graphs (few call edges, early-stage projects) the stdlib algorithm may group everything into one large community or produce no merges at all. Louvain handles this correctly.

### graph_analyze.py

New in v1.2.0. Classifies surprising cross-boundary edges and enriches god-nodes with community data.

- `CROSS_SCOPE` → severity `warning` (two classes in different VContainer scopes calling each other directly)
- `CROSS_ASSEMBLY` → severity `info`
- `CROSS_COMMUNITY` → severity `info`

### graph_validate.py

Two-mode validator — always runs during graph-builder.

**Mode 1 — Consistency (default, fast):** Checks `graph.json` internal integrity. No source files read.
- Orphan events: published/subscribed but not declared in graph
- Dangling call edges: resolved callee class **or interface** not in graph (`callee_class=null` is never flagged — it means external/unresolved)
- Installer registrations referencing missing classes
- Results → `validation.consistency.{issues[], issue_count, passed}`

**Mode 2 — Accuracy (`--accuracy` flag, slow):** Re-extracts a sample of source files via `csharp_extractor.py` (tree-sitter) and compares against graph facts. Single parse source — no duplicate regex logic.
- `--sample N` (default 20), `--seed N` (default 42)
- Results → `validation.accuracy.{agreement_pct, matches, mismatches, checks[]}`
- If `< 90%`, `low_accuracy_warning: true` recommends `--full` rebuild
- Skipped automatically if tree-sitter is unavailable (exit 2)
- Run manually: `python3 .claude/graph/graph_validate.py --graph .claude/graph/graph.json --accuracy`

**Never touches `validation.warnings[]`** — that array is owned by `graph-validator.sh`

Consistency mode does **not** flag `unresolved:true` registrations as dangling/missing-class
issues — they are known-incomplete by design (D3), not broken data.

### `/knowledge-graph registrations <Class>` — unresolved registrations

A registration produced from `builder.RegisterInstance(var)` whose `var` type could not be
resolved locally is shown **distinctly**, not as an empty type:

```
AudioModule
  RegisterInstance(?) — unresolved (AMBIGUOUS)
  Register<AudioService> as IAudioService (Singleton)
```

A `FALLBACK_EXTRACTOR` warning anywhere in `validation.warnings[]` (surfaced via
`/knowledge-graph violations`) means the regex-fallback extractor ran for at least one file —
treat that build's pub/sub and registration data as **low confidence** until tree-sitter is
available and `--full` is re-run.

### Query cheatsheet additions (v1.2.0)

- "Which classes form a module?" → `/knowledge-graph communities`
- "Architecture drifting where?" → `/knowledge-graph surprising`
- "God-nodes with community context?" → `/knowledge-graph god-nodes` (now uses `analysis.enhanced_god_nodes[]` when present)

---

## graph.html — Graph Visualizer

`.claude/graph/graph-viz.py` reads `graph.json` (resolving `scenes.json`/`prefabs.json`
`$partition` refs the same way `graph-mcp-server.py` does — fails fast if a referenced
partition file is missing) and emits one `graph.html`: inline CSS, an inline JSON data
island, and inline glue JS driving a **vis-network** force-directed layout. It is offline
and build-free — no CDN, no external fonts, no remote images — but **not** fully
self-contained: it references a vendored `vis-network.min.js` (pinned 9.1.6) that must sit
in the same directory. That vendored file is committed and is never written or touched by
`graph-viz.py`. Open `graph.html` directly via `file://`.

**What it shows:**
- **Nodes:** classes (color-coded by `is_mono_behaviour`), interfaces, events — each a
  visually distinct type/color, with a legend.
- **Edges:** `calls` (caller → callee), `implements` (class → interface), and publish/subscribe
  (class → event) with visually distinct styling for publish vs subscribe. Registration edges
  (installer → registered type) are drawn too, but any registration tagged `unresolved:true`
  is skipped — an empty-type registration has no valid node to point at.
- Hover a node to see its name/type/namespace; drag to reposition; scroll to zoom/pan.

**How to generate:**
```bash
# via the build pipeline (after export):
/build-knowledge-graph --viz

# or directly:
python3 .claude/graph/graph-viz.py [--graph PATH] [--out PATH]
# defaults: .claude/graph/graph.json -> .claude/graph/graph.html
```

**How to open:** just open `.claude/graph/graph.html` in any browser — no server, no build
step. `graph.html` itself is a generated artifact (**gitignored** — regenerate with the
command above rather than committing it); it renders only when the pinned `vis-network.min.js`
sits next to it. That vendored library, unlike `graph.html`, **is** committed to `.claude/graph/`.

If the graph has more than ~800 nodes, `graph-viz.py` still renders everything and prints a
stderr note that the layout will be dense — it never silently truncates nodes.

---

## Hybrid Architecture

The knowledge graph uses a two-backend split when `hybrid_graph` is enabled in `project-features.json` (default `false`):

| Query group | Backend | Queries |
|---|---|---|
| Call-graph (4) | `graph-mcp-server.py` via `graph_bfs_core.py` | `callers`, `impact`, `path`, `god-nodes` |
| Unity-semantic (11) | `jq` / `graph.json` (unchanged) | `summary`, `implementers`, `publishers`, `subscribers`, `registrations`, `scope-tree`, `prefab`, `violations`, `diff`, `communities`, `surprising` |

**`hybrid_graph` flag** in `project-features.json` gates all routing. Default is `false`.

- **Off (default):** behaviour identical to today — all 15 subcommands resolved via `jq`/`graph-traversal.py`, zero stderr output, no pip probe.
- **On + MCP connected (State A):** call-graph queries dispatched via `mcp__graph_mcp__*` tools backed by `graph_bfs_core.py`. Unity-semantic queries unchanged.
- **On + MCP absent (State B):** Bash-emitted warning on stderr + automatic fallback to `graph-traversal.py` (same result, slower startup due to lazy `pip` probe).

**Routing skill:** `.claude/skills/core/knowledge-graph-hybrid.md` — read before dispatching any call-graph query when `hybrid_graph` is enabled.

---

## Hybrid MCP Registration (User-applied)

The graph MCP server (`graph-mcp-server.py`) exposes the knowledge graph as MCP tools (`mcp__graph_mcp__*`) so Claude can query it directly during a session. Claude cannot edit `settings.json` — paste this block yourself.

### Prerequisites

Run this once in the same environment whose `python3` Claude Code invokes:

```bash
pip install mcp
```

### settings.json entry

Open `.claude/settings.json` and add the `mcpServers` block. If `mcpServers` already exists, add the `graph-mcp` key inside it — do not overwrite the existing object.

```json
"mcpServers": {
  "graph-mcp": {
    "command": "python3",
    "args": [".claude/graph/graph-mcp-server.py"]
  }
}
```

**Merge example** — if your `settings.json` already has another MCP server:

```json
"mcpServers": {
  "existing-server": { "command": "..." },
  "graph-mcp": {
    "command": "python3",
    "args": [".claude/graph/graph-mcp-server.py"]
  }
}
```

### Notes

- No `--watch` argument is needed — the server checks file mtime on each handler call and reloads automatically.
- The server reads `graph.json`, `scenes.json`, and `prefabs.json` from `.claude/graph/`.

### Verification

After editing `settings.json`, restart Claude Code. In the new session, `mcp__graph_mcp__*` tools should appear in the tool list. If they do not appear, confirm `pip install mcp` succeeded for the correct `python3` binary and that the JSON is valid.
