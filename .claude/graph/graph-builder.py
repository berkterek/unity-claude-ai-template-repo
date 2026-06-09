#!/usr/bin/env python3
"""graph-builder.py — Aggregates extractor output + SHA256 cache → graph.json

Usage:
  graph-builder.py [--full] [--incremental] [--changed-files a.cs,b.asmdef]
                   [--skip-mcp] [--output path/to/graph.json] [--quiet]

Replaces graph-builder.sh — pure Python stdlib, no jq dependency.
"""

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time


SCRIPT_DIR = pathlib.Path(__file__).parent.resolve()
EMPTY_CS = {
    "classes": [],
    "interfaces": [],
    "events": [],
    "vcontainer": {"installers": [], "scopes": []},
    "partial_calls": [],
}


# ── CLI / logging ────────────────────────────────────────────────────────────


def parse_args():
    p = argparse.ArgumentParser(
        prog="graph-builder.py",
        description="Aggregates extractor output + SHA256 cache → graph.json",
    )
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--full", dest="mode", action="store_const", const="full")
    mode.add_argument(
        "--incremental", dest="mode", action="store_const", const="incremental"
    )
    p.set_defaults(mode="incremental")
    p.add_argument("--changed-files", default="")
    p.add_argument("--skip-mcp", action="store_true")
    p.add_argument("--output", default=str(SCRIPT_DIR / "graph.json"))
    p.add_argument("--quiet", action="store_true")
    return p.parse_args()


def log(msg, quiet=False):
    if quiet:
        return
    print(f"graph-builder: {msg}", file=sys.stderr)


# ── Hashing / cache I/O ──────────────────────────────────────────────────────


def hash_file(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
    except OSError:
        return ""
    return h.hexdigest()


def load_hash_cache(cache_file, quiet=False):
    try:
        with open(cache_file) as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception as e:
        log(f"load_hash_cache failed ({cache_file}): {e}", quiet)
        return {}


def save_hash_cache(cache_file, data):
    d = os.path.dirname(cache_file) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        os.replace(tmp, cache_file)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_json_safe(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except Exception as e:
        log(f"read_json_safe failed ({path}): {e}")
        return default


# ── Project layout ───────────────────────────────────────────────────────────


def get_repo_root():
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except Exception as e:
        log(f"git rev-parse failed: {e}")
        return os.getcwd()
    return os.getcwd()


def read_unity_folder(repo_root):
    features = os.path.join(repo_root, ".claude", "project-features.json")
    data = read_json_safe(features, {})
    folder = data.get("unity_project_folder", ".")
    if not isinstance(folder, str) or not folder:
        return "."
    return folder.rstrip("/")


def get_git_sha():
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except Exception:
        pass
    return "unknown"


# ── File scanning ────────────────────────────────────────────────────────────


def scan_files(assets_root, changed_files_str):
    all_cs = []
    all_asmdef = []

    if changed_files_str:
        for f in changed_files_str.split(","):
            f = f.strip()
            if not f:
                continue
            if f.endswith(".cs"):
                all_cs.append(f)
            elif f.endswith(".asmdef"):
                all_asmdef.append(f)
        return all_cs, all_asmdef

    roots_cs = [
        os.path.join(assets_root, "_Framework"),
        os.path.join(assets_root, "_GameFolders", "Scripts"),
    ]
    for root in roots_cs:
        if not os.path.isdir(root):
            continue
        for p in pathlib.Path(root).rglob("*.cs"):
            all_cs.append(str(p))

    if os.path.isdir(assets_root):
        for p in pathlib.Path(assets_root).rglob("*.asmdef"):
            all_asmdef.append(str(p))

    return all_cs, all_asmdef


def select_changed(all_files, cache, mode):
    changed = []
    current_paths = []
    scanned = 0
    cache_hits = 0
    for f in all_files:
        if not f:
            continue
        if not os.path.isfile(f):
            # Track as scanned for ghost-purge accounting, but skip hashing.
            current_paths.append(f)
            scanned += 1
            continue
        current_paths.append(f)
        scanned += 1
        cur = hash_file(f)
        if mode == "full" or cur != cache.get(f, ""):
            changed.append(f)
        else:
            cache_hits += 1
    return changed, current_paths, scanned, cache_hits


# ── Extractor invocation ─────────────────────────────────────────────────────


def run_csharp_extractor(changed_cs, script_dir, quiet):
    if not changed_cs:
        return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []})
    py_ex = script_dir / "extractors" / "csharp_extractor.py"
    sh_ex = script_dir / "extractors" / "csharp-extractor.sh"
    csv = ",".join(changed_cs)
    # Try Python (tree-sitter) extractor first; fall back to shell on exit 2 (unavailable)
    cmds = []
    if py_ex.exists():
        cmds.append(("python3", ["python3", str(py_ex), "--changed-files", csv]))
    if sh_ex.exists():
        cmds.append(("bash", ["bash", str(sh_ex), "--changed-files", csv]))
    if not cmds:
        log("csharp extractor not found — using empty result", quiet)
        return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []})

    for label, cmd in cmds:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if r.returncode == 2 and label == "python3":
                log("csharp_extractor.py: tree-sitter unavailable — falling back to shell extractor", quiet)
                continue
            if r.returncode != 0:
                log(f"csharp extractor ({label}) exited {r.returncode}: {r.stderr.strip()}", quiet)
            if r.stdout and r.stdout.strip():
                return json.loads(r.stdout)
        except Exception as e:
            log(f"csharp extractor ({label}) failed: {e}", quiet)
    return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []})


