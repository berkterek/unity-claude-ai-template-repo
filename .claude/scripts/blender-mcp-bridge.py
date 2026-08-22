"""blender-mcp-bridge — stdio MCP server fronting Blender's built-in MCP add-on.

Blender's official `mcp` extension (Blender Lab, blender_version_min 5.1.0) does NOT
speak MCP. It runs a raw TCP socket server on localhost:9876 that accepts
null-byte-delimited JSON:

    -> {"type": "execute", "code": "<python>", "strict_json": true}\0
    <- {"status": "ok", "result": {...}, "stdout": "...", "stderr": "..."}\0

The executed code must assign a JSON-serializable dict to a global named `result`.
This file is the translation layer, so Claude Code can reach it as ordinary tools:

  mcp__blender__blender_scene_info
  mcp__blender__blender_execute
  mcp__blender__blender_export_fbx

Why a project-specific bridge and not just a generic exec tool: `blender_export_fbx`
hardcodes the FBX flags that make a Blender mesh land correctly in Unity, and refuses
the export when a pre-flight invariant fails. A rule written in a .md file cannot be
enforced on a binary asset by any Write/Edit hook — a tool that will not emit a wrong
file can. That is the enforcement point.

Env overrides: BLENDER_MCP_HOST (default localhost), BLENDER_MCP_PORT (default 9876).
"""

import asyncio
import json
import os
import socket

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp import types

HOST = os.environ.get("BLENDER_MCP_HOST", "localhost")
PORT = int(os.environ.get("BLENDER_MCP_PORT", "9876"))
TIMEOUT = float(os.environ.get("BLENDER_MCP_TIMEOUT", "120"))


# ── transport ────────────────────────────────────────────────────────────────
def _call(code: str, strict_json: bool = True) -> dict:
    """Round-trip one execute request. Raises RuntimeError on transport failure."""
    payload = json.dumps({"type": "execute", "code": code, "strict_json": strict_json})
    try:
        sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
    except OSError as ex:
        raise RuntimeError(
            "Cannot reach Blender at {}:{} ({}). Is Blender running with the MCP "
            "add-on enabled (Preferences > Add-ons > MCP, 'Auto Start' checked)?".format(HOST, PORT, ex)
        ) from ex
    try:
        sock.sendall((payload + "\0").encode("utf-8"))
        buf = bytearray()
        while not buf.endswith(b"\0"):
            chunk = sock.recv(65536)
            if not chunk:
                raise RuntimeError("Blender closed the connection before replying.")
            buf += chunk
    finally:
        sock.close()
    return json.loads(bytes(buf).rstrip(b"\0"))


# ── hard refusal: SystemExit terminates Blender ───────────────────────────────
# Measured 2026-08-22: `raise SystemExit` inside executed code escapes the add-on's
# `except Exception` handler (SystemExit is a BaseException) and kills the whole Blender
# process — the open .blend goes with it. The add-on's weak sandbox patches `sys.exit`
# but NOT the exception class, so that protection does not cover this. Refuse at the
# bridge, before the bytes reach the socket.
_FATAL_PATTERNS = ("SystemExit", "os._exit", "bpy.ops.wm.quit_blender", "bpy.app.quit")


def _reject_fatal(code: str) -> None:
    hits = [p for p in _FATAL_PATTERNS if p in code]
    if hits:
        raise RuntimeError(
            "Refused: code contains {} — this terminates the Blender process and loses the "
            "open .blend. Use a function with plain `return`s and assign to `result` instead.".format(hits)
        )


def _render(resp: dict) -> str:
    """Flatten a Blender response into text, keeping stdout/stderr visible."""
    out = [json.dumps(resp.get("result", {}), indent=2)] if resp.get("status") == "ok" else [
        "STATUS: error\n" + str(resp.get("message", "")).rstrip()
    ]
    for stream in ("stdout", "stderr"):
        if resp.get(stream):
            out.append("--- {} ---\n{}".format(stream, resp[stream].rstrip()))
    return "\n\n".join(out)


# ── tool: scene info ─────────────────────────────────────────────────────────
_SCENE_INFO = r'''
import bpy
sc = bpy.context.scene
us = sc.unit_settings

def xform(o):
    return {
        "name": o.name, "type": o.type,
        "parent": o.parent.name if o.parent else None,
        "collections": [c.name for c in o.users_collection],
        "loc": [round(v, 6) for v in o.location],
        "rot_euler_deg": [round(__import__("math").degrees(v), 4) for v in o.rotation_euler],
        "scale": [round(v, 6) for v in o.scale],
        "modifiers": [m.type for m in o.modifiers],
        "materials": [(s.material.name if s.material else None) for s in o.material_slots],
        "verts": len(o.data.vertices) if o.type == "MESH" else None,
        "tris": sum(len(p.vertices) - 2 for p in o.data.polygons) if o.type == "MESH" else None,
        "uv_layers": [l.name for l in o.data.uv_layers] if o.type == "MESH" else None,
    }

result = {
    "blender": bpy.app.version_string,
    "filepath": bpy.data.filepath,
    "is_dirty": bpy.data.is_dirty,
    "unit_system": us.system,
    "unit_scale_length": us.scale_length,
    "collections": {c.name: [o.name for o in c.objects] for c in bpy.data.collections},
    "objects": [xform(o) for o in bpy.data.objects],
}
'''


