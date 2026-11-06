# GENERATED-FROM-TEMPLATE — do not edit directly in project repos.
# Changes must be made in unity-claude-ai-template-repo and synced forward.
"""graph_bfs_core — pure shared BFS module for knowledge graph traversal.

NO file I/O. NO argparse. NO print / sys.stdout. NO sys.exit.
NO if __name__ == "__main__" block.

Takes loaded graph state as function arguments; returns result objects.
Owns the hops=3 and top=10 signature defaults (exclusively here).
"""
import difflib
import math
import re
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


# ---------------------------------------------------------------------------
# Symbol lookup — `where` / `what` (Task 8)
# ---------------------------------------------------------------------------

CHARS_PER_TOKEN = 2.5
_MEMBER_KINDS = (("methods", "method"), ("properties", "property"), ("fields", "field"))
_REGISTER_RE = re.compile(r"^(Register\w*)<([\w.]+)>$")
_MORE_SAMPLE = "… +999 more (raise --budget)"


def est_tokens(s):
    """Estimated token count of `s` (ceil(len / CHARS_PER_TOKEN))."""
    return math.ceil(len(s) / CHARS_PER_TOKEN)


def _types(g):
    """[(kind, record)] for every class and interface in the graph."""
    cb = g.get("codebase", {})
    out = [(c.get("kind") or "class", c) for c in cb.get("classes", []) or []]
    out.extend(("interface", i) for i in cb.get("interfaces", []) or [])
    return out


def _candidate(kind, owner, rec, file, signature=None):
    return {
        "kind": kind,
        "owner": owner,
        "name": rec.get("name", ""),
        "file": file,
        "line": rec.get("line"),
        "end_line": rec.get("end_line"),
        "signature": signature if signature is not None else rec.get("signature"),
        "doc": rec.get("doc"),
        "record": rec,
    }


def _type_candidate(kind, rec):
    bases = rec.get("base_types") or []
    sig = f"{kind} {rec.get('name', '')}" + (" : " + ", ".join(bases) if bases else "")
    return _candidate(kind, rec.get("namespace") or None, rec, rec.get("file"), sig)


def _member_candidates(type_kind, trec, member=None):
    out = []
    for key, mkind in _MEMBER_KINDS:
        for m in trec.get(key, []) or []:
            if member is not None and m.get("name") != member:
                continue
            sig = m.get("signature")
            if sig is None and m.get("type"):
                sig = f"{m['type']} {m.get('name', '')}"
            out.append(_candidate(mkind, trec.get("name"), m, trec.get("file"), sig))
    return out


def _registration_hits(g, name):
    """[(holder_rec, reg)] where the registration's type, factory_of or as_resolved names `name`."""
    out = []
    vc = g.get("codebase", {}).get("vcontainer", {}) or {}
    for holder in (vc.get("installers") or []) + (vc.get("scopes") or []):
        for reg in holder.get("registrations") or []:
            if name in (reg.get("type"), reg.get("factory_of")) or name in (reg.get("as_resolved") or ()):
                out.append((holder, reg))
    return out


def _registration_candidate(holder, reg, target):
    method = reg.get("method", "")
    rec = {"name": f"{method}<{target}>", "line": reg.get("line"), "end_line": reg.get("line")}
    return _candidate("registration", holder.get("name"), rec, holder.get("file"),
                      ".".join(reg.get("chain") or []) or None) | {"record": reg}


def resolve_symbol(name, g):
    """Candidates for `Type`, `Type.Member`, bare `Member` or `Register*<T>`; [] if unknown.

    Each candidate: {kind, owner, name, file, line, end_line, signature, doc, record}.
    A bare name resolves to types first; members are searched only when no type matches.
    """
    m = _REGISTER_RE.match(name)
    if m:
        method, target = m.groups()
        vc = g.get("codebase", {}).get("vcontainer", {}) or {}
        return [_registration_candidate(h, r, target)
                for h in (vc.get("installers") or []) + (vc.get("scopes") or [])
                for r in h.get("registrations") or []
                if r.get("method") == method and target in (r.get("type"), r.get("factory_of"))]

    types = _types(g)
    if "." in name:
        owner, _, member = name.partition(".")
        return [c for kind, t in types if t.get("name") == owner for c in _member_candidates(kind, t, member)]

    exact = [_type_candidate(kind, t) for kind, t in types if t.get("name") == name]
    if exact:
        return exact
    return [c for kind, t in types for c in _member_candidates(kind, t, name)]


