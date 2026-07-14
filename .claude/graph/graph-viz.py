#!/usr/bin/env python3
"""graph-viz.py — self-contained graph.html generator for the Unity Knowledge Graph.

Reads graph.json (+ resolves scenes.json / prefabs.json $partition refs, mirroring
graph-mcp-server.py's _resolve_partition), builds a node/edge model from
classes/interfaces/events + calls/implements/publish/subscribe, and emits ONE
self-contained graph.html: inline CSS, inline JSON data island, inline vanilla-JS
force-directed layout rendered on <canvas>. No external URLs, no CDN, no build step.

Usage:
    python3 graph-viz.py [--graph PATH] [--out PATH]

Defaults: .claude/graph/graph.json -> .claude/graph/graph.html
"""

import argparse
import json
import os
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


def build_nodes_edges(g):
    cb = g.get("codebase", {})
    classes = cb.get("classes", []) or []
    interfaces = cb.get("interfaces", []) or []
    events = cb.get("events", []) or []
    calls = cb.get("calls", []) or []

    nodes = []
    node_ids = set()

    for c in classes:
        name = c.get("name")
        if not name or name in node_ids:
            continue
        node_ids.add(name)
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

    return nodes, edges


# ── HTML template (self-contained: inline CSS + JS + canvas, no external URLs) ─

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
  #canvas-wrap { position: absolute; inset: 0; }
  canvas { display: block; width: 100%; height: 100%; background: #12141a; cursor: grab; }
  canvas.dragging { cursor: grabbing; }

  #legend {
    position: absolute; top: 12px; left: 12px; z-index: 10;
    background: rgba(20, 22, 28, 0.9); border: 1px solid #333844;
    border-radius: 8px; padding: 10px 14px; font-size: 12px; max-width: 260px;
  }
  #legend h3 { margin: 0 0 6px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; color: #9aa1ad; }
  .legend-row { display: flex; align-items: center; gap: 8px; margin: 3px 0; }
  .swatch { width: 12px; height: 12px; border-radius: 50%; flex: none; }
  .swatch.sq { border-radius: 3px; }
  .line-swatch { width: 22px; height: 0; border-top-width: 2px; border-top-style: solid; flex: none; }

  #tooltip {
    position: absolute; z-index: 20; pointer-events: none;
    background: rgba(20, 22, 28, 0.95); border: 1px solid #444b5a;
    border-radius: 6px; padding: 6px 10px; font-size: 12px; display: none;
    max-width: 320px; white-space: nowrap;
  }
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
</style>
</head>
<body>
<div id="canvas-wrap">
  <canvas id="graph-canvas"></canvas>
