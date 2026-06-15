# ProBuilder API Reference

## Package Info

| Field | Value |
|-------|-------|
| Package ID | `com.unity.probuilder` |
| Namespace | `UnityEngine.ProBuilder`, `UnityEngine.ProBuilder.MeshOperations` |
| Min Unity | Unity 2021.3 LTS |

---

## Shape Generation

ProBuilder provides shape generators for primitive geometry. All generators return a `GameObject` with a `ProBuilderMesh` component attached.

```csharp
using UnityEngine.ProBuilder;
using UnityEngine.ProBuilder.MeshOperations;

// Cube — size in world units
GameObject cube = ShapeGenerator.GenerateCube(PivotLocation.Center, new Vector3(2, 1, 4));

// Sphere
GameObject sphere = ShapeGenerator.GenerateSphere(
    PivotLocation.Center,
    radius: 1f,
    subdivisions: 2
);

// Cylinder
GameObject cylinder = ShapeGenerator.GenerateCylinder(
    PivotLocation.Center,
    subdivisions: 16,
    radius: 0.5f,
    height: 2f,
    heightCuts: 0
);

// Plane (flat grid)
GameObject plane = ShapeGenerator.GeneratePlane(
    PivotLocation.Center,
    width: 5f,
    height: 5f,
    widthSegments: 1,
    heightSegments: 1,
    axis: Axis.Up
);

// Staircase
GameObject stairs = ShapeGenerator.GenerateStair(
    PivotLocation.Center,
    size: new Vector3(2, 3, 4),
    steps: 6,
    buildSides: true
);

// Arch
GameObject arch = ShapeGenerator.GenerateArch(
    PivotLocation.Center,
    angle: 180f,
    radius: 1f,
    width: 0.5f,
    depth: 1f,
    radialCuts: 6,
    insideFaces: true,
    outsideFaces: true,
    frontFaces: true,
    backFaces: true
);

// Cone
GameObject cone = ShapeGenerator.GenerateCone(
    PivotLocation.Center,
    radius: 0.5f,
    height: 2f,
    subdivisions: 12
);
```

**After generating a shape, no additional `ToMesh()` / `Refresh()` call is needed — generators return a ready mesh.**

---

## ProBuilderMesh Operations

After modifying vertices, faces, or edges, always call `ToMesh()` + `Refresh()` to apply changes.

```csharp
ProBuilderMesh pbMesh = go.GetComponent<ProBuilderMesh>();

// --- Face Extrusion ---
IList<Face> faces = pbMesh.faces;
pbMesh.Extrude(faces, ExtrudeMethod.FaceNormal, distance: 1f);
pbMesh.ToMesh();
pbMesh.Refresh();

// Extrude methods:
// ExtrudeMethod.FaceNormal   — each face extrudes along its own normal
// ExtrudeMethod.VertexNormal — smoother extrusion on curved surfaces
// ExtrudeMethod.IndividualFaces — each face extrudes independently

// --- Delete Faces ---
pbMesh.DeleteFaces(new[] { faces[0] });
pbMesh.ToMesh();
pbMesh.Refresh();

// --- Subdivide Faces ---
SubdivideFaces.Subdivide(pbMesh, pbMesh.faces);
pbMesh.ToMesh();
pbMesh.Refresh();

// --- Merge Objects ---
// Merges multiple ProBuilderMesh objects into one
ProBuilderMesh merged = CombineMeshes.Combine(new[] { meshA, meshB }, targetGO);
merged.ToMesh();
merged.Refresh();
```

---

## Face, Vertex, Edge Access

```csharp
ProBuilderMesh pbMesh = go.GetComponent<ProBuilderMesh>();

// Faces — IList<Face>
IList<Face> allFaces = pbMesh.faces;

// Vertices (positions in local space) — IList<Vertex>
IList<Vertex> vertices = pbMesh.GetVertices();
foreach (var v in vertices)
{
    Vector3 pos    = v.position;
    Vector3 normal = v.normal;
    Vector2 uv0    = v.uv0;
}

// Edges — IEnumerable<Edge>
foreach (Face face in allFaces)
{
    foreach (Edge edge in face.edges)
    {
        int indexA = edge.a;
        int indexB = edge.b;
    }
}

// Get indices (for manual mesh ops)
int[] triangleIndices = pbMesh.GetIndices(faces);
```

---

## UV Unwrapping

ProBuilder's UV editor is primarily used interactively, but basic UV auto-unwrap can be triggered via API:

```csharp
using UnityEngine.ProBuilder.MeshOperations;

// Auto UV — planar project from face normal
var uvUnwrap = new UnwrapParameters
{
    packMargin = 20f,
    angleError = 8f,
    areaError  = 15f,
    hardAngle  = 88f
};

AutoUnwrapSettings settings = AutoUnwrapSettings.defaultAutoUnwrapSettings;
pbMesh.SetTextureChannel(Channel.Channel0, new AutoUnwrapSettings());
pbMesh.ToMesh();
pbMesh.Refresh();

// Manual UV offset/rotation/scale per face
foreach (var face in pbMesh.faces)
{
    face.uv = new AutoUnwrapSettings
    {
        offset = new Vector2(0.5f, 0f),
        rotation = 90f,
        scale = Vector2.one * 2f
    };
}
pbMesh.ToMesh();
pbMesh.Refresh();
```

