# hybrid_graph Auto-Activation in /setup-project — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Step 5.6 to `.claude/commands/setup-project.md` so that `hybrid_graph` activates automatically (pip install + project-scoped MCP registration) whenever `graph=true`, with no user-facing prompt.

**Architecture:** A single markdown command file is modified. Step 5.6 is inserted between Step 5.5 (graph build) and Step 2 (folder generation). The step contains four sequential sub-steps that bail out on failure, ensuring `hybrid_graph=true` is only written to `project-features.json` after both pip and MCP registration succeed.

**Tech Stack:** Bash (pip, claude CLI, jq, sed), Markdown

## Global Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. `claude mcp add` is a CLI command run via Bash and is not affected by this constraint.
- `project-features.json` uses `jq` for writes — never `sed` for JSON.
- MCP registration is **project-scoped** (`--scope project`) — never `--scope user`.
- Absolute path via `$(pwd)` for the server path — relative paths break MCP daemon startup.
- `hybrid_graph=true` is written **only** after 5.6a (pip) and 5.6b (MCP) both succeed.
- Step 5.6 only runs when `graph=true`. When `graph=false`, skip entirely.

---

## File Map

| File | Action | Line range |
|------|--------|-----------|
| `.claude/commands/setup-project.md` | Modify — insert Step 5.6 block | After line 177 (end of Step 5.5 `---`), before `### Step 2` |

No new files are created.

---

## Task 1: Insert Step 5.6 into setup-project.md

**Files:**
- Modify: `.claude/commands/setup-project.md` — insert between the closing `---` of Step 5.5 (line 177) and `### Step 2 — Generate Folder Structure` (line 180)

**Interfaces:**
- Consumes: `graph=true` decision from Step 1c (already in file)
- Produces: `hybrid_graph=true` in `project-features.json` and project-scoped `graph-mcp` MCP entry

- [ ] **Step 1: Read the current file around the insertion point**

Verify line 177 is the `---` separator after Step 5.5 and line 180 starts `### Step 2`:

```bash
sed -n '155,185p' .claude/commands/setup-project.md
```

Expected output contains:
```
### Step 5.5 — Initial Graph Build (if graph=true)
...
   ```
---

### Step 2 — Generate Folder Structure
```

- [ ] **Step 2: Insert Step 5.6 block**

Insert the following block between the `---` (end of Step 5.5) and `### Step 2`. The exact insertion: replace the `---\n\n### Step 2` boundary with `---\n\n### Step 5.6 ...\n\n---\n\n### Step 2`.

Use the Edit tool with the following old/new strings:

**old_string** (exact — the `---` separator and the first line of Step 2):
```
---

### Step 2 — Generate Folder Structure
```

**new_string** (Step 5.6 block inserted between them):
```
---

### Step 5.6 — Hybrid Graph Activation (runs immediately after Step 5.5, only when graph=true)

Activate `hybrid_graph` automatically — no user prompt. Runs four sub-steps in sequence; any failure aborts the chain and leaves `hybrid_graph=false` in `project-features.json`.

**Re-run guard (check first):**
```bash
claude mcp list | grep -q "graph-mcp" && echo "ALREADY_REGISTERED"
```
If output is `ALREADY_REGISTERED` → print "hybrid_graph already active — skipping Step 5.6." and stop.

#### 5.6a — pip Probe

```bash
python3 -m pip install mcp --quiet --exists-action i 2>&1
```

- `--exists-action i` = skip silently if already installed
- On non-zero exit: print the failure message below, set `HYBRID_FAILED=true`, skip 5.6b–5.6e.

**Failure output:**
```
[hybrid_graph] pip install mcp failed.
Manual fix: run `pip install mcp`, then re-run /setup-project.
hybrid_graph left as false.
```

#### 5.6b — MCP Registration

```bash
claude mcp add --scope project graph-mcp \
  python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