def _suggestion(name, g):
    types = _types(g)
    owner, dot, member = name.partition(".")
    if dot:
        pool = [f"{t.get('name')}.{c['name']}" for _, t in types if t.get("name") == owner
                for c in _member_candidates("", t)]
        hint = suggest_node(name, pool) if pool else ""
        if hint:
            return hint
        name = owner
    pool = {t.get("name") for _, t in types if t.get("name")}
    for kind, t in types:
        pool.update(c["name"] for c in _member_candidates(kind, t))
    return suggest_node(name, pool)


def _not_found(name, g):
    msg = f"Symbol '{name}' not found in graph."
    hint = _suggestion(name, g)
    return {"ok": False, "not_found": True, "message": msg + (" " + hint if hint else "")}


def where_core(name, g):
    """Locate a symbol: file, line range and the matching ranged-Read arguments.

    Returns {"ok": True, "hits": [{kind, owner, name, file, line, end_line, read}], "ambiguous": bool}
    where read is {"offset", "limit"} or None when end_line is unavailable, or
    {"ok": False, "not_found": True, "message": str}.
    """
    cands = resolve_symbol(name, g)
    if not cands:
        return _not_found(name, g)
    hits = []
    for c in cands:
        line, end = c["line"], c["end_line"]
        read = {"offset": line, "limit": end - line + 1} if line is not None and end is not None else None
        hits.append({"kind": c["kind"], "owner": c["owner"], "name": c["name"], "file": c["file"],
                     "line": line, "end_line": end, "read": read})
    return {"ok": True, "hits": hits, "ambiguous": len(hits) > 1}


def budget_truncate(sections, budget_tokens):
    """Join [(name, [lines])] under a token budget -> (text, truncated).

    The first section (header) is always kept whole. The first section that does not fit is
    filled line by line, then `… +N more (raise --budget)` is appended and later sections are dropped.
    """
    out = []
    used = 0
    for idx, (_name, lines) in enumerate(sections):
        if not lines:
            continue
        if idx == 0:
            out.extend(lines)
            used += sum(est_tokens(ln) + 1 for ln in lines)
            continue
        if used + sum(est_tokens(ln) + 1 for ln in lines) <= budget_tokens:
            out.extend(lines)
            used += sum(est_tokens(ln) + 1 for ln in lines)
            continue
        reserve = est_tokens(_MORE_SAMPLE) + 1
        kept = 0
        for ln in lines:
            cost = est_tokens(ln) + 1
            if used + cost + reserve > budget_tokens:
                break
            out.append(ln)
            used += cost
            kept += 1
        tail = sum(len(ls) for _, ls in sections[idx + 1:])
        marker = f"… +{len(lines) - kept + tail} more (raise --budget)"
        while kept > 0 and used + est_tokens(marker) + 1 > budget_tokens:
            out.pop()
            used -= est_tokens(lines[kept - 1]) + 1
            kept -= 1
            marker = f"… +{len(lines) - kept + tail} more (raise --budget)"
        # Exception: when even the bare marker exceeds the budget, it is still emitted -
        # it is the only signal that output was truncated.
        out.append(marker)
        return "\n".join(out), True
    return "\n".join(out), False


def _range(line, end):
    if line is None:
        return "?"
    return str(line) if end is None else f"{line}-{end}"


def _header_lines(c):
    head = f"{c['kind']} {c['name']}" if not c["owner"] or c["kind"] in ("class", "interface") \
        else f"{c['kind']} {c['owner']}.{c['name']}"
    loc = f"{c['file']}:{_range(c['line'], c['end_line'])}"
    if c["end_line"] is None and c["kind"] != "registration":
        loc += "  (range unavailable (no end_line in this graph — regex extractor or a graph built before extraction_version 7; rebuild with --full))"
    lines = [head, "  " + loc]
    if c["kind"] in ("class", "interface") and c["owner"]:
        lines[0] += f"  [{c['owner']}]"
    if c["signature"]:
        lines.append("  signature: " + str(c["signature"]))
    return lines


def _doc_lines(doc):
    if not isinstance(doc, dict):
        return []
    lines = []
    if doc.get("summary"):
        lines.append("summary: " + doc["summary"])
    if doc.get("remarks"):
        lines.append("remarks: " + doc["remarks"])
    return lines