def run_asmdef_extractor(changed_asmdef, script_dir, quiet):
    if not changed_asmdef:
        return []
    sh_ex = script_dir / "extractors" / "asmdef-extractor.sh"
    if not sh_ex.exists():
        log("asmdef extractor not found — using empty result", quiet)
        return []
    csv = ",".join(changed_asmdef)
    try:
        r = subprocess.run(
            ["bash", str(sh_ex), "--changed-files", csv],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if r.returncode != 0:
            log(f"asmdef extractor exited {r.returncode}: {r.stderr.strip()}", quiet)
        if r.stdout and r.stdout.strip():
            data = json.loads(r.stdout)
            return data if isinstance(data, list) else []
    except Exception as e:
        log(f"asmdef extractor failed: {e}", quiet)
    return []


# ── Retain / purge / merge ───────────────────────────────────────────────────


def retain_entries(existing_graph, reextracted_files, mode):
    if mode == "full":
        return {
            "classes": [],
            "interfaces": [],
            "assemblies": [],
            "installers": [],
        }
    re_set = set(reextracted_files)
    cb = existing_graph.get("codebase", {}) or {}
    vc = cb.get("vcontainer") or {}

    def keep(arr):
        out = []
        for e in arr or []:
            sf = e.get("source_file")
            if sf not in re_set:
                out.append(e)
        return out

    return {
        "classes": keep(cb.get("classes", [])),
        "interfaces": keep(cb.get("interfaces", [])),
        "assemblies": keep(cb.get("assemblies", [])),
        "installers": keep(vc.get("installers", [])),
    }


def purge_ghosts(entries, current_paths):
    if not current_paths:
        return entries
    path_set = set(current_paths)
    out = []
    for e in entries:
        sf = e.get("source_file")
        if sf is None or sf in path_set:
            out.append(e)
    return out


def merge_arrays(*arrays):
    result = []
    for a in arrays:
        if a:
            result.extend(a)
    return result


def merge_call_edges(existing_calls, new_partial_calls, changed_cs, mode):
    if mode == "incremental" and changed_cs:
        changed_set = set(changed_cs)
        retained = [
            c
            for c in (existing_calls or [])
            if c.get("caller_file") not in changed_set
            and c.get("callee_file") not in changed_set
        ]
        return retained + list(new_partial_calls or [])
    if mode == "full":
        return list(new_partial_calls or [])
    # incremental with no changes
    return list(existing_calls or [])


# ── Analysis (formerly inline Python heredocs) ───────────────────────────────


def event_pivot(classes):
    events = {}
    for cls in classes:
        cname = cls.get("name", "")
        cfile = cls.get("file", "")
        cconf = cls.get("confidence", "INFERRED")
        for ev in cls.get("events_published", []) or []:
            e = events.setdefault(
                ev,
                {
                    "name": ev,
                    "file": cfile,
                    "source_file": cfile,
                    "publishers": [],
                    "subscribers": [],
                    "confidence": cconf,
                },
            )
            if cname and cname not in e["publishers"]:
                e["publishers"].append(cname)
        for ev in cls.get("events_subscribed", []) or []:
            e = events.setdefault(
                ev,
                {
                    "name": ev,
                    "file": cfile,
                    "source_file": cfile,
                    "publishers": [],
                    "subscribers": [],
                    "confidence": cconf,
                },
            )
            if cname and cname not in e["subscribers"]:
                e["subscribers"].append(cname)
    return list(events.values())


def resolve_implementers(interfaces, classes):
    iface_map = {i["name"]: i for i in interfaces if i.get("name")}
    for cls in classes:
        cname = cls.get("name")
        if not cname:
            continue
        for impl in cls.get("implements", []) or []:
            if impl in iface_map:
                imps = iface_map[impl].setdefault("implementers", [])
                if cname not in imps:
                    imps.append(cname)
    return list(iface_map.values())


def scope_merge(retained_scopes, new_scopes, mcp_scope_parents):
    by_name = {}
    for s in retained_scopes or []:
        name = s.get("name")
        if name:
            by_name[name] = s
    for s in new_scopes or []:
        name = s.get("name")
        if name:
            by_name[name] = s
    scopes = list(by_name.values())
    if mcp_scope_parents:
        parent_map = {
            p["scope_name"]: p["parent_name"]
            for p in mcp_scope_parents
            if p.get("scope_name") and p.get("parent_name")
        }
        for s in scopes:
            if s.get("name") in parent_map:
                s["parent"] = parent_map[s["name"]]
    return scopes


def check_path_drift(prefabs, unity_folder, repo_root, quiet):
    warnings = []
    for p in prefabs or []:
        path = p.get("path", "")
        if not path:
            continue
        if unity_folder == ".":
            disk_path = os.path.join(repo_root, path)
        else:
            disk_path = os.path.join(repo_root, unity_folder, path)
        if not os.path.exists(disk_path):
            warnings.append(
                {
                    "code": "STALE_PREFAB_PATH",
                    "message": "Prefab path no longer exists on disk: " + path,
                    "entity": p.get("name", "?"),
                }
            )
    if warnings and not quiet:
        log(
            "STALE_PREFAB_PATH — "
            + str(len(warnings))
            + " stale prefab(s) detected. Run /build-knowledge-graph with MCP to refresh.",
            quiet,
        )
    return warnings


def check_missing_scripts(scenes, prefabs, quiet):
    warnings = []

    def is_missing(component):
        if not isinstance(component, dict):
            return False
        name = component.get("name")
        return name is None or name == ""

    def check_go(go, scene_name, path=""):
        if not isinstance(go, dict):
            return
        go_name = go.get("name", "?")
        full_path = (path + "/" + go_name) if path else go_name
        has_flag = go.get("has_missing_scripts")
        has_null_comp = any(
            is_missing(c) for c in go.get("components", []) or []
        )
        if has_flag or has_null_comp:
            warnings.append(
                {
                    "code": "MISSING_SCRIPT",
                    "message": "Null component (missing/deleted script) on: "
                    + full_path
                    + " in scene: "
                    + scene_name,
                    "entity": go_name,
                    "scene": scene_name,
                }
            )
        for child in go.get("children", []) or []:
            check_go(child, scene_name, full_path)

    for scene in scenes or []:
        scene_name = scene.get("name", "?")
        for go in scene.get("gameObjects", scene.get("gameobjects", [])) or []:
            check_go(go, scene_name)

    for prefab in prefabs or []:
        if prefab.get("has_missing_scripts"):
            warnings.append(
                {
                    "code": "MISSING_SCRIPT",
                    "message": "Null component (missing/deleted script) on prefab: "
                    + prefab.get("path", prefab.get("name", "?")),
                    "entity": prefab.get("name", "?"),
                }
            )

    if warnings and not quiet:
        log(
            "MISSING_SCRIPT — " + str(len(warnings)) + " missing script(s) detected.",
            quiet,
        )
    return warnings


# ── MCP cache ────────────────────────────────────────────────────────────────


def mcp_age_minutes(path):
    try:
        return int((time.time() - os.path.getmtime(path)) / 60)
    except Exception:
        return 9999


def load_mcp_cache(mcp_cache_path, output_path, mode, skip_mcp, quiet):
    existing = read_json_safe(output_path, {})
    cb = existing.get("codebase", {}) if isinstance(existing, dict) else {}
    fallback_scenes = cb.get("scenes", []) if isinstance(cb, dict) else []
    fallback_prefabs = cb.get("prefabs", []) if isinstance(cb, dict) else []

    if skip_mcp:
        return {
            "status": "skipped",
            "scenes": fallback_scenes,
            "prefabs": fallback_prefabs,
            "scope_parents": [],
            "extracted_at": None,
            "skip_reason": "SKIP_MCP_FLAG",
        }

    if not os.path.exists(mcp_cache_path):
        return {
            "status": "skipped",
            "scenes": [],
            "prefabs": [],
            "scope_parents": [],
            "extracted_at": None,
            "skip_reason": "MCP_UNAVAILABLE",
        }

    age = mcp_age_minutes(mcp_cache_path)
    mcp = read_json_safe(mcp_cache_path, {})
    if not isinstance(mcp, dict):
        mcp = {}

    if age < 60 and mode != "full":
        log(f"mcp cache reused ({age}m old)", quiet)
        return {
            "status": "ok",
            "scenes": mcp.get("scenes", []) or [],
            "prefabs": mcp.get("prefabs", []) or [],
            "scope_parents": mcp.get("scope_parents", []) or [],
            "extracted_at": mcp.get("extracted_at"),
            "skip_reason": None,
        }

    pcount = len(fallback_prefabs)
    log(
        f"mcp cache stale ({age}m old) — retaining {pcount} prefabs from existing graph; run /build-knowledge-graph to refresh",
        quiet,
    )
    return {
        "status": "retained",
        "scenes": fallback_scenes,
        "prefabs": fallback_prefabs,
        "scope_parents": mcp.get("scope_parents", []) or [],
        "extracted_at": mcp.get("extracted_at"),
        "skip_reason": None,
    }


def build_mcp_meta(mcp_result):
    status = mcp_result.get("status", "skipped")
    extracted_at = mcp_result.get("extracted_at")
    if status == "ok":
        return {"status": "ok", "extracted_at": extracted_at}
    if status == "retained":
        return {
            "status": "retained",
            "note": "stale cache — prefabs retained from previous extraction",
            "extracted_at": extracted_at,
        }
    return {
        "status": "skipped",
        "skipped_reason": mcp_result.get("skip_reason") or "MCP_UNAVAILABLE",
    }


# ── Final assembly + atomic write ────────────────────────────────────────────


def assemble_graph(
    classes,
    interfaces,
    events,
    installers,
    scopes,
    assemblies,
    scenes,
    prefabs,
    mcp_meta,
    calls,
    stale_warnings,
    missing_warnings,
    scanned,
    cache_hits,
    build_ms,
    git_sha,
):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "schema_version": "1.2.0",
        "generated_at": now,
        "generator": f"graph-builder.py@{git_sha}",
        "confidence_legend": {
            "EXTRACTED": "Explicit machine-readable data (asmdef JSON, tree-sitter AST)",
            "INFERRED": "Derived from regex patterns — correct on common cases, may miss edge cases",
            "AMBIGUOUS": "Conflicting signals — needs human review",
        },
        "codebase": {
            "classes": classes,
            "interfaces": interfaces,
            "events": events,
            "vcontainer": {"installers": installers, "scopes": scopes},
            "assemblies": assemblies,
            "scenes": scenes,
            "prefabs": prefabs,
            "mcp_extraction": mcp_meta,
            "calls": calls,
        },
        "validation": {
            "errors": [],
            "warnings": list(stale_warnings or []) + list(missing_warnings or []),
        },
        "stats": {
            "scanned_files": scanned,
            "cache_hits": cache_hits,
            "build_ms": build_ms,
            "call_count": len(calls or []),
        },
    }


