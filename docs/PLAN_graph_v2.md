# PLAN — Graph Module v2 (Graphify-Inspired Extension)

> **Version:** v1 — 2026-06-08
> **Status:** Active
> **Scope:** `.claude/graph/` (Python modules, schema v1.2.0, builder integration), `.claude/commands/knowledge-graph.md`, `.claude/graph/test/`

> **Complexity Score: 0.72 / 1.0 — Complex**
> Rationale: 4 net-new Python modules with non-trivial algorithms (community detection, surprising-connection heuristics, accuracy diff), a schema version bump that downstream queries depend on, an optional `tree-sitter` dependency that must degrade gracefully, two new `/knowledge-graph` subcommands, and integration into a 510-line builder that already has SHA256 cache, MCP merge, ghost purge, and atomic write. Lowered from 0.85 because (a) all new modules are read-only (run AFTER atomic write), (b) builder integration is additive (no rewrite of existing flow), and (c) fallback paths exist for every new feature (stdlib community detection, regex C# extraction).

## Context

The graph module today (`schema_version: 1.1.0`) gives us classes, interfaces, events, VContainer scopes, assemblies, scenes/prefabs (via MCP), call edges, and BFS traversals (impact/path/god-nodes/callers). It is mature but **structurally flat** — every node is queryable, but there is no notion of *modules / communities* that group related classes, no analysis of *surprising connections* (cross-domain coupling that may indicate architectural drift), and no automated *accuracy validation* that compares the graph against the source.

Graphify (the inspiration) ships these as first-class outputs. We adopt the same shape: introduce a `communities[]` block alongside `classes[]`, an `analysis{}` block for surprising-connection and enhanced god-node reports, and a `graph_validate.py` accuracy pipeline that produces a `validation.accuracy{}` report. We also land the `csharp_extractor.py` wrapper around tree-sitter that has been deferred since v1.1.0 — the bash extractor remains the fallback when tree-sitter is not installed.

All new logic runs **after** the atomic write in `graph-builder.sh` (read-only, non-fatal, exit 0 always) so a crash in any new module cannot corrupt `graph.json`. The schema bumps to `1.2.0` (additive — every new field is optional, old consumers continue to work).

## Goals

- [ ] G1 — `csharp_extractor.py` produces EXTRACTED-confidence output via tree-sitter; bash extractor remains regex fallback.
- [ ] G2 — `graph_cluster.py` writes `codebase.communities[]` using stdlib greedy modularity (Louvain via `networkx` as optional pip upgrade).
- [ ] G3 — `graph_analyze.py` writes `analysis.surprising_connections[]` and `analysis.enhanced_god_nodes[]` to `graph.json`.
- [ ] G4 — `graph_validate.py` writes `validation.accuracy{}` by sampling N classes and verifying extraction matches source.
- [ ] G5 — Schema `1.1.0 → 1.2.0` with additive `codebase.communities[]`, `analysis{}`, and `validation.accuracy{}` definitions.
- [ ] G6 — Two new `/knowledge-graph` subcommands: `communities` and `surprising`.
- [ ] G7 — `verify-graphify.sh` gains a T9 section covering all four new modules + schema validation.
- [ ] G8 — All new modules degrade gracefully (exit 0, missing-dep messages) — never block a build.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — Schema bump to v1.2.0 (additive defs) | ⏳ Pending | P1 |
| 1 | T2 — `csharp_extractor.py` (tree-sitter wrapper) | ⏳ Pending | P1 |
| 2 | T3 — `graph_cluster.py` (community detection) | ⏳ Pending | P2 |
| 2 | T4 — `graph_analyze.py` (surprising + god-nodes) | ⏳ Pending | P2 |
| 2 | T5 — `graph_validate.py` (accuracy validation) | ⏳ Pending | P2 |
| 3 | T6 — `graph-builder.sh` post-write hook integration | ⏳ Pending | — |
| 4 | T7 — `/knowledge-graph communities` subcommand | ⏳ Pending | P4 |
| 4 | T7b — Update `graph-traversal.py` god-nodes to prefer `analysis.enhanced_god_nodes[]` | ⏳ Pending | P4 |
| 4 | T8 — `/knowledge-graph surprising` subcommand | ⏳ Pending | P4 |
| 5 | T9 — Test additions in `verify-graphify.sh` | ⏳ Pending | — |
| 5 | T10 — Update docs (`knowledge-graph.md`, `build-knowledge-graph.md`) | ⏳ Pending | — |

T1 and T2 are independent (P1 — parallel). T3/T4/T5 depend on T1 schema definitions (P2 — parallel with each other, sequential after P1). T6 depends on T3+T4+T5. T7/T8 depend on T3+T4 (P4 — parallel). T9/T10 are last (sequential).

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/graph/schema.json` | Modify | T1 — bump version, add `communityEntry`, `analysisBlock`, `accuracyReport`, `surprisingConnection` defs |
| `.claude/graph/extractors/csharp_extractor.py` | Add | T2 — tree-sitter wrapper, JSON output matching `csharp-extractor.sh` shape |
| `.claude/graph/extractors/csharp-extractor.sh` | Modify | T2 — preflight: call `python3 csharp_extractor.py` first; fall back to bash regex on non-zero |
| `.claude/graph/graph_cluster.py` | Add | T3 — reads + rewrites `graph.json` atomically with `communities[]` |
| `.claude/graph/graph_analyze.py` | Add | T4 — reads + rewrites with `analysis.surprising_connections[]`, `analysis.enhanced_god_nodes[]` |
| `.claude/graph/graph_validate.py` | Add | T5 — reads + rewrites with `validation.accuracy{}` |
| `.claude/graph/graph-builder.sh` | Modify | T6 — after atomic write (~line 501), invoke 3 new modules; bump schema_version to 1.2.0 |
| `.claude/graph/graph-traversal.py` | Modify | T7b — `cmd_god_nodes()` prefers `analysis.enhanced_god_nodes[]` when present |
| `.claude/commands/knowledge-graph.md` | Modify | T7+T8 — add `communities` and `surprising` subcommand sections |
| `.claude/graph/test/verify-graphify.sh` | Modify | T9 — add T9 section (6 new tests) |
| `.claude/graph/test/fixtures/v2_communities/` | Add | T9 — minimal fixture C# files for cluster/analyze/validate tests |
| `.claude/docs/knowledge-graph.md` | Modify | T10 — v1.2.0 changelog, new fields, new subcommands |
| `.claude/commands/build-knowledge-graph.md` | Modify | T10 — Step 6 summary: Communities + Accuracy lines |

---

## Task T1 — Schema bump to v1.2.0

**Files:**
- `.claude/graph/schema.json`

**parallel_group:** P1

**Steps:**
1. [ ] Update `description` to mention v1.2.0 changes: communities, analysis, accuracy.
2. [ ] Inside `codebase`, add an optional `communities` array referencing `#/definitions/communityEntry`.
3. [ ] Add a top-level optional `analysis` property referencing `#/definitions/analysisBlock`.
4. [ ] Inside `validation`, add an optional `accuracy` property referencing `#/definitions/accuracyReport`.
5. [ ] Add four new definitions: `communityEntry`, `analysisBlock`, `surprisingConnection`, `accuracyReport`.
6. [ ] Validate: `python3 -c "import json; json.load(open('.claude/graph/schema.json'))"` must succeed.

**Test Type:** NoTest _(JSON schema — covered by T9 jq-shape assertions)_

**Code Skeleton:**
```json
"communityEntry": {
  "type": "object",
  "required": ["id", "members"],
  "properties": {
    "id":         { "type": "integer" },
    "label":      { "type": "string" },
    "members":    { "type": "array", "items": { "type": "string" } },
    "size":       { "type": "integer" },
    "modularity": { "type": "number" },
    "scope":      { "type": "string" },
    "algorithm":  { "type": "string", "enum": ["greedy-modularity-stdlib", "louvain-networkx"] }
  }
},
"analysisBlock": {
  "type": "object",
  "properties": {
    "generated_at":           { "type": "string" },
    "surprising_connections": { "type": "array", "items": { "$ref": "#/definitions/surprisingConnection" } },
    "enhanced_god_nodes":     { "type": "array" }
  }
},
"surprisingConnection": {
  "type": "object",
  "required": ["caller", "callee", "reason"],
  "properties": {
    "caller":           { "type": "string" },
    "callee":           { "type": "string" },
    "caller_community": { "type": "integer" },
    "callee_community": { "type": "integer" },
    "caller_scope":     { "type": "string" },
    "callee_scope":     { "type": "string" },
    "reason":           { "type": "string", "enum": ["CROSS_COMMUNITY", "CROSS_SCOPE", "CROSS_ASSEMBLY"] },
    "severity":         { "type": "string", "enum": ["info", "warning"] }
  }
},
"accuracyReport": {
  "type": "object",
  "properties": {
    "sampled_classes": { "type": "integer" },
    "matches":         { "type": "integer" },
    "mismatches":      { "type": "integer" },
    "agreement_pct":   { "type": "number" },
    "checks":          { "type": "array" }
  }
}
```

**Acceptance Criteria:**
- `schema.json` parses as valid JSON.
- Existing `graph.json` still validates (additive change — no required fields added to existing entries).
- `schema_version` in schema description matches `1.2.0`.

---

## Task T2 — `csharp_extractor.py` (tree-sitter wrapper)

**Files:**
- `.claude/graph/extractors/csharp_extractor.py` (new)
- `.claude/graph/extractors/csharp-extractor.sh` (modify — add preflight)

**parallel_group:** P1

**Steps:**
1. [ ] Create `csharp_extractor.py`. CLI: `--changed-files a.cs,b.cs` (same as bash extractor).
2. [ ] Try importing `tree_sitter` and `tree_sitter_c_sharp`. On failure, print one stderr line and `sys.exit(2)`.
3. [ ] Walk AST: `class_declaration` → emit class entry with `confidence: "EXTRACTED"`.
4. [ ] Inside each class: `method_declaration` → emit `methods[]` entries.
5. [ ] Inside each method body: `invocation_expression` → emit `partial_calls[]` entries.
6. [ ] Detect VContainer registrations (`builder.Register<T>`) and IEventBus publish/subscribe.
7. [ ] Output JSON matching the bash extractor shape: `{classes, interfaces, events, vcontainer{installers,scopes}, partial_calls}`.
8. [ ] In `csharp-extractor.sh`: insert preflight block at the top of the main extraction logic. If `python3 csharp_extractor.py` exits 0 with non-empty stdout, use that output and `exit 0`. Otherwise continue with existing regex pipeline.

**Test Type:** NoTest _(integration verified by T9)_

**Code Skeleton:**
```python
#!/usr/bin/env python3
# csharp_extractor.py — tree-sitter C# AST extractor.
# Optional dep: pip install tree-sitter tree-sitter-c-sharp
# Exit codes: 0=success, 1=parse error, 2=tree-sitter unavailable
import sys, json, argparse, os

def _try_import():
    try:
        import tree_sitter_c_sharp as ts_cs
        from tree_sitter import Language, Parser
        return Language(ts_cs.language()), Parser
    except Exception as e:
        print(f"csharp_extractor.py: tree-sitter unavailable ({e})", file=sys.stderr)
        sys.exit(2)

def extract_file(parser, path):
    src = open(path, 'rb').read()
    tree = parser.parse(src)
    # walk tree.root_node for class_declaration, method_declaration, invocation_expression
    return {"classes": [], "interfaces": [], "partial_calls": []}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--changed-files", default="")
    args = ap.parse_args()
    lang, ParserCls = _try_import()
    p = ParserCls(); p.language = lang
    files = [f for f in args.changed_files.split(",") if f.strip().endswith(".cs")]
    out = {"classes": [], "interfaces": [], "events": [],
           "vcontainer": {"installers": [], "scopes": []}, "partial_calls": []}
    for f in files:
        r = extract_file(p, f)
        out["classes"].extend(r["classes"])
        out["partial_calls"].extend(r["partial_calls"])
    print(json.dumps(out))

if __name__ == "__main__": main()
```

```bash
# csharp-extractor.sh preflight (insert before existing regex pipeline).
# Safe under set -euo pipefail: subshell captures exit code explicitly.
_EXTRACTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v python3 >/dev/null 2>&1 && [[ -f "$_EXTRACTOR_DIR/csharp_extractor.py" ]]; then
  TS_OUT=""
  TS_EXIT=0
  TS_OUT=$(python3 "$_EXTRACTOR_DIR/csharp_extractor.py" \
    --changed-files "$CHANGED_FILES" 2>/dev/null) || TS_EXIT=$?
  if [[ $TS_EXIT -eq 0 && -n "$TS_OUT" ]]; then
    echo "$TS_OUT"; exit 0
  fi
  # TS_EXIT=2 means tree-sitter unavailable → fall through to regex (INFERRED)
fi
# ... existing regex pipeline continues unchanged — confidence remains INFERRED ...
```

**Acceptance Criteria:**
- With tree-sitter installed: output has `confidence: "EXTRACTED"` on all class entries.
- Without tree-sitter: exits 2, stderr has one line, `csharp-extractor.sh` continues via regex.
- `graph-builder.sh` receives the same JSON shape regardless of which path ran.

---

## Task T3 — `graph_cluster.py` (community detection)

**Files:**
- `.claude/graph/graph_cluster.py` (new)

**parallel_group:** P2

**Steps:**
1. [ ] CLI: `python3 graph_cluster.py --graph PATH [--algorithm auto|stdlib|louvain] [--min-size 2]`.
2. [ ] Load graph. If `codebase.calls[]` is empty, exit 0 with stderr message.
3. [ ] Build class-level undirected adjacency from calls: `caller.split('.')[0]` ↔ `callee.split('.')[0]`, self-loops excluded.
4. [ ] Algorithm dispatch: if `networkx` available and `--algorithm auto|louvain`, use `networkx.community.louvain_communities(seed=42)`. Otherwise use stdlib greedy (3-pass degree-sorted neighbour merge).
5. [ ] For each community, derive `label` from the dominant assembly name (most files in common path prefix); set `scope` if all members share one VContainer scope.
6. [ ] Set `algorithm` field to `"louvain-networkx"` or `"greedy-modularity-stdlib"`.
7. [ ] Atomic write: temp file → `jq empty` validate → `os.replace`.
8. [ ] Exit 0 on all exceptions (print to stderr).

**Test Type:** NoTest _(T9 asserts `codebase.communities | length >= 1` on populated graph)_

**Code Skeleton:**
```python
#!/usr/bin/env python3
import json, os, sys, argparse, tempfile
from collections import defaultdict

def stdlib_greedy(nodes, adj):
    community = {n: i for i, n in enumerate(nodes)}
    for _ in range(3):
        changed = False
        for n in sorted(nodes, key=lambda x: -len(adj[x])):
            counts = defaultdict(int)
            for m in adj[n]: counts[community[m]] += 1
            if counts:
                best = max(counts.items(), key=lambda kv: kv[1])
                if best[0] != community[n] and best[1] > 1:
                    community[n] = best[0]; changed = True
        if not changed: break
    remap = {}
    for n in nodes:
        c = community[n]
        if c not in remap: remap[c] = len(remap)
        community[n] = remap[c]
    return community

def atomic_write(g, path):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f: json.dump(g, f, indent=2)
    os.replace(tmp, path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--graph", required=True)
    ap.add_argument("--algorithm", default="auto", choices=["auto","stdlib","louvain"])
    ap.add_argument("--min-size", type=int, default=2)
    args = ap.parse_args()
    try:
        with open(args.graph) as f: g = json.load(f)
        calls = g.get("codebase", {}).get("calls", []) or []
        if not calls:
            print("graph_cluster: no call edges — skipping", file=sys.stderr); return
        adj = defaultdict(set); nodes = set()
        for e in calls:
            a = e["caller"].split(".")[0]; b = e["callee"].split(".")[0]
            if a and b and a != b:
                adj[a].add(b); adj[b].add(a); nodes.add(a); nodes.add(b)
        nodes = sorted(nodes)
        algo = "greedy-modularity-stdlib"
        try:
            if args.algorithm in ("auto", "louvain"):
                import networkx as nx
                from networkx.algorithms.community import louvain_communities
                G = nx.Graph()
        for u in adj:
            for v in adj[u]: G.add_edge(u, v)
                comms = louvain_communities(G, seed=42)
                community = {n: i for i, c in enumerate(comms) for n in c}
                algo = "louvain-networkx"
            else: raise ImportError
        except Exception: community = stdlib_greedy(nodes, adj)
        buckets = defaultdict(list)
        for n, c in community.items(): buckets[c].append(n)
        assemblies = g["codebase"].get("assemblies", [])
        classes_by_name = {c["name"]: c for c in g["codebase"].get("classes", [])}
        communities = []
        for cid, members in sorted(buckets.items()):
            if len(members) < args.min_size: continue
            communities.append({
                "id": cid, "members": sorted(members), "size": len(members),
                "label": f"community-{sorted(members)[0]}", "scope": "",
                "modularity": 0.0, "algorithm": algo
            })
        g.setdefault("codebase", {})["communities"] = communities
        atomic_write(g, args.graph)
        print(f"graph_cluster: {len(communities)} communities ({algo})", file=sys.stderr)
    except Exception as e:
        print(f"graph_cluster: error — {e}", file=sys.stderr)

if __name__ == "__main__": main()
```

**Acceptance Criteria:**
- `graph.json` after run has `codebase.communities[]`; each entry has `id`, `members`, `algorithm`.
- Exits 0 on empty edges and on exceptions.
- `jq empty graph.json` still passes after run.
- `algorithm` = `"greedy-modularity-stdlib"` when networkx unavailable.

---

## Task T4 — `graph_analyze.py` (surprising connections + enhanced god-nodes)

**Files:**
- `.claude/graph/graph_analyze.py` (new)

**parallel_group:** P2

**Steps:**
1. [ ] CLI: `python3 graph_analyze.py --graph PATH [--top-god 10] [--max-surprising 50]`.
2. [ ] Load graph. If `codebase.communities[]` missing or empty, print stderr and exit 0.
3. [ ] Build `comm_of` map: `{class_name: community_id}` from `communities[].members`.
4. [ ] Build `scope_of` map: from `vcontainer.scopes[].installers` chain → which scope owns each installer → which installer registers each class.
5. [ ] Build `asm_of` map: from `classes[].file` prefix matched against `assemblies[].file` directory.
6. [ ] For each call edge: classify as CROSS_SCOPE (warning), CROSS_ASSEMBLY (info), or CROSS_COMMUNITY (info). Emit the strongest. Exclude edges where either endpoint is unknown.
7. [ ] Sort: warnings first, then by caller name. Cap at `--max-surprising`.
8. [ ] Enhanced god-nodes: top-N by total degree (reuse existing god-nodes logic), attach `community_id` and `cross_community_edges` count. Severity: `critical` if cross > 10, `warning` if > 3, else `info`.
9. [ ] Atomic write: set `analysis.generated_at`, `analysis.surprising_connections`, `analysis.enhanced_god_nodes`.
10. [ ] Exit 0 on all exceptions.

**Test Type:** NoTest _(T9 asserts `analysis.surprising_connections` present)_

**Code Skeleton:**
```python
#!/usr/bin/env python3
import json, os, sys, argparse, tempfile
from collections import defaultdict
from datetime import datetime, timezone

def classify_edge(a, b, comm_of, scope_of, asm_of):
    if scope_of.get(a) and scope_of.get(b) and scope_of[a] != scope_of[b]:
        return "CROSS_SCOPE", "warning"
    if asm_of.get(a) and asm_of.get(b) and asm_of[a] != asm_of[b]:
        return "CROSS_ASSEMBLY", "info"
    if comm_of.get(a) is not None and comm_of.get(b) is not None and comm_of[a] != comm_of[b]:
        return "CROSS_COMMUNITY", "info"
    return None, None

def atomic_write(g, path):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f: json.dump(g, f, indent=2)
    os.replace(tmp, path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--graph", required=True)
    ap.add_argument("--top-god", type=int, default=10)
    ap.add_argument("--max-surprising", type=int, default=50)
    args = ap.parse_args()
    try:
        with open(args.graph) as f: g = json.load(f)
        communities = g.get("codebase", {}).get("communities", [])
        if not communities:
            print("graph_analyze: no communities[] — run graph_cluster.py first", file=sys.stderr); return
        comm_of = {m: c["id"] for c in communities for m in c["members"]}
        # Build scope_of from vcontainer
        scope_of = {}
        for scope in g["codebase"].get("vcontainer", {}).get("scopes", []):
            for inst_name in scope.get("installers", []):
                for inst in g["codebase"].get("vcontainer", {}).get("installers", []):
                    if inst["name"] == inst_name:
                        for reg in inst.get("registrations", []):
                            scope_of[reg.get("type", "")] = scope["name"]
        # Build asm_of from classes[].file prefix vs assemblies
        asm_of = {}
        assemblies = g["codebase"].get("assemblies", [])
        for cls in g["codebase"].get("classes", []):
            f = cls.get("file", "")
            for a in assemblies:
                if f.startswith(os.path.dirname(a.get("file", "??"))):
                    asm_of[cls["name"]] = a["name"]; break
        # Classify edges
        surprising = []
        degree = defaultdict(lambda: {"in": 0, "out": 0})
        cross_count = defaultdict(int)
        for e in g["codebase"].get("calls", []):
            a = e["caller"].split(".")[0]; b = e["callee"].split(".")[0]
            degree[a]["out"] += 1; degree[b]["in"] += 1
            reason, sev = classify_edge(a, b, comm_of, scope_of, asm_of)
            if reason:
                surprising.append({
                    "caller": e["caller"], "callee": e["callee"],
                    "caller_community": comm_of.get(a), "callee_community": comm_of.get(b),
                    "caller_scope": scope_of.get(a, ""), "callee_scope": scope_of.get(b, ""),
                    "reason": reason, "severity": sev,
                })
                cross_count[a] += 1
        surprising.sort(key=lambda x: (x["severity"] != "warning", x["caller"]))
        surprising = surprising[:args.max_surprising]
        # Enhanced god-nodes
        god_nodes = []
        for n, d in sorted(degree.items(), key=lambda kv: -(kv[1]["in"]+kv[1]["out"]))[:args.top_god]:
            total = d["in"] + d["out"]
            cc = cross_count[n]
            sev = "critical" if cc > 10 else ("warning" if cc > 3 else "info")
            god_nodes.append({
                "node": n, "in": d["in"], "out": d["out"], "total": total,
                "community_id": comm_of.get(n), "cross_community_edges": cc,
                "is_god_node": total > 20, "severity": sev,
            })
        g["analysis"] = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "surprising_connections": surprising,
            "enhanced_god_nodes": god_nodes,
        }
        atomic_write(g, args.graph)
        print(f"graph_analyze: {len(surprising)} surprising, {len(god_nodes)} god-nodes", file=sys.stderr)
    except Exception as e:
        print(f"graph_analyze: error — {e}", file=sys.stderr)

if __name__ == "__main__": main()
```

**Acceptance Criteria:**
- `analysis.surprising_connections[]` present; each entry has valid `reason` and `severity`.
- `analysis.enhanced_god_nodes[]` present; each entry has `community_id`.
- Exits 0 when communities missing (warns to stderr).
- Exits 0 on exceptions.

---

## Task T5 — `graph_validate.py` (accuracy validation)

**Files:**
- `.claude/graph/graph_validate.py` (new)

**parallel_group:** P2

**Steps:**
1. [ ] CLI: `python3 graph_validate.py --graph PATH [--sample N] [--seed 42]`.
2. [ ] Load graph. Sample min(N, len(classes)) classes using `random.Random(seed)`.
3. [ ] For each sampled class, open `source_file` and run grep-style checks:
   - `class <name>` present in file → `declaration` check.
   - Each `methods[].name` appears as `<name>(` pattern → `method:<name>` check.
   - Each `events_published[]` appears as `Publish<Event>` or `new Event(` → `event_pub:<name>` check.
4. [ ] Aggregate: `matches`, `mismatches`, `agreement_pct = round(matches / total * 100, 1)`.
5. [ ] Write `validation.accuracy{}`. If `agreement_pct < 90`, set `validation.accuracy.low_accuracy_warning = true` and a `warning_message` string — **do NOT append to `validation.warnings[]`** because `graph-validator.sh` overwrites that array during `--validate` runs. All accuracy warnings stay inside `validation.accuracy` to avoid conflicts.
6. [ ] Before atomic write, deduplicate: remove any existing `validation.accuracy` block (replace, not append) so seeded reruns are idempotent.
7. [ ] Atomic write.
8. [ ] Exit 0 always.

**Test Type:** NoTest _(T9 asserts deterministic output with --seed 42)_

**Code Skeleton:**
```python
#!/usr/bin/env python3
import json, os, sys, argparse, tempfile, random, re

def check_class(cls):
    path = cls.get("source_file") or cls.get("file", "")
    checks = []
    try:
        text = open(path).read()
    except Exception:
        return [{"class": cls["name"], "field": "file_read", "match": False}]
    checks.append({"class": cls["name"], "field": "declaration",
                   "match": bool(re.search(rf'class\s+{re.escape(cls["name"])}\b', text))})
    for m in cls.get("methods", []):
        checks.append({"class": cls["name"], "field": f"method:{m['name']}",
                       "match": bool(re.search(rf'\b{re.escape(m["name"])}\s*\(', text))})
    for ev in cls.get("events_published", []):
        present = (f"Publish<{ev}>" in text) or (f"new {ev}(" in text)
        checks.append({"class": cls["name"], "field": f"event_pub:{ev}", "match": present})
    return checks

def atomic_write(g, path):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
    with os.fdopen(fd, "w") as f: json.dump(g, f, indent=2)
    os.replace(tmp, path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--graph", required=True)
    ap.add_argument("--sample", type=int, default=20)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    try:
        with open(args.graph) as f: g = json.load(f)
        classes = g.get("codebase", {}).get("classes", [])
        if not classes:
            print("graph_validate: no classes to validate", file=sys.stderr); return
        rnd = random.Random(args.seed)
        sample = rnd.sample(classes, min(args.sample, len(classes)))
        all_checks = []
        for cls in sample: all_checks.extend(check_class(cls))
        matches = sum(1 for c in all_checks if c["match"])
        mismatches = len(all_checks) - matches
        pct = round(matches / max(len(all_checks), 1) * 100, 1)
        g.setdefault("validation", {})["accuracy"] = {
            "sampled_classes": len(sample), "matches": matches,
            "mismatches": mismatches, "agreement_pct": pct, "checks": all_checks,
            # accuracy warnings stored here, NOT in validation.warnings[] (owned by graph-validator.sh)
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

if __name__ == "__main__": main()
```

**Acceptance Criteria:**
- `validation.accuracy.agreement_pct` is a number 0–100.
- `--seed 42` produces identical output on two consecutive runs (idempotent replace, not append).
- `validation.accuracy.low_accuracy_warning = true` when pct < 90; `validation.warnings[]` is NOT touched.
- Exits 0 always.

---

## Task T6 — Wire new modules into `graph-builder.sh`

**Files:**
- `.claude/graph/graph-builder.sh`

**Steps:**
1. [ ] Bump `schema_version` literal from `"1.1.0"` to `"1.2.0"` (search for `"1.1.0"` near the `jq` assembly block).
2. [ ] Locate the call to `python3 graph-traversal.py --finalize-calls` (approximately line 494). Insert the Analysis Stage block **immediately after that call completes** (after finalize-calls, before the `echo "$NOW" > "$LAST_BUILD"` line is not required — just after finalize-calls is sufficient).
3. [ ] Guard the entire block with `if command -v python3 >/dev/null 2>&1; then ... fi`.
4. [ ] Call in order: `graph_cluster.py` → `graph_analyze.py` → `graph_validate.py`. Each call uses a separate `if` with `|| true` to prevent `set -e` from aborting on non-zero.
5. [ ] After running the three modules, read `COMM_COUNT` and `ACC_PCT` from the updated `graph.json` with `jq`.
6. [ ] Append `, ${COMM_COUNT} communities, ${ACC_PCT}% accuracy` to the existing summary log line.
7. [ ] For quiet mode: use `2>/dev/null` only when `[[ -n "${QUIET:-}" ]]` — check with an explicit conditional, not `${QUIET:+...}` (which is not a valid redirection pattern).

**Test Type:** NoTest _(T9 full-build integration test)_

**Code Skeleton:**
```bash
# ── Analysis stage — v1.2.0 modules ─────────────────────────────────────────
_GRAPH_DIR="$(dirname "$0")"
if command -v python3 >/dev/null 2>&1; then
  _run_module() {
    local script="$1"; shift
    [[ -f "$script" ]] || { log "$(basename "$script") not found (non-fatal)"; return; }
    if [[ -n "${QUIET:-}" ]]; then
      python3 "$script" "$@" 2>/dev/null || log "$(basename "$script") failed (non-fatal)"
    else
      python3 "$script" "$@" || log "$(basename "$script") failed (non-fatal)"
    fi
  }
  _run_module "$_GRAPH_DIR/graph_cluster.py"  --graph "$OUTPUT"
  _run_module "$_GRAPH_DIR/graph_analyze.py"  --graph "$OUTPUT"
  _run_module "$_GRAPH_DIR/graph_validate.py" --graph "$OUTPUT" --sample 20
fi

COMM_COUNT=$(jq '(.codebase.communities // []) | length' "$OUTPUT" 2>/dev/null || echo 0)
ACC_PCT=$(jq '.validation.accuracy.agreement_pct // "n/a"' "$OUTPUT" 2>/dev/null || echo "n/a")
```

**Acceptance Criteria:**
- Full build output has `schema_version: "1.2.0"`.
- `codebase.communities[]` and `validation.accuracy{}` present after full build on a project with C# files.
- Removing any new module file causes a log warning but not a build failure.
- `--quiet` flag suppresses module stderr output.

---

## Task T7 — `/knowledge-graph communities` subcommand

**Files:**
- `.claude/commands/knowledge-graph.md`

**parallel_group:** P4

**Steps:**
1. [ ] Add `### communities [--scope <ScopeName>]` section.
2. [ ] Document default jq query (top 5 members shown per community, safe for optional field):
   ```bash
   jq '(.codebase.communities // []) | map({id, label, size, scope, algorithm, members: .members[0:5]})' .claude/graph/graph.json
   ```
3. [ ] Document `--scope` filter variant (also uses `// []`).
4. [ ] Add empty-state message when `communities[]` is missing or empty.
5. [ ] Add to "When to use" table: `"Which classes form a module?"` → `communities`.

**Test Type:** NoTest

**Acceptance Criteria:**
- Documented jq queries execute without error against a v1.2.0 graph with communities.
- Empty-state message documented.

---

## Task T7b — Update `graph-traversal.py` god-nodes to use enhanced data

**Files:**
- `.claude/graph/graph-traversal.py`

**parallel_group:** P4

**Steps:**
1. [ ] In `cmd_god_nodes()`, after loading the graph, check if `g.get("analysis", {}).get("enhanced_god_nodes")` is non-empty.
2. [ ] If present, use `enhanced_god_nodes[]` as the output (already sorted and enriched with `community_id`, `cross_community_edges`, `severity`). Respect `--top N`.
3. [ ] If absent (older graph or analysis hasn't run), fall through to the existing degree-computation path unchanged.
4. [ ] Output format: add `community_id` and `severity` fields when available; omit them when falling back to legacy mode.

**Test Type:** NoTest _(T9 assertion: after full build with graph_analyze.py, god-nodes output includes `community_id`)_

**Code Skeleton:**
```python
def cmd_god_nodes(g, top_n):
    enhanced = g.get("analysis", {}).get("enhanced_god_nodes", [])
    if enhanced:
        # Use pre-computed enriched data from graph_analyze.py
        nodes = sorted(enhanced, key=lambda n: -n.get("total", 0))[:top_n]
        for n in nodes:
            print(f"{n['node']:50s}  total={n['total']:4d}  "
                  f"community={n.get('community_id','?')}  severity={n.get('severity','info')}")
        return
    # Legacy fallback: degree-only computation (unchanged)
    # ... existing implementation ...
```

**Acceptance Criteria:**
- When `analysis.enhanced_god_nodes[]` exists, output includes `community_id` and `severity`.
- When it is absent, output is identical to current behaviour.
- `--top N` is respected in both paths.

---

## Task T8 — `/knowledge-graph surprising` subcommand

**Files:**
- `.claude/commands/knowledge-graph.md`

**parallel_group:** P4

**Steps:**
1. [ ] Add `### surprising [--severity warning|info] [--limit N]` section.
2. [ ] Default jq query (warnings first, limit 20, safe for optional field):
   ```bash
   jq '(.analysis.surprising_connections // []) | sort_by(.severity != "warning") | .[0:20]' .claude/graph/graph.json
   ```
3. [ ] Severity filter variant (also uses `// []`).
4. [ ] Empty-state message when `analysis` missing or connections empty.
5. [ ] Add to "When to use" table: `"Architecture drifting where?"` → `surprising`.

**Test Type:** NoTest

**Acceptance Criteria:**
- Documented jq queries execute without error.
- Severity filter documented.

---

## Task T9 — Test additions in `verify-graphify.sh`

**Files:**
- `.claude/graph/test/verify-graphify.sh`
- `.claude/graph/test/fixtures/v2_communities/` (new directory with 2–3 minimal C# fixture files)

**Steps:**
1. [ ] Create `fixtures/v2_communities/graph_fixture.json` — a hand-crafted minimal `graph.json` with `codebase.calls[]` containing at least 2 class-level edges across different VContainer scopes, and matching `codebase.classes[]` entries. This fixture is used **only** by tests that call the Python modules directly with `--graph fixtures/v2_communities/graph_fixture.json` (e.g. T9.2–T9.4 Python-direct calls). The builder-based tests (T9.1, T9.6) run `graph-builder.sh --full` against whatever C# source exists in the real repo — on an empty template repo they gracefully hit `known_fail`. No separate C# source files are needed in the fixture directory.
2. [ ] Add `run_v2_module_tests()` function with 6 tests (see skeleton).
3. [ ] Wire `run_v2_module_tests` into the main test dispatcher (the `case "$1"` block or equivalent entry point at the bottom of `verify-graphify.sh`).
4. [ ] Do NOT update a "total count assertion" — `verify-graphify.sh` uses PASS/FAIL counters not a hardcoded total. The new function simply adds 6 more assertions to the running counters.

**Test Type:** NoTest _(this IS the test harness)_

**Code Skeleton:**
```bash
run_v2_module_tests() {
  section "T9 — V2 Modules"

  local WORK_GRAPH="$SANDBOX/graph_v2_test.json"
  # Build against the fixture
  bash "$GRAPH_DIR/graph-builder.sh" --full --skip-mcp --quiet --output "$WORK_GRAPH"

  # 9.1 — schema version
  local sv; sv=$(jq -r '.schema_version' "$WORK_GRAPH")
  [[ "$sv" == "1.2.0" ]] && pass "schema_version = 1.2.0" || fail "schema_version is $sv (expected 1.2.0)"

  # 9.2 — communities present (only if calls exist)
  local call_count; call_count=$(jq '.codebase.calls | length' "$WORK_GRAPH")
  if [[ "$call_count" -gt 0 ]]; then
    local comm_count; comm_count=$(jq '.codebase.communities | length' "$WORK_GRAPH")
    [[ "$comm_count" -ge 1 ]] && pass "communities[] has $comm_count entries" \
                               || fail "expected ≥1 community, got $comm_count"
  else
    pass "no calls — communities[] skip expected"
  fi

  # 9.3 — analysis block present
  jq -e '.analysis' "$WORK_GRAPH" >/dev/null 2>&1 \
    && pass "analysis{} block present" \
    || known_fail "analysis{} missing" "no call edges in fixture"

  # 9.4 — accuracy deterministic
  python3 "$GRAPH_DIR/graph_validate.py" --graph "$WORK_GRAPH" --sample 5 --seed 42 2>/dev/null
  local p1; p1=$(jq -r '.validation.accuracy.agreement_pct' "$WORK_GRAPH")
  python3 "$GRAPH_DIR/graph_validate.py" --graph "$WORK_GRAPH" --sample 5 --seed 42 2>/dev/null
  local p2; p2=$(jq -r '.validation.accuracy.agreement_pct' "$WORK_GRAPH")
  [[ "$p1" == "$p2" ]] && pass "graph_validate.py deterministic ($p1%)" \
                        || fail "non-deterministic: $p1 vs $p2"

  # 9.5 — csharp_extractor.py exits 2 without tree-sitter
  PYTHONPATH=/nonexistent python3 "$GRAPH_DIR/extractors/csharp_extractor.py" \
    --changed-files "x.cs" 2>/dev/null
  local ts_exit=$?
  [[ "$ts_exit" -eq 2 ]] && pass "csharp_extractor.py exits 2 when tree-sitter absent" \
                           || known_fail "exit $ts_exit (expected 2)" "tree-sitter may be installed"

  # 9.6 — builder survives missing graph_cluster.py (use a temp copy of builder dir, not mv on live file)
  local SANDBOX_DIR; SANDBOX_DIR=$(mktemp -d)
  cp "$GRAPH_DIR/graph-builder.sh" "$SANDBOX_DIR/"
  cp "$GRAPH_DIR/graph-traversal.py" "$SANDBOX_DIR/" 2>/dev/null || true
  # Intentionally omit graph_cluster.py from sandbox
  cp "$GRAPH_DIR/graph_analyze.py"  "$SANDBOX_DIR/" 2>/dev/null || true
  cp "$GRAPH_DIR/graph_validate.py" "$SANDBOX_DIR/" 2>/dev/null || true
  bash "$SANDBOX_DIR/graph-builder.sh" --full --skip-mcp --quiet --output "$WORK_GRAPH" 2>/dev/null
  local rc=$?
  rm -rf "$SANDBOX_DIR"
  [[ "$rc" -eq 0 ]] && pass "builder exits 0 when graph_cluster.py absent" \
                      || fail "builder must not fail without v2 modules"
}
```

**Acceptance Criteria:**
- All 6 T9 tests listed; at worst, some are `KNOWN_FAIL` on an empty template repo (no C# source).
- `verify-graphify.sh` total count updated.
- No existing T3–T8 tests broken.

---

## Task T10 — Documentation refresh

**Files:**
- `.claude/docs/knowledge-graph.md`
- `.claude/commands/build-knowledge-graph.md`

**Steps:**
1. [ ] In `knowledge-graph.md`: add v1.2.0 section describing `codebase.communities[]`, `analysis{}`, `validation.accuracy{}`. Add entries for new subcommands in the query cheatsheet.
2. [ ] In `build-knowledge-graph.md` Step 6 summary block, append:
   ```
   Communities: <n>
   Accuracy:    <pct>%
   ```
3. [ ] In `build-knowledge-graph.md`, add a note after Step 6: if `Accuracy < 90%`, recommend `--full` rebuild.
4. [ ] Note in `knowledge-graph.md`: editing `.claude/CLAUDE.md` graph query cheatsheet is a manual follow-up (not automated by this task).

**Test Type:** NoTest

**Doc Skeleton:**

In `knowledge-graph.md`, add after the existing query cheatsheet:

```markdown
## v1.2.0 Fields

| Field | jq path | Description |
|-------|---------|-------------|
| Communities | `.codebase.communities` | Class community groups |
| Surprising connections | `.analysis.surprising_connections` | Cross-scope/assembly edges |
| Enhanced god-nodes | `.analysis.enhanced_god_nodes` | God-nodes with community + severity |
| Accuracy report | `.validation.accuracy` | Extraction accuracy vs source |

Query cheatsheet additions:
- "Which classes form a module?" → `/knowledge-graph communities`
- "Architecture drifting where?" → `/knowledge-graph surprising`
```

In `build-knowledge-graph.md` Step 6, replace the summary block template with:

```markdown
Classes:      <n>  (Methods: <n>)
Events:       <n>
Installers:   <n>
Calls:        <n>
Communities:  <n>
Accuracy:     <pct>%   ← if < 90%, run --full

Errors:   <n>
Warnings: <n>
```

**Acceptance Criteria:**
- `knowledge-graph.md` references jq paths for all three new v1.2.0 blocks.
- `build-knowledge-graph.md` Step 6 template includes Communities and Accuracy lines.
- If accuracy < 90%, the `--full` rebuild suggestion is documented.

---

## Key Design Decisions

1. **Read-only post-write modules.** New modules run after the atomic `mv` in the builder. A failure cannot corrupt the core graph. Pre-write integration would be slightly more efficient but riskier given the builder's complexity.

2. **stdlib-first, networkx-optional.** Ships a greedy community detector adequate for repos under ~500 classes. Real Louvain available when `networkx` is installed.

3. **Class-level communities, not method-level.** Method calls collapsed to class-level edges before clustering — communities align with modules/services.

4. **Exit 0 always.** Every new module follows the existing `graph-traversal.py` pattern: print to stderr on failure, exit 0. Build never fails because of analysis modules.

5. **Schema additive, never breaking.** v1.2.0 adds optional blocks only. Old `/knowledge-graph` queries work unchanged.

6. **`tree-sitter` is an optional upgrade.** `csharp_extractor.py` is a NEW file; `csharp-extractor.sh` is modified only to add a preflight check. The bash path is untouched otherwise.

7. **Two new subcommands, not five.** `communities` and `surprising` only. God-nodes enhanced in-place via `analysis.enhanced_god_nodes[]`. T4 enriches the data; T7b (part of T7/T8 phase) updates `graph-traversal.py`'s `cmd_god_nodes()` to prefer `analysis.enhanced_god_nodes[]` over the legacy degree-only computation when that block is present.

## Anticipated Challenges

- **tree-sitter wheel lag on some Python versions.** Fallback exit 2 path must be reliable.
- **Community labels from dominant assembly can be generic.** Acceptable for v1; a `--label-by scope` option can follow in v2.
- **Cross-scope edges are common during bootstrap.** AppScope → GameScope wiring is legitimate. Severity = `info` for most cross edges; only CROSS_SCOPE is `warning`.
- **Accuracy validation re-reads source on every build.** `--sample 20` default caps I/O cost.
- **Builder summary line length.** Adding two counters is acceptable; users can grep `graph:` lines.

## Follow-up (out of scope for this plan)
- Update `.claude/CLAUDE.md` graph query cheatsheet with `communities` and `surprising` entries (manual edit required — CLAUDE.md is protected from automated writes).
- `pip install tree-sitter tree-sitter-c-sharp` step in `/setup-project` flow.
- `networkx` as optional pip dependency note in setup docs.
