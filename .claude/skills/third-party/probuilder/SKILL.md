---
name: probuilder
description: "Unity ProBuilder in-editor mesh modeling — create/edit 3D geometry, UV mapping, poly shapes, Boolean ops, material assignment. Use for level design and rapid prototyping inside Unity Editor."
globs: ["**/ProBuilder*", "**/*ProBuilder*.cs", "**/PolyShape*.cs", "**/pb_Object*.cs"]
---

# ProBuilder — In-Editor 3D Modeling

ProBuilder (`com.unity.probuilder`) is Unity's built-in level design and mesh editing tool. It lets you create, edit, and texture 3D geometry directly inside the Unity Editor without leaving to external DCC tools.

## When to Use

- Blocking out levels (greybox / whitebox)
- Creating simple architectural meshes (walls, floors, ramps, platforms)
- Rapid prototype scenes before handing off to artists
- Low-poly stylized geometry that ships as-is

See → [`api.md`](api.md) for full API reference.
See → [`integration.md`](integration.md) for VContainer / prefab workflow and scene hierarchy placement.

## Key APIs at a Glance

```csharp
using UnityEngine.ProBuilder;
using UnityEngine.ProBuilder.MeshOperations;

// Create a ProBuilder mesh shape
var go    = ShapeGenerator.GenerateCube(PivotLocation.Center, Vector3.one);
var pbMesh = go.GetComponent<ProBuilderMesh>();

// Extrude faces
var faces = pbMesh.faces;
pbMesh.Extrude(faces, ExtrudeMethod.FaceNormal, 1f);
pbMesh.ToMesh();
pbMesh.Refresh();

// Subdivide
SubdivideFaces.Subdivide(pbMesh, pbMesh.faces);
pbMesh.ToMesh();
pbMesh.Refresh();

// Bake to regular Mesh (removes ProBuilder dependency at runtime)
var meshFilter = go.GetComponent<MeshFilter>();
var bakedMesh  = pbMesh.GetComponent<MeshFilter>().sharedMesh;
```

## Critical Rules

1. **Always call `ToMesh()` + `Refresh()` after any mesh edit** — edits are not applied until these are called.
2. **Bake ProBuilder meshes before shipping** — never reference ProBuilder API in runtime game code.
3. **Save meshes as assets after baking** — raw ProBuilder meshes are scene-embedded and bloat build size.
4. **Logic/Visual separation still applies** — ProBuilder mesh goes on `Body/` child, not the root prefab GO.
5. **Materials → `Arts/Materials/<Domain>/`** — do not leave ProBuilder-generated materials in the scene.
