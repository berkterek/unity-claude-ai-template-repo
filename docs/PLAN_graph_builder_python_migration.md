# PLAN — Migrate graph-builder.sh to Python

> **Version:** v1 — 2026-06-09
> **Status:** Active
> **Scope:** `.claude/graph/graph-builder.py` (new), `.claude/graph/graph-builder.sh` (retired), `.claude/hooks/graph-auto-update.sh` (updated), `.claude/graph/graph-watch.sh` (updated)

**Complexity: 0.8 — Complex**

## Context

`graph-builder.sh` is a 533-line Bash+jq orchestrator that aggregates extractor output, manages a SHA256 file-hash cache, merges incremental and retained graph entries, runs inline Python heredocs for analysis, and writes an atomic `graph.json`. It has 47 `jq` calls — including an 18-argument `jq -n` final assembly at line 430 — making it fragile and difficult to extend. The current bug (lines 255–258: array merges via `jq -n` with shell-variable arguments) is a direct consequence of jq receiving oversized shell strings that exceed macOS's shell argument size limit.

The migration moves all orchestration, JSON manipulation, and cache logic into a single `graph-builder.py` file using Python's stdlib only. The four inline Python heredocs (event pivoting, interface resolution, path drift detection, missing-script detection) become first-class functions rather than subprocess-spawned heredocs. The two extractors (`csharp_extractor.py` and `asmdef-extractor.sh`) remain as subprocess calls with identical CLI contracts. The `jq` binary dependency is eliminated entirely.

Two shell files that invoke the builder — `graph-auto-update.sh` and `graph-watch.sh` — require line-level edits to swap `bash "$BUILDER"` for `python3 "$BUILDER_PY"`. Because `settings.json` is write-protected by `check-config-protection.sh`, no settings changes are required; the hook entries already reference `graph-auto-update.sh`, which is the file being updated. The original `graph-builder.sh` is retained with a deprecation comment — not deleted — to allow rollback during transition.

## Goals

- [ ] Eliminate jq dependency from graph-builder pipeline
- [ ] Fix array-merge bug caused by jq receiving oversized shell strings (current bug: lines 255–258)
- [ ] Preserve full CLI surface: `--full`, `--incremental`, `--changed-files`, `--skip-mcp`, `--output`, `--quiet`
- [ ] Preserve incremental cache semantics and atomic write guarantees
- [ ] Preserve all post-write module invocations (graph-traversal.py, graph_cluster.py, graph_analyze.py, graph_validate.py)
- [ ] Update hook callers (graph-auto-update.sh, graph-watch.sh) to invoke graph-builder.py
- [ ] Output graph.json that is schema-identical to current output (schema_version: "1.2.0", same top-level keys)

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | Task 1 — Core scaffold: CLI, logging, hashing, file scan, cache I/O | ⏳ Pending | — |
| 2 | Task 2 — Extractor invocation + incremental retain + ghost purge + merge | ⏳ Pending | — |
| 3 | Task 3 — Analysis functions (inline Python heredocs → functions) | ⏳ Pending | — |
| 4 | Task 4 — MCP cache handling | ⏳ Pending | — |
| 5 | Task 5 — Final assembly + atomic write + post-write modules + summary | ⏳ Pending | — |
| 6 | Task 6 — Hook updates (graph-auto-update.sh, graph-watch.sh) | ⏳ Pending | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/graph-builder.py` | Create | New orchestrator; replaces graph-builder.sh |
| `.claude/graph/graph-builder.sh` | Modify (deprecation comment only) | Add `# DEPRECATED: use graph-builder.py` at top; do NOT delete |
| `.claude/hooks/graph-auto-update.sh` | Modify | Swap BUILDER var and nohup call to python3 |
| `.claude/graph/graph-watch.sh` | Modify | Swap BUILDER path to graph-builder.py and update invocation |

---

## Task 1 — Core scaffold: CLI, logging, hashing, file scan, cache I/O

**Files:**
- `.claude/graph/graph-builder.py` (create)

