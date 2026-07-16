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
    p.add_argument(
        "--force",
        action="store_true",
        help="Bypass collapse guard (use when genuinely deleting many files).",
    )
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
    # Full directory walk — always performed for ghost-purge correctness.
    full_cs = []
    full_asmdef = []
    roots_cs = [
        os.path.join(assets_root, "_Framework"),
        os.path.join(assets_root, "_GameFolders", "Scripts"),
    ]
    for root in roots_cs:
        if not os.path.isdir(root):
            continue
        for p in pathlib.Path(root).rglob("*.cs"):
            full_cs.append(str(p))
    if os.path.isdir(assets_root):
        for p in pathlib.Path(assets_root).rglob("*.asmdef"):
            full_asmdef.append(str(p))

    if not changed_files_str:
        return full_cs, full_asmdef

    # Incremental mode: extraction targets only the changed files, but
    # current_paths is derived from the full walk so ghost-purge is correct.
    # Normalize paths to relative (cwd == repo_root at this point) so they
    # match the relative source_file values written by the extractor.  The hook
    # passes absolute paths; the full walk and extractor both use relative ones;
    # mixing the two formats causes retain/purge set-lookups to miss, producing
    # duplicate entries and silent data decay.
    changed_cs = []
    changed_asmdef = []
    for f in changed_files_str.split(","):
        f = f.strip()
        if not f:
            continue
        try:
            # realpath resolves symlinks on both sides before relpath so that
            # macOS /private/var vs /var aliasing does not prevent relativization.
            f = os.path.relpath(os.path.realpath(f), os.path.realpath("."))
        except ValueError:
            pass  # relpath fails across drives on Windows — keep as-is
        if f.endswith(".cs"):
            changed_cs.append(f)
        elif f.endswith(".asmdef"):
            changed_asmdef.append(f)

    # Return changed files as the primary lists (extracted below) but attach the
    # full-walk lists as a second pair so the caller can build current_paths from them.
    return changed_cs, changed_asmdef, full_cs, full_asmdef


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
    """Returns (result_dict, used_fallback: bool). used_fallback is True when the
    tree-sitter python extractor was unavailable (exit 2) and the regex-based
    shell extractor was used instead — its pub/sub + registration data is
    LOW CONFIDENCE (D1)."""
    if not changed_cs:
        return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []}), False
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
        return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []}), False

    used_fallback = False
    for label, cmd in cmds:
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if r.returncode == 2 and label == "python3":
                log("csharp_extractor.py: tree-sitter unavailable — falling back to shell extractor", quiet)
                used_fallback = True
                continue
            if r.returncode != 0:
                log(f"csharp extractor ({label}) exited {r.returncode}: {r.stderr.strip()}", quiet)
            if r.stdout and r.stdout.strip():
                return json.loads(r.stdout), used_fallback
        except Exception as e:
            log(f"csharp extractor ({label}) failed: {e}", quiet)
    return dict(EMPTY_CS, vcontainer={"installers": [], "scopes": []}), used_fallback


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
        "scopes": keep(vc.get("scopes", [])),
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
            if c.get("caller_file") not in changed_set   # callee_file clause removed (RC1 blocker fix)
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


def _is_test_file(path):
    p = (path or "").replace("\\", "/")
    if "/Tests/" in p or "/Test/" in p:
        return True
    stem = p.rsplit("/", 1)[-1].split(".", 1)[0]
    return "Test" in stem


