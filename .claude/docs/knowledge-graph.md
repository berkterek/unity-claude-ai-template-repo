# Knowledge Graph

The template ships with a Graphify-inspired knowledge graph at `.claude/graph/graph.json` (schema v1.2.0).
Opt-in via `project-features.json` (`"graph": true`). When enabled, it is the single source of truth
for `/catch-up`, `/orchestrate` pre-scan, and `/context-prime`.

**Pipeline:** detect → extract (C# / asmdef / MCP) → build → finalize-calls → analyze → report → export

**Commands:**
- `/build-knowledge-graph [--full|--incremental] [--skip-mcp] [--validate] [--validate-with-codex]`
- `/knowledge-graph <summary|implementers|publishers|subscribers|registrations|scope-tree|prefab|violations|diff|callers|impact|path|god-nodes>`

**Triggers (kept in sync automatically):**
- Every Write/Edit → PostToolUse `graph-auto-update.sh` (incremental, background, non-blocking)
- Every `git commit` → `.git/hooks/post-commit` (full rebuild, background)
- Manual → `/build-knowledge-graph`

**Manual settings.json entry** (Claude cannot edit settings.json — add this yourself):
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/graph-auto-update.sh" }
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
- **partial_calls[] extraction** — call sites are extracted per file and merged into `codebase.calls[]` by `graph-builder.sh`. BCL types (`Debug`, `Mathf`, `Vector3`…) and C# keywords are filtered out. Confidence: `INFERRED`.
- **Stale MCP cache** — when `mcp-extract.json` is older than 60 minutes, `graph-builder.sh` retains prefabs and scenes from the existing `graph.json` instead of dropping them. Run `/build-knowledge-graph` with Unity Editor open to refresh MCP data. `--full` always invalidates the MCP cache regardless of age — retained prefabs are cross-checked against disk and stale paths emit `STALE_PREFAB_PATH` warnings in `validation.warnings[]`.
- **Missing scripts** — null component entries (`"null"` in `comps=(...)`) during MCP extraction set `has_missing_scripts: true` on the GO/prefab. `graph-builder.sh` collects these into `MISSING_SCRIPT` warnings in `validation.warnings[]`. Surface with `/knowledge-graph violations`.
- **Python JSON passing** — both `STALE_PATH_WARNINGS` and `MISSING_SCRIPT_WARNINGS` blocks pass data via env vars (`MCP_PREFABS_JSON`, `MISSING_INPUT_JSON`) + `json.loads(os.environ[...])`, not `echo | python3 -`. Bash heredoc overrides stdin so the pipe pattern silently delivers empty input to Python.
- **Subfolder layout (UNITY_FOLDER)** — `STALE_PATH_WARNINGS` passes `UNITY_FOLDER` to Python and prepends it to the `Assets/...` path before `os.path.exists()`. Without this, every prefab appears stale on projects where `Assets/` is not at repo root.
- **gameObjects key casing** — MISSING_SCRIPT detection reads `scene.get("gameObjects", scene.get("gameobjects", []))` to handle both camelCase (MCP cache output) and lowercase (older extractions).

### graph-builder.sh call edge merge

- **Full build (`--full`):** discards retained call edges, uses only freshly extracted `partial_calls[]`.
- **Incremental with changed files:** retains edges from unchanged files, replaces edges for changed files only.
- **Incremental with no changed files:** retains all existing call edges unchanged (no re-extraction needed).
- After assembly, `graph-traversal.py --finalize-calls` deduplicates edges and promotes `EXTRACTED` over `INFERRED` for the same caller+callee+file+line.

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

- `algorithm: "greedy-modularity-stdlib"` — default, no pip install needed
- `algorithm: "louvain-networkx"` — higher quality; requires `pip install networkx`

### graph_analyze.py

New in v1.2.0. Classifies surprising cross-boundary edges and enriches god-nodes with community data.

- `CROSS_SCOPE` → severity `warning` (two classes in different VContainer scopes calling each other directly)
- `CROSS_ASSEMBLY` → severity `info`
- `CROSS_COMMUNITY` → severity `info`

### graph_validate.py

New in v1.2.0. Spot-checks graph accuracy against source files. Default: sample 20 classes, seed 42.

- `validation.accuracy.agreement_pct` — percentage of checks that matched source
- If `< 90%`, `low_accuracy_warning: true` and a `warning_message` recommend `--full` rebuild
- **Never touches `validation.warnings[]`** — that array is owned by `graph-validator.sh`

### Query cheatsheet additions (v1.2.0)

- "Which classes form a module?" → `/knowledge-graph communities`
- "Architecture drifting where?" → `/knowledge-graph surprising`
- "God-nodes with community context?" → `/knowledge-graph god-nodes` (now uses `analysis.enhanced_god_nodes[]` when present)
