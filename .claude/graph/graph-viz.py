#!/usr/bin/env python3
"""graph-viz.py — graph.html generator for the Unity Knowledge Graph.

Reads graph.json (+ resolves scenes.json / prefabs.json $partition refs, mirroring
graph-mcp-server.py's _resolve_partition), builds a node/edge model from
classes/interfaces/events + calls/implements/publish/subscribe, and emits ONE
graph.html: inline CSS, inline JSON data island, inline glue JS that drives a
vis-network force-directed layout. The page is self-contained except for the
vendored vis-network.min.js (pinned 9.1.6, committed alongside graph.html and
referenced relatively) — no CDN, no external URLs, no build step. That vendored
file is NEVER written or touched by this script.

Usage:
    python3 graph-viz.py [--graph PATH] [--out PATH]

Defaults: .claude/graph/graph.json -> .claude/graph/graph.html
(vis-network.min.js must already sit next to the --out path.)
"""

import argparse
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

MAX_NODES_BEFORE_WARNING = 800


# ── Partition resolver — mirrors graph-mcp-server.py's _resolve_partition ─────

def _resolve_partition(obj, base_dir):
    """Walk the graph dict and replace {"$partition": "file.json"} refs.

    Fails fast (raises FileNotFoundError) if a referenced partition file is
    missing — a silent [] substitution would hide a broken graph.
    """
    if isinstance(obj, dict):
        if len(obj) == 1 and "$partition" in obj:
            part = os.path.join(base_dir, obj["$partition"])
            if not os.path.exists(part):
                raise FileNotFoundError(f"graph partition missing: {part}")
            with open(part, encoding="utf-8") as fh:
                return _resolve_partition(json.load(fh), base_dir)
        return {k: _resolve_partition(v, base_dir) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolve_partition(v, base_dir) for v in obj]
    return obj


def load_graph(path):
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    return _resolve_partition(raw, os.path.dirname(os.path.abspath(path)))


# ── Node / edge model ──────────────────────────────────────────────────────────

def _caller_class(qualified):
    """Best-effort 'Class' extraction from a 'Class.Method' or 'Ns.Class.Method' caller/callee."""
    if not qualified:
        return None
    parts = qualified.split(".")
    if len(parts) >= 2:
        return parts[-2]
    return parts[0]


_INSTANCE_SUFFIX = re.compile(r"\s*\(\d+\)$")


def _prefab_name(p):
    """Prefab display name. Supports both the flat fixture schema (top-level
    'name') and the real graph.json schema (nested under 'root')."""
    return p.get("name") or (p.get("root") or {}).get("name")


def _prefab_components(p):
    """All component type names on a prefab. Flat schema exposes a top-level
    'components' list; the real schema stores them on the root GO and its
    recursive children — flatten the whole tree."""
    comps = list(p.get("components") or [])
    root = p.get("root")
    if isinstance(root, dict):
        stack = [root]
        while stack:
            go = stack.pop()
            comps.extend(go.get("components") or [])
            for ch in go.get("children") or []:
                stack.append(ch)
    return comps


def _prefab_is_variant(p):
    if "isVariant" in p:
        return bool(p.get("isVariant"))
    return bool((p.get("root") or {}).get("isVariant"))


def _prefab_base(p):
    return p.get("basePrefab") or (p.get("root") or {}).get("basePrefab")


def _scene_name(s):
    """Scene display name. Flat fixture schema carries 'name'; the real schema
    only has 'path', so derive the name from the .unity file basename."""
    name = s.get("name")
    if name:
        return name
    path = s.get("path", "") or ""
    base = os.path.basename(path)
    if base.endswith(".unity"):
        base = base[:-len(".unity")]
    return base or path


