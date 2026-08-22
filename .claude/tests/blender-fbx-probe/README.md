# Blender → FBX → Unity Probe Harness

Measures whether the export contract in `.claude/scripts/blender-mcp-bridge.py` actually lands
correctly in a real Unity Editor. Third test layer in this repo, and the first one that opens Unity.

## The gap this covers

| Layer | Covered by | Measures | Deterministic? |
|---|---|---|---|
| A hook's exit code on planted input | `.claude/hooks/tests/` — 36 bats suites, 417 tests | exit code | yes |
| A reviewer prompt's effect on a verdict | `.claude/tests/reviewer-fixtures/` | which criteria fire on planted defects | no — costs an agent |
| A pipeline's gate order and state-file lifecycle | `.claude/tests/pipeline-dry-run/` | gate sequence, state files | no — costs an agent |
| **A binary asset's geometry, transform, materials and bones after a real Unity import** | **this harness** | world size, root scale, root euler, mesh/material/bone counts | **yes** |

Unlike the two agent-driven harnesses this one **is** deterministic and CI-able in principle — it is
plain `bpy` + `Unity -batchmode`, no model in the loop. What stops it being CI today is only its two
external prerequisites: a running Blender with the MCP add-on, and a licensed Unity Editor.

Still covered by nothing: PlayMode tests, prefab/scene authoring, and `TD-COMPILE` against real
project code.

## Why it exists

Measured 2026-08-22. The export originally shipped with `apply_scale_options="FBX_SCALE_NONE"` and a
verification that asserted **world bounds only**. All four `apply_scale_options` values pass that
check — including the two that import with `rootScale=(100,100,100)` and a `270.020°` root rotation.
A size-only assertion is decoration. Full evidence table: `SKILL.md` → Card 5a.

Then, on its very first run, this harness disproved a claim in `SKILL.md` itself: the `skinned` case
was written expecting a `270.02°` rotation, generalising the plain-mesh result, and returned
`(0,0,0)`. Both the skill and the bridge's warning text were corrected to match the measurement.
That is the harness paying for itself twice before being committed.

## How to run

```bash
.claude/tests/blender-fbx-probe/run-probe.sh              # all cases, cleans up, exit 0 = green
.claude/tests/blender-fbx-probe/run-probe.sh --case skinned --keep
.claude/tests/blender-fbx-probe/run-probe.sh --help
```

**Prerequisites.** Blender running with the official MCP add-on, on an **empty unsaved file** — the
harness clears the scene and refuses to run (exit 2) when a file is open or dirty, so it can never
destroy an artist's work. A Unity 6 Editor under `/Applications/Unity/Hub/Editor/6000.*`, or
`--unity PATH`. Nothing is ever saved to the `.blend`.

Exit `0` all assertions passed · `1` at least one FAIL · `2` could not run.

## Cases and what each would catch

| Case | Asserts | The defect it catches |
|---|---|---|
| `static_box` | world `(1,4,2)`, scale `1`, euler `0` | wrong `apply_scale_options` (scale-100 root) or wrong axis flags |
| `parented` | child world Y `== 3.0` | a child offset converted with a different basis than its vertices — mesh right, hierarchy wrong |
| `multi_mesh` | 3 MeshFilters, span `5m` | objects silently dropped, or merged into one mesh |
| `two_materials` | 2 distinct materials | a material slot lost — half the model renders with the wrong material |
| `skinned` | 1 bone, scale `1`, euler `0` | the rig path drifting away from the measured-clean baseline |

The source box is deliberately **1 × 2 × 4 m** — distinct on every axis, so a swapped axis appears as
`(1,2,4)` instead of `(1,4,2)` and a unit error appears as ×100. A cube would hide both.

`material_count: 0` accepts `<= 1` on the Unity side: Unity substitutes a default material when none
was authored, so demanding exactly 0 would fail for a reason that is not a defect.

## Why a generator, not committed fixtures

The inputs are `.fbx` meshes and the harness is a Unity project. A committed `.fbx` is an unreviewable
binary blob — a diff cannot show that a vertex moved — and a committed Unity project is ~13 MB of
`Library/` per run. Both are rebuilt from `bpy` primitives on every run, so what is under test is
always the **current** export contract rather than a snapshot of an older one. Same reasoning as the
two sibling harnesses, for a different reason each time: they generate because committing their input
would trip a content hook or strand a `gate-cleared`; this one generates because its input is binary.

## Extending it

Add a tuple to `CASES` in `build-cases.py`: a name, the `bpy` code that builds it (it must set
`result = {"objects": [...]}`), and the expectations dict. The Unity side is generic — it reads
`cases.json` and needs no edit unless you add a new expectation key. Keys understood today are listed
in the comment above `CASES`.

**When a case fails, do not adjust the expectation to make it green.** That is what the `skinned` case
was almost used for. Establish which side is wrong first: the expectation may be an untested
generalisation (it was, that time), or the export contract may have genuinely regressed. Record which,
in the case's own `note`.
