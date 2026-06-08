#!/usr/bin/env python3
# graph_validate.py — Accuracy validation: spot-check graph.json against source files.
# Writes validation.accuracy{} atomically. Exit 0 always.
# Accuracy warnings are stored ONLY in validation.accuracy{} — never in validation.warnings[]
# (that array is owned by graph-validator.sh and overwritten during --validate runs).
import json
import os
import sys
import argparse
import tempfile
import random
import re


def check_class(cls):
    """Verify that class facts in the graph match what's in the source file."""
    path = cls.get("source_file") or cls.get("file", "")
    checks = []
    try:
        text = open(path).read()
    except Exception:
        return [{"class": cls["name"], "field": "file_read", "match": False}]

    # Declaration check
    checks.append({
        "class": cls["name"],
        "field": "declaration",
        "match": bool(re.search(rf'class\s+{re.escape(cls["name"])}\b', text)),
    })

    # Method presence checks
    for m in cls.get("methods", []):
        checks.append({
            "class": cls["name"],
            "field": f"method:{m['name']}",
            "match": bool(re.search(rf'\b{re.escape(m["name"])}\s*\(', text)),
        })

    # Event publish checks
    for ev in cls.get("events_published", []):
        present = (f"Publish<{ev}>" in text) or (f"new {ev}(" in text)
        checks.append({
            "class": cls["name"],
            "field": f"event_pub:{ev}",
            "match": present,
        })

    return checks


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


def main():
    ap = argparse.ArgumentParser(description="Spot-check graph.json accuracy against source files.")
    ap.add_argument("--graph", required=True, help="Path to graph.json")
    ap.add_argument("--sample", type=int, default=20, help="Number of classes to sample")
    ap.add_argument("--seed", type=int, default=42, help="RNG seed for deterministic sampling")
    args = ap.parse_args()

    try:
        with open(args.graph) as f:
            g = json.load(f)

        classes = g.get("codebase", {}).get("classes", [])
        if not classes:
            print("graph_validate: no classes to validate", file=sys.stderr)
            return

        rnd = random.Random(args.seed)
        sample = rnd.sample(classes, min(args.sample, len(classes)))

        all_checks = []
        for cls in sample:
            all_checks.extend(check_class(cls))

        matches = sum(1 for c in all_checks if c["match"])
        mismatches = len(all_checks) - matches
        pct = round(matches / max(len(all_checks), 1) * 100, 1)

        # Replace (not append) any existing accuracy block — reruns are idempotent
        g.setdefault("validation", {})["accuracy"] = {
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
        atomic_write(g, args.graph)
        print(f"graph_validate: {pct}% accuracy ({matches}/{len(all_checks)} checks)", file=sys.stderr)

    except Exception as e:
        print(f"graph_validate: error — {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
