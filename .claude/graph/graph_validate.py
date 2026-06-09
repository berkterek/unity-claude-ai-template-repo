#!/usr/bin/env python3
# graph_validate.py — Two-mode graph validation.
#
# Mode 1 (default): Consistency check — graph.json internal integrity only.
#   No source files read, no regex parse. Checks orphan events, missing
#   installers, dangling call edges, etc. Always runs during graph-builder.
#
# Mode 2 (--accuracy): Accuracy check — re-extracts a sample of source files
#   via csharp_extractor.py and compares against graph facts. Slow; run
#   manually or in CI only. Requires csharp_extractor.py (tree-sitter).
#
# Exit 0 always.
import json
import os
import sys
import argparse
import subprocess
import tempfile


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def atomic_write(g, path):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(g, f, indent=2)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# ---------------------------------------------------------------------------
# Mode 1: Consistency check (graph vs. graph — no source files)
# ---------------------------------------------------------------------------

def run_consistency(g):
    """Check graph.json internal integrity. Returns list of issue dicts."""
    issues = []
    codebase = g.get("codebase", {})
    classes  = codebase.get("classes", [])
    events   = codebase.get("events", [])

    class_names = {c["name"] for c in classes}
    event_names = {e["name"] if isinstance(e, dict) else e for e in events}

    # Orphan events: published but never declared
    for cls in classes:
        for ev in cls.get("events_published", []):
            if ev not in event_names:
                issues.append({
                    "type": "ORPHAN_EVENT_PUB",
                    "class": cls["name"],
                    "event": ev,
                    "detail": f"{cls['name']} publishes {ev} but event is not declared in graph",
                })
        for ev in cls.get("events_subscribed", []):
            if ev not in event_names:
                issues.append({
                    "type": "ORPHAN_EVENT_SUB",
                    "class": cls["name"],
                    "event": ev,
                    "detail": f"{cls['name']} subscribes to {ev} but event is not declared in graph",
                })

    # Dangling call edges: callee class not in graph
    for cls in classes:
        for call in cls.get("calls", []):
            callee_cls = call.get("callee_class", "")
            if callee_cls and callee_cls not in class_names:
                issues.append({
                    "type": "DANGLING_CALL",
                    "class": cls["name"],
                    "callee": callee_cls,
                    "detail": f"{cls['name']} calls {callee_cls}.{call.get('callee_method','')} but {callee_cls} not in graph",
                })

    # Installer references non-existent class
    vcontainer = codebase.get("vcontainer", {})
    for installer in vcontainer.get("installers", []):
        for reg in installer.get("registrations", []):
            cls_name = reg.get("class", "")
            if cls_name and cls_name not in class_names:
                issues.append({
                    "type": "INSTALLER_MISSING_CLASS",
                    "installer": installer.get("name", "?"),
                    "class": cls_name,
                    "detail": f"Installer {installer.get('name','?')} registers {cls_name} but class not in graph",
                })

    return issues


# ---------------------------------------------------------------------------
# Mode 2: Accuracy check (graph vs. source via csharp_extractor.py)
# ---------------------------------------------------------------------------

