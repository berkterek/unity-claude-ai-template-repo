---
name: blender-mcp
description: Use when producing, inspecting, or exporting 3D assets from Blender for this Unity project — modelling via MCP, checking a mesh before export, or getting an FBX into Assets/. Covers Blender's official MCP add-on (Blender Lab), the bridge that makes it reachable from Claude Code, and the Unity-correct export contract.
model-tier: sonnet
---

# Blender → Unity via MCP

> Measured against Blender **5.2.0 LTS** with the official `mcp` extension (Blender Lab v1.0.0,
> `blender_version_min = 5.1.0`) on 2026-08-22. Facts below were observed, not assumed.

## Cards

### Card 1: The Official Add-on Is Not an MCP Server — A Bridge Is Mandatory

**WHEN:** Wiring Claude Code to Blender for the first time, or debugging "Blender MCP tools are missing".

**WRONG:**
```bash
# There is no MCP endpoint at this address to connect to.
claude mcp add blender --transport sse http://localhost:9876
# Equally wrong: the third-party add-on's bridge. Same port, DIFFERENT protocol.
claude mcp add blender -- uvx blender-mcp
```

**RIGHT:**
```bash
claude mcp add blender -- python3 "$(git rev-parse --show-toplevel)/.claude/scripts/blender-mcp-bridge.py"
```

Blender's own add-on runs a raw TCP socket on `localhost:9876` speaking null-byte-delimited JSON —
one request type, nothing else:

```
-> {"type":"execute","code":"<python>","strict_json":true}\0
<- {"status":"ok","result":{...},"stdout":"...","stderr":"..."}\0
```

The executed code **must** assign a JSON-serializable `dict` to a global named `result`; anything else
is returned as an error telling you so. `.claude/scripts/blender-mcp-bridge.py` is the stdio MCP server
that translates this into `mcp__blender__*` tools.

**GOTCHA:** `uvx blender-mcp` is the bridge for **`ahujasid/blender-mcp`** — a *different*, third-party
add-on that also binds 9876 but speaks a command vocabulary (`get_scene_info`, `execute_blender_code`, …)
the official add-on has never heard of. Almost every Blender skill published online targets that one.
Pointing it at the official add-on fails on the first call, and the error looks like a connection problem
rather than a protocol mismatch. Check which add-on is enabled before believing any external skill.

---

### Card 2: `SystemExit` Kills Blender — Never Bail Out of Executed Code That Way

**WHEN:** Writing Python for `blender_execute`, or any code that needs an early exit.

**WRONG:**
```python
if not targets:
    result = {"status": "error", "message": "nothing to export"}
    raise SystemExit          # terminates the Blender PROCESS
```

**RIGHT:**
```python
def run():
    if not targets:
        return {"status": "error", "message": "nothing to export"}
    ...
    return {"status": "ok", ...}

result = run()                # plain returns, one assignment at the end
```

**GOTCHA:** Measured 2026-08-22 — this closed Blender outright, taking the open `.blend` with it. The
add-on wraps `exec()` in `except Exception`; `SystemExit` derives from `BaseException`, so it escapes the
handler, unwinds through the timer callback, and ends the process. The add-on's own `weak_sandbox.py`
patches `sys.exit` to raise instead — but it does **not** touch the `SystemExit` class, so `raise SystemExit`
walks straight through that protection. `blender_execute` in the bridge refuses code containing
`SystemExit`, `os._exit`, `bpy.ops.wm.quit_blender`, or `bpy.app.quit` before the bytes reach the socket.
That refusal is the only thing standing between an early-return habit and a lost `.blend`.

---

### Card 3: Read Before You Write — `blender_scene_info` First, Every Time

**WHEN:** Starting any task against an already-open `.blend` you did not author in this session.

**WRONG:** Going straight to `blender_export_fbx`, or straight to modelling, on the assumption that a
file which *looks* fine in the viewport is import-ready.

**RIGHT:** `mcp__blender__blender_scene_info` first. It is read-only and reports the three things that
decide whether the export is usable: `unit_scale_length`, per-object `scale`, and per-mesh `uv_layers`.