def atomic_write_json(data, output_path):
    d = os.path.dirname(os.path.abspath(output_path)) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
        # validate
        with open(tmp) as f:
            json.load(f)
        os.replace(tmp, output_path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def update_hash_cache(cache, all_files):
    updated = dict(cache)
    for f in all_files:
        if not f or not os.path.isfile(f):
            continue
        h = hash_file(f)
        if h:
            updated[f] = h
    return updated


# ── Post-write modules ───────────────────────────────────────────────────────


def run_post_module(script_path, extra_args, quiet):
    name = os.path.basename(script_path)
    if not os.path.isfile(script_path):
        log(f"{name} not found (non-fatal)", quiet)
        return
    cmd = ["python3", str(script_path)] + list(extra_args)
    try:
        if quiet:
            r = subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            if r.returncode != 0:
                log(f"{name} failed (non-fatal): {r.stderr.strip()}", False)
        else:
            r = subprocess.run(cmd, check=False)
            if r.returncode != 0:
                log(f"{name} failed (non-fatal)", quiet)
    except Exception as e:
        log(f"{name} crashed (non-fatal): {e}", quiet)


# ── Summary ──────────────────────────────────────────────────────────────────


def print_summary(
    output_path,
    class_count,
    method_count,
    event_count,
    installer_count,
    cache_hits,
    scanned,
    build_ms,
    quiet,
):
    if quiet:
        return
    g = read_json_safe(output_path, {})
    cb = g.get("codebase", {}) if isinstance(g, dict) else {}
    val = g.get("validation", {}) if isinstance(g, dict) else {}
    call_count = len(cb.get("calls", []) or [])
    comm_count = len(cb.get("communities", []) or [])
    accuracy = (val.get("accuracy") or {}).get("agreement_pct", "n/a")
    reparsed = max(0, scanned - cache_hits)
    log(
        f"graph: {class_count} classes ({method_count} methods), {event_count} events, "
        f"{installer_count} installers, {call_count} call edges, {comm_count} communities, "
        f"{accuracy}% accuracy ({cache_hits} cached, {reparsed} reparsed) in {build_ms}ms",
        quiet,
    )


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    args = parse_args()
    start_ms = int(time.time() * 1000)
    quiet = args.quiet

    repo_root = get_repo_root()
    unity_folder = read_unity_folder(repo_root)
    assets_root = "Assets" if unity_folder == "." else f"{unity_folder}/Assets"

    cache_dir = SCRIPT_DIR / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = str(cache_dir / "file-hashes.json")
    mcp_cache = str(cache_dir / "mcp-extract.json")
    last_build_file = str(SCRIPT_DIR / ".last-build")
    output_path = args.output

    # Initialize files if missing
    if not os.path.isfile(cache_file):
        save_hash_cache(cache_file, {})
    if not os.path.isfile(output_path):
        atomic_write_json({}, output_path)

    # ── Scan files
    all_cs, all_asmdef = scan_files(assets_root, args.changed_files)
    cache = load_hash_cache(cache_file, quiet)

    changed_cs, cs_paths, scanned_cs, hits_cs = select_changed(
        all_cs, cache, args.mode
    )
    changed_asmdef, asm_paths, scanned_asm, hits_asm = select_changed(
        all_asmdef, cache, args.mode
    )

    scanned = scanned_cs + scanned_asm
    cache_hits = hits_cs + hits_asm
    current_paths = cs_paths + asm_paths

    log(
        f"scan: {scanned} files, {cache_hits} cache hits, "
        f"{len(changed_cs) + len(changed_asmdef)} to re-extract",
        quiet,
    )

    # ── Run extractors
    if changed_cs:
        log(f"running csharp-extractor on {len(changed_cs)} files…", quiet)
    cs_output = run_csharp_extractor(changed_cs, SCRIPT_DIR, quiet)

    if changed_asmdef:
        log(f"running asmdef-extractor on {len(changed_asmdef)} files…", quiet)
    asmdef_output = run_asmdef_extractor(changed_asmdef, SCRIPT_DIR, quiet)

    # ── MCP cache
    mcp_result = load_mcp_cache(mcp_cache, output_path, args.mode, args.skip_mcp, quiet)
    mcp_scenes = mcp_result["scenes"]
    mcp_prefabs = mcp_result["prefabs"]
    mcp_scope_parents = mcp_result["scope_parents"]
    mcp_meta = build_mcp_meta(mcp_result)

    # ── Retain / merge with existing graph
    existing_graph = read_json_safe(output_path, {})
    reextracted_files = list(changed_cs) + list(changed_asmdef)
    retained = retain_entries(existing_graph, reextracted_files, args.mode)

    retained["classes"] = purge_ghosts(retained["classes"], current_paths)
    retained["interfaces"] = purge_ghosts(retained["interfaces"], current_paths)
    retained["assemblies"] = purge_ghosts(retained["assemblies"], current_paths)
    retained["installers"] = purge_ghosts(retained["installers"], current_paths)

    new_classes = cs_output.get("classes", []) or []
    new_ifaces = cs_output.get("interfaces", []) or []
    new_installers = (cs_output.get("vcontainer") or {}).get("installers", []) or []
    new_scopes = (cs_output.get("vcontainer") or {}).get("scopes", []) or []
    new_partial_calls = cs_output.get("partial_calls", []) or []

    all_classes = merge_arrays(retained["classes"], new_classes)
    all_ifaces_pre = merge_arrays(retained["interfaces"], new_ifaces)
    all_assemblies = merge_arrays(retained["assemblies"], asmdef_output)
    all_installers = merge_arrays(retained["installers"], new_installers)

    # ── Event pivot + interface implementers
    all_events = event_pivot(all_classes)
    all_ifaces = resolve_implementers(all_ifaces_pre, all_classes)

    # ── Scope merge (retained + new) + MCP parent backfill
    retained_scopes = (
        (existing_graph.get("codebase", {}) or {}).get("vcontainer", {}) or {}
    ).get("scopes", []) or []
    if args.mode == "full":
        retained_scopes = []
    all_scopes = scope_merge(retained_scopes, new_scopes, mcp_scope_parents)

    # ── Call edges
    existing_calls = (existing_graph.get("codebase", {}) or {}).get("calls", []) or []
    all_calls = merge_call_edges(existing_calls, new_partial_calls, changed_cs, args.mode)

    # ── Validation warnings
    stale_warnings = check_path_drift(mcp_prefabs, unity_folder, repo_root, quiet)
    missing_warnings = check_missing_scripts(mcp_scenes, mcp_prefabs, quiet)

    # ── Assemble + atomic write
    end_ms = int(time.time() * 1000)
    build_ms = end_ms - start_ms
    git_sha = get_git_sha()

    graph = assemble_graph(
        classes=all_classes,
        interfaces=all_ifaces,
        events=all_events,
        installers=all_installers,
        scopes=all_scopes,
        assemblies=all_assemblies,
        scenes=mcp_scenes,
        prefabs=mcp_prefabs,
        mcp_meta=mcp_meta,
        calls=all_calls,
        stale_warnings=stale_warnings,
        missing_warnings=missing_warnings,
        scanned=scanned,
        cache_hits=cache_hits,
        build_ms=build_ms,
        git_sha=git_sha,
    )

    atomic_write_json(graph, output_path)

    # ── Update hash cache
    updated_cache = update_hash_cache(cache, all_cs + all_asmdef)
    save_hash_cache(cache_file, updated_cache)

    # ── Post-write modules (non-fatal)
    run_post_module(
        str(SCRIPT_DIR / "graph-traversal.py"),
        ["--finalize-calls", "--graph", output_path],
        quiet,
    )
    run_post_module(
        str(SCRIPT_DIR / "graph_cluster.py"),
        ["--graph", output_path],
        quiet,
    )
    run_post_module(
        str(SCRIPT_DIR / "graph_analyze.py"),
        ["--graph", output_path],
        quiet,
    )
    run_post_module(
        str(SCRIPT_DIR / "graph_validate.py"),
        ["--graph", output_path, "--sample", "20"],
        quiet,
    )

    # ── .last-build
    now_iso = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    try:
        with open(last_build_file, "w") as f:
            f.write(now_iso + "\n")
    except OSError as e:
        log(f"could not write .last-build: {e}", quiet)

    # ── Summary
    method_count = sum(
        len(c.get("methods", []) or []) for c in all_classes
    )
    print_summary(
        output_path=output_path,
        class_count=len(all_classes),
        method_count=method_count,
        event_count=len(all_events),
        installer_count=len(all_installers),
        cache_hits=cache_hits,
        scanned=scanned,
        build_ms=build_ms,
        quiet=quiet,
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
