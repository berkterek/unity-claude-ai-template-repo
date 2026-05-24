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

### Step 2b — Scope parent extraction (LifetimeScope prefabs)

For each prefab whose component list includes `LifetimeScope` (or any subclass):
1. Use `manage_components` with action `get` to read the Inspector state of that prefab.
2. Look for the serialized field `parentReference` on the `LifetimeScope` component.
3. If `parentReference` is non-null and references another prefab, extract the referenced prefab's name.
4. Record: `{ scope_name: "<ClassName on prefab>", parent_name: "<referenced LifetimeScope class>" }`.

This populates the top-level `scope_parents` array in `mcp-extract.json`, which `graph-builder.sh` uses to backfill `parent` on scope entries that the C# extractor left as `null`.

### Step 2c — Prefab component field values

For each prefab, after reading the component list:
1. For each component (skip Transform, Rigidbody, Collider-only components with no serialized fields), use `manage_components` with action `get` to read Inspector field values.
2. Capture simple scalar field values only: `int`, `float`, `string`, `bool`, `enum` (as string label).
3. Skip: array fields, nested object fields, UnityEngine.Object references (too noisy).
4. Store as `component_fields` on the prefab entry:
   ```json
   "component_fields": [
     {
       "component": "AudioConfiguration",
       "fields": { "masterVolume": 1.0, "sfxVolume": 0.8, "musicVolume": 0.7 }
     }
   ]
   ```

This allows `/knowledge-graph prefab <Name>` to show actual configured values, not just component names.

### Step 3 — Write output

Write the result to `.claude/graph/cache/mcp-extract.json`:

```json
{
  "scenes": [ /* sceneEntry[] per schema */ ],
  "prefabs": [ /* prefabEntry[] — each may include component_fields[] */ ],
  "scope_parents": [
    { "scope_name": "GameScope", "parent_name": "AppScope" }
  ],
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