**GOTCHA:** Measured on a real prototype kit: **110 of 111 meshes had no UV layer.** Nothing in Blender's
viewport says so, and Unity raises no error on import — every textured material simply renders untextured.
This is the class of defect that is invisible to every static check in this repo (no content hook can read
a `.fbx`), so the read step is not optional politeness, it is the only detection there is. The counterpart is
Card 5a: even a mesh that passes every pre-flight check can still import with a broken root transform,
which is why the export contract is pinned by a real Unity measurement and not by the flag docs.

---

### Card 4: FBX, Not glTF — Because Unity Imports FBX With No Package

**WHEN:** Choosing the export format for a mesh headed into `Assets/`.

**RIGHT:** `.fbx`, via `mcp__blender__blender_export_fbx`.

**GOTCHA:** glTF is the cleaner format and Blender's glTF 2.0 exporter handles the Z-up → Y-up conversion
more predictably than FBX does — but Unity has **no built-in `.glb` importer**. Using glTF means adding
glTFast or UnityGLTF, which is a Required Stack change (see `CLAUDE.md` → Required Stack), and this
template does not carry one. FBX imports natively with zero dependency, and its one real trap — the
scale factor — is closed by fixed flags (below), not by hope. Do not "upgrade" this to glTF without
first taking the Required Stack decision to the human.

---

### Card 5: Export Flags Are Fixed — Do Not Re-Derive Them Per Asset

**WHEN:** Exporting, or tempted to call `bpy.ops.export_scene.fbx` by hand through `blender_execute`.

**RIGHT:** Use `blender_export_fbx`. It hardcodes the pairing that makes Blender metres and Unity units
agree, and refuses the write when a pre-flight check fails:

| Flag | Value | Why |
|---|---|---|
| `apply_unit_scale` + `apply_scale_options` | `True` + `FBX_SCALE_UNITS` | 1 Blender metre == 1 Unity unit **with `rootScale=(1,1,1)`**. `FBX_SCALE_NONE` also lands the right world size — but via a `scale=100` root (Card 5a) |
| `global_scale` | `1.0` | any other value re-opens the same bug |
| `axis_forward` / `axis_up` | `-Z` / `Y` | Blender Z-up → Unity Y-up |
| `bake_space_transform` | `True` for static, forced `False` when an ARMATURE is in the selection | `True` bakes the axis conversion into the vertices, so the Unity root stays unrotated (Card 5a). Unsafe for skinned content, hence the automatic downgrade |
| `use_tspace` | `True` | tangents, required by any normal-mapped material |
| `add_leaf_bones` | `False` | leaf bones show up as junk bones in Unity's rig |
| `mesh_smooth_type` | `FACE` | avoids Unity's smoothing-group import warnings |

Pre-flight refusals, each tied to a failure that is **silent** on the Unity side:
`unit_scale_length != 1.0` (every mesh off by that factor) · non-uniform object scale (skewed normals,
unrecoverable post-import) · a mesh with no UV layer (Card 3).

**GOTCHA:** `strict=false` exports anyway and still reports the problems — use it only when the human has
seen the problem list and decided to ship it, never to make a red result go away. A hand-rolled
`bpy.ops.export_scene.fbx` through `blender_execute` skips every pre-flight check at once; that is the
same failure shape as writing a `.cs` through Bash to dodge the content hooks (`CLAUDE.md` → Never route
around a blocking hook).

---

### Card 5a: A Correct World Size Does Not Mean a Correct Import

**WHEN:** Reviewing an imported mesh, or tempted to change `apply_scale_options` / `bake_space_transform`.

**WRONG — all four `apply_scale_options` values pass a world-size check:**
```
FBX_SCALE_NONE    local=(0.010,0.020,0.040) rootScale=(100,100,100) rootEuler=(270.020,0,0) WORLD=(1,4,2)
FBX_SCALE_CUSTOM  local=(0.010,0.020,0.040) rootScale=(100,100,100) rootEuler=(270.020,0,0) WORLD=(1,4,2)
FBX_SCALE_ALL     local=(1.000,2.000,4.000) rootScale=(1,1,1)       rootEuler=(270.020,0,0) WORLD=(1,4,2)
FBX_SCALE_UNITS   local=(1.000,2.000,4.000) rootScale=(1,1,1)       rootEuler=(270.020,0,0) WORLD=(1,4,2)
```

**RIGHT — `FBX_SCALE_UNITS` + `bake_space_transform=True`:**
```
                  local=(1.000,4.000,2.000) rootScale=(1,1,1)       rootEuler=(0,0,0)       WORLD=(1,4,2)
```