def resolve_call_targets(calls, classes, interfaces):
    """Resolve each call edge's callee head token to a real project type + file.
    - REV4: same simple name on multiple files -> prefer the single NON-test file;
      if 0 or >=2 non-test candidates remain, leave unresolved (None) -- no guess.
    - REV5: set method_match = True/False/None from the resolved type's methods[]
      (True=present, False=populated-but-absent, None=methods[] empty/unknown).
      Computed fresh every build; NEVER touches confidence (which persists and
      would desync full vs. incremental, and already carries RC3's INFERRED).
      methods[] is name-only and omits inherited/interface methods, so
      method_match=False is a soft signal, never a reason to drop the edge.
    - Lever 0: every edge gets `callee_kind` in {internal, external, unresolved}:
      internal = linked to a project type; external = a resolved-but-non-project
      type (Unity/BCL/3rd-party, e.g. Transform/List/IContainerBuilder) which is
      a CORRECT null; unresolved = a bare variable head we could not type, or an
      ambiguous same-name project type -- the genuine miss. Lets reporting tell
      "correctly external" apart from "actually missed" instead of lumping both
      into a null callee_class.
    - Lever 1: inherited-field second-chance. When the head is a variable name
      (not a type), resolve it through the caller class's own + inherited
      `field_types` map (walking base_types across files -- only possible in this
      global pass), and link ONLY when the resolved PROJECT type actually
      declares the method (method_match True). The method guard stops fluent
      chain tails (e.g. `_playerController.Obs.Subscribe()` -> head
      `_playerController`) from fabricating false `PlayerController.Subscribe`
      edges.
    Runs over ALL edges every build (resolution is global)."""
    by_name = {}
    for c in list(classes) + list(interfaces):
        n = c.get("name")
        if not n:
            continue
        methods = {m.get("name") for m in (c.get("methods") or []) if m.get("name")}
        by_name.setdefault(n, []).append((c.get("file"), methods, _is_test_file(c.get("file"))))

    # Class index for Lever 1 base-chain field walk. Prefer the non-test
    # declaration when a simple name collides (test fakes live under /Tests/).
    class_by_name = {}
    for c in classes:
        n = c.get("name")
        if not n:
            continue
        prev = class_by_name.get(n)
        if prev is None or (_is_test_file(prev.get("file")) and not _is_test_file(c.get("file"))):
            class_by_name[n] = c

    def _pick(head):
        """REV4 tie-break: the single non-test candidate, else None (no guess)."""
        cands = by_name.get(head)
        if not cands:
            return None
        if len(cands) == 1:
            return cands[0]
        non_test = [c for c in cands if not c[2]]
        return non_test[0] if len(non_test) == 1 else None

    def _looks_type(tok):
        """A head that is itself a type name is PascalCase (upper first char).
        Fields/params/locals are _camelCase or camelCase -> not a type."""
        return bool(tok) and tok[0].isupper()

    def _field_type(caller_class, field):
        """Resolve `field` through caller_class's own + inherited field_types.
        Walks the base chain (first non-interface base) with a cycle/depth guard.
        Returns the declared type name, or None."""
        name = caller_class
        seen = set()
        for _ in range(8):                                 # depth cap == cycle guard
            if not name or name in seen:
                break
            seen.add(name)
            cls = class_by_name.get(name)
            if cls is None:
                break
            ft = cls.get("field_types") or {}
            if field in ft:
                return ft[field]
            ifaces = set(cls.get("implements") or [])
            bases = cls.get("base_types") or []
            name = next((b for b in bases if b not in ifaces), None)
        return None

    for e in calls:
        head, _, method = (e.get("callee") or "").partition(".")
        e["callee_class"] = None
        e["callee_file"] = None
        e["method_match"] = None
        e["callee_kind"] = "unresolved"

        # Primary path: head is itself a project type name. Unchanged REV4/REV5
        # behavior -- links on the type regardless of method_match.
        if head in by_name:
            pick = _pick(head)
            if pick is not None:
                file, methods, _ = pick
                e["callee_class"] = head
                e["callee_file"] = file
                e["callee_kind"] = "internal"
                if method and methods:                     # REV5: method_match, NOT confidence
                    e["method_match"] = method in methods
            # else: ambiguous project name -> stays unresolved (never guessed)
            continue

        # Head is a resolved-but-non-project type (Unity/BCL/3rd-party). Correct
        # null -- no project node exists to link.
        if _looks_type(head):
            e["callee_kind"] = "external"
            continue

        # Lever 1: head is a variable name. Try the caller's field_types chain.
        caller_class = (e.get("caller") or "").partition(".")[0].lstrip("@")
        rtype = _field_type(caller_class, head)
        if not rtype:
            continue                                       # unresolved (default)
        if rtype not in by_name:
            e["callee_kind"] = "external"                  # e.g. _transform -> Transform
            continue
        pick = _pick(rtype)
        if pick is None:
            continue                                       # ambiguous -> unresolved
        file, methods, _ = pick
        # Guard: only link when the resolved type actually declares the method.
        # A field typed to a project class whose methods[] lacks this method is
        # almost always a fluent-chain tail -- do NOT fabricate the edge.
        if method and methods and method in methods:
            e["callee_class"] = rtype
            e["callee_file"] = file
            e["method_match"] = True
            e["callee_kind"] = "internal"
        # else: method absent/unknown -> leave unresolved (conservative)
    return calls


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


