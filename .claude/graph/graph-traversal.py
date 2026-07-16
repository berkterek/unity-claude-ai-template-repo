#!/usr/bin/env python3
# GENERATED-FROM-TEMPLATE — do not edit directly in project repos.
# Changes must be made in unity-claude-ai-template-repo and synced forward.
"""Knowledge graph traversal — impact, callers, path, god-nodes, finalize-calls."""
import argparse
import json
import os
import sys
import tempfile
from collections import defaultdict

# Resolve shared BFS core from the same directory as this script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graph_bfs_core

DEFAULT_GRAPH = os.path.join(os.path.dirname(__file__), "graph.json")


# ---------------------------------------------------------------------------
# Graph loading
# ---------------------------------------------------------------------------

def load_graph(path):
    """Load graph.json and build forward/reverse adjacency sets.

    Returns (raw_graph, forward, reverse, edges).
    """
    if not os.path.exists(path):
        print(f"ERR_GRAPH_MISSING: run /build-knowledge-graph first.", file=sys.stderr)
        sys.exit(2)
    with open(path, encoding="utf-8") as f:
        g = json.load(f)
    edges = g.get("codebase", {}).get("calls", []) or []
    forward = defaultdict(set)   # caller -> {callee}
    reverse = defaultdict(set)   # callee -> {caller}
    for e in edges:
        caller = e.get("caller", "")
        callee = e.get("callee", "")
        if caller and callee:
            forward[caller].add(callee)
            reverse[callee].add(caller)
    return g, forward, reverse, edges


# Called by future query subcommands that need scenes/prefab data.
def resolve_partition(graph, key, graph_dir):
    """Return the full array for a partitioned or inline codebase key.

    Handles both legacy inline arrays and v1.3.0+ $partition references.
    Missing key returns []. Missing partition file raises FileNotFoundError.
    """
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
        if not isinstance(data, list):
            raise ValueError(f"Partition {fpath} expected a JSON array, got {type(data).__name__}")
        return data
    return []


# ---------------------------------------------------------------------------
# Subcommands — delegate traversal logic to graph_bfs_core
# ---------------------------------------------------------------------------