Measured 2026-08-22, Unity **6000.3.8f1**, batchmode, throwaway project. Source: a Blender box of
X=1 m, Y=2 m, Z=4 m with object scale `(1,1,1)` — deliberately distinct per axis, so a swapped axis shows
up as `(1,2,4)` instead of `(1,4,2)` and a scale error shows up as ×100.

**Why the first two rows are defects even though the size is right.** A `scale=100` prefab root is not
cosmetic: colliders scale with it (a `SphereCollider` inherits the factor and physics queries go wrong),
child local scale math is off by 100, and any script assigning `localScale` fights the import. A
`270.020°` root rotation is worse than merely rotated — it is not even `270.000`, so the mesh arrives
very slightly skewed and every child placed under it inherits that error.

**Why `FBX_SCALE_UNITS` over `FBX_SCALE_ALL`.** Measurably identical here, because `global_scale` is
pinned to `1.0`. They diverge only if someone changes it: `UNITS` then puts the custom factor on the
**object transform** (visible in the Inspector, debuggable), `ALL` folds it into the **FBX header scale**
(invisible, and re-opens exactly the ×100 class of bug). Prefer the failure you can see.

**GOTCHA:** Unity's own `ModelImporter.bakeAxisConversion = true` does **not** fix the rotation — measured,
it turns `270.020°` into `89.980°`. The conversion has to be baked on the **Blender** side. So do not
"solve" a rotated root with an `AssetPostprocessor`; re-export instead. And note what this Card proves
about test design: a check that only asserts world bounds passes all four variants, including the two
broken ones. Assert `rootScale` and `rootEuler` too, or the test is decoration.

**Scope of the 270.020° figure — do not generalise it.** Every number above was measured on a **plain,
unrigged mesh**. Adding an ARMATURE changes the answer: with `bake_space_transform=False` a skinned mesh
imports with `rootEuler=(0,0,0)` anyway, because Unity resolves the conversion itself once a skeleton is
present. This file asserted the opposite until the probe harness measured it. Reproduce any of this with
`.claude/tests/blender-fbx-probe/run-probe.sh`; extending a measured number to a case you did not run is
how the wrong claim got here in the first place.

---

### Card 6: The Bridge Never Saves the `.blend`

**WHEN:** Any session that touches a file an artist has open.

**GOTCHA:** `blender_export_fbx` restores the artist's selection and active object when it finishes, and
no tool in the bridge calls `bpy.ops.wm.save_mainfile`. Keep it that way: an agent silently saving over
someone's work-in-progress is unrecoverable, and `blender_scene_info` reports `is_dirty` precisely so a
human can be asked first. Never add an auto-save. Also never assume the `.blend` lives in this repo —
measured, it sat in a completely separate project folder, so writing near it is a cross-repo edit.

---

## Setup

1. **Blender side** — Preferences → Add-ons → search `MCP` (Blender Lab, built in on 5.1+). Enable it,
   check **Auto Start**, leave Host/Port at `localhost` / `9876`.
2. **Claude Code side** — register the bridge once:
   ```bash
   claude mcp add blender -- python3 "$(git rev-parse --show-toplevel)/.claude/scripts/blender-mcp-bridge.py"
   ```
   Needs the `mcp` Python package (`python3 -c "import mcp"`). Restart the session; the tools appear as
   `mcp__blender__blender_scene_info`, `..._export_fbx`, `..._execute`.
3. **Verify** without a restart — the bridge is importable and its transport is one function:
   ```bash
   python3 -c "
   import importlib.util as u
   s=u.spec_from_file_location('b','.claude/scripts/blender-mcp-bridge.py'); m=u.module_from_spec(s); s.loader.exec_module(m)
   print(m._call('import bpy; result={\"v\": bpy.app.version_string}'))"
   ```

Env overrides: `BLENDER_MCP_HOST`, `BLENDER_MCP_PORT`, `BLENDER_MCP_TIMEOUT`.

Headless is supported by the add-on and needs no bridge change — the socket is the same:
`blender --background file.blend --command blender_mcp`. Deferred (long-running) responses are **not**
available in background mode; each request must complete before returning.

## Workflow

