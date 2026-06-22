# Design Spec — hybrid_graph Auto-Activation in /setup-project

> **Date:** 2026-06-22
> **Status:** Approved
> **Scope:** `.claude/commands/setup-project.md` — add Step 5.6

---

## Problem

`hybrid_graph` is present in `project-features.json` but is never activated during `/setup-project`. It defaults to `false` and users have no path to enable it without manual intervention. The feature requires two external registrations (pip package + Claude Code MCP server) that are easy to miss or misconfigure.

---

## Decision

`hybrid_graph` is NOT a user-facing question during setup. It activates automatically whenever `graph=true`. The user never sees a "do you want hybrid_graph?" prompt — the feature is treated as the standard graph backend, not an opt-in extension.

---

## Architecture

### Trigger Condition

Step 5.6 runs only when:
- `graph=true` (user enabled Knowledge Graph)
- Fresh setup OR re-run where `hybrid_graph` is `false` or MCP is not yet registered

Re-run guard:
```bash
claude mcp list | grep -q "graph-mcp" && echo "ALREADY_REGISTERED"
```
If already registered → skip Step 5.6 entirely, print "hybrid_graph already active."

---

## Step 5.6 — Hybrid Graph Activation

Runs immediately after Step 5.5 (initial graph build). Four sub-steps execute in sequence; any failure stops the chain and leaves `hybrid_graph=false`.

### 5.6a — pip Probe

```bash
python3 -m pip install mcp --quiet --exists-action i 2>&1
```

- `--exists-action i` = ignore if already installed, no-op
- On failure: print manual instructions, set `HYBRID_FAILED=true`, skip remaining sub-steps

**Failure output:**
```
[hybrid_graph] pip install mcp failed.
Manual fix: run `pip install mcp`, then re-run /setup-project.
hybrid_graph left as false.
```

### 5.6b — MCP Registration

```bash
claude mcp list | grep -q "graph-mcp" || \
  claude mcp add --scope project graph-mcp \
    python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
```

- `--scope project` = registration scoped to this repository only
- Absolute path via `$(pwd)` prevents working-directory ambiguity when MCP daemon starts
- `grep -q` guard prevents duplicate registration errors on re-run

On failure: print manual instructions, skip 5.6c and 5.6d.

**Failure output:**
```
[hybrid_graph] MCP registration failed.
Manual fix: claude mcp add --scope project graph-mcp python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
Then re-run /setup-project to write hybrid_graph=true.
```

### 5.6c — project-features.json Update

```bash
tmp=$(mktemp)
jq '.hybrid_graph = true' .claude/project-features.json > "$tmp" && mv "$tmp" .claude/project-features.json
```

- Uses `jq` for correct JSON handling — `sed` on JSON is fragile
- Atomic write via temp file — partial writes cannot corrupt the JSON
- Only runs if 5.6a and 5.6b both succeeded

### 5.6d — CLAUDE.md Feature Table Update

```bash
sed -i '' 's/| `hybrid_graph` | \*\*DISABLED\*\*/| `hybrid_graph` | **ENABLED**/' .claude/CLAUDE.md
```

- Non-critical: on failure, print a warning and continue (does not block activation)
- CLAUDE.md template has a fixed-format table row — sed target is stable

### 5.6e — Confirmation Output

```
✓ hybrid_graph activated
  • MCP server: graph-mcp (project-scoped)
  • Call-graph queries routed via MCP: callers, impact, path, god-nodes
  • Unity-semantic queries unchanged: summary, violations, scope-tree, etc.

⚠  Restart Claude Code to activate MCP in the current session.
   New sessions start the server automatically.
```

---

## Error Handling Summary

| Sub-step | On failure | hybrid_graph written? |
|----------|-----------|----------------------|
| 5.6a pip install | Stop, print manual fix | ❌ remains false |
| 5.6b MCP add | Stop, print manual fix | ❌ remains false |
| 5.6c jq write | Stop, print error | ❌ (not yet written) |
| 5.6d CLAUDE.md sed | Warn, continue | ✅ (non-critical) |

**Invariant:** `hybrid_graph=true` is only written after both pip and MCP registration succeed. A partially configured state (true in JSON but no working MCP server) would cause silent routing failures.

---

## Re-run Behavior

When `/setup-project` detects `project-features.json` already exists with `hybrid_graph=true` and `claude mcp list` shows `graph-mcp`:

```
hybrid_graph already active — skipping Step 5.6.
```

When `hybrid_graph=false` but MCP is already registered (unusual state):
- Run only 5.6a (pip probe) + 5.6c (write true) + 5.6d (CLAUDE.md)
- Skip 5.6b (MCP already registered)

---

## Files Modified by This Design

| File | Change |
|------|--------|
| `.claude/commands/setup-project.md` | Add Step 5.6 after Step 5.5 |
| `.claude/project-features.json` | `hybrid_graph` written `true` on success |
| `.claude/CLAUDE.md` | Feature table row updated DISABLED → ENABLED |

No new files are created. `graph-mcp-server.py` and `graph_bfs_core.py` already exist on the `graph` branch.

---

## Out of Scope

- Making `hybrid_graph` a user-facing opt-in question — decided against (auto-activation)
- User-scoped MCP registration — decided against (project-scoped for isolation)
- Modifying `graph-mcp-server.py` — already functional, no changes needed
- CI/CD integration of MCP server — out of scope for this template
