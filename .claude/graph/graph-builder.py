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
import re
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


# ── Extraction-semantics versioning (Task 10) ────────────────────────────────
# Bump ONLY when extraction SEMANTICS change — i.e. when the same input file would now
# produce a different record.
#   2 — v4 Tasks 1+2: which value lands in `type`/`as` for a registration.
#   3 — scope parent resolution: a scope whose parent is assigned by
#       `ParentReference.Create<T>()` in Awake() now reports that parent instead of null, and an
#       unresolved parent carries parent_unresolved_reason. Same input file, different record.
#   4 — events[] is built from IEvent DECLARATION records (correct file/line/namespace) instead
#       of from the first publisher's file, declared-but-unreferenced events now appear at all,
#       and installer detection is structural (an Install* method taking IContainerBuilder)
#       rather than a name suffix, so AppModules/SceneModules stop being invisible.
# Usually this is bumped WITHOUT schema_version, because the shape is unchanged and only the
# meaning moves. Versions 3 and 4 are both exceptions — each also added fields — so
# schema_version moved with them (1.5.0, then 1.6.0). Bumping both is not the default.
EXTRACTION_VERSION = 4


def _stored_extraction_version(output_path):
    # NOTE: graph.json has no "metadata" wrapper object — schema_version/generator/
    # generated_at all live at the document's top level (see build_graph()). This
    # field follows that existing shape rather than the plan's informal "metadata
    # dict" phrasing, which refers to the group of fields, not a literal nested key.
    try:
        with open(output_path, "r", encoding="utf-8") as fh:
            return int(json.load(fh).get("extraction_version", 0))
    except Exception:
        return 0  # missing/unreadable/malformed -> promote (the safe direction)


# ── Disk-vs-graph reconciliation (Task 6) ────────────────────────────────────


def norm(p):
    """Repo-root-relative, realpath-resolved — the convention fixed in 57c9340.
    See docs/plans/graph-incremental-purge-fix.md:5."""
    return os.path.relpath(os.path.realpath(p), os.path.realpath("."))


# v4 (grill D2): the disk side is filtered by declaration kind. Measured on piggy-doku —
# unfiltered gave 9 permanent false positives (4 enum-only, 2 struct-only, 3 *Events.cs),
# filtered gives 63 == 63, zero false positives. This regex is a HOLE, not an alarm: a
# declaring file it misses drops out of the comparison silently, so the excluded count is
# logged (below) rather than left implicit.
_DECL_RE = re.compile(r'\b(?:class|interface)\s+[A-Za-z_]', re.M)

# Comments and string literals are stripped BEFORE the declaration test. Without this a
# file whose only mention of "class" sits in a comment (e.g. `// class GhostThing — see
# below`) or in a string counts as declaring, lands on the disk side of the comparison,
# finds no matching graph node, and raises GRAPH_DISK_MISMATCH on a perfectly healthy
# build — a FALSE ALARM, which Task 6's acceptance criterion forbids outright ("zero
# false positives — this is the gate"). Reproduced end-to-end during v4 verification.
# The plan's D2 residual-risk note anticipated only the opposite failure (the regex
# MISSING a real declaration); this is the over-matching direction. Same comment/string
# -stripping precedent as check-no-monobehaviour-in-services.sh.
_COMMENT_OR_STRING_RE = re.compile(
    r'/\*.*?\*/'          # block comment
    r'|//[^\n]*'          # line comment
    r'|@"(?:[^"]|"")*"'   # verbatim string
    r'|"(?:\\.|[^"\\])*"' # regular string
    r"|'(?:\\.|[^'\\])*'",  # char literal
    re.S,
)


def _strip_comments_and_strings(src):
    return _COMMENT_OR_STRING_RE.sub(" ", src)