**Steps:**
1. [ ] Add shebang `#!/usr/bin/env python3` and module docstring matching graph-builder.sh header.
2. [ ] Implement `parse_args()` using `argparse` with flags: `--full`/`--incremental` (mutually exclusive, default `incremental`), `--changed-files` (comma-separated), `--skip-mcp` (store_true), `--output` (default: `<script_dir>/graph.json`), `--quiet` (store_true).
3. [ ] Implement `log(msg, quiet)` — prints `graph-builder: {msg}` to stderr unless `quiet=True`.
4. [ ] Implement `hash_file(path) -> str` using `hashlib.sha256` with 64 KB read chunks. Replaces the `sha256sum`/`shasum` shell tool detection on lines 33–36.
5. [ ] Implement `read_unity_folder(repo_root) -> str` — reads `<repo_root>/.claude/project-features.json`, returns `unity_project_folder` field (stripped trailing slash, default `"."`). Use `subprocess.run(["git", "rev-parse", "--show-toplevel"])` to find repo root.
6. [ ] Implement `scan_files(assets_root, changed_files_str) -> tuple[list[str], list[str]]` — returns `(all_cs, all_asmdef)`. When `changed_files_str` is set, split on commas and classify by extension. Otherwise use `pathlib.Path.rglob` on Assets root.
7. [ ] Implement `load_hash_cache(cache_file) -> dict` — reads `file-hashes.json`; returns `{}` on missing/invalid.
8. [ ] Implement `save_hash_cache(cache_file, data)` — atomic write via `tempfile.NamedTemporaryFile` + `os.replace`.
9. [ ] Implement `select_changed(all_files, cache, mode) -> tuple[list[str], list[str], int, int]` — returns `(changed, current_paths, scanned_count, cache_hits)`. Changed when `mode=="full"` or sha256 differs from cache.
10. [ ] Wire all above into `main()` — initialize paths, `os.makedirs(cache_dir, exist_ok=True)`, ensure `graph.json` exists as `{}` if absent.

**Test Type:** NoTest

**Code Skeleton:**
```python
#!/usr/bin/env python3
"""graph-builder.py — Aggregates extractor output + SHA256 cache → graph.json"""
import argparse, hashlib, json, os, pathlib, subprocess, sys, tempfile, time

SCRIPT_DIR = pathlib.Path(__file__).parent

def parse_args():
    p = argparse.ArgumentParser()
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--full", dest="mode", action="store_const", const="full")
    mode.add_argument("--incremental", dest="mode", action="store_const", const="incremental")
    p.set_defaults(mode="incremental")
    p.add_argument("--changed-files", default="")
    p.add_argument("--skip-mcp", action="store_true")
    p.add_argument("--output", default=str(SCRIPT_DIR / "graph.json"))
    p.add_argument("--quiet", action="store_true")
    return p.parse_args()

def log(msg, quiet=False):
    if not quiet:
        print(f"graph-builder: {msg}", file=sys.stderr)

def hash_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def load_hash_cache(cache_file: str) -> dict:
    try:
        with open(cache_file) as f:
            return json.load(f)
    except Exception:
        return {}

def save_hash_cache(cache_file: str, data: dict):
    d = os.path.dirname(cache_file) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp, cache_file)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def select_changed(all_files, cache, mode):
    changed, current_paths = [], []
    scanned = cache_hits = 0
    for f in all_files:
        if not os.path.isfile(f):
            continue
        current_paths.append(f)
        scanned += 1
        cur = hash_file(f)
        if mode == "full" or cur != cache.get(f, ""):
            changed.append(f)
        else:
            cache_hits += 1
    return changed, current_paths, scanned, cache_hits
```

**Acceptance Criteria:**
- `python3 .claude/graph/graph-builder.py --help` prints all six flags without error.
- `python3 .claude/graph/graph-builder.py --full --skip-mcp --quiet` exits 0 and writes valid JSON to output path.
- `.claude/graph/cache/file-hashes.json` is created after first run.

---

## Task 2 — Extractor invocation + incremental retain + ghost purge + merge

**Files:**
- `.claude/graph/graph-builder.py` (extend)