```
blender_scene_info          → read units, scale, UV, tri count. Never skip.
   ↓ problems?              → fix in Blender (blender_execute) or hand back to the artist
blender_export_fbx          → Assets/_GameFolders/Arts/Models/<Domain>/<Name>.fbx
   ↓
Unity import settings       → materialImportMode = None; the project assigns the material (see below)
   ↓
prefab                      → logic on root, visuals on a Body child (rules/unity-prefabs.md)
```

### The importer cannot give you a URP material — measured, not predicted

`materialImportMode` defaults to `ImportViaMaterialDescription`, and an import measured under Unity
2022.3.62f2 produced `material count 1 → 'Default-Material' shader='Standard'`. That is not a
misconfiguration to correct: **FBX has no concept of a shader.** The format carries a Lambert/Phong
description, so whatever the Blender material was — Principled BSDF, a node graph, anything — the
importer can only map it onto a built-in shader. There is no export setting that makes a URP or a
third-party material come out the other side. In URP a Standard material renders magenta.

So set `materialImportMode = None` and let the project assign the material. Two consequences follow:

- **The URP Render Pipeline Converter is the wrong tool here.** It converts Standard →
  `Universal Render Pipeline/Lit`, which is still not the material a project using a third-party
  toon/stylised shader wants — the manual assignment happens either way, so the convert step only adds
  one. It is a one-off migration tool for an existing project, not a per-import step.
- **Leaving the default on accumulates orphans.** Every import mints another `Default-Material`
  reference that nobody assigned and nobody deletes, and each one is a future magenta render.

Where the material comes from is a project question, not a Blender one — a palette/catalog asset if the
domain has one, otherwise `Arts/Materials/<Domain>/` per `rules/performance.md`.

The FBX lands as an asset, not a prefab. Turning it into one is ordinary Unity work and follows
`rules/unity-prefabs.md` — Logic/Visual separation, domain folder, and Card 5 (extract before the
second copy) all apply unchanged. Model files go to `Arts/Models/<Domain>/`, mirroring the
`Arts/Materials/<Domain>/` convention in `rules/performance.md`.

## Portability to Another Project

Nothing here is bound to this repo's contents — the bridge only needs Python + the `mcp` package, and
the skill only references `rules/` files every project built from this template already has. To move it:
copy `.claude/scripts/blender-mcp-bridge.py` and this folder, then run the `claude mcp add` line from
step 2. The `$(git rev-parse --show-toplevel)` in that command resolves per-repo, so the same line works
verbatim in the new project.

## Known Gaps — Deliberately Not Built

- **No mesh generation from a reference image.** `image-to-3d` style flows (Meshy API) are a real
  capability but a paid external dependency, and their default `target_polycount` (~30k) and topology are
  tuned for viewers, not game budgets. Evaluate before adopting; do not assume the output is game-ready.
- **No hook can verify an exported `.fbx`.** Content hooks fire on `Edit|Write` and read text; a mesh is
  binary. The pre-flight checks inside `blender_export_fbx` are the entire enforcement surface. This is
  why the checks live in the tool rather than in a rule file — a Card cannot refuse to write a mesh.
- **Rig export is only shallowly verified.** An ARMATURE forces `bake_space_transform=False`, and a
  **minimal single-bone auto-weighted rig** imports clean anyway — `rootScale=(1,1,1)`,
  `rootEuler=(0,0,0)`, 1 bone, measured by the `skinned` case in `.claude/tests/blender-fbx-probe/`.
  That was a surprise: this file previously predicted a ~270.02° rotation there, by generalising the
  plain-mesh result of Card 5a, and the harness's first run disproved it. A **real multi-bone animated
  character** — multiple influences per vertex, non-identity rest pose, actual animation clips — is
  still unverified, and the export says so in its `problems` list rather than going quiet.
- **The 2022.3 measurements above are one-off, with no regression coverage.**
  `.claude/tests/blender-fbx-probe/` drives Unity 6; the material and transform figures cited above were
  measured by hand against 2022.3.62f2 in a scratchpad and nothing re-runs them. A future change to the
  export contract will be checked against Unity 6 only. Adding 2022.3 as a second probe target is the
  fix; until then, do not read a green probe run as evidence about 2022.3.
- **No Unity-side import-settings automation.** `audio-clip-agent` is the shape this would take
  (a temporary Editor script applying settings in bulk) if model import settings ever need it.
