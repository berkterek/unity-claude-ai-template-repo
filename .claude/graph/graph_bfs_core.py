"""graph_bfs_core — pure shared BFS module for knowledge graph traversal.

NO file I/O. NO argparse. NO print / sys.stdout. NO sys.exit.
NO if __name__ == "__main__" block.

Takes loaded graph state as function arguments; returns result objects.
Owns the hops=3 and top=10 signature defaults (exclusively here).
"""
import difflib
from collections import defaultdict, deque


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
# Graph helpers
# ---------------------------------------------------------------------------

def all_nodes(g, forward, reverse):
    """Collect all node identifiers from calls + classes."""
    nodes = set(forward.keys()) | set(reverse.keys())
    for cls in g.get("codebase", {}).get("classes", []):
        name = cls.get("name")
        if name:
            nodes.add(name)
    return nodes


def check_node(node, all_node_set):
    """Return (True, "") if node is present, else (False, suggestion_message)."""
    if node in all_node_set:
        return True, ""
    hint = suggest_node(node, all_node_set)
    msg = f"Node '{node}' not found in graph."
    if hint:
        msg += f" {hint}"
    return False, msg


def suggest_node(node, all_node_set):
    """Return difflib suggestion string for a missing node, or empty string."""
    suggestions = difflib.get_close_matches(node, all_node_set, n=3, cutoff=0.5)
    if suggestions:
        return "Did you mean: " + ", ".join(suggestions) + "?"
    return ""


def require_edges(forward, reverse):
    """Return (True, "") if call edges exist, else (False, message)."""
    if not forward and not reverse:
        return False, "Graph has no call edges yet. Rebuild with: /build-knowledge-graph --full"
    return True, ""


# ---------------------------------------------------------------------------
# Query cores — return result dicts; never print, never exit
# ---------------------------------------------------------------------------

def callers_core(node, g, forward, reverse, edges):
    """One-hop reverse lookup.

    Returns:
        {"ok": True,  "hits": [...]}         — callers found
        {"ok": False, "no_callers": True, "node": node}  — no callers
        {"ok": False, "no_edges": True,  "message": str} — empty graph
        {"ok": False, "not_found": True, "message": str} — node absent
    """
    ok, msg = require_edges(forward, reverse)
    if not ok:
        return {"ok": False, "no_edges": True, "message": msg}

    known = all_nodes(g, forward, reverse)
    found, msg = check_node(node, known)
    if not found:
        return {"ok": False, "not_found": True, "message": msg}

    hits = [
        {
            "caller": e.get("caller", ""),
            "file": e.get("file", None),
            "line": e.get("line", None),
            "confidence": e.get("confidence", None),
        }
        for e in edges
        if e.get("callee") == node
    ]

    if not hits:
        return {"ok": False, "no_callers": True, "node": node}

    return {"ok": True, "hits": hits}


def impact_core(node, g, forward, reverse, edges, hops=3):
    """BFS forward + reverse from node.

    hops=3 is the exclusive owner of this default (Decision 10).
    Accepts None as equivalent to the default.

    Returns:
        {"ok": True,  "root": ..., "hops": ..., "downstream": [...], "upstream": [...], "total_affected": int}
        {"ok": False, "no_edges": True,  "message": str}
        {"ok": False, "not_found": True, "message": str}
    """
    if hops is None:
        hops = 3

    ok, msg = require_edges(forward, reverse)
    if not ok:
        return {"ok": False, "no_edges": True, "message": msg}

    known = all_nodes(g, forward, reverse)
    found, msg = check_node(node, known)
    if not found:
        return {"ok": False, "not_found": True, "message": msg}

    down = [n for n, _ in bfs(forward, node, hops)]
    up   = [n for n, _ in bfs(reverse, node, hops)]

    return {
        "ok": True,
        "root": node,
        "hops": hops,
        "downstream": sorted(set(down)),
        "upstream": sorted(set(up)),
        "total_affected": len(set(down) | set(up)),
    }


def path_core(a, b, g, forward, reverse, edges):
    """BFS shortest path from a to b.

    Returns:
        {"ok": True,  "from": a, "to": b, "length": int, "path": [...]}
        {"ok": False, "same_node": True, "from": a, "to": b, "length": 0, "path": [a]}
        {"ok": False, "no_edges": True,  "message": str}
        {"ok": False, "not_found": True, "message": str}   — a or b absent
        {"ok": False, "no_path": True,   "from": a, "to": b} — no route
    """
    ok, msg = require_edges(forward, reverse)
    if not ok:
        return {"ok": False, "no_edges": True, "message": msg}

    known = all_nodes(g, forward, reverse)

    found_a, msg_a = check_node(a, known)
    if not found_a:
        return {"ok": False, "not_found": True, "message": msg_a}

    found_b, msg_b = check_node(b, known)
    if not found_b:
        return {"ok": False, "not_found": True, "message": msg_b}

    if a == b:
        return {"ok": False, "same_node": True, "from": a, "to": b, "length": 0, "path": [a]}

    prev = {}
    frontier = deque([a])
    seen = {a}

    while frontier:
        n = frontier.popleft()
        if n == b:
            break
        for nxt in forward.get(n, ()):
            if nxt in seen:
                continue
            seen.add(nxt)
            prev[nxt] = n
            frontier.append(nxt)

    if b not in prev:
        return {"ok": False, "no_path": True, "from": a, "to": b}

    path = [b]
    while path[-1] != a:
        path.append(prev[path[-1]])
    path.reverse()

    return {"ok": True, "from": a, "to": b, "length": len(path) - 1, "path": path}


def god_nodes_core(g, forward, reverse, edges, top=10):
    """Rank nodes by in+out degree; prefer pre-computed enhanced_god_nodes when available.

    top=10 is the exclusive owner of this default (Decision 10).
    Accepts None as equivalent to the default.

    Returns:
        {"ok": False, "no_edges": True, "message": str}
        {"ok": True,  "enhanced": bool, "ranked": [...]}
    """
    if top is None:
        top = 10

    ok, msg = require_edges(forward, reverse)
    if not ok:
        return {"ok": False, "no_edges": True, "message": msg}

    # Prefer pre-computed enriched data from graph_analyze.py when available
    enhanced = g.get("analysis", {}).get("enhanced_god_nodes", [])
    if enhanced:
        ranked = sorted(enhanced, key=lambda n: -n.get("total", 0))[:top]
        return {"ok": True, "enhanced": True, "ranked": ranked}

    # Legacy fallback: degree-only computation
    file_map = {}
    for cls in g.get("codebase", {}).get("classes", []):
        name = cls.get("name")
        if name:
            file_map[name] = cls.get("file")

    nodes = set(forward.keys()) | set(reverse.keys())
    ranked = sorted(
        (
            {
                "node": n,
                "in": len(reverse[n]),
                "out": len(forward[n]),
                "total": len(reverse[n]) + len(forward[n]),
                "file": file_map.get(n),
            }
            for n in nodes
        ),
        key=lambda x: -x["total"],
    )[:top]

    for r in ranked:
        r["is_god_node"] = r["total"] > 20

    return {"ok": True, "enhanced": False, "ranked": ranked}
