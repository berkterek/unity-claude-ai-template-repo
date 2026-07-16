# GENERATED-FROM-TEMPLATE — do not edit directly in project repos.
# Changes must be made in unity-claude-ai-template-repo and synced forward.
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
    """Collect all node identifiers from calls + classes + interfaces.

    Interfaces are included so a bare-interface query (e.g. `callers ISoundService`)
    passes check_node — its callers are reached via match_keys, not via the
    forward/reverse keys (callee strings are always Type.Method-shaped, so a bare
    interface token is never itself an adjacency key). REV3 end-to-end path.
    """
    nodes = set(forward.keys()) | set(reverse.keys())
    codebase = g.get("codebase", {})
    for cls in codebase.get("classes", []):
        name = cls.get("name")
        if name:
            nodes.add(name)
    for iface in codebase.get("interfaces", []):
        name = iface.get("name")
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
# RC4 — class-granularity + interface->concrete matching (Task 5)
# ---------------------------------------------------------------------------

def implements_map(g):
    """{concrete_class: set(interfaces)} from codebase.classes[].implements."""
    m = defaultdict(set)
    for cls in g.get("codebase", {}).get("classes", []):
        name = cls.get("name")
        if not name:
            continue
        for iface in cls.get("implements", []) or []:
            m[name].add(iface)
    return m


def match_keys(node, g):
    """Expand a query node (bare `Class` or `Class.Method`) into {key: match_kind}
    for matching against edge `callee` strings.

    One-directional BY DESIGN: concrete class -> its implemented interfaces ONLY.
    We never bridge interface -> implementers (`callers ISvc` is NOT expanded to
    each implementer's direct callers) — that would double-count degree in
    god_nodes/analyze/cluster and conflate distinct call relationships. Do not
    add a bidirectional bridge later.
    """
    im = implements_map(g)
    if "." in node:
        head, _, method = node.partition(".")
        keys = {node: "exact"}
        for iface in im.get(head, ()):
            # REV-methodbridge: a method query also reaches interface-routed
            # DI callers of the same method, so it is never poorer than the
            # bare-class query.
            keys.setdefault(f"{iface}.{method}", "interface_bridge")
        return keys

    keys = {node: "class_prefix"}
    for iface in im.get(node, ()):
        keys.setdefault(iface, "interface_bridge")
    return keys


_MATCH_KIND_PRIORITY = {"exact": 0, "class_prefix": 1, "interface_bridge": 2}


def _callee_match_kind(callee, keys):
    """Best match_kind for `callee` against the `keys` dict from match_keys(), or None.

    Priority: exact > class_prefix > interface_bridge. Matches when the callee's
    full string or head token equals a key, or the callee starts with `key + "."`.
    """
    callee = callee or ""
    head = callee.split(".", 1)[0]
    best = None
    for key, kind in keys.items():
        if callee == key or head == key or callee.startswith(key + "."):
            if best is None or _MATCH_KIND_PRIORITY[kind] < _MATCH_KIND_PRIORITY[best]:
                best = kind
    return best


def class_adjacency(edges, g):
    """(fwd_class, rev_class) — head-collapsed class-level call adjacency, with
    `implements` wired as a first-class BFS relation (REV6), not a query-time
    key bridge like `match_keys`.

    DIRECTION IS LOAD-BEARING: for every concrete class that implements an
    interface, the link goes on `rev_class[concrete]` (+ symmetric
    `fwd_class[interface]`). `impact_core`'s upstream walk uses `rev_class`, so
    `impact <concrete>` can only reach a caller that targets the interface if
    `rev_class[concrete]` contains that interface. Putting the link only on
    `fwd_class[concrete]` (the intuitive-looking but WRONG choice) would leave
    upstream BFS unable to reach interface-only callers.
    """
    fwd_class, rev_class = defaultdict(set), defaultdict(set)
    for e in edges:
        ch = (e.get("caller") or "").split(".", 1)[0]
        eh = (e.get("callee") or "").split(".", 1)[0]
        if ch and eh:
            fwd_class[ch].add(eh)          # caller -> callee
            rev_class[eh].add(ch)          # callee -> caller (upstream / impact walk)
    for concrete, ifaces in implements_map(g).items():
        for iface in ifaces:
            rev_class[concrete].add(iface)  # REV6: upstream(impact) steps concrete -> interface
            fwd_class[iface].add(concrete)  # symmetric; forward/path from interface -> impl
    return fwd_class, rev_class


# ---------------------------------------------------------------------------
# Query cores — return result dicts; never print, never exit
# ---------------------------------------------------------------------------

def callers_core(node, g, forward, reverse, edges):
    """One-hop reverse lookup.

    Returns:
        {"ok": True,  "hits": [...]}         — callers found; each hit carries
            "matched_via" in {"exact", "class_prefix", "interface_bridge"}
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

    targets = match_keys(node, g)
    hits = []
    for e in edges:
        kind = _callee_match_kind(e.get("callee", ""), targets)
        if kind is None:
            continue
        hits.append({
            "caller": e.get("caller", ""),
            "file": e.get("file", None),
            "line": e.get("line", None),
            "confidence": e.get("confidence", None),
            "matched_via": kind,
        })

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

    # REV6: a bare-class node BFSes over class_adjacency, which wires
    # `implements` as a first-class relation so it can reach interface-only
    # callers/callees. A method-specific node keeps method-granularity
    # (unchanged existing behaviour).
    if "." in node:
        fwd, rev = forward, reverse
    else:
        fwd, rev = class_adjacency(edges, g)

    down = [n for n, _ in bfs(fwd, node, hops)]
    up   = [n for n, _ in bfs(rev, node, hops)]

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

    # REV6: only switch to class-granularity when BOTH endpoints are bare
    # class names — a mixed or fully method-specific query keeps the
    # existing method-level adjacency untouched.
    if "." in a or "." in b:
        fwd = forward
    else:
        fwd, _rev = class_adjacency(edges, g)

    prev = {}
    frontier = deque([a])
    seen = {a}

    while frontier:
        n = frontier.popleft()
        if n == b:
            break
        for nxt in fwd.get(n, ()):
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