def run_accuracy(g, extractor_path, sample_size, seed):
    import random
    classes = g.get("codebase", {}).get("classes", [])
    if not classes:
        return None

    rnd = random.Random(seed)
    sample = rnd.sample(classes, min(sample_size, len(classes)))

    all_checks = []
    for cls in sample:
        path = cls.get("source_file") or cls.get("file", "")
        if not path or not os.path.exists(path):
            all_checks.append({"class": cls["name"], "field": "file_read", "match": False})
            continue

        # Re-extract via csharp_extractor.py (tree-sitter)
        try:
            r = subprocess.run(
                ["python3", extractor_path, "--changed-files", path],
                capture_output=True, text=True, timeout=30
            )
            if r.returncode == 2:
                print("graph_validate(accuracy): tree-sitter unavailable — skipping accuracy check", file=sys.stderr)
                return None
            extracted_classes = json.loads(r.stdout).get("classes", []) if r.stdout.strip() else []
        except Exception as e:
            print(f"graph_validate(accuracy): extractor failed for {path}: {e}", file=sys.stderr)
            continue

        ext_cls = next((c for c in extracted_classes if c["name"] == cls["name"]), None)

        # Declaration check
        all_checks.append({
            "class": cls["name"],
            "field": "declaration",
            "match": ext_cls is not None,
        })
        if ext_cls is None:
            continue

        # Method presence checks
        ext_methods = {m["name"] for m in ext_cls.get("methods", [])}
        for m in cls.get("methods", []):
            all_checks.append({
                "class": cls["name"],
                "field": f"method:{m['name']}",
                "match": m["name"] in ext_methods,
            })

        # Event publish checks
        ext_pubs = set(ext_cls.get("events_published", []))
        for ev in cls.get("events_published", []):
            all_checks.append({
                "class": cls["name"],
                "field": f"event_pub:{ev}",
                "match": ev in ext_pubs,
            })

    if not all_checks:
        return None

    matches    = sum(1 for c in all_checks if c["match"])
    mismatches = len(all_checks) - matches
    pct        = round(matches / max(len(all_checks), 1) * 100, 1)
    return {
        "sampled_classes": len(sample),
        "matches": matches,
        "mismatches": mismatches,
        "agreement_pct": pct,
        "checks": all_checks,
        "low_accuracy_warning": pct < 90,
        "warning_message": (
            f"Graph accuracy {pct}% (< 90%) — run /build-knowledge-graph --full"
            if pct < 90 else ""
        ),
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Validate graph.json.")
    ap.add_argument("--graph",    required=True, help="Path to graph.json")
    ap.add_argument("--accuracy", action="store_true",
                    help="Run accuracy check (re-extracts source via csharp_extractor.py). Slow.")
    ap.add_argument("--sample",   type=int, default=20, help="Classes to sample (accuracy mode)")
    ap.add_argument("--seed",     type=int, default=42,  help="RNG seed")
    args = ap.parse_args()

    try:
        with open(args.graph) as f:
            g = json.load(f)
    except Exception as e:
        print(f"graph_validate: cannot read graph — {e}", file=sys.stderr)
        return

    classes = g.get("codebase", {}).get("classes", [])
    if not classes:
        print("graph_validate: no classes to validate", file=sys.stderr)
        return

    g.setdefault("validation", {})

    # ── Mode 1: Consistency (always)
    issues = run_consistency(g)
    g["validation"]["consistency"] = {
        "issues": issues,
        "issue_count": len(issues),
        "passed": len(issues) == 0,
    }
    if issues:
        print(f"graph_validate: {len(issues)} consistency issue(s)", file=sys.stderr)
        for iss in issues[:5]:
            print(f"  [{iss['type']}] {iss['detail']}", file=sys.stderr)
    else:
        print("graph_validate: consistency OK", file=sys.stderr)

    # ── Mode 2: Accuracy (--accuracy flag only)
    if args.accuracy:
        script_dir   = os.path.dirname(os.path.abspath(__file__))
        extractor    = os.path.join(script_dir, "extractors", "csharp_extractor.py")
        if not os.path.exists(extractor):
            print("graph_validate(accuracy): csharp_extractor.py not found — skipping", file=sys.stderr)
        else:
            result = run_accuracy(g, extractor, args.sample, args.seed)
            if result:
                g["validation"]["accuracy"] = result
                pct = result["agreement_pct"]
                print(
                    f"graph_validate(accuracy): {pct}% "
                    f"({result['matches']}/{result['matches'] + result['mismatches']} checks)",
                    file=sys.stderr
                )

    atomic_write(g, args.graph)


if __name__ == "__main__":
    main()