---

## Material Assignment

```csharp
using UnityEngine.ProBuilder;

ProBuilderMesh pbMesh = go.GetComponent<ProBuilderMesh>();

// Assign material to ALL faces
pbMesh.SetMaterial(pbMesh.faces, myMaterial);
pbMesh.ToMesh();
pbMesh.Refresh();

// Assign material to specific faces only
var targetFaces = new List<Face> { pbMesh.faces[0], pbMesh.faces[2] };
pbMesh.SetMaterial(targetFaces, wallMaterial);
pbMesh.ToMesh();
pbMesh.Refresh();
```

**Material files must be saved to `_GameFolders/Arts/Materials/<Domain>/` — not left as scene-embedded assets.**

---

## PolyShape (Draw Tool)

PolyShape lets you draw a 2D footprint and extrude it into a 3D mesh:

```csharp
using UnityEngine.ProBuilder;

// Create PolyShape component
var go        = new GameObject("Room");         // runtime: use Instantiate(_prefab) instead
var polyShape = go.AddComponent<PolyShape>();
var pbMesh    = go.AddComponent<ProBuilderMesh>();

// Define the 2D footprint (XZ plane)
polyShape.SetControlPoints(new List<Vector3>
{
    new Vector3(0,  0, 0),
    new Vector3(5,  0, 0),
    new Vector3(5,  0, 8),
    new Vector3(0,  0, 8)
});

polyShape.extrude = 3f;   // height
polyShape.CreateShapeFromPolygon();
pbMesh.ToMesh();
pbMesh.Refresh();
```

> PolyShape creation via `new GameObject()` is ONLY valid in Editor scripts. Runtime game code must instantiate from a prefab.

---

## Boolean Operations

Requires ProBuilder 5.0+ and the ProGrids-free workflow:

```csharp
using UnityEngine.ProBuilder.MeshOperations;

// Subtract meshB from meshA
ProBuilderMesh result = Boolean.Perform(
    BooleanOperation.Subtract,
    meshA,
    meshB
);
result.ToMesh();
result.Refresh();

// Union
ProBuilderMesh union = Boolean.Perform(BooleanOperation.Union, meshA, meshB);

// Intersect
ProBuilderMesh intersect = Boolean.Perform(BooleanOperation.Intersect, meshA, meshB);
```

Boolean operations are **Editor-only** — don't call them at runtime.

---

## Baking to Regular Mesh (Runtime-Safe)

ProBuilder meshes depend on the ProBuilder package. Before shipping, bake them to standard `Mesh` assets:

```csharp
// Editor script — bake and save as asset
using UnityEngine.ProBuilder;
using UnityEditor;

public static void BakeProBuilderMesh(ProBuilderMesh pbMesh, string savePath)
{
    // Strip ProBuilder components and keep the raw Mesh
    var mf    = pbMesh.GetComponent<MeshFilter>();
    var baked = Object.Instantiate(mf.sharedMesh);

    AssetDatabase.CreateAsset(baked, savePath);
    AssetDatabase.SaveAssets();

    // Replace ProBuilderMesh with standard MeshFilter + MeshRenderer
    Object.DestroyImmediate(pbMesh);
}
```

Or use the built-in menu: **Tools → ProBuilder → Export → Export Asset**.

**Rules:**
- Baked `.asset` mesh files go to `_GameFolders/Arts/Meshes/<Domain>/`
- After baking, the `ProBuilderMesh` component is removed — the GO becomes a regular prefab
- Baked prefab follows normal Logic/Visual separation (mesh on `Body/` child)

---

## Selecting Elements (Editor API)

For Editor tooling or custom Editor scripts that need to manipulate selection:

```csharp
using UnityEditor.ProBuilder;

// Get the current ProBuilder selection
MeshSelection selection = MeshSelection.activeMesh;

// Selected faces
IEnumerable<Face> selectedFaces = selection?.selectedFaces;

// Programmatically set selection
ProBuilderEditor.selectMode = SelectMode.Face;
```

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Mesh looks unchanged after edit | Always call `ToMesh()` + `Refresh()` |
| Pink materials in URP | ProBuilder uses Built-in shaders by default — assign URP materials manually |
| ProBuilder mesh visible in builds but modifiable | Bake to `.asset` before building |
| `new GameObject()` in runtime code | Instantiate from a prefab instead |
| ProBuilder components in final build | Use **Tools → ProBuilder → Strip ProBuilder Scripts** before build |
| UV coordinates wrong after extrusion | Call `Refresh(RefreshMask.UV)` explicitly if auto-refresh misses UVs |
