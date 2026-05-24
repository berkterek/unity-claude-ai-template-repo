# Knowledge Graph

The template ships with a Graphify-inspired knowledge graph at `.claude/graph/graph.json`.
Opt-in via `project-features.json` (`"graph": true`). When enabled, it is the single source of truth
for `/catch-up`, `/orchestrate` pre-scan, and `/context-prime`.

**Pipeline:** detect → extract (C# / asmdef / MCP) → build → cluster → analyze → report → export

**Commands:**
- `/build-knowledge-graph [--full|--incremental] [--skip-mcp] [--validate] [--validate-with-codex]`
- `/knowledge-graph <summary|implementers|publishers|subscribers|registrations|scope-tree|prefab|violations|diff>`

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