def build_nodes_edges(g):
    cb = g.get("codebase", {})
    classes = cb.get("classes", []) or []
    interfaces = cb.get("interfaces", []) or []
    events = cb.get("events", []) or []
    calls = cb.get("calls", []) or []
    prefabs = cb.get("prefabs", [])
    scenes = cb.get("scenes", [])
    if not isinstance(prefabs, list):
        prefabs = []
    if not isinstance(scenes, list):
        scenes = []

    nodes = []
    node_ids = set()
    class_ids = set()   # classes only (not interfaces/events) — used for component matching

    for c in classes:
        name = c.get("name")
        if not name or name in node_ids:
            continue
        node_ids.add(name)
        class_ids.add(name)
        nodes.append({
            "id": name,
            "type": "class",
            "is_mono_behaviour": bool(c.get("is_mono_behaviour")),
            "namespace": c.get("namespace", ""),
        })

    for i in interfaces:
        name = i.get("name")
        if not name or name in node_ids:
            continue
        node_ids.add(name)
        nodes.append({"id": name, "type": "interface", "namespace": i.get("namespace", "")})

    for e in events:
        name = e.get("name")
        if not name or name in node_ids:
            continue
        node_ids.add(name)
        nodes.append({"id": name, "type": "event"})

    edges = []

    # calls: caller -> callee (class-level, deduped)
    seen_calls = set()
    for edge in calls:
        caller_cls = _caller_class(edge.get("caller", ""))
        callee_cls = _caller_class(edge.get("callee", ""))
        if not caller_cls or not callee_cls:
            continue
        if caller_cls not in node_ids or callee_cls not in node_ids:
            continue
        if caller_cls == callee_cls:
            continue
        key = ("calls", caller_cls, callee_cls)
        if key in seen_calls:
            continue
        seen_calls.add(key)
        edges.append({"type": "calls", "source": caller_cls, "target": callee_cls})

    # implements: class -> interface
    for c in classes:
        name = c.get("name")
        if not name:
            continue
        for iface in c.get("implements", []) or []:
            if iface in node_ids:
                edges.append({"type": "implements", "source": name, "target": iface})

    # publish / subscribe: class -> event
    for c in classes:
        name = c.get("name")
        if not name:
            continue
        for ev in c.get("events_published", []) or []:
            if ev in node_ids:
                edges.append({"type": "publish", "source": name, "target": ev})
        for ev in c.get("events_subscribed", []) or []:
            if ev in node_ids:
                edges.append({"type": "subscribe", "source": name, "target": ev})

    # registrations (installer -> registered type), skipping unresolved:true (D3)
    installers = cb.get("vcontainer", {}).get("installers", []) or []
    for installer in installers:
        installer_name = installer.get("name")
        if not installer_name:
            continue
        for reg in installer.get("registrations", []) or []:
            if reg.get("unresolved") is True:
                continue
            t = reg.get("type", "")
            if t and t in node_ids and installer_name in node_ids:
                edges.append({"type": "registers", "source": installer_name, "target": t})

    # injects: class -> constructor/[*Inject] dependency (interface node preferred,
    # then class node). Unresolved framework types (R3/UniTask/Unity) are silently
    # dropped by the node_ids membership test. Deduped per (class, dependency).
    seen_inject = set()
    for c in classes:
        name = c.get("name")
        if not name:
            continue
        for dep in c.get("dependencies", []) or []:
            if dep not in node_ids or dep == name:
                continue
            key = ("injects", name, dep)
            if key in seen_inject:
                continue
            seen_inject.add(key)
            edges.append({"type": "injects", "source": name, "target": dep})

    # ── Partitioned data: prefab + scene nodes (from scenes.json / prefabs.json) ─
    # Prefab node ids are prefixed with "prefab:" and scene ids with "scene:" so
    # they never collide with class/interface/event names (which are bare).
    prefab_name_to_id = {}
    for p in prefabs:
        name = _prefab_name(p)
        if not name:
            continue
        pid = "prefab:" + name
        if pid in node_ids:
            continue
        node_ids.add(pid)
        prefab_name_to_id[name] = pid
        nodes.append({
            "id": pid,
            "label": name,
            "type": "prefab",
            "namespace": p.get("domain", "") or "",   # reuse tooltip slot
        })

    scene_entries = []   # (scene_id, scene_dict) for the contains walk below
    for s in scenes:
        name = _scene_name(s)
        if not name:
            continue
        sid = "scene:" + name
        if sid in node_ids:
            continue
        node_ids.add(sid)
        scene_entries.append((sid, s))
        nodes.append({
            "id": sid,
            "label": name,
            "type": "scene",
            "namespace": s.get("path", "") or "",   # reuse tooltip slot
        })

    # has_component: prefab -> class, for each component type that is a known class
    seen_has = set()
    for p in prefabs:
        name = _prefab_name(p)
        pid = prefab_name_to_id.get(name) if name else None
        if not pid:
            continue
        for comp in _prefab_components(p):
            if comp in class_ids:
                key = (pid, comp)
                if key in seen_has:
                    continue
                seen_has.add(key)
                edges.append({"type": "has_component", "source": pid, "target": comp})

    # variant_of: prefab -> prefab, when basePrefab matches another prefab node
    seen_variant = set()
    for p in prefabs:
        name = _prefab_name(p)
        pid = prefab_name_to_id.get(name) if name else None
        if not pid:
            continue
        base = _prefab_base(p)
        base_id = prefab_name_to_id.get(base) if base else None
        if not base_id or base_id == pid:
            continue
        key = (pid, base_id)
        if key in seen_variant:
            continue
        seen_variant.add(key)
        edges.append({"type": "variant_of", "source": pid, "target": base_id})

    # contains: scene -> prefab (GO name matches a prefab after stripping the
    # instance suffix). Fallback when no prefab matches: scene -> class edges for
    # GO components that are known classes — so scenes never float disconnected.
    seen_contains = set()

    def _walk_go(go, sid):
        raw_name = go.get("name", "") or ""
        base = _INSTANCE_SUFFIX.sub("", raw_name)
        pid = prefab_name_to_id.get(base)
        if pid:
            key = (sid, pid)
            if key not in seen_contains:
                seen_contains.add(key)
                edges.append({"type": "contains", "source": sid, "target": pid})
        else:
            for comp in go.get("components") or []:
                if comp in class_ids:
                    key = (sid, comp)
                    if key not in seen_contains:
                        seen_contains.add(key)
                        edges.append({"type": "contains", "source": sid, "target": comp})
        for ch in go.get("children") or []:
            _walk_go(ch, sid)

    for sid, s in scene_entries:
        for go in s.get("gameobjects") or []:
            _walk_go(go, sid)

    return nodes, edges


