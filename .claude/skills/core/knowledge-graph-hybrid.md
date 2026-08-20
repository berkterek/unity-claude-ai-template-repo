---
name: knowledge-graph-hybrid
description: "Routes the 4 call-graph queries (callers/impact/path/god-nodes) to the in-process graph-mcp-server.py (backed by graph_bfs_core.py) with graph-traversal.py fallback; Unity-semantic queries stay on graph.json."
model-tier: light
---

# Knowledge Graph Hybrid Routing Skill

## Step 1 — Gate Check

Read `hybrid_graph` from `.claude/project-features.json`.

```bash
python3 -c "
import json, sys
with open('.claude/project-features.json') as f:
    features = json.load(f)
print(features.get('hybrid_graph', False))
"
```

- If result is `false` or the key is absent → **stop here**. Use today's backend unchanged for every subcommand. No State A/B evaluation. No pip probe. No stderr warning. Complete silence.
- If result is `true` → continue to Step 2.

---

## Step 2 — Routing Table (only when `hybrid_graph` is `true`)

15 total subcommands split into two groups:

### Group 1 — Call-Graph Queries (routed through hybrid backend)

| Subcommand | Hybrid backend (State A) | Fallback (State B) |
|------------|--------------------------|---------------------|
| `callers` | `mcp__graph_mcp__callers` | `python3 .claude/graph/graph-traversal.py callers` |
| `impact` | `mcp__graph_mcp__impact` | `python3 .claude/graph/graph-traversal.py impact` |
| `path` | `mcp__graph_mcp__path` | `python3 .claude/graph/graph-traversal.py path` |
| `god-nodes` | `mcp__graph_mcp__god_nodes` | `python3 .claude/graph/graph-traversal.py god-nodes` |

### Group 2 — Unity-Semantic Queries (never routed through MCP in any mode)

| Subcommand | Backend |
|------------|---------|
| `summary` | `graph.json` (jq) unchanged |
| `implementers` | `graph.json` (jq) unchanged |
| `publishers` | `graph.json` (jq) unchanged |
| `subscribers` | `graph.json` (jq) unchanged |
| `registrations` | `graph.json` (jq) unchanged |
| `scope-tree` | `graph.json` (jq) unchanged |
| `prefab` | `graph.json` (jq) unchanged |
| `violations` | `graph.json` (jq) unchanged |
| `diff` | `graph.json` (jq) unchanged |
| `communities` | `graph.json` (jq) unchanged |
| `surprising` | `graph.json` (jq) unchanged |

**Note:** The 11 Unity-semantic queries NEVER route through MCP in any mode. `graph-traversal.py`'s CLI surface and output are intentionally preserved.

---

## Step 3 — 2-State MCP Availability Model (call-graph queries only)

For each call-graph query (`callers`, `impact`, `path`, `god-nodes`), determine the state before executing:

### State A — Tool Present

The `mcp__graph_mcp__*` tools are present in this session.

→ Call the MCP tool directly. No warning. No pip probe. No fallback.

### State B — Tool Absent

The `mcp__graph_mcp__*` tools are NOT present in this session.

Execute the following sequence:

#### 3a. Lazy Once-Per-Session Pip Probe (only on first State B hit)

Run once per session on the first State B encounter:

```bash
python3 -c "import mcp" 2>/dev/null
```

- **Non-zero exit** (`mcp` not installed): emit this specific diagnostic BEFORE the generic warning:
  ```bash
  echo "the 'mcp' package required by graph-mcp-server is not installed — pip install mcp" >&2
  ```
- **Zero exit** (`mcp` installed but tool absent): no specific diagnostic — proceed directly to the generic warning.

#### 3b. Generic Warning (CANONICAL OWNER)

Always emit this exact Bash command in State B (after the optional specific diagnostic):

```bash
echo "MCP not connected — results may be incomplete" >&2
```

This is the single canonical owner of that warning string. It must appear verbatim — do not paraphrase.

#### 3c. Fallback Execution

Run the appropriate `graph-traversal.py` subcommand with the original arguments:

```bash
python3 .claude/graph/graph-traversal.py <subcommand> [args]
```

---

## MCP Tool Input Arguments

When State A is active, pass arguments to MCP tools as follows:

### `mcp__graph_mcp__callers`

| Arg | Type | Required |
|-----|------|----------|
| `node` | string (Class.Method format) | Yes |

### `mcp__graph_mcp__impact`

| Arg | Type | Required | Notes |
|-----|------|----------|-------|
| `node` | string | Yes | |
| `hops` | integer | No | Omit entirely if user did not specify. `graph_bfs_core` default is `3`. Do NOT pass `None` or `0` as a sentinel. |

### `mcp__graph_mcp__path`

| Arg | Type | Required |
|-----|------|----------|
| `a` | string | Yes |
| `b` | string | Yes |

### `mcp__graph_mcp__god_nodes`

| Arg | Type | Required | Notes |
|-----|------|----------|-------|
| `top` | integer | No | Omit entirely if user did not specify. `graph_bfs_core` default is `10`. Do NOT pass `None`. Note: MCP tool name uses underscore: `god_nodes`. |

**Default rule:** When `hops` or `top` is omitted by the user, pass nothing (omit the parameter entirely) — `graph_bfs_core` function signatures supply the defaults. Do NOT inject schema-level defaults.

---

## Architecture Notes

- `graph-mcp-server.py` loads `graph.json` + `scenes.json` + `prefabs.json` into RAM at startup.
- Stale-detection: each handler call checks `graph.json` mtime; all three partitions reload atomically when stale.
- Atomic rebind is lock-free — module-level names rebound in one no-`await` burst.
- Not-found / empty-result / suggestion outcomes are returned as successful tool results (matching the CLI `--json` shape). JSON-RPC errors are reserved for genuine faults only.
- `graph-traversal.py` CLI surface + output are identical before and after the v4 refactoring (internals import `graph_bfs_core`).