**Steps:**
1. [ ] Implement `run_csharp_extractor(changed_cs, script_dir, quiet) -> dict` — subprocess call to `csharp_extractor.py --changed-files <csv>` (prefer `.py`; fall back to `csharp-extractor.sh`). Returns `EMPTY_CS` dict on failure or empty input.
2. [ ] Implement `run_asmdef_extractor(changed_asmdef, script_dir, quiet) -> list` — subprocess call to `asmdef-extractor.sh --changed-files <csv>`. Returns `[]` on failure.
3. [ ] Implement `retain_entries(existing_graph, reextracted_files, mode) -> dict` — in `full` mode returns empty lists; in `incremental` filters each array to keep entries whose `source_file` is NOT in `reextracted_files`. Replaces lines 209–221 (4 jq calls).
4. [ ] Implement `purge_ghosts(entries, current_paths)` — filters out entries whose `source_file` is not in `current_paths`. When `current_paths` is empty, returns unchanged (no files scanned ≠ all files deleted). Replaces lines 232–246.
5. [ ] Implement `merge_arrays(*arrays) -> list` — `sum(arrays, [])`.
6. [ ] Implement `merge_call_edges(existing_calls, new_partial_calls, changed_cs, mode) -> list` — 3-branch: incremental-with-changes drops old edges for changed files + appends new; full-mode uses new only; no-changes retains existing. Replaces lines 261–276.

**Test Type:** NoTest

**Code Skeleton:**
```python
EMPTY_CS = {"classes":[],"interfaces":[],"events":[],
            "vcontainer":{"installers":[],"scopes":[]},"partial_calls":[]}

def run_csharp_extractor(changed_cs, script_dir, quiet):
    if not changed_cs:
        return EMPTY_CS
    py_ex = script_dir / "extractors" / "csharp_extractor.py"
    sh_ex = script_dir / "extractors" / "csharp-extractor.sh"
    csv = ",".join(changed_cs)
    cmd = ["python3", str(py_ex), "--changed-files", csv] if py_ex.exists() \
          else ["bash", str(sh_ex), "--changed-files", csv] if sh_ex.exists() \
          else None
    if not cmd:
        return EMPTY_CS
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return json.loads(r.stdout) if r.stdout.strip() else EMPTY_CS
    except Exception:
        return EMPTY_CS

def retain_entries(existing_graph, reextracted_files, mode):
    if mode == "full":
        return {"classes":[],"interfaces":[],"assemblies":[],"installers":[]}
    re_set = set(reextracted_files)
    cb = existing_graph.get("codebase", {})
    def keep(arr): return [e for e in arr if e.get("source_file") not in re_set]
    return {
        "classes":    keep(cb.get("classes", [])),
        "interfaces": keep(cb.get("interfaces", [])),
        "assemblies": keep(cb.get("assemblies", [])),
        "installers": keep((cb.get("vcontainer") or {}).get("installers", [])),
    }

def purge_ghosts(entries, current_paths):
    if not current_paths:
        return entries
    path_set = set(current_paths)
    return [e for e in entries if e.get("source_file") is None
            or e["source_file"] in path_set]
```

**Acceptance Criteria:**
- Incremental run with one changed file retains all entries from unchanged files.
- Full run produces empty retained lists (all files re-extracted).
- Ghost purge removes entries for files no longer on disk without removing entries with `source_file: null`.
- `merge_call_edges` in incremental mode drops old edges for the changed file and adds new partial_calls.

---

## Task 3 — Analysis functions (inline Python heredocs → proper functions)

**Files:**
- `.claude/graph/graph-builder.py` (extend)

**Steps:**
1. [ ] Implement `event_pivot(classes) -> list` — port of lines 279–303 heredoc. Iterate merged classes, build events dict keyed by event name, accumulate publishers/subscribers. Return `list(events.values())`.
2. [ ] Implement `resolve_implementers(interfaces, classes) -> list` — port of lines 307–322. Build iface_map, iterate classes, append class name to matching interface's `implementers`. Return updated interface list.
3. [ ] Implement `scope_merge(retained_scopes, new_scopes, mcp_scope_parents) -> list` — port of lines 328–343. Merge retained + new (new wins on name conflict), backfill `.parent` from mcp_scope_parents list of `{scope_name, parent_name}` dicts.
4. [ ] Implement `check_path_drift(prefabs, unity_folder, quiet) -> list` — port of lines 349–368. Returns `{"code":"STALE_PREFAB_PATH", "message":..., "entity":...}` dicts. Logs warning when drift found.
5. [ ] Implement `check_missing_scripts(scenes, prefabs) -> list` — port of lines 377–411. Recursive `_check_go()` walker on `children`. Handles both `gameObjects` and `gameobjects` key spellings. Returns `{"code":"MISSING_SCRIPT", ...}` dicts.