def _declares_node(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return bool(_DECL_RE.search(_strip_comments_and_strings(fh.read())))
    except OSError:
        return False   # unreadable -> not comparable; counted as excluded


def reconcile_graph_with_disk(graph, disk_cs, quiet, limit=10):
    """Non-fatal net for silent omissions. Path SET comparison, not counts:
    a count check passes when one file drops and another is added.
    BOTH sides go through norm() — mixed path formats were the 57c9340 bug."""
    try:
        cb = graph.get("codebase", {})
        # ONLY these two kinds exist in the graph. `enums`/`structs` are not node kinds at all,
        # so events stay out of this comparison. The original reason was that
        # events[].source_file named the PUBLISHER rather than the declaration site; since
        # extraction v4 it names the declaration site, but folding it in is still wrong — the
        # DISK side of this comparison is filtered by _DECL_RE (`class`/`interface` only), so an
        # event-only file never appears there and every added graph path would surface as a
        # spurious "references files not on disk". See Task 6 step 4.
        graph_paths = {
            norm(n.get("source_file") or n.get("file"))
            for kind in ("classes", "interfaces")
            for n in cb.get(kind, []) or []
            if (n.get("source_file") or n.get("file"))
        }
        candidates = [p for p in disk_cs if p]
        disk_paths = {norm(p) for p in candidates if _declares_node(p)}
        excluded = len(candidates) - len(disk_paths)
        if excluded:
            log(f"reconciliation: {excluded} .cs file(s) excluded — declare no class/interface "
                f"(enum-only, struct-only, event declaration sites)", quiet)
        missing = sorted(disk_paths - graph_paths)
        extra   = sorted(graph_paths - disk_paths)
        if not missing and not extra:
            return
        if missing:
            head = ", ".join(missing[:limit])
            tail = f" (+{len(missing) - limit} more)" if len(missing) > limit else ""
            log(f"WARNING: GRAPH_DISK_MISMATCH — {len(missing)} .cs file(s) on disk are "
                f"absent from the graph: {head}{tail}. "
                f"Run 'python3 .claude/graph/graph-builder.py --full' to rebuild.", quiet)
        if extra:
            log(f"WARNING: GRAPH_DISK_MISMATCH — {len(extra)} graph node(s) reference "
                f"files not on disk: {', '.join(extra[:limit])}", quiet)
    except Exception as e:
        log(f"reconciliation check failed (non-fatal): {e}", quiet)


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
            "events": [],
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
        # Event DECLARATION records, retained by the file that declares them. Safe to key on
        # source_file only because events[].source_file is now the declaration site; while it was
        # the publisher's file, retaining on it would have kept an event alive whose declaring
        # file had been deleted. publishers/subscribers are not retained here — event_pivot
        # recomputes them from all_classes on every build.
        "events": keep(cb.get("events", [])),
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


def event_pivot(classes, event_defs=None):
    """Build events[] from DECLARATION records, with publishers/subscribers pivoted on top.

    This used to take `classes` only and set each event's `file`/`source_file` to the file of
    whichever class happened to publish or subscribe FIRST. So "where is this event declared?"
    got a confidently wrong answer for every event whose publisher lives elsewhere — which is
    all of them, since an IEvent struct is declared in `<Domain>Events.cs` and published from a
    service. `line` and `namespace` were lost outright, and `confidence` reported the publishing
    class's value rather than the event's.

    Worse, an event that is declared but never published or subscribed never entered events[] at
    all: it was invisible, not merely mislocated. That interacts badly with the R2
    EVENT_DANGLING rule, which catches "publisher but no subscriber" — the strictly worse
    "neither" case was undetectable.

    The extractor has always emitted correct declaration records (name, namespace, file, line,
    confidence "EXTRACTED" — see csharp_extractor.py, the IEvent struct branch); the builder
    simply never read them. It does now, and they are authoritative for identity and location.

    An event referenced by a Publish/Subscribe call with no declaration record still appears —
    dropping it would hide a real reference — but carries `declaration_unresolved: true` instead
    of a plausible-looking file. Same rule as scope parents: an unknown must announce itself
    rather than borrow a neighbour's value.
    """
    events = {}

    for d in event_defs or []:
        name = d.get("name")
        if not name:
            continue
        events[name] = {
            "name": name,
            "namespace": d.get("namespace", ""),
            "file": d.get("file", ""),
            "source_file": d.get("source_file") or d.get("file", ""),
            "line": d.get("line"),
            "publishers": [],
            "subscribers": [],
            "confidence": d.get("confidence", "EXTRACTED"),
        }

    def _referenced(ev, cls):
        e = events.get(ev)
        if e is None:
            e = events[ev] = {
                "name": ev,
                "file": "",
                "source_file": "",
                "publishers": [],
                "subscribers": [],
                "confidence": cls.get("confidence", "INFERRED"),
                # No IEvent struct declaration was extracted for this name. Do NOT fall back to
                # the referencing class's file: that is the original bug, and it reads as fact.
                "declaration_unresolved": True,
            }
        return e

    for cls in classes:
        cname = cls.get("name", "")
        for ev in cls.get("events_published", []) or []:
            e = _referenced(ev, cls)
            if cname and cname not in e["publishers"]:
                e["publishers"].append(cname)
        for ev in cls.get("events_subscribed", []) or []:
            e = _referenced(ev, cls)
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
    """Merge scope entries and resolve each one's parent from both available routes.

    A LifetimeScope's parent reaches VContainer two ways, and until this function read both, the
    graph reported a bare `null` for every scope whose parent is assigned in code — which
    `/knowledge-graph scope-tree` then presented as the fact "this scope has no parent".

      - "code"      — `ParentReference.Create<T>()` in the scope's Awake(). Set by
                      csharp_extractor.py, which sees C# source with or without Unity running.
      - "inspector" — the serialized `parentReference.TypeName` on the prefab, read by the MCP
                      extractor (mcp-extractor.md Step 2b). Requires the Editor connected.

    Code wins on conflict: `Create<T>()` overwrites the whole struct at runtime, so a differing
    Inspector value is dead config, not a competing answer.

    When neither route resolves, the scope carries `parent_unresolved_reason` instead of a naked
    null, so an absent parent can never again be read as a proven absence. Note the reason
    "no-parent-declared" is genuinely ambiguous — it fits a real root scope (AppScope) AND a
    parent assigned indirectly (through a helper, or `Create<>` via a variable). It says what was
    looked at, not what is true.
    """
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

    inspector_parent = {}
    mcp_saw = set()
    for p in mcp_scope_parents or []:
        sn = p.get("scope_name")
        if not sn:
            continue
        mcp_saw.add(sn)
        if p.get("parent_name"):
            inspector_parent[sn] = p["parent_name"]

    for s in scopes:
        name = s.get("name")
        # A retained (cache-hit) entry may carry a stale reason from a previous build; recompute.
        s.pop("parent_unresolved_reason", None)
        if s.get("parent") and s.get("parent_source") == "code":
            continue                                   # code route already resolved it
        if name in inspector_parent:
            s["parent"] = inspector_parent[name]
            s["parent_source"] = "inspector"
            continue
        s["parent"] = None
        s.pop("parent_source", None)
        s["parent_unresolved_reason"] = (
            "no-parent-declared" if name in mcp_saw else "mcp-extraction-absent"
        )
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
    # The branch above is `age < 60 and mode != "full"`, so this one fires for TWO different
    # reasons and used to report only one of them. On a --full run with a cache written seconds
    # ago it printed "mcp cache stale (0m old)" — a false cause — and then told the reader to
    # "run /build-knowledge-graph", i.e. the command they had just run. Naming the actual reason
    # and the actual next step matters more here than the wording: a message that misidentifies
    # why it fired sends the reader to fix the wrong thing.
    if mode == "full":
        log(
            f"mcp cache bypassed by --full (cache is {age}m old, not stale) — retaining {pcount} "
            f"prefabs from the existing graph. A --full run re-extracts from scratch and does not "
            f"reuse the cache: refresh it via the MCP extractor, then run --incremental to merge.",
            quiet,
        )
    else:
        log(
            f"mcp cache stale ({age}m old, limit 60m) — retaining {pcount} prefabs from existing "
            f"graph; re-run the MCP extraction (Unity Editor must be open) to refresh it",
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
        "schema_version": "1.6.0",
        "generated_at": now,
        "generator": f"graph-builder.py@{git_sha}",
        "extraction_version": EXTRACTION_VERSION,
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

    # ── Extraction-semantics staleness check (Task 10) ──────────────────────
    # An --incremental run never re-extracts unchanged files, so if extraction
    # SEMANTICS changed since the graph was last built (EXTRACTION_VERSION bump),
    # old records would survive forever while the graph reports itself fresh.
    # Promote once to --full; the same run writes the new version, so the next
    # run is incremental again (self-clearing).
    if args.mode == "incremental":
        stored_extraction_version = _stored_extraction_version(output_path)
        if stored_extraction_version != EXTRACTION_VERSION:
            log(
                f"extraction_version mismatch (graph={stored_extraction_version}, "
                f"builder={EXTRACTION_VERSION}) — promoting this --incremental run to "
                f"--full once so stale records are re-extracted",
                quiet,
            )
            args.mode = "full"

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
    new_event_defs = cs_output.get("events", []) or []

    all_classes = merge_arrays(retained["classes"], new_classes)
    all_ifaces_pre = merge_arrays(retained["interfaces"], new_ifaces)
    all_assemblies = merge_arrays(retained["assemblies"], asmdef_output)
    all_installers = merge_arrays(retained["installers"], new_installers)

    # ── Event pivot + interface implementers
    all_event_defs = merge_arrays(retained["events"], new_event_defs)
    all_events = event_pivot(all_classes, all_event_defs)
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

    # ── Disk-vs-graph reconciliation (non-fatal; catches silent omissions like
    # the ghost-purge/collapse bugs this file already guards against elsewhere)
    reconcile_graph_with_disk(graph, full_cs, quiet)

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
