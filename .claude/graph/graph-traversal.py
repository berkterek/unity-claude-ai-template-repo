#!/usr/bin/env python3
"""Knowledge graph traversal — impact, callers, path, god-nodes, finalize-calls."""
import argparse
import json
import os
import sys
import tempfile
import difflib
from collections import defaultdict, deque, Counter

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


def require_edges(forward, reverse, label):
    """Exit 0 with suggestion message if call graph is empty."""
    if not forward and not reverse:
        print(
            f"Graph has no call edges yet. Rebuild with: /build-knowledge-graph --full",
            file=sys.stderr,
        )
        sys.exit(0)


def all_nodes(g, forward, reverse):
    """Collect all node identifiers from calls + classes."""
    nodes = set(forward.keys()) | set(reverse.keys())
    for cls in g.get("codebase", {}).get("classes", []):
        name = cls.get("name")
        if name:
            nodes.add(name)
    return nodes


def suggest_node(node, known_nodes):
    """Return difflib suggestions for a missing node."""
    suggestions = difflib.get_close_matches(node, known_nodes, n=3, cutoff=0.5)
    if suggestions:
        return "Did you mean: " + ", ".join(suggestions) + "?"
    return ""


def check_node(node, known_nodes):
    """If node not in known_nodes, print suggestion and exit 0."""
    if node not in known_nodes:
        hint = suggest_node(node, known_nodes)
        msg = f"Node '{node}' not found in graph."
        if hint:
            msg += f" {hint}"
        print(msg, file=sys.stderr)
        sys.exit(0)


# ---------------------------------------------------------------------------
# BFS
# ---------------------------------------------------------------------------

def bfs(adj, start, max_hops):
    """BFS up to max_hops from start. Returns list of (node, depth)."""
    seen = {start}
    frontier = deque([(start, 0)])
    out = []
    while frontier:
        node, d = frontier.popleft()
        if d >= max_hops:
            continue
        for nxt in adj.get(node, ()):
            if nxt in seen:
                continue
            seen.add(nxt)
            out.append((nxt, d + 1))
            frontier.append((nxt, d + 1))
    return out


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_impact(args, ctx):
    g, fwd, rev, edges = ctx
    require_edges(fwd, rev, "impact")
    known = all_nodes(g, fwd, rev)
    check_node(args.node, known)

    down = [n for n, _ in bfs(fwd, args.node, args.hops)]
    up   = [n for n, _ in bfs(rev, args.node, args.hops)]

    result = {
        "root": args.node,
        "hops": args.hops,
        "downstream": sorted(set(down)),
        "upstream": sorted(set(up)),
        "total_affected": len(set(down) | set(up)),
    }

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        # Pretty two-column table
        print(f"Impact analysis for: {args.node}  (hops={args.hops})")
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
    require_edges(fwd, rev, "callers")
    known = all_nodes(g, fwd, rev)
    check_node(args.node, known)

    hits = [
        {
            "caller": e.get("caller", ""),
            "file": e.get("file", None),
            "line": e.get("line", None),
            "confidence": e.get("confidence", None),
        }
        for e in edges
        if e.get("callee") == args.node
    ]

    if not hits:
        print(f"No direct callers found for {args.node}.")
        sys.exit(0)

    if args.json:
        print(json.dumps(hits, indent=2))
    else:
        print(f"Direct callers of: {args.node}")
        for h in hits:
            loc = f"{h['file']}:{h['line']}" if h['file'] else "(unknown)"
            conf = h['confidence'] or ""
            print(f"  {h['caller']:<50}  {loc}  {conf}")


def cmd_path(args, ctx):
    g, fwd, rev, edges = ctx
    require_edges(fwd, rev, "path")
    known = all_nodes(g, fwd, rev)
    check_node(args.a, known)
    check_node(args.b, known)

    if args.a == args.b:
        result = {"from": args.a, "to": args.b, "length": 0, "path": [args.a]}
        print(json.dumps(result, indent=2) if args.json else f"Same node: {args.a}")
        return

    prev = {}
    frontier = deque([args.a])
    seen = {args.a}

    while frontier:
        n = frontier.popleft()
        if n == args.b:
            break
        for nxt in fwd.get(n, ()):
            if nxt in seen:
                continue
            seen.add(nxt)
            prev[nxt] = n
            frontier.append(nxt)

    if args.b not in prev:
        print(f"No path from {args.a} to {args.b} in the call graph.", file=sys.stderr)
        sys.exit(1)

    path = [args.b]
    while path[-1] != args.a:
        path.append(prev[path[-1]])
    path.reverse()

    result = {"from": args.a, "to": args.b, "length": len(path) - 1, "path": path}

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Shortest path: {args.a} → {args.b}  (length={result['length']})")
        print("  " + " → ".join(path))


def cmd_god_nodes(args, ctx):
    g, fwd, rev, edges = ctx
    require_edges(fwd, rev, "god-nodes")

    # Build file lookup from classes[]
    file_map = {}
    for cls in g.get("codebase", {}).get("classes", []):
        name = cls.get("name")
        if name:
            file_map[name] = cls.get("file")

    nodes = set(fwd.keys()) | set(rev.keys())
    ranked = sorted(
        (
            {
                "node": n,
                "in": len(rev[n]),
                "out": len(fwd[n]),
                "total": len(rev[n]) + len(fwd[n]),
                "file": file_map.get(n),
            }
            for n in nodes
        ),
        key=lambda x: -x["total"],
    )[: args.top]

    for r in ranked:
        r["is_god_node"] = r["total"] > 20

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
        os.unlink(tmp_path)
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
    p_impact.add_argument("--hops", type=int, default=3, help="BFS depth (default 3).")
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
    p_god.add_argument("--top", type=int, default=10, help="How many to show (default 10).")
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