# ── tool: export fbx ─────────────────────────────────────────────────────────
# Pre-flight refusals, each tied to a failure that is silent on the Unity side:
#   unit_scale_length != 1.0  -> every imported mesh is off by that factor
#   non-uniform object scale  -> normals skew; Unity cannot recover it post-import
#   no UV layer on a mesh     -> any textured material renders untextured, no error
# Export flags: apply_scale_options=FBX_SCALE_NONE + global_scale=1.0 is the pair that
# keeps 1 Blender metre == 1 Unity unit. axis_forward=-Z/axis_up=Y is Blender Z-up ->
# Unity Y-up. bake_space_transform stays False (True corrupts animated rigs).
_EXPORT_FBX = r'''
import bpy, os

COLLECTION = {collection!r}
OBJECTS    = {objects!r}
DEST       = {dest!r}
STRICT     = {strict!r}

# NOTE: everything runs inside a function with plain `return`s. Do NOT bail out with
# `raise SystemExit` — the add-on catches `Exception`, not `BaseException`, so SystemExit
# escapes the handler and the socket is closed with no reply at all (measured 2026-08-22).
def run():
    sc = bpy.context.scene
    problems, checked = [], []

    checked.append("unit_scale_length == 1.0")
    if abs(sc.unit_settings.scale_length - 1.0) > 1e-9:
        problems.append(
            "scene unit_settings.scale_length is {{}}, must be 1.0 for 1 Blender metre == 1 Unity unit".format(
                sc.unit_settings.scale_length))

    if COLLECTION:
        col = bpy.data.collections.get(COLLECTION)
        if col is None:
            return {{"status": "error", "message": "No collection named {{!r}}. Have: {{}}".format(
                COLLECTION, sorted(c.name for c in bpy.data.collections))}}
        targets = list(col.all_objects)
    elif OBJECTS:
        targets, missing = [], []
        for n in OBJECTS:
            o = bpy.data.objects.get(n)
            if o is None:
                missing.append(n)
            else:
                targets.append(o)
        if missing:
            return {{"status": "error", "message": "No object(s) named: {{}}".format(missing)}}
    else:
        return {{"status": "error", "message": "Pass either collection or objects."}}

    meshes = [o for o in targets if o.type == "MESH"]
    if not meshes:
        problems.append("selection contains no MESH object")

    checked.append("uniform object scale")
    checked.append("mesh has a UV layer")
    for o in meshes:
        sx, sy, sz = o.scale
        if max(abs(sx - sy), abs(sy - sz), abs(sx - sz)) > 1e-6:
            problems.append("{{}}: non-uniform scale {{}}".format(o.name, [round(v, 5) for v in o.scale]))
        if not o.data.uv_layers:
            problems.append("{{}}: no UV layer".format(o.name))

    # Axis conversion: measured 2026-08-22 in Unity 6000.3.8f1 (see SKILL.md Card 5a).
    # bake_space_transform=True writes Unity-oriented vertices, leaving rootScale=(1,1,1)
    # and rootEuler=(0,0,0). With False, Unity carries the conversion as a 270.020 deg
    # rotation on the imported root -- correct world size, but a rotated, imprecise root.
    # It is unsafe for skinned/animated content, so an ARMATURE in the selection forces False.
    has_armature = any(o.type == "ARMATURE" for o in targets) or any(
        m.type == "ARMATURE" for o in meshes for m in o.modifiers)
    bake_space = not has_armature
    checked.append("armature present -> bake_space_transform")
    if has_armature:
        problems.append(
            "ARMATURE present: bake_space_transform forced False (baking it is unsafe for skinned "
            "content). Measured on a minimal single-bone auto-weighted rig this still imports with "
            "rootScale=(1,1,1) and rootEuler=(0,0,0) -- but a real multi-bone animated character is "
            "UNVERIFIED. Inspect the root transform and the bone hierarchy in Unity.")

    if problems and STRICT and not (has_armature and len(problems) == 1):
        return {{"status": "refused", "checked": checked, "problems": problems,
                 "hint": "Fix in Blender, or re-call with strict=false to export anyway."}}

    parent = os.path.dirname(DEST)
    if parent:
        os.makedirs(parent, exist_ok=True)

    # Save and restore the artist's live selection — this runs inside their open session.
    prev_sel = list(bpy.context.selected_objects)
    prev_active = bpy.context.view_layer.objects.active
    try:
        bpy.ops.object.select_all(action="DESELECT")
        for o in targets:
            try:
                o.select_set(True)
            except RuntimeError:
                pass  # not in the active view layer
        bpy.context.view_layer.objects.active = meshes[0] if meshes else None

        bpy.ops.export_scene.fbx(
            filepath=DEST,
            use_selection=True,
            apply_unit_scale=True,
            apply_scale_options="FBX_SCALE_UNITS",
            global_scale=1.0,
            axis_forward="-Z",
            axis_up="Y",
            bake_space_transform=bake_space,
            object_types={{"MESH", "ARMATURE", "EMPTY"}},
            use_mesh_modifiers=True,
            mesh_smooth_type="FACE",
            use_tspace=True,
            add_leaf_bones=False,
            path_mode="COPY",
            embed_textures=False,
        )
    finally:
        bpy.ops.object.select_all(action="DESELECT")
        for o in prev_sel:
            try:
                o.select_set(True)
            except RuntimeError:
                pass
        bpy.context.view_layer.objects.active = prev_active

    return {{
        "status": "ok",
        "dest": DEST,
        "bytes": os.path.getsize(DEST) if os.path.exists(DEST) else 0,
        "exported": [o.name for o in targets],
        "meshes": len(meshes),
        "tris": sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes),
        "checked": checked,
        "problems": problems,
        "bake_space_transform": bake_space,
        "note": ("1 Blender metre == 1 Unity unit; Z-up converted to Y-up. Blender file NOT saved. "
                 "Verified in Unity 6000.3.8f1: rootScale=(1,1,1), rootEuler=(0,0,0), world size exact."
                 if bake_space else
                 "1 Blender metre == 1 Unity unit. ARMATURE present so the axis conversion stays on "
                 "the transform rather than in the vertices. Verified clean on a minimal rig; a real "
                 "animated character is unverified. Blender file NOT saved."),
    }}

result = run()
'''