**Test Type:** NoTest

**Code Skeleton:**
```python
def event_pivot(classes):
    events = {}
    for cls in classes:
        for ev in cls.get("events_published", []):
            e = events.setdefault(ev, {"name": ev, "file": cls.get("file",""),
                "source_file": cls.get("file",""), "publishers": [], "subscribers": [],
                "confidence": cls.get("confidence","INFERRED")})
            if cls["name"] not in e["publishers"]:
                e["publishers"].append(cls["name"])
        for ev in cls.get("events_subscribed", []):
            e = events.setdefault(ev, {"name": ev, "file": cls.get("file",""),
                "source_file": cls.get("file",""), "publishers": [], "subscribers": [],
                "confidence": cls.get("confidence","INFERRED")})
            if cls["name"] not in e["subscribers"]:
                e["subscribers"].append(cls["name"])
    return list(events.values())

def resolve_implementers(interfaces, classes):
    iface_map = {i["name"]: i for i in interfaces}
    for cls in classes:
        for impl in cls.get("implements", []):
            if impl in iface_map:
                imps = iface_map[impl].setdefault("implementers", [])
                if cls["name"] not in imps:
                    imps.append(cls["name"])
    return list(iface_map.values())

def scope_merge(retained_scopes, new_scopes, mcp_scope_parents):
    by_name = {s["name"]: s for s in retained_scopes}
    for s in new_scopes:
        by_name[s["name"]] = s
    scopes = list(by_name.values())
    if mcp_scope_parents:
        parent_map = {p["scope_name"]: p["parent_name"] for p in mcp_scope_parents}
        for s in scopes:
            if s["name"] in parent_map:
                s["parent"] = parent_map[s["name"]]
    return scopes
```

**Acceptance Criteria:**
- `event_pivot` on a class with `events_published=["RunStarted"]` returns one entry with that class in `publishers`.
- `resolve_implementers` appends class name to matching interface's `implementers` list.
- `scope_merge` deduplicates by name (new wins) and backfills `.parent` from MCP data.
- `check_path_drift` returns empty list when all prefab paths exist on disk.
- `check_missing_scripts` returns `MISSING_SCRIPT` warnings when a component name is `null`.

---

## Task 4 — MCP cache handling

**Files:**
- `.claude/graph/graph-builder.py` (extend)

**Steps:**
1. [ ] Implement `read_json_safe(path, default)` — loads JSON from path; returns `default` on any exception. Used throughout for safe reads.
2. [ ] Implement `mcp_age_minutes(path) -> int` — `int((time.time() - os.path.getmtime(path)) / 60)`. Returns `9999` on error.
3. [ ] Implement `load_mcp_cache(mcp_cache_path, output_path, mode, skip_mcp, quiet) -> dict` — 3-branch logic mirroring lines 155–189:
   - `skip_mcp=True` → retain scenes/prefabs from existing graph.json, status `"skipped"`, reason `"SKIP_MCP_FLAG"`
   - File missing → empty arrays, status `"skipped"`, reason `"MCP_UNAVAILABLE"`
   - File present + age < 60min + mode != "full" → read from mcp file, status `"ok"`
   - File present + stale or mode=="full" → fallback to existing graph.json scenes/prefabs, status `"retained"`
4. [ ] Implement `build_mcp_meta(mcp_result) -> dict` — builds the `mcp_extraction` sub-dict matching lines 421–428.

**Test Type:** NoTest

