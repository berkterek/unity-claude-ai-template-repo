# PLAN — Graph Partition Architecture (Scenes & Prefabs)

> **Version:** v1.1 — 2026-06-16
> **Status:** Active
> **Scope:** `.claude/graph/graph-builder.py`, `.claude/graph/graph-traversal.py`, `.claude/graph/schema.json`

**Complexity: 0.35 — Simple**

## Context

The knowledge graph currently embeds `scenes[]` and `prefabs[]` as inline arrays directly inside `graph.json`. These arrays grow large as a project accumulates scenes and prefabs. Because `graph-traversal.py` never queries these arrays at runtime (call-graph queries only touch `calls[]`), the data is pure document storage that inflates every load of `graph.json` for zero traversal benefit.

The partition architecture moves `scenes[]` and `prefabs[]` into sibling files `scenes.json` and `prefabs.json` in the same `.claude/graph/` directory. The main `graph.json` replaces those arrays with `{"$partition": "scenes.json"}` and `{"$partition": "prefabs.json"}` reference objects. A new utility function in `graph-traversal.py` dereferences a partition on demand. All other consumers (graph_cluster.py, graph_analyze.py, graph_validate.py, `check_path_drift`, `check_missing_scripts`) are unaffected.

Backward-compatibility: graphs written before this change (inline arrays, no partition files) continue to load correctly. Schema bumped to v1.3.0.

## Goals

