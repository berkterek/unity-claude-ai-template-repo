# /build-knowledge-graph — Unity Knowledge Graph Builder

Build or refresh the Unity Knowledge Graph (`graph.json`). Indexes every class, interface,
event, installer, scope, asmdef, scene, and prefab in the project.

## Usage

```
/build-knowledge-graph                       # incremental build (default)
/build-knowledge-graph --full                # full rebuild, ignore cache
/build-knowledge-graph --mcp-only            # refresh scene/prefab data only (MCP)
/build-knowledge-graph --skip-mcp            # skip scene/prefab extraction
/build-knowledge-graph --validate            # run architecture invariant checks
/build-knowledge-graph --validate-with-codex # run + Codex accuracy spot-check
/build-knowledge-graph --quiet               # suppress progress output
/build-knowledge-graph --viz                 # also emit graph.html (visualizer)
```

---

## Step 0 — Plugin Preflight

Check `.claude/graph/graph-builder.sh` exists.

If missing:
```
The Unity Knowledge Graph has not been set up for this project.
Run /setup-project and enable the 'graph' feature flag to install it.
```
Stop here.

Check `.claude/project-features.json`. If `.graph` is not `true`:
```
Knowledge Graph feature is disabled (project-features.json.graph = false).
Enable it first: set graph = true in .claude/project-features.json, then re-run.
```
Stop here.

---

## Step 1 — Parse Flags

| Flag | Default | Effect |
|------|---------|--------|
| `--full` | off | Rebuild from scratch, ignore SHA256 cache |
| `--incremental` | on | Use cache, only re-extract changed files |
| `--mcp-only` | off | Skip shell extraction; run ONLY the MCP extractor then merge |
| `--skip-mcp` | off | Skip scene/prefab MCP extraction entirely |
| `--validate` | off | Run `graph-validator.sh` after build |
| `--validate-with-codex` | off | Run Codex accuracy spot-check after build |
| `--quiet` | off | Suppress progress output |
| `--viz` | off | After export, generate `graph.html` (vis-network visualizer) |

---

## Step 2 — Shell Extraction

If `--mcp-only` is NOT set:

1. Back up existing graph:
   ```bash
   cp .claude/graph/graph.json .claude/graph/graph.json.bak 2>/dev/null || true
   ```
2. Run the builder:
   ```bash
   bash .claude/graph/graph-builder.sh [--full|--incremental] [--skip-mcp] [--quiet]
   ```
   Stream stderr to the user.

---

## Step 3 — MCP Extraction (RUNTIME — Unity Editor must be open)

If `--skip-mcp` is NOT set:

1. Read `.claude/skills/core/unity-mcp-patterns/SKILL.md` for batch_execute rules.
2. Read `.claude/graph/extractors/mcp-extractor.md`.
3. Execute the MCP extraction process per the extractor skill.
4. The extractor writes output to `.claude/graph/cache/mcp-extract.json`.
5. Re-run the builder to merge MCP data:
   ```bash
   bash .claude/graph/graph-builder.sh --incremental
   ```

If Unity Editor is not connected:
- Log: "MCP unavailable — skipping scene/prefab extraction. graph.mcp_extraction.status = skipped."
- Continue (non-fatal).

---

## Step 4 — Architecture Validation

If `--validate` or `--validate-with-codex` set:

```bash
bash .claude/graph/graph-validator.sh .claude/graph/graph.json
```

Print the validator output to the user. If exit 1 (errors found), ask:
```
Architecture errors found. Fix them before committing? (y/n)
```
Do not block the build on warnings.

---

## Step 5 — Codex Accuracy Check

If `--validate-with-codex` set:

1. Read `.claude/graph/codex-validator.md`.
2. Hand the prompt to `codex:codex-rescue` per the pattern in `/fix-codex` Step 1.
3. Display the JSON report.
4. If agreement < 95%: list all disagreements and suggest `--full` rebuild.

---

## Step 6 — Summary

Print:
```
graph.json updated
  Classes:      <n>  (Methods: <n>)
  Interfaces:   <n>
  Events:       <n>
  Installers:   <n>
  Assemblies:   <n>
  Scenes:       <n>
  Prefabs:      <n>
  Cache hits:   <n> / <total>
  Build time:   <ms>ms
  MCP status:   ok | skipped (<reason>)
  Validation:   <n errors>, <n warnings>
  Communities:  <n>
  Accuracy:     <pct>%   ← if < 90%, run --full
```

If `Accuracy < 90%`, recommend re-running with `--full` to force a complete re-extraction.

If `graph.json.bak` exists, show a one-line diff:
```bash
diff <(jq -S '.codebase.classes | map(.name) | sort' .claude/graph/graph.json.bak) \
     <(jq -S '.codebase.classes | map(.name) | sort' .claude/graph/graph.json)
```

---

## Step 7 — Visualizer (optional, `--viz` only)

If `--viz` was passed, generate the HTML graph visualizer **after** the
export/partition write from the preceding steps has completed:

```bash
python3 .claude/graph/graph-viz.py --graph .claude/graph/graph.json --out .claude/graph/graph.html
```

Print the resulting node/edge counts (emitted by the script to stderr) to the user, e.g.:
```
graph.html written: .claude/graph/graph.html (nodes=147, edges=191, publish_edges=12)
```

`graph.html` is a generated artifact (**gitignored**) — open it directly in a browser
(`file://` works, no server needed). It renders via a vendored `vis-network.min.js` (pinned
9.1.6, **committed**) that must sit next to it. It is **not** produced by a default build; the
flag must be passed explicitly. See `.claude/docs/knowledge-graph.md` for what it renders.
