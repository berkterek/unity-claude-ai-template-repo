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

---

## Extractor Reliability Notes

Lessons from live testing — read before debugging graph output.

### csharp-extractor.sh

- **Multi-line class declarations** (`class Foo\n  : IBar`) are handled by a python3 parser that joins up to 6 lines. Single-line and multi-line declarations both produce correct `base_types[]` and `implements[]`.
- **Fully qualified interface names** (`Game.Abstracts.IFoo`) are reduced to their last segment (`IFoo`) before being stored. Both short and qualified names produce correct `implements[]`.
- **Stale MCP cache** — when `mcp-extract.json` is older than 60 minutes, `graph-builder.sh` retains prefabs and scenes from the existing `graph.json` instead of dropping them. Run `/build-knowledge-graph` with Unity Editor open to refresh MCP data.

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