- [ ] Partition files `scenes.json` and `prefabs.json` written atomically before `graph.json`
- [ ] `graph.json` stores `{"$partition": "scenes.json"}` and `{"$partition": "prefabs.json"}` instead of inline arrays
- [ ] `load_mcp_cache` correctly resolves `$partition` refs when reading retained data from existing graph
- [ ] `resolve_partition(graph, key, graph_dir)` in `graph-traversal.py` returns full array for inline or partitioned graphs
- [ ] `schema.json` bumped to v1.3.0 with `oneOf` on `scenes` and `prefabs`
- [ ] Backward compatibility: graphs with inline arrays continue to load without error

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Write partition files atomically | ⏳ Pending | A |
| 1 | Task 2 — Fix load_mcp_cache fallback for $partition refs | ⏳ Pending | A |
| 2 | Task 3 — Replace inline arrays with $partition refs in assemble_graph() | ⏳ Pending | B |
| 3 | Task 4 — Add resolve_partition utility to graph-traversal.py | ⏳ Pending | C |
| 4 | Task 5 — Bump schema.json to v1.3.0 | ⏳ Pending | C |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/graph-builder.py` | Modify | Add `write_partition_files()`, `_resolve_inline_or_partition()`, update `assemble_graph()`, update call site |
| `.claude/graph/graph-traversal.py` | Modify | Add `resolve_partition()` utility |
| `.claude/graph/schema.json` | Modify | Bump to v1.3.0, `scenes`/`prefabs` become `oneOf` |
| `.claude/graph/scenes.json` | Add (generated) | Partition file for scenes array; commit alongside graph.json — same policy as graph.json (generated, tracked in repo, never hand-edited) |
| `.claude/graph/prefabs.json` | Add (generated) | Partition file for prefabs array; commit alongside graph.json — same policy as graph.json (generated, tracked in repo, never hand-edited) |

---

## Task 1 — Write Partition Files Atomically

**Phase:** 1 | **Parallel group:** A | **File:** `.claude/graph/graph-builder.py`

### Context

Before `graph.json` is written, `scenes.json` and `prefabs.json` must already exist on disk so that any reader that immediately opens `graph.json` and dereferences the `$partition` ref can resolve it without a missing-file error. Atomic write (write to `.tmp`, then `os.replace`) matches the existing pattern used for `graph.json`.

### Steps

1. [ ] Add a helper `write_partition_files(graph_dir, scenes, prefabs)` that writes `scenes.json` and `prefabs.json` atomically to `graph_dir` using the same `.tmp` + `os.replace` pattern already used for `graph.json`.
2. [ ] Add a helper `_resolve_inline_or_partition(value, graph_dir)` that accepts either a raw list or a `{"$partition": "<filename>"}` dict and returns the resolved list. Used by `load_mcp_cache` to recover inline-or-partitioned fallback data from an existing graph file.
3. [ ] Call `write_partition_files(graph_dir, scenes_list, prefabs_list)` immediately before the `graph.json` atomic write in the existing build pipeline, passing the fully assembled lists.
4. [ ] **Version policy for generated files:** Commit `scenes.json` and `prefabs.json` alongside `graph.json` — same policy as `graph.json` (generated, tracked in repo, never hand-edited). Do not add these files to `.gitignore`.

**Test Type:** NoTest (Python tooling script)

**Code Skeleton:**
```python
def write_partition_files(graph_dir, scenes, prefabs):
    for filename, data in [("scenes.json", scenes), ("prefabs.json", prefabs)]:
        dest = os.path.join(graph_dir, filename)
        fd, tmp = tempfile.mkstemp(dir=graph_dir, suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
            with open(tmp) as f:
                json.load(f)
            os.replace(tmp, dest)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise

def _resolve_inline_or_partition(value, graph_dir):
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and "$partition" in value:
        fname = value["$partition"]
        result = read_json_safe(os.path.join(graph_dir, fname), [])
        return result if isinstance(result, list) else []
    return []
```

**Acceptance Criteria:**
- `scenes.json` and `prefabs.json` exist on disk before `graph.json` is finalized.
- Both files are valid JSON arrays.
- If the write of either partition file fails, the whole build aborts (no partial state).
- Re-running the builder overwrites the partition files cleanly via atomic replace.

---

## Task 2 — Fix load_mcp_cache Fallback for $partition Refs

**Phase:** 1 | **Parallel group:** A | **File:** `.claude/graph/graph-builder.py`

### Context

`load_mcp_cache()` reads the previous `graph.json` to carry forward data that did not change. After this change, an existing `graph.json` may contain `{"$partition": "scenes.json"}` instead of an inline array. The current fallback logic reads `cb.get("scenes", [])` directly, which would return the dict object rather than the resolved list.

### Steps

1. [ ] Locate `load_mcp_cache()` in `graph-builder.py`.
2. [ ] Replace lines 513–514 — `fallback_scenes = cb.get("scenes", []) if isinstance(cb, dict) else []` and `fallback_prefabs = cb.get("prefabs", []) if isinstance(cb, dict) else []` — with calls to `_resolve_inline_or_partition`, computing `graph_dir = os.path.dirname(os.path.abspath(output_path))`.
3. [ ] `_resolve_inline_or_partition` (added in Task 1) handles both the legacy inline-list case and the new `$partition` dict case — no additional branching needed here.

**Test Type:** NoTest (Python tooling script)

**Code Skeleton:**
```python
graph_dir = os.path.dirname(os.path.abspath(output_path))
fallback_scenes  = _resolve_inline_or_partition(cb.get("scenes",  []) if isinstance(cb, dict) else [], graph_dir)
fallback_prefabs = _resolve_inline_or_partition(cb.get("prefabs", []) if isinstance(cb, dict) else [], graph_dir)
```

**Acceptance Criteria:**
- Running the builder against a graph that contains `$partition` refs produces correct `fallback_scenes` and `fallback_prefabs` lists.
- Running the builder against a legacy inline-array graph produces the same result as before this change.
- No `KeyError` or `TypeError` when the partition file is missing (graceful fallback to empty list).

---

## Task 3 — Replace Inline Arrays with $partition Refs in assemble_graph()

**Phase:** 2 | **Parallel group:** B | **File:** `.claude/graph/graph-builder.py`

### Context

`assemble_graph()` constructs the dict serialized to `graph.json`. Currently it embeds `scenes` and `prefabs` as full inline arrays. After Task 1 writes the partition files, this task replaces those entries with reference objects.

### Steps

1. [ ] In `assemble_graph()`, replace the `"scenes": scenes` and `"prefabs": prefabs` entries with `"scenes": {"$partition": "scenes.json"}` and `"prefabs": {"$partition": "prefabs.json"}`.
2. [ ] Update `"schema_version"` from `"1.2.0"` to `"1.3.0"` in the same function (line 607).
3. [ ] Confirm `assemble_graph()` still receives the raw lists as arguments (they are forwarded to `write_partition_files` in Task 1 — do not remove the parameters).

**Test Type:** NoTest (Python tooling script)

**Code Skeleton:**
```python
# Inside assemble_graph() return dict, codebase block:
"scenes":  {"$partition": "scenes.json"},
"prefabs": {"$partition": "prefabs.json"},
# and:
"schema_version": "1.3.0",
```

**Acceptance Criteria:**
- `graph.json` written to disk contains `{"$partition": "scenes.json"}` and `{"$partition": "prefabs.json"}` under the `scenes` and `prefabs` keys — not inline arrays.
- `scenes.json` and `prefabs.json` exist as sibling files with the expected arrays.
- `schema_version` in `graph.json` reads `"1.3.0"`.

---

## Task 4 — Add resolve_partition Utility to graph-traversal.py

**Phase:** 3 | **Parallel group:** C | **File:** `.claude/graph/graph-traversal.py`

### Context

Consumers that need the full scenes or prefabs list from a graph dict (which now may contain a `$partition` ref) need a single resolution point rather than duplicating dereferencing logic.

> **Note:** This utility has no current callers in `graph-traversal.py` — scenes/prefabs are never queried by the traversal engine today. This is an additive utility for future callers (e.g. a `prefab` or `scene` subcommand that needs partition data).

### Steps

1. [ ] After `load_graph()`, add `resolve_partition(graph, key, graph_dir)` with the comment `# Called by future query subcommands that need scenes/prefab data.` on the line immediately above the `def` signature.
2. [ ] If `graph["codebase"][key]` is a list, return it directly (backward-compatible inline case).
3. [ ] If it is a dict with `"$partition"`, read and return the JSON array from the referenced file in `graph_dir`.
4. [ ] If the partition file is missing, raise `FileNotFoundError` with a descriptive message.
5. [ ] If `key` is absent from `graph["codebase"]`, return `[]`.

**Test Type:** NoTest (Python tooling script)

**Code Skeleton:**
```python
# Called by future query subcommands that need scenes/prefab data.
def resolve_partition(graph, key, graph_dir):
    value = graph.get("codebase", {}).get(key)
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and "$partition" in value:
        fpath = os.path.join(graph_dir, value["$partition"])
        if not os.path.exists(fpath):
            raise FileNotFoundError(f"Partition file missing: {fpath}")
        with open(fpath, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    return []
```

**Acceptance Criteria:**
- `resolve_partition(g, "scenes", graph_dir)` returns the full scenes list for both inline and partitioned graphs.
- `resolve_partition(g, "prefabs", graph_dir)` returns the full prefabs list for both inline and partitioned graphs.
- Missing key returns `[]` without raising.
- Missing partition file raises `FileNotFoundError`.

---

## Task 5 — Bump schema.json to v1.3.0

**Phase:** 4 | **Parallel group:** C | **File:** `.claude/graph/schema.json`

### Context

The schema currently defines `scenes` and `prefabs` as arrays. The new wire format allows either an inline array or a `$partition` reference object. The schema must accept both via `oneOf`.

### Steps

1. [ ] Bump `"version"` in `schema.json` to `"1.3.0"`.
2. [ ] Change the `scenes` property definition from `{"type": "array", ...}` to a `oneOf` that accepts either an array or `{"$partition": string}`.
3. [ ] Apply the identical `oneOf` pattern to the `prefabs` property.

**Test Type:** NoTest (schema file, validated by graph_validate.py post-write)

**Code Skeleton:**
```json
"scenes": {
  "oneOf": [
    {
      "type": "array",
      "items": { "$ref": "#/definitions/sceneEntry" },
      "description": "Inline array (legacy, pre-v1.3.0)."
    },
    {
      "type": "object",
      "required": ["$partition"],
      "properties": {
        "$partition": { "type": "string" }
      },
      "additionalProperties": false,
      "description": "Partition reference (v1.3.0+)."
    }
  ]
},
"prefabs": {
  "oneOf": [
    {
      "type": "array",
      "items": { "$ref": "#/definitions/prefabEntry" },
      "description": "Inline array (legacy, pre-v1.3.0)."
    },
    {
      "type": "object",
      "required": ["$partition"],
      "properties": {
        "$partition": { "type": "string" }
      },
      "additionalProperties": false,
      "description": "Partition reference (v1.3.0+)."
    }
  ]
}
```

**Acceptance Criteria:**
- `schema.json` version field reads `"1.3.0"`.
- A graph with inline arrays validates against the schema without error.
- A graph with `$partition` refs validates against the schema without error.
- A graph with a bare string for `scenes` fails validation.