```

- `--scope project` — registration scoped to this repository only
- `$(pwd)` — absolute path; prevents working-directory ambiguity when MCP daemon starts
- On non-zero exit: print the failure message below, skip 5.6c–5.6e.

**Failure output:**
```
[hybrid_graph] MCP registration failed.
Manual fix:
  claude mcp add --scope project graph-mcp python3 "$(pwd)/.claude/graph/graph-mcp-server.py"
Then re-run /setup-project to write hybrid_graph=true.
```

#### 5.6c — Write hybrid_graph=true to project-features.json

```bash
tmp=$(mktemp)
jq '.hybrid_graph = true' .claude/project-features.json > "$tmp" && mv "$tmp" .claude/project-features.json
```

- Uses `jq` for correct JSON handling — `sed` on JSON is fragile
- Atomic write via temp file — partial writes cannot corrupt the file
- Only runs after 5.6a and 5.6b both succeeded

#### 5.6d — Update CLAUDE.md Feature Table

```bash
sed -i '' 's/| `hybrid_graph` | \*\*DISABLED\*\*/| `hybrid_graph` | **ENABLED**/' .claude/CLAUDE.md
```

- Non-critical: on failure, print a warning and continue — does not block activation
- The CLAUDE.md template has a fixed-format table row; this sed target is stable

#### 5.6e — Confirmation

Print:
```
✓ hybrid_graph activated
  • MCP server: graph-mcp (project-scoped)
  • Call-graph queries via MCP: callers, impact, path, god-nodes
  • Unity-semantic queries unchanged: summary, violations, scope-tree, etc.

⚠  Restart Claude Code to activate MCP in the current session.
   New sessions start the server automatically.
```

---

### Step 2 — Generate Folder Structure
```

- [ ] **Step 3: Verify the insertion is correct**

```bash
grep -n "Step 5.6\|Step 5.5\|Step 2 — Generate" .claude/commands/setup-project.md
```

Expected output (line numbers approximate):
```
155:### Step 5.5 — Initial Graph Build (if graph=true)
178:### Step 5.6 — Hybrid Graph Activation
240:### Step 2 — Generate Folder Structure
```

Also verify `hybrid_graph` appears in the content:
```bash
grep -c "hybrid_graph" .claude/commands/setup-project.md
```
Expected: `5` or more occurrences.

- [ ] **Step 4: Verify project-features.json and CLAUDE.md are NOT modified**

Step 5.6 modifies those files at runtime (when `/setup-project` is actually run by a user). At plan implementation time, we are only editing the command file. Confirm:

```bash
git diff --name-only
```

Expected: only `.claude/commands/setup-project.md` is modified.

- [ ] **Step 5: Commit**

```bash
git add .claude/commands/setup-project.md
git commit -m "$(cat <<'EOF'
feat(setup): add Step 5.6 — hybrid_graph auto-activation

When graph=true, /setup-project now automatically:
  1. pip installs the mcp package (idempotent)
  2. registers graph-mcp-server.py as a project-scoped MCP server
  3. writes hybrid_graph=true to project-features.json
  4. updates the CLAUDE.md feature table

Failure in pip or MCP registration leaves hybrid_graph=false to
prevent a partially-configured state from causing silent routing bugs.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- ✅ `hybrid_graph` not asked as a user question — auto-activated on `graph=true`
- ✅ pip probe (5.6a) with idempotent `--exists-action i`
- ✅ Project-scoped MCP registration (5.6b) with absolute path
- ✅ `hybrid_graph=true` written only after both pip and MCP succeed (5.6c)
- ✅ CLAUDE.md feature table updated, non-critical failure handling (5.6d)
- ✅ Confirmation output with restart warning (5.6e)
- ✅ Re-run guard at top of step
- ✅ Failure messages match spec exactly
- ✅ Error handling table: pip fail → false, MCP fail → false, jq fail → false, sed fail → warn+continue

**Placeholder scan:** No TBD/TODO. All bash commands are complete and runnable. ✅

**Type consistency:** No function signatures — command file only. ✅