# ── HTML template — inline CSS + JSON data island + vis-network glue JS ──────
# Self-contained except for the vendored vis-network.min.js referenced relatively.

HTML_TEMPLATE = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Unity Knowledge Graph</title>
<style>
  :root { color-scheme: light dark; }
  html, body {
    margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden;
    background: #12141a; color: #e8e8ec;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  }
  #graph { position: absolute; inset: 0; background: #12141a; }

  #legend {
    position: absolute; top: 12px; left: 12px; z-index: 10;
    background: rgba(20, 22, 28, 0.9); border: 1px solid #333844;
    border-radius: 8px; padding: 10px 14px; font-size: 12px; max-width: 260px;
  }
  #legend h3 { margin: 0 0 6px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: #9aa1ad; }
  .legend-row { display: flex; align-items: center; gap: 8px; margin: 3px 0; }
  .legend-row.toggle { cursor: pointer; user-select: none; }
  .legend-row.toggle.off { opacity: 0.35; }
  .swatch { width: 12px; height: 12px; border-radius: 50%; flex: none; }
  .swatch.sq { border-radius: 3px; }
  .swatch.diamond { border-radius: 2px; transform: rotate(45deg); }
  .swatch.tri {
    width: 0; height: 0; border-radius: 0; background: none !important;
    border-left: 6px solid transparent; border-right: 6px solid transparent;
    border-bottom-width: 12px; border-bottom-style: solid;
  }
  .line-swatch { width: 22px; height: 0; border-top-width: 2px; border-top-style: solid; flex: none; }

  #stats {
    position: absolute; bottom: 12px; left: 12px; z-index: 10;
    background: rgba(20, 22, 28, 0.9); border: 1px solid #333844;
    border-radius: 8px; padding: 6px 12px; font-size: 11px; color: #9aa1ad;
  }
  #note {
    position: absolute; bottom: 12px; right: 12px; z-index: 10;
    background: rgba(120, 90, 20, 0.9); border: 1px solid #7a5c14;
    border-radius: 8px; padding: 6px 12px; font-size: 11px; display: none;
  }
  /* vis-network's built-in tooltip, restyled for the dark theme */
  div.vis-tooltip {
    background: rgba(20, 22, 28, 0.95) !important; border: 1px solid #444b5a !important;
    color: #e8e8ec !important; border-radius: 6px !important; padding: 6px 10px !important;
    font-family: inherit !important; font-size: 12px !important; box-shadow: none !important;
  }
