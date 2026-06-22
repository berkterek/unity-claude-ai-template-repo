#!/usr/bin/env python3
# graph_cluster.py — Community detection for the Unity knowledge graph.
# Reads graph.json, writes codebase.communities[] back atomically.
# Exit 0 always — failures are non-fatal and logged to stderr.
import json
import os
import sys
import argparse
import tempfile
from collections import defaultdict


def stdlib_greedy(nodes, adj):
    """3-pass degree-sorted greedy community merge."""
    community = {n: i for i, n in enumerate(nodes)}
    for _ in range(3):
        changed = False
        for n in sorted(nodes, key=lambda x: -len(adj[x])):
            counts = defaultdict(int)
            for m in adj[n]:
                counts[community[m]] += 1
            if counts:
                best = max(counts.items(), key=lambda kv: kv[1])
                if best[0] != community[n] and best[1] >= 1:
                    community[n] = best[0]
                    changed = True
        if not changed:
            break
    # Remap to contiguous IDs
    remap = {}
    for n in nodes:
        c = community[n]
        if c not in remap:
            remap[c] = len(remap)
        community[n] = remap[c]
    return community


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
    ap = argparse.ArgumentParser(description="Community detection for graph.json.")
    ap.add_argument("--graph", required=True, help="Path to graph.json")
    ap.add_argument("--algorithm", default="auto", choices=["auto", "stdlib", "louvain"])
    ap.add_argument("--min-size", type=int, default=2)
    args = ap.parse_args()

    try:
        with open(args.graph) as f:
            g = json.load(f)

        calls = g.get("codebase", {}).get("calls", []) or []
        if not calls:
            print("graph_cluster: no call edges — skipping", file=sys.stderr)
            return

        # Build class-level undirected adjacency from method-level call edges
        adj = defaultdict(set)
        nodes = set()
        for e in calls:
            a = e["caller"].split(".")[0]
            b = e["callee"].split(".")[0]
            if a and b and a != b:
                adj[a].add(b)
                adj[b].add(a)
                nodes.add(a)
                nodes.add(b)

        nodes = sorted(nodes)
        if not nodes:
            print("graph_cluster: no class-level edges — skipping", file=sys.stderr)
            return

        algo = "greedy-modularity-stdlib"
        community = None

        if args.algorithm in ("auto", "louvain"):
            try:
                import networkx as nx
                from networkx.algorithms.community import louvain_communities
                G = nx.Graph()
                for u in adj:
                    for v in adj[u]:
                        G.add_edge(u, v)
                comms = louvain_communities(G, seed=42)
                community = {n: i for i, c in enumerate(comms) for n in c}
                algo = "louvain-networkx"
            except Exception:
                pass  # fall through to stdlib

        if community is None:
            community = stdlib_greedy(nodes, adj)

        buckets = defaultdict(list)
        for n, c in community.items():
            buckets[c].append(n)

        communities = []
        for cid, members in sorted(buckets.items()):
            if len(members) < args.min_size:
                continue
            communities.append({
                "id": cid,
                "members": sorted(members),
                "size": len(members),
                "label": f"community-{sorted(members)[0]}",
                "scope": "",
                "modularity": 0.0,
                "algorithm": algo,
            })

        g.setdefault("codebase", {})["communities"] = communities
        atomic_write(g, args.graph)
        print(f"graph_cluster: {len(communities)} communities ({algo})", file=sys.stderr)

    except Exception as e:
        print(f"graph_cluster: error — {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