**Code Skeleton:**
```python
def mcp_age_minutes(path):
    try:
        return int((time.time() - os.path.getmtime(path)) / 60)
    except Exception:
        return 9999

def read_json_safe(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default

def load_mcp_cache(mcp_cache_path, output_path, mode, skip_mcp, quiet):
    existing = read_json_safe(output_path, {})
    cb = existing.get("codebase", {})
    fallback_scenes  = cb.get("scenes", [])
    fallback_prefabs = cb.get("prefabs", [])

    if skip_mcp:
        return {"status":"skipped","scenes":fallback_scenes,"prefabs":fallback_prefabs,
                "scope_parents":[],"extracted_at":None,"skip_reason":"SKIP_MCP_FLAG"}
    if not os.path.exists(mcp_cache_path):
        return {"status":"skipped","scenes":[],"prefabs":[],"scope_parents":[],
                "extracted_at":None,"skip_reason":"MCP_UNAVAILABLE"}

    age = mcp_age_minutes(mcp_cache_path)
    mcp = read_json_safe(mcp_cache_path, {})
    if age < 60 and mode != "full":
        log(f"mcp cache reused ({age}m old)", quiet)
        return {"status":"ok","scenes":mcp.get("scenes",[]),"prefabs":mcp.get("prefabs",[]),
                "scope_parents":mcp.get("scope_parents",[]),
                "extracted_at":mcp.get("extracted_at"),"skip_reason":None}
    pcount = len(fallback_prefabs)
    log(f"mcp cache stale ({age}m old) — retaining {pcount} prefabs from existing graph; run /build-knowledge-graph to refresh", quiet)
    return {"status":"retained","scenes":fallback_scenes,"prefabs":fallback_prefabs,
            "scope_parents":mcp.get("scope_parents",[]),
            "extracted_at":mcp.get("extracted_at"),"skip_reason":None}
```

**Acceptance Criteria:**
- `--skip-mcp`: scenes/prefabs from existing graph.json, status `"skipped"`.
- Missing mcp file: empty arrays, status `"skipped"`.
- Fresh mcp file (< 60min) + incremental: status `"ok"`, data from mcp file.
- Stale mcp file or `--full`: status `"retained"`, fallback to existing graph.json scenes/prefabs.

---

## Task 5 — Final assembly + atomic write + post-write modules + summary

**Files:**
- `.claude/graph/graph-builder.py` (extend — complete `main()`)

**Steps:**
1. [ ] Implement `get_git_sha() -> str` — `subprocess.run(["git","rev-parse","--short","HEAD"])` with fallback `"unknown"`.
2. [ ] Implement `assemble_graph(classes, interfaces, events, installers, scopes, assemblies, scenes, prefabs, mcp_meta, calls, stale_warnings, missing_warnings, scanned, cache_hits, build_ms, git_sha) -> dict` — builds final dict with `schema_version:"1.2.0"`, `generator:"graph-builder.py@{sha}"`, all nested arrays, stats block. Field order must match existing schema (same keys as current graph.json).
3. [ ] Implement `atomic_write_json(data, output_path)` — write via `tempfile.NamedTemporaryFile(dir=..., suffix=".tmp", delete=False)`, validate with `json.loads(open(tmp).read())`, then `os.replace(tmp, output_path)`. On failure: unlink tmp, raise.
4. [ ] Implement `update_hash_cache(cache, all_files) -> dict` — iterate `all_files`, compute `hash_file(f)` for existing files, update cache, return updated dict. Call `save_hash_cache` after.
5. [ ] Implement `run_post_module(script_path, extra_args, quiet)` — `subprocess.run(["python3", str(script_path)] + extra_args, check=False)`. Non-fatal on error; log warning.
6. [ ] In `main()`, after atomic write, call in order:
   - `graph-traversal.py --finalize-calls --graph <output>`
   - `graph_cluster.py --graph <output>`
   - `graph_analyze.py --graph <output>`
   - `graph_validate.py --graph <output> --sample 20`
7. [ ] Write `.last-build` file: `open(SCRIPT_DIR / ".last-build", "w").write(now_iso)`.
8. [ ] Implement `print_summary(output_path, class_count, event_count, installer_count, cache_hits, scanned, build_ms, quiet)` — read call/community counts from written graph.json via `read_json_safe`, print summary line to stderr.

**Test Type:** NoTest