</div>
<div id="legend">
  <h3>Node Types</h3>
  <div class="legend-row"><span class="swatch" style="background:#4fc3f7"></span> Class (MonoBehaviour)</div>
  <div class="legend-row"><span class="swatch" style="background:#7986cb"></span> Class (plain C#)</div>
  <div class="legend-row"><span class="swatch sq" style="background:#81c784"></span> Interface</div>
  <div class="legend-row"><span class="swatch" style="background:#ffb74d"></span> Event</div>
  <h3 style="margin-top:10px;">Edge Types</h3>
  <div class="legend-row"><span class="line-swatch" style="border-color:#5c6470"></span> Calls</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#81c784"></span> Implements</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#ffb74d"></span> Publish</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#4fc3f7;border-top-style:dashed"></span> Subscribe</div>
  <div class="legend-row"><span class="line-swatch" style="border-color:#ba68c8;border-top-style:dotted"></span> Registers</div>
</div>
<div id="tooltip"></div>
<div id="stats"></div>
<div id="note">Large graph (&gt;800 nodes) — layout may be dense.</div>

<script type="application/json" id="graph-data">
__DATA__
</script>

<script>
(function () {
  "use strict";

  var raw = JSON.parse(document.getElementById("graph-data").textContent);
  var nodes = raw.nodes.map(function (n, i) {
    return {
      id: n.id, type: n.type, is_mono_behaviour: !!n.is_mono_behaviour,
      namespace: n.namespace || "",
      x: (Math.random() - 0.5) * 800, y: (Math.random() - 0.5) * 800,
      vx: 0, vy: 0, idx: i
    };
  });
  var edges = raw.edges;

  var byId = {};
  nodes.forEach(function (n) { byId[n.id] = n; });
  var edgeList = edges.map(function (e) {
    return { type: e.type, source: byId[e.source], target: byId[e.target] };
  }).filter(function (e) { return e.source && e.target; });

  document.getElementById("stats").textContent =
    "nodes: " + nodes.length + "   edges: " + edgeList.length;
  if (nodes.length > __MAX_NODES__) {
    document.getElementById("note").style.display = "block";
  }

  var canvas = document.getElementById("graph-canvas");
  var ctx = canvas.getContext("2d");
  var wrap = document.getElementById("canvas-wrap");
  var tooltip = document.getElementById("tooltip");

  var view = { scale: 1, ox: 0, oy: 0 };

  function resize() {
    canvas.width = wrap.clientWidth * window.devicePixelRatio;
    canvas.height = wrap.clientHeight * window.devicePixelRatio;
    canvas.style.width = wrap.clientWidth + "px";
    canvas.style.height = wrap.clientHeight + "px";
    view.ox = canvas.width / 2;
    view.oy = canvas.height / 2;
  }
  window.addEventListener("resize", resize);
  resize();

  // ── Force-directed layout: simple O(n^2) repulsion + spring attraction ──────
  var REPULSION = 2600;
  var SPRING_LEN = 90;
  var SPRING_K = 0.02;
  var DAMPING = 0.85;
  var CENTER_K = 0.002;

  function step() {
    var n = nodes.length;
    for (var i = 0; i < n; i++) {
      var a = nodes[i];
      var fx = -a.x * CENTER_K;
      var fy = -a.y * CENTER_K;
      for (var j = 0; j < n; j++) {
        if (i === j) continue;
        var b = nodes[j];
        var dx = a.x - b.x, dy = a.y - b.y;
        var d2 = dx * dx + dy * dy + 0.01;
        var d = Math.sqrt(d2);
        var f = REPULSION / d2;
        fx += (dx / d) * f;
        fy += (dy / d) * f;
      }
      a.fx = fx; a.fy = fy;
    }
    edgeList.forEach(function (e) {
      var dx = e.target.x - e.source.x, dy = e.target.y - e.source.y;
      var d = Math.sqrt(dx * dx + dy * dy) || 0.01;
      var stretch = d - SPRING_LEN;
      var f = SPRING_K * stretch;
      var fx = (dx / d) * f, fy = (dy / d) * f;
      e.source.fx += fx; e.source.fy += fy;
      e.target.fx -= fx; e.target.fy -= fy;
    });
    nodes.forEach(function (a) {
      if (a.dragging) return;
      a.vx = (a.vx + a.fx) * DAMPING;
      a.vy = (a.vy + a.fy) * DAMPING;
      a.x += a.vx;
      a.y += a.vy;
    });
  }

  var EDGE_COLORS = {
    calls: "#5c6470", implements: "#81c784", publish: "#ffb74d",
    subscribe: "#4fc3f7", registers: "#ba68c8"
  };
  var EDGE_DASH = {
    calls: [], implements: [], publish: [], subscribe: [5, 4], registers: [2, 3]
  };

  function nodeColor(n) {
    if (n.type === "interface") return "#81c784";
    if (n.type === "event") return "#ffb74d";
    if (n.type === "class") return n.is_mono_behaviour ? "#4fc3f7" : "#7986cb";
    return "#aaaaaa";
  }
  function nodeRadius(n) {
    return n.type === "event" ? 5 : (n.type === "interface" ? 6 : 7);
  }
  function nodeShape(n) { return n.type === "interface" ? "sq" : "circle"; }

  function toScreen(x, y) {
    return [x * view.scale + view.ox, y * view.scale + view.oy];
  }
  function toWorld(sx, sy) {
    return [(sx - view.ox) / view.scale, (sy - view.oy) / view.scale];
  }

  function draw() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.lineWidth = 1;
    edgeList.forEach(function (e) {
      var p1 = toScreen(e.source.x, e.source.y);
      var p2 = toScreen(e.target.x, e.target.y);
      ctx.beginPath();
      ctx.setLineDash(EDGE_DASH[e.type] || []);
      ctx.strokeStyle = EDGE_COLORS[e.type] || "#5c6470";
      ctx.moveTo(p1[0], p1[1]);
      ctx.lineTo(p2[0], p2[1]);
      ctx.stroke();
    });
    ctx.setLineDash([]);

    nodes.forEach(function (n) {
      var p = toScreen(n.x, n.y);
      var r = nodeRadius(n) * Math.max(view.scale, 0.4);
      ctx.fillStyle = nodeColor(n);
      if (nodeShape(n) === "sq") {
        ctx.fillRect(p[0] - r, p[1] - r, r * 2, r * 2);
      } else {
        ctx.beginPath();
        ctx.arc(p[0], p[1], r, 0, Math.PI * 2);
        ctx.fill();
      }
      if (n === hoverNode || n === dragNode) {
        ctx.strokeStyle = "#ffffff";
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.arc(p[0], p[1], r + 3, 0, Math.PI * 2);
        ctx.stroke();
      }
    });
  }

  function tick() {
    step();
    draw();
    requestAnimationFrame(tick);
  }

  // ── Interaction: hover-to-label, drag-to-reposition, wheel-to-zoom ──────────
  var hoverNode = null, dragNode = null, panning = false, panStart = null;

  function nodeAtScreen(sx, sy) {
    var w = toWorld(sx, sy);
    var best = null, bestD = 1e9;
    nodes.forEach(function (n) {
      var dx = n.x - w[0], dy = n.y - w[1];
      var d = dx * dx + dy * dy;
      var r = nodeRadius(n) + 4;
      if (d < r * r && d < bestD) { best = n; bestD = d; }
    });
    return best;
  }

  canvas.addEventListener("mousemove", function (ev) {
    var rect = canvas.getBoundingClientRect();
    var sx = (ev.clientX - rect.left) * window.devicePixelRatio;
    var sy = (ev.clientY - rect.top) * window.devicePixelRatio;

    if (dragNode) {
      var w = toWorld(sx, sy);
      dragNode.x = w[0]; dragNode.y = w[1];
      dragNode.vx = 0; dragNode.vy = 0;
      return;
    }
    if (panning) {
      view.ox += sx - panStart[0];
      view.oy += sy - panStart[1];
      panStart = [sx, sy];
      return;
    }
    var hit = nodeAtScreen(sx, sy);
    hoverNode = hit;
    if (hit) {
      tooltip.style.display = "block";
      tooltip.style.left = (ev.clientX + 14) + "px";
      tooltip.style.top = (ev.clientY + 10) + "px";
      tooltip.textContent = hit.id + " (" + hit.type + (hit.namespace ? ", " + hit.namespace : "") + ")";
    } else {
      tooltip.style.display = "none";
    }
  });

  canvas.addEventListener("mousedown", function (ev) {
    var rect = canvas.getBoundingClientRect();
    var sx = (ev.clientX - rect.left) * window.devicePixelRatio;
    var sy = (ev.clientY - rect.top) * window.devicePixelRatio;
    var hit = nodeAtScreen(sx, sy);
    if (hit) {
      dragNode = hit;
      dragNode.dragging = true;
      canvas.classList.add("dragging");
    } else {
      panning = true;
      panStart = [sx, sy];
      canvas.classList.add("dragging");
    }
  });

  window.addEventListener("mouseup", function () {
    if (dragNode) { dragNode.dragging = false; }
    dragNode = null;
    panning = false;
    canvas.classList.remove("dragging");
  });

  canvas.addEventListener("wheel", function (ev) {
    ev.preventDefault();
    var factor = ev.deltaY < 0 ? 1.1 : 0.9;
    view.scale = Math.max(0.05, Math.min(8, view.scale * factor));
  }, { passive: false });

  tick();
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
    print(f"graph.html written: {args.out} "
          f"(nodes={len(nodes)}, edges={len(edges)}, publish_edges={n_pub})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
