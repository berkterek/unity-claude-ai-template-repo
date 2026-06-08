#!/usr/bin/env python3
# graph_analyze.py — Surprising connections + enhanced god-nodes analysis.
# Reads graph.json (requires codebase.communities[]), writes analysis{} back atomically.
# Exit 0 always — failures are non-fatal and logged to stderr.
import json
import os
import sys
import argparse
import tempfile
from collections import defaultdict
from datetime import datetime, timezone


def classify_edge(a, b, comm_of, scope_of, asm_of):
    """Return (reason, severity) or (None, None) if edge is not surprising."""
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
    ap = argparse.ArgumentParser(description="Analyze graph.json for surprising connections and enhanced god-nodes.")
    ap.add_argument("--graph", required=True, help="Path to graph.json")
    ap.add_argument("--top-god", type=int, default=10)
    ap.add_argument("--max-surprising", type=int, default=50)
    args = ap.parse_args()

    try:
        with open(args.graph) as f:
            g = json.load(f)

        communities = g.get("codebase", {}).get("communities", [])
        if not communities:
            print("graph_analyze: no communities[] — run graph_cluster.py first", file=sys.stderr)
            # Still write an empty analysis block so downstream queries are safe
            g["analysis"] = {
                "generated_at": datetime.now(timezone.utc).isoformat(),
                "surprising_connections": [],
                "enhanced_god_nodes": [],
            }
            atomic_write(g, args.graph)
            return

        # Build lookup maps
        comm_of = {m: c["id"] for c in communities for m in c["members"]}

        # scope_of: class_name → scope_name via installer registrations
        scope_of = {}
        vc = g.get("codebase", {}).get("vcontainer", {})
        installers_by_name = {inst["name"]: inst for inst in vc.get("installers", [])}
        for scope in vc.get("scopes", []):
            for inst_name in scope.get("installers", []):
                inst = installers_by_name.get(inst_name, {})
                for reg in inst.get("registrations", []):
                    t = reg.get("type", "")
                    if t:
                        scope_of[t] = scope["name"]

        # asm_of: class_name → assembly_name via file prefix
        asm_of = {}
        assemblies = g.get("codebase", {}).get("assemblies", [])
        for cls in g.get("codebase", {}).get("classes", []):
            f = cls.get("file", "")
            for a in assemblies:
                adir = os.path.dirname(a.get("file", "__nonexistent__"))
                if f.startswith(adir + os.sep) or f.startswith(adir + "/"):
                    asm_of[cls["name"]] = a["name"]
                    break

        # Classify call edges
        surprising = []
        degree = defaultdict(lambda: {"in": 0, "out": 0})
        cross_count = defaultdict(int)

        for e in g.get("codebase", {}).get("calls", []):
            a = e["caller"].split(".")[0]
            b = e["callee"].split(".")[0]
            degree[a]["out"] += 1
            degree[b]["in"] += 1
            reason, sev = classify_edge(a, b, comm_of, scope_of, asm_of)
            if reason:
                surprising.append({
                    "caller": e["caller"],
                    "callee": e["callee"],
                    "caller_community": comm_of.get(a),
                    "callee_community": comm_of.get(b),
                    "caller_scope": scope_of.get(a, ""),
                    "callee_scope": scope_of.get(b, ""),
                    "reason": reason,
                    "severity": sev,
                })
                cross_count[a] += 1

        # Sort: warnings first, then by caller
        surprising.sort(key=lambda x: (x["severity"] != "warning", x["caller"]))
        surprising = surprising[:args.max_surprising]

        # Enhanced god-nodes: top-N by total degree with community enrichment
        god_nodes = []
        for n, d in sorted(degree.items(), key=lambda kv: -(kv[1]["in"] + kv[1]["out"]))[:args.top_god]:
            total = d["in"] + d["out"]
            cc = cross_count[n]
            sev = "critical" if cc > 10 else ("warning" if cc > 3 else "info")
            god_nodes.append({
                "node": n,
                "in": d["in"],
                "out": d["out"],
                "total": total,
                "community_id": comm_of.get(n),
                "cross_community_edges": cc,
                "is_god_node": total > 20,
                "severity": sev,
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


if __name__ == "__main__":
    main()