def write_partition_files(graph_dir, scenes, prefabs):
    """Write scenes.json and prefabs.json atomically to graph_dir.

    Both files contain a plain JSON array at root level.
    Raises on any write failure — caller must abort before writing main graph.
    """
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
    """Return the array from an inline list or a $partition reference.

    Returns [] on missing partition file (graceful degradation).
    """
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and "$partition" in value:
        fname = value["$partition"]
        result = read_json_safe(os.path.join(graph_dir, fname), [])
        return result if isinstance(result, list) else []
    return []


# ── MCP cache ────────────────────────────────────────────────────────────────


def mcp_age_minutes(path):
    try:
        return int((time.time() - os.path.getmtime(path)) / 60)
    except Exception:
        return 9999


def load_mcp_cache(mcp_cache_path, output_path, mode, skip_mcp, quiet):
    existing = read_json_safe(output_path, {})
    cb = existing.get("codebase", {}) if isinstance(existing, dict) else {}
    _graph_dir = os.path.dirname(os.path.abspath(output_path))
    fallback_scenes  = _resolve_inline_or_partition(cb.get("scenes",  []) if isinstance(cb, dict) else [], _graph_dir)
    fallback_prefabs = _resolve_inline_or_partition(cb.get("prefabs", []) if isinstance(cb, dict) else [], _graph_dir)

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
    fallback_warnings,
    scanned,
    cache_hits,
    build_ms,
    git_sha,
):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return {
        "schema_version": "1.3.0",
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
            "scenes": {"$partition": "scenes.json"},
            "prefabs": {"$partition": "prefabs.json"},
            "mcp_extraction": mcp_meta,
            "calls": calls,
        },
        "validation": {
            "errors": [],
            "warnings": list(stale_warnings or []) + list(missing_warnings or []) + list(fallback_warnings or []),
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
    # Resolve --output against the ORIGINAL cwd before we chdir, so an explicit
    # relative --output keeps pointing where the caller expects. (Default is the
    # absolute SCRIPT_DIR/graph.json, so this is a no-op for the common case.)
    args.output = os.path.abspath(args.output)
    # All scan / extractor / post-module paths are repo-relative and inherit our
    # cwd. Pin cwd to repo_root so the builder produces identical results no matter
    # where it is invoked from (a git hook, .claude/graph/, or the repo root).
    # Previously a non-root cwd silently scanned 0 files and wrote an empty graph.
    try:
        os.chdir(repo_root)
    except OSError as e:
        log(f"could not chdir to repo_root ({repo_root}): {e}", quiet)

    unity_folder = read_unity_folder(repo_root)
    assets_root = "Assets" if unity_folder == "." else f"{unity_folder}/Assets"

    # Guard: when unity_project_folder names an explicit subfolder, that folder's
    # Assets/ MUST exist — a missing one means a typo'd unity_project_folder, so we
    # fail loudly (exit 1) instead of silently writing an empty graph.
    # NOT triggered when unity_project_folder == "." : a repo with no Assets/ is a
    # valid "template mode" state (the graph test harness runs in exactly this mode)
    # and must still produce an empty graph and exit 0. The os.chdir above is what
    # actually fixes the original wrong-cwd silent-0-files bug; this guard only
    # catches the remaining explicit-subfolder misconfiguration.
    if (
        not args.changed_files
        and unity_folder != "."
        and not os.path.isdir(assets_root)
    ):
        log(
            f"ERROR: assets root not found: {os.path.abspath(assets_root)} "
            f"(repo_root={repo_root}, unity_project_folder={unity_folder!r}). "
            f"Fix unity_project_folder in .claude/project-features.json.",
            quiet=False,
        )
        return 1

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
    scan_result = scan_files(assets_root, args.changed_files)
    if len(scan_result) == 4:
        # Incremental mode: extraction targets only changed files, but the full
        # directory walk is returned separately for ghost-purge correctness.
        all_cs, all_asmdef, full_cs, full_asmdef = scan_result
    else:
        all_cs, all_asmdef = scan_result
        full_cs, full_asmdef = all_cs, all_asmdef
    cache = load_hash_cache(cache_file, quiet)

    changed_cs, cs_paths, scanned_cs, hits_cs = select_changed(
        all_cs, cache, args.mode
    )
    changed_asmdef, asm_paths, scanned_asm, hits_asm = select_changed(
        all_asmdef, cache, args.mode
    )

    scanned = scanned_cs + scanned_asm
    cache_hits = hits_cs + hits_asm
    # current_paths for ghost-purge always comes from the full directory walk so
    # that a single-file --changed-files run does not incorrectly treat every
    # other file in the project as deleted.
    current_paths = [f for f in full_cs if f] + [f for f in full_asmdef if f]

    log(
        f"scan: {scanned} files, {cache_hits} cache hits, "
        f"{len(changed_cs) + len(changed_asmdef)} to re-extract",
        quiet,
    )

    # ── Run extractors
    if changed_cs:
        log(f"running csharp-extractor on {len(changed_cs)} files…", quiet)
    cs_output, used_fallback_extractor = run_csharp_extractor(changed_cs, SCRIPT_DIR, quiet)

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
    all_calls = resolve_call_targets(all_calls, all_classes, all_ifaces)   # RC1

    # ── Validation warnings
    stale_warnings = check_path_drift(mcp_prefabs, unity_folder, repo_root, quiet)
    missing_warnings = check_missing_scripts(mcp_scenes, mcp_prefabs, quiet)
    fallback_warnings = []
    if used_fallback_extractor:
        fallback_msg = (
            "tree-sitter unavailable — pub/sub + registration data is LOW CONFIDENCE "
            "(regex fallback under-reports non-generic Publish/RegisterInstance)."
        )
        fallback_warnings.append({"code": "FALLBACK_EXTRACTOR", "message": fallback_msg})
        print(f"WARNING: FALLBACK_EXTRACTOR — {fallback_msg}", file=sys.stderr)

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
        fallback_warnings=fallback_warnings,
        scanned=scanned,
        cache_hits=cache_hits,
        build_ms=build_ms,
        git_sha=git_sha,
    )

    # ── Collapse guard (incremental mode only)
    # If the new class count is less than 50% of the existing count, the update
    # almost certainly triggered the ghost-purge collapse bug (or a misconfigured
    # --changed-files).  Abort the write and keep the old graph intact so that
    # stale-but-complete data is always preferred over fresh-but-empty data.
    # Use --force to bypass when you are genuinely deleting a large batch of files.
    if not args.force and args.mode != "full":
        existing_class_count = len(
            (existing_graph.get("codebase", {}) or {}).get("classes", []) or []
        )
        if existing_class_count >= 10 and len(all_classes) < existing_class_count * 0.5:
            print(
                f"ERROR (graph-builder): collapse guard triggered — "
                f"new class count ({len(all_classes)}) is less than 50% of existing "
                f"({existing_class_count}). Graph NOT written. "
                f"Run '/build-knowledge-graph' (full build) or re-run with --force.",
                file=sys.stderr,
            )
            return 1

    # ── Write partition files (must precede main graph write)
    graph_dir = os.path.dirname(os.path.abspath(output_path))
    write_partition_files(graph_dir, mcp_scenes, mcp_prefabs)

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