</style>
</head>
<body>
<div id="graph"></div>
<div id="legend">
  <h3>Node Types (click to filter)</h3>
  <div class="legend-row toggle" data-cat="mono"><span class="swatch" style="background:#4fc3f7"></span> Class (MonoBehaviour)</div>
  <div class="legend-row toggle" data-cat="class"><span class="swatch" style="background:#7986cb"></span> Class (plain C#)</div>
  <div class="legend-row toggle" data-cat="interface"><span class="swatch sq" style="background:#81c784"></span> Interface</div>
  <div class="legend-row toggle" data-cat="event"><span class="swatch" style="background:#ffb74d"></span> Event</div>
  <div class="legend-row toggle" data-cat="prefab"><span class="swatch diamond" style="background:#e57373"></span> Prefab</div>
  <div class="legend-row toggle" data-cat="scene"><span class="swatch tri" style="border-bottom-color:#4db6ac"></span> Scene</div>
  <h3 style="margin-top:10px;">Edge Types</h3>
  <div class="legend-row"><span class="line-swatch" style="border-color:#5c6470"></span> Calls</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#81c784"></span> Implements</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#ffb74d"></span> Publish</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#4fc3f7;border-top-style:dashed"></span> Subscribe</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#ba68c8;border-top-style:dashed"></span> Registers</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#f06292;border-top-style:dashed"></span> Injects</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#8d6e63"></span> Has Component</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#4db6ac;border-top-style:dashed"></span> Contains</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#e57373;border-top-style:dashed"></span> Variant Of</div>
</div>
<div id="stats"></div>
<div id="note">Large graph (&gt;800 nodes) — layout may be dense.</div>

<script type="application/json" id="graph-data">
__DATA__
</script>

<!-- Vendored, pinned vis-network 9.1.6 — lives in the same directory, never regenerated -->
<script src="vis-network.min.js"></script>

<script>
(function () {
  "use strict";

  var raw = JSON.parse(document.getElementById("graph-data").textContent);

  // Same filter category derivation as before: MonoBehaviour classes vs plain C#.
  function filterKey(n) { return n.type === "class" ? (n.is_mono_behaviour ? "mono" : "class") : n.type; }

  // Node visuals by category / type.
  var CAT_COLOR = {
    mono: "#4fc3f7", "class": "#7986cb", interface: "#81c784",
    event: "#ffb74d", prefab: "#e57373", scene: "#4db6ac"
  };
  var TYPE_SHAPE = { interface: "square", prefab: "diamond", scene: "triangle" }; // default "dot"

  // Edge visuals by type.
  var EDGE_COLORS = {
    calls: "#5c6470", implements: "#81c784", publish: "#ffb74d",
    subscribe: "#4fc3f7", registers: "#ba68c8", injects: "#f06292",
    has_component: "#8d6e63", contains: "#4db6ac", variant_of: "#e57373"
  };
  var EDGE_DASHED = {
    subscribe: true, registers: true, injects: true, contains: true, variant_of: true
  };

  // Node degree → hubs read a little bigger.
  var degree = {};
  raw.edges.forEach(function (e) {
    degree[e.source] = (degree[e.source] || 0) + 1;
    degree[e.target] = (degree[e.target] || 0) + 1;
  });

  // ── Build vis node objects (master copies kept for re-adding on filter show) ─
  var allNodes = raw.nodes.map(function (n) {
    var cat = filterKey(n);
    var base = n.type === "scene" ? 12 : (n.type === "prefab" ? 10 : 8);
    var ns = n.namespace || "";
    var lbl = n.label || n.id;
    return {
      id: n.id,
      label: lbl,
      _cat: cat,
      shape: TYPE_SHAPE[n.type] || "dot",
      color: { background: CAT_COLOR[cat] || "#aaaaaa", border: CAT_COLOR[cat] || "#aaaaaa" },
      size: base + Math.sqrt(degree[n.id] || 0),
      title: lbl + " (" + n.type + (ns ? ", " + ns : "") + ")",
      font: { color: "#e8e8ec", size: 11 }
    };
  });

  var visEdges = raw.edges.map(function (e, i) {
    return {
      id: "e" + i,
      from: e.source,
      to: e.target,
      color: { color: EDGE_COLORS[e.type] || "#5c6470" },
      dashes: !!EDGE_DASHED[e.type],
      arrows: { to: { enabled: true, scaleFactor: 0.5 } }
    };
  });

  var nodeById = {};
  allNodes.forEach(function (n) { nodeById[n.id] = n; });

  var nodesDS = new vis.DataSet(allNodes);
  var edgesDS = new vis.DataSet(visEdges);

  var container = document.getElementById("graph");
  var options = {
    nodes: { borderWidth: 0, font: { color: "#e8e8ec" } },
    edges: { smooth: false, width: 1 },
    physics: {
      solver: "forceAtlas2Based",
      forceAtlas2Based: {
        gravitationalConstant: -60, centralGravity: 0.005, springLength: 120,
        springConstant: 0.08, damping: 0.4, avoidOverlap: 0.8
      },
      stabilization: { iterations: 200, fit: true }
    },
    interaction: { hover: true, tooltipDelay: 100, hideEdgesOnDrag: true }
  };

  var network = new vis.Network(container, { nodes: nodesDS, edges: edgesDS }, options);

  // Freeze the layout once it settles — no perpetual motion.
  network.once("stabilizationIterationsDone", function () {
    network.setOptions({ physics: { enabled: false } });
  });

  // ── Stats: visible node/edge counts read from the live DataSets ─────────────
  var statsEl = document.getElementById("stats");
  function updateStats() {
    var present = {};
    nodesDS.getIds().forEach(function (id) { present[id] = true; });
    var ve = 0;
    edgesDS.forEach(function (e) { if (present[e.from] && present[e.to]) ve++; });
    statsEl.textContent = "nodes: " + nodesDS.length + "   edges: " + ve;
  }
  updateStats();

  if (allNodes.length > __MAX_NODES__) {
    document.getElementById("note").style.display = "block";
  }

  // ── Legend-as-filter: remove a category's nodes (saving positions) / re-add ──
  var hiddenStore = {}; // cat -> array of node objects carrying their saved x/y

  Array.prototype.forEach.call(document.querySelectorAll(".legend-row.toggle"), function (row) {
    row.addEventListener("click", function () {
      var cat = row.getAttribute("data-cat");
      if (hiddenStore[cat]) {
        // Show again at the exact saved coordinates — layout does not jump,
        // and physics stays disabled.
        nodesDS.add(hiddenStore[cat]);
        hiddenStore[cat] = null;
        row.classList.remove("off");
      } else {
        // Hide: capture live positions, then remove. vis auto-hides any edge
        // whose endpoint is gone.
        var ids = nodesDS.getIds().filter(function (id) {
          return nodeById[id] && nodeById[id]._cat === cat;
        });
        var pos = network.getPositions(ids);
        hiddenStore[cat] = ids.map(function (id) {
          var src = nodeById[id];
          var copy = {};
          for (var k in src) { if (src.hasOwnProperty(k)) copy[k] = src[k]; }
          if (pos[id]) { copy.x = pos[id].x; copy.y = pos[id].y; }
          return copy;
        });
        nodesDS.remove(ids);
        row.classList.add("off");
      }
      updateStats();
    });
  });
})();
</script>
</body>
</html>
"""


def render_html(nodes, edges):
    data = json.dumps({"nodes": nodes, "edges": edges})
    html = HTML_TEMPLATE.replace("__DATA__", data)
    html = html.replace("__MAX_NODES__", str(MAX_NODES_BEFORE_WARNING))
    return html


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate a self-contained graph.html from graph.json")
    parser.add_argument("--graph", default=os.path.join(SCRIPT_DIR, "graph.json"),
                         help="Path to graph.json (default: .claude/graph/graph.json)")
    parser.add_argument("--out", default=os.path.join(SCRIPT_DIR, "graph.html"),
                         help="Output HTML path (default: .claude/graph/graph.html)")
    args = parser.parse_args(argv)

    if not os.path.exists(args.graph):
        print(f"error: graph file not found: {args.graph}", file=sys.stderr)
        return 1

    lib = os.path.join(os.path.dirname(os.path.abspath(args.out)), "vis-network.min.js")
    if not os.path.exists(lib):
        print(f"error: vendored library missing: {lib}\n"
              f"       graph.html requires vis-network.min.js (pinned 9.1.6) in the same "
              f"directory as the output.\n"
              f"       Download it once and commit it:\n"
              f"         curl -sfL -o '{lib}' "
              f"https://unpkg.com/vis-network@9.1.6/standalone/umd/vis-network.min.js",
              file=sys.stderr)
        return 1

    try:
        g = load_graph(args.graph)
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: {args.graph} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    nodes, edges = build_nodes_edges(g)

    if len(nodes) > MAX_NODES_BEFORE_WARNING:
        print(f"note: {len(nodes)} nodes exceeds {MAX_NODES_BEFORE_WARNING} — "
              f"rendering everything, layout will be dense", file=sys.stderr)

    html = render_html(nodes, edges)

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(html)

    n_pub = sum(1 for e in edges if e["type"] == "publish")
    n_inject = sum(1 for e in edges if e["type"] == "injects")
    n_prefab = sum(1 for n in nodes if n["type"] == "prefab")
    n_scene = sum(1 for n in nodes if n["type"] == "scene")
    n_has = sum(1 for e in edges if e["type"] == "has_component")
    n_contains = sum(1 for e in edges if e["type"] == "contains")
    n_variant = sum(1 for e in edges if e["type"] == "variant_of")
    print(f"graph.html written: {args.out} "
          f"(nodes={len(nodes)}, edges={len(edges)}, publish_edges={n_pub}, "
          f"inject_edges={n_inject}, prefab_nodes={n_prefab}, scene_nodes={n_scene}, "
          f"has_component_edges={n_has}, contains_edges={n_contains}, "
          f"variant_of_edges={n_variant})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