server = Server("blender")


@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="blender_scene_info",
            description=(
                "Read-only inventory of the open .blend: units, collections, and per-object "
                "transform / scale / modifiers / materials / UV / tri count. Run this FIRST — "
                "unit scale and non-uniform scale are the two things that silently break a Unity import."
            ),
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="blender_export_fbx",
            description=(
                "Export a collection or named objects to .fbx with Unity-correct settings "
                "(1 m == 1 unit, Z-up baked to Y-up so the Unity root stays unrotated and unscaled, "
                "tangents, no leaf bones). Refuses to write the file "
                "when a pre-flight check fails: scene unit scale != 1.0, non-uniform object scale, "
                "or a mesh with no UV layer. Never saves the .blend."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "dest": {"type": "string", "description": "Absolute .fbx output path. Parent dirs are created."},
                    "collection": {"type": "string", "description": "Collection to export (recursive). Use this or objects."},
                    "objects": {"type": "array", "items": {"type": "string"}, "description": "Explicit object names."},
                    "strict": {"type": "boolean", "default": True, "description": "false = export despite pre-flight problems."},
                },
                "required": ["dest"],
            },
        ),
        types.Tool(
            name="blender_execute",
            description=(
                "Run Python inside the running Blender. The code MUST assign a JSON-serializable "
                "dict to a global named `result`. Escape hatch for anything the two tools above do "
                "not cover (modelling, materials, UV, cleanup). Mutates the artist's live session — "
                "prefer blender_scene_info for reads."
            ),
            inputSchema={
                "type": "object",
                "properties": {"code": {"type": "string"}},
                "required": ["code"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
    try:
        if name == "blender_scene_info":
            resp = _call(_SCENE_INFO)
        elif name == "blender_export_fbx":
            dest = arguments.get("dest", "")
            if not dest.endswith(".fbx"):
                raise RuntimeError("dest must end in .fbx, got {!r}".format(dest))
            if not os.path.isabs(dest):
                raise RuntimeError("dest must be an absolute path, got {!r}".format(dest))
            resp = _call(_EXPORT_FBX.format(
                collection=arguments.get("collection") or "",
                objects=list(arguments.get("objects") or []),
                dest=dest,
                strict=bool(arguments.get("strict", True)),
            ))
        elif name == "blender_execute":
            # strict_json=False: LLM-written code routinely returns a bpy object by
            # accident; repr() lets it read the mistake instead of losing the whole reply.
            _reject_fatal(arguments["code"])
            resp = _call(arguments["code"], strict_json=False)
        else:
            raise RuntimeError("Unknown tool: {}".format(name))
    except Exception as ex:
        return [types.TextContent(type="text", text="ERROR: {}".format(ex))]
    return [types.TextContent(type="text", text=_render(resp))]


async def _main() -> None:
    async with stdio_server() as (r, w):
        await server.run(r, w, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(_main())
