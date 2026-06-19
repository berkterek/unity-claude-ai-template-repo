"""graph-mcp-server — stdio MCP server exposing call-graph BFS tools.

Loads graph.json + scenes.json + prefabs.json from SCRIPT_DIR into RAM at
startup. Checks graph.json mtime on every handler call and reloads all three
partitions when stale (atomic rebind, lock-free). Delegates all traversal
logic to graph_bfs_core.

Tool names surface in Claude Code as:
  mcp__graph_mcp__callers
  mcp__graph_mcp__impact
  mcp__graph_mcp__path
  mcp__graph_mcp__god_nodes
"""

import asyncio
import json
import os
import sys
from collections import defaultdict
from typing import Optional

# ── SCRIPT_DIR: all file paths relative to this file's directory ──────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

import graph_bfs_core  # noqa: E402 — must come after sys.path insert

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp import types

# ── Graph file paths (SCRIPT_DIR-relative) ────────────────────────────────────
_graph_json_path   = os.path.join(SCRIPT_DIR, "graph.json")
_scenes_json_path  = os.path.join(SCRIPT_DIR, "scenes.json")
_prefabs_json_path = os.path.join(SCRIPT_DIR, "prefabs.json")

# ── Module-level graph state ──────────────────────────────────────────────────
_g: dict = {}
_forward: dict = defaultdict(set)
_reverse: dict = defaultdict(set)
_edges: list = []
_graph_mtime: float = 0.0


# ── Graph loader ──────────────────────────────────────────────────────────────

def _resolve_partition(obj, base_dir: str):
    """Walk the graph dict and replace {\"$partition\": \"file.json\"} refs."""
    if isinstance(obj, dict):
        if "$partition" in obj and len(obj) == 1:
            part_path = os.path.join(base_dir, obj["$partition"])
            with open(part_path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        return {k: _resolve_partition(v, base_dir) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_resolve_partition(item, base_dir) for item in obj]
    return obj


def load_graph():
    """Load graph.json + scenes.json + prefabs.json; build adjacency; return state.

    Fails fast (raises) if ANY of the three partition files is missing,
    unreadable, or contains malformed JSON.

    Returns:
        (g, forward, reverse, edges) — fresh objects every call.
    """
    # Fail fast: all three files must exist and be readable JSON.
    for path in (_graph_json_path, _scenes_json_path, _prefabs_json_path):
        if not os.path.exists(path):
            raise FileNotFoundError(f"Required partition file missing: {path}")

    with open(_graph_json_path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)

    # Resolve $partition references (scenes.json / prefabs.json).
    g = _resolve_partition(raw, SCRIPT_DIR)

    # Build adjacency from codebase.calls[].
    forward: dict = defaultdict(set)
    reverse: dict = defaultdict(set)
    edges: list = g.get("codebase", {}).get("calls", [])

    for edge in edges:
        caller = edge.get("caller", "")
        callee = edge.get("callee", "")
        if caller and callee:
            forward[caller].add(callee)
            reverse[callee].add(caller)

    return g, forward, reverse, edges


# ── Startup load ──────────────────────────────────────────────────────────────
try:
    _g, _forward, _reverse, _edges = load_graph()
    _graph_mtime = os.path.getmtime(_graph_json_path)
except Exception as _startup_err:
    print(
        f"graph-mcp-server: startup failed — {_startup_err}",
        file=sys.stderr,
    )
    sys.exit(1)


# ── Stale-check helper (called at top of every handler) ───────────────────────

def _maybe_reload():
    """Check graph.json mtime; atomically rebind module-level state if stale."""
    global _g, _forward, _reverse, _edges, _graph_mtime
    try:
        current_mtime = os.path.getmtime(_graph_json_path)
    except OSError as e:
        print(f"graph-mcp-server: cannot stat {_graph_json_path}: {e}", file=sys.stderr)
        return  # Can't stat — keep last-good.
    if current_mtime != _graph_mtime:
        try:
            g, fwd, rev, edg = load_graph()
            # Atomic rebind — no await here
            _g, _forward, _reverse, _edges, _graph_mtime = g, fwd, rev, edg, current_mtime
        except Exception as e:
            print(
                f"graph-mcp-server: reload failed, using last-good graph: {e}",
                file=sys.stderr,
            )


# ── MCP server ────────────────────────────────────────────────────────────────

server = Server("graph-mcp")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="callers",
            description=(
                "One-hop reverse lookup: returns every call-site that directly calls "
                "the given node (Class.Method). Delegates to graph_bfs_core.callers_core."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "node": {
                        "type": "string",
                        "description": "Fully-qualified method name, e.g. AudioService.PlaySound",
                    }
                },
                "required": ["node"],
            },
        ),
        types.Tool(
            name="impact",
            description=(
                "BFS forward + reverse from node up to `hops` hops. "
                "Returns downstream and upstream affected nodes. "
                "Default hops=3 is supplied by the core when omitted."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "node": {
                        "type": "string",
                        "description": "Starting node, e.g. AudioService.PlaySound",
                    },
                    "hops": {
                        "type": "integer",
                        "description": "BFS depth limit (optional; core default is 3).",
                    },
                },
                "required": ["node"],
            },
        ),
        types.Tool(
            name="path",
            description=(
                "BFS shortest path from node `a` to node `b` through the call graph."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "a": {
                        "type": "string",
                        "description": "Source node.",
                    },
                    "b": {
                        "type": "string",
                        "description": "Target node.",
                    },
                },
                "required": ["a", "b"],
            },
        ),
        types.Tool(
            name="god_nodes",
            description=(
                "Rank nodes by total call-graph degree (in+out). "
                "Returns the top `top` over-coupled nodes. "
                "Default top=10 is supplied by the core when omitted."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "top": {
                        "type": "integer",
                        "description": "How many results to return (optional; core default is 10).",
                    },
                },
                "required": [],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict):
    """Dispatch tool calls to graph_bfs_core, returning JSON string results."""
    _maybe_reload()

    if name == "callers":
        node = arguments.get("node", "")
        result = graph_bfs_core.callers_core(node, _g, _forward, _reverse, _edges)
        return [types.TextContent(type="text", text=json.dumps(result))]

    if name == "impact":
        node = arguments.get("node", "")
        hops = arguments.get("hops", None)  # None → core uses default 3
        result = graph_bfs_core.impact_core(node, _g, _forward, _reverse, _edges, hops)
        return [types.TextContent(type="text", text=json.dumps(result))]

    if name == "path":
        a = arguments.get("a", "")
        b = arguments.get("b", "")
        result = graph_bfs_core.path_core(a, b, _g, _forward, _reverse, _edges)
        return [types.TextContent(type="text", text=json.dumps(result))]

    if name == "god_nodes":
        top = arguments.get("top", None)  # None → core uses default 10
        result = graph_bfs_core.god_nodes_core(_g, _forward, _reverse, _edges, top)
        return [types.TextContent(type="text", text=json.dumps(result))]

    raise ValueError(f"Unknown tool: {name}")


# ── Entry point ───────────────────────────────────────────────────────────────

async def main():
    async with stdio_server() as (read_stream, write_stream):
        init_options = server.create_initialization_options()
        await server.run(read_stream, write_stream, init_options)


if __name__ == "__main__":
    asyncio.run(main())