def cmd_impact(args, ctx):
    g, fwd, rev, edges = ctx
    hops = args.hops  # None → core uses its default of 3
    result = graph_bfs_core.impact_core(args.node, g, fwd, rev, edges, hops=hops)

    if not result["ok"]:
        if result.get("no_edges"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        if result.get("not_found"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        return

    if args.json:
        out = {k: v for k, v in result.items() if k != "ok"}
        print(json.dumps(out, indent=2))
    else:
        # Pretty two-column table
        print(f"Impact analysis for: {result['root']}  (hops={result['hops']})")
        print(f"  Total affected: {result['total_affected']}")
        print()
        max_len = max(
            len(result["downstream"]), len(result["upstream"]), 1
        )
        header_l = "DOWNSTREAM (what it reaches)"
        header_r = "UPSTREAM (what reaches it)"
        col = max(40, max(len(n) for n in result["downstream"] + result["upstream"] + [header_l, header_r]) + 2)
        print(f"  {header_l:<{col}}  {header_r}")
        print(f"  {'-'*col}  {'-'*col}")
        for i in range(max_len):
            l = result["downstream"][i] if i < len(result["downstream"]) else ""
            r = result["upstream"][i]   if i < len(result["upstream"])   else ""
            print(f"  {l:<{col}}  {r}")


def cmd_callers(args, ctx):
    g, fwd, rev, edges = ctx
    result = graph_bfs_core.callers_core(args.node, g, fwd, rev, edges)

    if not result["ok"]:
        if result.get("no_edges"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        if result.get("not_found"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        if result.get("no_callers"):
            print(f"No direct callers found for {result['node']}.")
            sys.exit(0)
        return

    hits = result["hits"]
    if args.json:
        print(json.dumps(hits, indent=2))
    else:
        print(f"Direct callers of: {args.node}")
        for h in hits:
            loc = f"{h['file']}:{h['line']}" if h['file'] else "(unknown)"
            conf = h['confidence'] or ""
            via = h.get("matched_via") or ""
            print(f"  {h['caller']:<50}  {loc}  {conf}  {via}")


def cmd_path(args, ctx):
    g, fwd, rev, edges = ctx
    result = graph_bfs_core.path_core(args.a, args.b, g, fwd, rev, edges)

    if result.get("same_node"):
        out = {"from": result["from"], "to": result["to"], "length": 0, "path": result["path"]}
        print(json.dumps(out, indent=2) if args.json else f"Same node: {result['from']}")
        return

    if not result["ok"]:
        if result.get("no_edges"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        if result.get("not_found"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        if result.get("no_path"):
            print(f"No path from {result['from']} to {result['to']} in the call graph.", file=sys.stderr)
            sys.exit(1)
        return

    if args.json:
        out = {k: v for k, v in result.items() if k != "ok"}
        print(json.dumps(out, indent=2))
    else:
        print(f"Shortest path: {result['from']} → {result['to']}  (length={result['length']})")
        print("  " + " → ".join(result["path"]))


def cmd_god_nodes(args, ctx):
    g, fwd, rev, edges = ctx
    top = args.top  # None → core uses its default of 10
    result = graph_bfs_core.god_nodes_core(g, fwd, rev, edges, top=top)

    if not result["ok"]:
        if result.get("no_edges"):
            print(result["message"], file=sys.stderr)
            sys.exit(0)
        return

    ranked = result["ranked"]

    if result["enhanced"]:
        if args.json:
            print(json.dumps(ranked, indent=2))
        else:
            print(f"Top {len(ranked)} nodes by degree (in+out):")
            header = f"  {'NODE':<50}  {'IN':>5}  {'OUT':>5}  {'TOTAL':>7}  {'COMM':>6}  SEV"
            print(header)
            print("  " + "-" * (len(header) - 2))
            for r in ranked:
                comm = str(r.get("community_id", "?"))
                sev = r.get("severity", "info")
                print(f"  {r['node']:<50}  {r['in']:>5}  {r['out']:>5}  {r['total']:>7}  {comm:>6}  {sev}")
    else:
        if args.json:
            print(json.dumps(ranked, indent=2))
        else:
            print(f"Top {len(ranked)} nodes by degree (in+out):")
            header = f"  {'NODE':<50}  {'IN':>5}  {'OUT':>5}  {'TOTAL':>7}  GOD?"
            print(header)
            print("  " + "-" * (len(header) - 2))
            for r in ranked:
                god = "*** GOD NODE ***" if r["is_god_node"] else ""
                print(f"  {r['node']:<50}  {r['in']:>5}  {r['out']:>5}  {r['total']:>7}  {god}")


def cmd_finalize_calls(args):
    """Sort, dedupe, and promote EXTRACTED over INFERRED edges; rewrite graph.json atomically."""
    path = args.graph
    if not os.path.exists(path):
        print(f"ERR_GRAPH_MISSING: run /build-knowledge-graph first.", file=sys.stderr)
        sys.exit(2)

    with open(path, encoding="utf-8") as f:
        g = json.load(f)

    calls = g.get("codebase", {}).get("calls", []) or []

    if not calls:
        print("No calls[] to finalize.", file=sys.stderr)
        sys.exit(0)

    # Confidence priority: EXTRACTED > INFERRED (higher index = better)
    CONF_RANK = {"INFERRED": 0, "EXTRACTED": 1}

    # Key: (caller, callee, file, line) — keep best confidence
    best = {}
    for e in calls:
        key = (
            e.get("caller", ""),
            e.get("callee", ""),
            e.get("file", ""),
            e.get("line", 0),
        )
        existing = best.get(key)
        if existing is None:
            best[key] = e
        else:
            # Promote if current confidence is higher
            curr_rank = CONF_RANK.get(str(e.get("confidence", "")).upper(), -1)
            prev_rank = CONF_RANK.get(str(existing.get("confidence", "")).upper(), -1)
            if curr_rank > prev_rank:
                best[key] = e

    # Sort by (caller, line)
    deduped = sorted(
        best.values(),
        key=lambda e: (e.get("caller", ""), e.get("line", 0) or 0),
    )

    original_count = len(calls)
    deduped_count = len(deduped)

    g["codebase"]["calls"] = deduped

    # Atomic write
    dir_name = os.path.dirname(path)
    fd, tmp_path = tempfile.mkstemp(dir=dir_name, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(g, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    removed = original_count - deduped_count
    print(
        f"finalize-calls: {original_count} → {deduped_count} edges"
        + (f" ({removed} dupes removed)" if removed else " (no dupes)"),
        file=sys.stderr,
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser():
    parser = argparse.ArgumentParser(
        prog="graph-traversal.py",
        description="Knowledge graph traversal — impact, callers, path, god-nodes.",
    )
    parser.add_argument(
        "--graph",
        default=DEFAULT_GRAPH,
        metavar="PATH",
        help=f"Path to graph.json (default: {DEFAULT_GRAPH})",
    )
    parser.add_argument(
        "--finalize-calls",
        action="store_true",
        help="Sort + dedupe calls[] and atomically rewrite graph.json.",
    )

    sub = parser.add_subparsers(dest="command")

    # impact
    p_impact = sub.add_parser("impact", help="BFS forward+reverse from a node.")
    p_impact.add_argument("node", help="Class or Class.Method to analyse.")
    p_impact.add_argument("--hops", type=int, default=None, help="BFS depth (default 3).")
    p_impact.add_argument("--json", action="store_true", help="Output JSON.")

    # callers
    p_callers = sub.add_parser("callers", help="One-hop reverse lookup (direct callers).")
    p_callers.add_argument("node", help="Class.Method to look up.")
    p_callers.add_argument("--json", action="store_true", help="Output JSON.")

    # path
    p_path = sub.add_parser("path", help="BFS shortest path A → B.")
    p_path.add_argument("a", metavar="NodeA")
    p_path.add_argument("b", metavar="NodeB")
    p_path.add_argument("--json", action="store_true", help="Output JSON.")

    # god-nodes
    p_god = sub.add_parser("god-nodes", help="Rank nodes by in+out degree.")
    p_god.add_argument("--top", type=int, default=None, help="How many to show (default 10).")
    p_god.add_argument("--json", action="store_true", help="Output JSON.")

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    # --finalize-calls is a top-level flag (no subcommand needed)
    if args.finalize_calls:
        cmd_finalize_calls(args)
        return

    if not args.command:
        parser.print_help()
        sys.exit(0)

    ctx = load_graph(args.graph)

    dispatch = {
        "impact":     cmd_impact,
        "callers":    cmd_callers,
        "path":       cmd_path,
        "god-nodes":  cmd_god_nodes,
    }
    dispatch[args.command](args, ctx)


if __name__ == "__main__":
    main()