def _reg_line(holder, reg):
    target = reg.get("type") or reg.get("factory_of") or "?"
    parts = [f"{holder.get('name')}: {reg.get('method', '')}<{target}>"]
    if reg.get("chain"):
        parts.append("chain=" + ".".join(reg["chain"]))
    if reg.get("as"):
        parts.append("as=" + reg["as"])
    if reg.get("as_resolved"):
        parts.append("as_resolved=" + ",".join(reg["as_resolved"]))
    parts.append(f"(line {reg.get('line')})")
    return "  " + " ".join(parts)


def _dispatch_label(n):
    return "high" if n <= 1 else ("medium" if n <= 3 else "low")


def _implementer_lines(g, rec):
    name = rec.get("name")
    where = {}
    for impl in rec.get("implementers") or []:
        where.setdefault(impl, None)
    for c in g.get("codebase", {}).get("classes", []) or []:
        if name in (c.get("implements") or []):
            where[c.get("name")] = c
    classes = None
    lines = []
    for impl, c in sorted(where.items()):
        if c is None:
            if classes is None:
                classes = {x.get("name"): x for x in g.get("codebase", {}).get("classes", []) or []}
            c = classes.get(impl)
        loc = f" ({c.get('file')}:{c.get('line')})" if c else ""
        lines.append(f"  {impl}{loc}")
    n = len(lines)
    return [f"implementers: dispatch: {n} implementer(s) ({_dispatch_label(n)} confidence)"] + lines


def _caller_lines(c, g, forward, reverse, edges):
    if c["kind"] in ("class", "interface"):
        node = c["name"]
    elif c["kind"] == "method":
        node = f"{c['owner']}.{c['name']}"
    else:
        return []
    res = callers_core(node, g, forward, reverse, edges)
    if not res.get("ok"):
        return []
    hits = sorted(res["hits"], key=lambda h: (str(h.get("file")), h.get("line") or 0))
    return [f"callers ({len(hits)}):"] + [
        f"  {h['caller']} ({h['file']}:{h['line']}) [{h['matched_via']}]" for h in hits]


def _member_lines(c):
    rec = c["record"]
    lines = []
    for m in _member_candidates(c["kind"], rec):
        lines.append(f"  {m['name']} {_range(m['line'], m['end_line'])}  {m['signature'] or ''}".rstrip())
    return ["members:"] + lines if lines else []


def what_core(name, g, forward, reverse, edges, budget_tokens=2000):
    """One-call symbol briefing, trimmed to `budget_tokens`.

    Returns {"ok": True, "text": str, "truncated": bool, "sections": [names]} or
    {"ok": False, "not_found": True, "message": str}. An ambiguous bare member name yields
    a candidate list (header only); qualify it as Type.Member.
    """
    cands = resolve_symbol(name, g)
    if not cands:
        return _not_found(name, g)
    if len(cands) > 1:
        lines = [f"ambiguous: {len(cands)} candidates for '{name}' — qualify as Type.Member"]
        lines += [f"  {c['kind']} {c['owner']}.{c['name']}  {c['file']}:{_range(c['line'], c['end_line'])}"
                  for c in cands]
        return {"ok": True, "text": "\n".join(lines), "truncated": False, "sections": ["header"]}

    c = cands[0]
    is_type = c["kind"] in ("class", "interface")
    secs = [("header", _header_lines(c)), ("doc", _doc_lines(c["doc"]))]
    if c["kind"] == "registration":
        holder = {"name": c["owner"]}
        secs.append(("registrations", ["registrations:", _reg_line(holder, c["record"])]))
    elif is_type:
        regs = _registration_hits(g, c["name"])
        if regs:
            secs.append(("registrations", ["registrations:"] + [_reg_line(h, r) for h, r in regs]))
    if c["kind"] == "interface":
        secs.append(("implementers", _implementer_lines(g, c["record"])))
    secs.append(("callers", _caller_lines(c, g, forward, reverse, edges)))
    if is_type:
        secs.append(("members", _member_lines(c)))
    secs = [s for s in secs if s[1]]
    text, truncated = budget_truncate(secs, budget_tokens)
    return {"ok": True, "text": text, "truncated": truncated, "sections": [n for n, _ in secs]}