**Code Skeleton:**
```python
def assemble_graph(classes, interfaces, events, installers, scopes, assemblies,
                   scenes, prefabs, mcp_meta, calls, stale_warnings, missing_warnings,
                   scanned, cache_hits, build_ms, git_sha):
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "schema_version": "1.2.0",
        "generated_at": now,
        "generator": f"graph-builder.py@{git_sha}",
        "confidence_legend": {
            "EXTRACTED": "Explicit machine-readable data (asmdef JSON, tree-sitter AST)",
            "INFERRED":  "Derived from regex patterns — correct on common cases, may miss edge cases",
            "AMBIGUOUS": "Conflicting signals — needs human review",
        },
        "codebase": {
            "classes": classes, "interfaces": interfaces, "events": events,
            "vcontainer": {"installers": installers, "scopes": scopes},
            "assemblies": assemblies, "scenes": scenes, "prefabs": prefabs,
            "mcp_extraction": mcp_meta, "calls": calls,
        },
        "validation": {"errors": [], "warnings": stale_warnings + missing_warnings},
        "stats": {"scanned_files": scanned, "cache_hits": cache_hits, "build_ms": build_ms},
    }

def atomic_write_json(data, output_path):
    d = os.path.dirname(os.path.abspath(output_path))
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        json.loads(open(tmp).read())  # validate
        os.replace(tmp, output_path)
    except Exception:
        try: os.unlink(tmp)
        except OSError: pass
        raise
```

**Acceptance Criteria:**
- `python3 .claude/graph/graph-builder.py --full --skip-mcp` writes `graph.json` with `schema_version:"1.2.0"` and all top-level keys.
- `generator` field starts with `"graph-builder.py@"`.
- `python3 -c "import json; json.load(open('.claude/graph/graph.json'))"` passes without error.
- Post-write modules are called; individual failure is non-fatal (overall exit 0).
- `.claude/graph/.last-build` is written.
- Summary line printed to stderr unless `--quiet`.

---

## Task 6 — Hook updates

**Files:**
- `.claude/hooks/graph-auto-update.sh` (modify)
- `.claude/graph/graph-watch.sh` (modify)

**Steps:**
1. [ ] In `graph-auto-update.sh`: read the file to find the `BUILDER=` line. Change its value from `graph-builder.sh` path to `graph-builder.py` path. Change the existence check from `-x` to `-f`. Update the `nohup bash "$BUILDER"` invocation to `nohup python3 "$BUILDER"`.
2. [ ] In `graph-watch.sh`: read the full file first. **Rename** the `BUILDER` variable to `BUILDER_PY` everywhere it appears (declaration on line 9 + all uses on lines 11, 12, and the trigger invocation). Change the path value from `graph-builder.sh` to `graph-builder.py`. Change existence check from `-x` to `-f`. Change invocation from `bash "$BUILDER"` to `python3 "$BUILDER_PY"`. Update the "not found" error message to reference `BUILDER_PY`.
3. [ ] Add deprecation comment at top of `graph-builder.sh`: `# DEPRECATED: use graph-builder.py — this file is retained for rollback only`.
4. [ ] Verify: `grep -r "graph-builder" .claude/hooks/ .claude/graph/graph-watch.sh` shows only `.py` references (except the deprecation comment in `.sh`).

**Test Type:** NoTest

**Acceptance Criteria:**
- `grep "graph-builder" .claude/hooks/graph-auto-update.sh` shows `.py`, not `.sh` in the command.
- `grep "graph-builder" .claude/graph/graph-watch.sh` shows `.py` references for invocations.
- `graph-builder.sh` has deprecation comment at top and is NOT deleted.
- Manual run: `python3 .claude/graph/graph-builder.py --full --skip-mcp` completes, then trigger a file edit — confirm `graph-auto-update.sh` background process spawns the `.py` builder.

---

## Transition Strategy

During implementation (Tasks 1–5), `graph-builder.sh` remains the active builder. Only after Task 5 is complete and `python3 .claude/graph/graph-builder.py --full --skip-mcp` runs successfully should Task 6 (hook updates) be executed.

**Rollback:** If `graph-builder.py` produces incorrect output, revert `graph-auto-update.sh` and `graph-watch.sh` to point back to `graph-builder.sh`. The `.sh` file is never deleted.
