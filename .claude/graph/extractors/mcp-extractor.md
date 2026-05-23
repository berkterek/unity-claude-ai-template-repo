---
name: mcp-extractor
description: "EDITOR/MCP ONLY — Extracts scenes/prefabs/components via MCP into graph cache. Unity Editor must be open. Read this skill before any MCP calls."
alwaysApply: false
---

# MCP Extractor

**[EDITOR/MCP — Unity Editor must be open]**

This extractor cannot run when the Editor is closed. `/build-knowledge-graph` skips it automatically
if MCP is unavailable and sets `codebase.mcp_extraction.status: "skipped"`.

## Inputs

| Flag | Default | Description |
|------|---------|-------------|
| `--scenes <path1>,<path2>` | (all scenes) | Comma-separated scene paths to extract |
| `--prefabs <dir>` | `Assets/_GameFolders/Prefabs` | Prefab root directory |

## PRE-CONDITION GATE — Run Before Any Other Step

1. Read `.claude/skills/core/unity-mcp-patterns/SKILL.md`.
2. Confirm which MCP actions exist:
   - Scene hierarchy: `manage_scene` with `get_hierarchy` or equivalent
   - Component reads: `manage_components` read action
   - Prefab info: `manage_scene` or `get_info`/`get_hierarchy` on prefab
3. If any required action is ABSENT → mark extraction as `[BLOCKED — MCP action unconfirmed]`, write empty output (see Failure Modes), and stop.

## Process

All MCP calls must be batched via `batch_execute` per the unity-mcp-patterns skill Rule 1.

### Step 1 — Scene extraction

For each scene (all scenes, or filtered by `--scenes`):
1. Load the scene via `manage_scene`.
2. Walk root GameObjects and their children (2 levels deep).
3. For each GameObject: collect component type list via `manage_components`.
4. Build the `gameobjects[]` tree matching the schema.

### Step 2 — Prefab enumeration

```bash
find Assets -name '*.prefab' 2>/dev/null
```

For each `.prefab` file:
1. Use the confirmed prefab action to read component list.
2. Detect `isVariant` by checking the `.prefab` YAML for `m_PrefabParent`:
   ```bash
   grep -l 'm_PrefabParent:' Assets/**/*.prefab
   ```
3. Classify `domain` from path using this heuristic:
   - `**/UI/**` → `UI`
   - `**/VFX/**` → `VFX`
   - `**/Enemies/**` → `Enemies`
   - `**/Characters/**` → `Characters`
   - `**/Environment/**` → `Environment`
   - `**/Audio/**` → `Audio`
   - `**/Bootstrap/**` → `Bootstrap`
   - `**/CoreObjects/**` → `CoreObjects`
   - Otherwise → `ThirdParty`

### Step 3 — Write output

Write the result to `.claude/graph/cache/mcp-extract.json`:

```json
{
  "scenes": [ /* sceneEntry[] per schema */ ],
  "prefabs": [ /* prefabEntry[] per schema */ ],
  "extracted_at": "<ISO8601 UTC>"
}
```

After writing, re-run:
```bash
bash .claude/graph/graph-builder.sh --incremental
```
so the new MCP data gets merged into `graph.json`.

## Failure Modes

If Unity Editor is not connected or any MCP action is unavailable:

1. Exit 0 (never crash — the rest of the build still proceeds).
2. Write empty output to `.claude/graph/cache/mcp-extract.json`:
   ```json
   {
     "scenes": [],
     "prefabs": [],
     "extracted_at": null
   }
   ```
3. The builder sets `codebase.mcp_extraction.status: "skipped"` with
   `skipped_reason: "MCP_UNAVAILABLE"` in the top-level metadata.
4. Do NOT set per-item confidence fields for skipped entries.

## Confidence

All MCP-extracted entries use `confidence: "EXTRACTED"` (live Editor data is authoritative).
