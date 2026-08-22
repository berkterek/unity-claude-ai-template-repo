#!/usr/bin/env python3
"""Builds every probe case in the running Blender and exports each via the REAL export tool.

Called by run-probe.sh. Writes <outdir>/*.fbx plus <outdir>/cases.json, the manifest the
Unity-side assertion script reads.

Every case is built from scratch with bpy primitives — nothing is committed. The export
always goes through blender_export_fbx's own code path, never a hand-rolled
bpy.ops.export_scene.fbx call, because the whole point is to measure the shipped contract.
"""

import argparse
import importlib.util
import json
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BRIDGE = os.path.join(REPO, ".claude", "scripts", "blender-mcp-bridge.py")


def load_bridge():
    spec = importlib.util.spec_from_file_location("blbridge", BRIDGE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Each case: (name, blender-build-python, expectations-dict)
# Expectation keys the Unity side understands:
#   world           [x,y,z]  Renderer.bounds.size of the whole imported hierarchy
#   root_scale      [x,y,z]  root transform localScale
#   root_euler      [x,y,z]  root transform localEulerAngles
#   mesh_count      int      MeshFilter count in the imported hierarchy
#   material_count  int      distinct sharedMaterials across the hierarchy
#   bone_count      int      SkinnedMeshRenderer bones (0 = expect no skinned renderer)
#   expect_refused  bool     the export itself must refuse; nothing reaches Unity
#   note            str      printed alongside, for cases that assert documented-imperfect
CASES = [
    (
        "static_box",
        '''
import bpy
bpy.ops.mesh.primitive_cube_add(size=2.0)
o = bpy.context.object; o.name = "P_Static"
o.scale = (0.5, 1.0, 2.0)                      # -> X=1m Y=2m Z=4m
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
result = {"objects": ["P_Static"]}
''',
        {"world": [1, 4, 2], "root_scale": [1, 1, 1], "root_euler": [0, 0, 0],
         "mesh_count": 1, "material_count": 0, "bone_count": 0,
         "note": "baseline — the only case verified before this harness existed"},
    ),
    (
        # Parenting is where a naive axis conversion breaks: the child's offset must be
        # converted with the same basis as its vertices, or the mesh is right and the
        # hierarchy is wrong.
        "parented",
        '''
import bpy
bpy.ops.object.empty_add(location=(0, 0, 0))
p = bpy.context.object; p.name = "P_Root"
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 3.0))   # 3m up Blender Z
c = bpy.context.object; c.name = "P_Child"
c.parent = p
c.matrix_parent_inverse = p.matrix_world.inverted()
result = {"objects": ["P_Root", "P_Child"]}
''',
        # child spans z 2.5..3.5 in Blender -> Unity Y 2.5..3.5, so total extent
        # from origin is not the mesh size; assert the mesh size and the child's Y offset.
        {"world": [1, 1, 1], "root_scale": [1, 1, 1], "root_euler": [0, 0, 0],
         "mesh_count": 1, "material_count": 0, "bone_count": 0,
         "child_world_y": 3.0,
         "note": "child offset must convert with the same basis as its vertices"},
    ),
    (
        "multi_mesh",
        '''
import bpy
names = []
for i, x in enumerate((-2.0, 0.0, 2.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, 0, 0))
    bpy.context.object.name = "P_Multi_%d" % i
    names.append(bpy.context.object.name)
result = {"objects": names}
''',
        {"world": [5, 1, 1], "root_scale": [1, 1, 1], "root_euler": [0, 0, 0],
         "mesh_count": 3, "material_count": 0, "bone_count": 0,
         "note": "three 1m cubes at x=-2,0,2 -> 5m total span, 3 MeshFilters"},
    ),
    (
        # Two slots on one mesh. A dropped slot is invisible until the wrong half of the
        # model renders with the wrong material.
        "two_materials",
        '''
import bpy
bpy.ops.mesh.primitive_cube_add(size=1.0)
o = bpy.context.object; o.name = "P_Mats"
for n in ("P_MatA", "P_MatB"):
    m = bpy.data.materials.new(n)
    m.use_nodes = True
    o.data.materials.append(m)
for i, poly in enumerate(o.data.polygons):
    poly.material_index = i % 2
result = {"objects": ["P_Mats"], "slots": [s.material.name for s in o.material_slots]}
''',
        {"world": [1, 1, 1], "root_scale": [1, 1, 1], "root_euler": [0, 0, 0],
         "mesh_count": 1, "material_count": 2, "bone_count": 0,
         "note": "both material slots must survive the export"},
    ),
    (
        # An ARMATURE forces bake_space_transform=False. The first version of this case
        # asserted a ~270.02 deg root rotation, because that is what bake=False produces for
        # a PLAIN mesh (measured, SKILL.md Card 5a). The harness's first run returned
        # (0,0,0) instead and thereby corrected the prediction: with a skeleton present
        # Unity resolves the conversion itself. Keeping the wrong expectation would have
        # meant a permanently red suite documenting a defect that does not exist.
        "skinned",
        '''
import bpy
bpy.ops.object.armature_add(location=(0, 0, 0))
arm = bpy.context.object; arm.name = "P_Arm"
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
msh = bpy.context.object; msh.name = "P_Skin"
bpy.ops.object.select_all(action="DESELECT")
msh.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
result = {"objects": ["P_Arm", "P_Skin"],
          "bones": [b.name for b in arm.data.bones],
          "vgroups": [g.name for g in msh.vertex_groups]}
''',
        {"root_scale": [1, 1, 1], "root_euler": [0, 0, 0], "euler_tol": 0.01,
         "mesh_count": 1, "material_count": 0, "bone_count": 1,
         "note": "bake_space_transform=False (armature) yet still clean — measured, not assumed. "
                 "This is a MINIMAL single-bone auto-weighted rig; a real animated character "
                 "remains unverified. A regression here means the rig path drifted."},
    ),
]

CLEAR = '''
import bpy
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
    for d in list(coll):
        if d.users == 0:
            coll.remove(d)
result = {"left": [o.name for o in bpy.data.objects]}
'''


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--outdir", required=True, help="where the .fbx files and cases.json go")
    ap.add_argument("--case", action="append", help="run only this case (repeatable)")
    args = ap.parse_args()

    m = load_bridge()
    os.makedirs(args.outdir, exist_ok=True)

    # Refuse to run against a file with unsaved work — this clears the scene.
    probe = m._call('import bpy\nresult = {"dirty": bpy.data.is_dirty, "path": bpy.data.filepath, '
                    '"objects": len(bpy.data.objects)}')
    if probe.get("status") != "ok":
        print("Blender not reachable: {}".format(probe.get("message", probe)), file=sys.stderr)
        return 2
    info = probe["result"]
    if info["dirty"] or info["path"]:
        print("REFUSED: Blender has a file open ({}) or unsaved changes (dirty={}). This harness "
              "clears the scene. Open an empty Blender (File > New) and re-run."
              .format(info["path"] or "<untitled>", info["dirty"]), file=sys.stderr)
        return 2

    selected = set(args.case or [c[0] for c in CASES])
    manifest = []

    for name, build, expect in CASES:
        if name not in selected:
            continue
        m._call(CLEAR)
        built = m._call(build)
        if built.get("status") != "ok":
            print("[{}] BUILD FAILED: {}".format(name, built.get("message", "")[:400]), file=sys.stderr)
            manifest.append({"name": name, "build_failed": True, **expect})
            continue

        objs = built["result"]["objects"]
        dest = os.path.join(args.outdir, "{}.fbx".format(name))
        exported = m._call(m._EXPORT_FBX.format(collection="", objects=objs, dest=dest, strict=True))
        res = exported.get("result", {})
        print("[{:<14}] build={} export={} bake_space={} problems={}".format(
            name, objs, res.get("status"), res.get("bake_space_transform"), res.get("problems")))
        manifest.append({
            "name": name,
            "fbx": "Assets/Models/{}.fbx".format(name),
            "export_status": res.get("status"),
            "bake_space_transform": res.get("bake_space_transform"),
            "export_problems": res.get("problems", []),
            **expect,
        })

    m._call(CLEAR)
    with open(os.path.join(args.outdir, "cases.json"), "w") as fh:
        json.dump({"cases": manifest}, fh, indent=2)
    print("\nmanifest: {}/cases.json ({} case)".format(args.outdir, len(manifest)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
