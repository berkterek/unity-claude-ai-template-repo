# ProBuilder — VContainer / Prefab / Scene Integration

## Scene Hierarchy Placement

ProBuilder meshes are environment geometry — they go under `[Environment]` in the scene hierarchy.

```
Scene
├── [Setup]
├── [Services]
├── [UI]
├── [Environment]          ← ProBuilder meshes here
│   ├── Room.prefab        ← baked or live ProBuilder mesh
│   ├── Platform.prefab
│   └── Corridor.prefab
├── [Characters]
└── [VFX]
```

ProBuilder meshes with logic (e.g. a moving platform with a `PlatformController`) still go to `[Environment]` — the classification is by domain, not by the presence of logic scripts. Only characters/NPCs go to `[Characters]`.

---

## Prefab Workflow for ProBuilder Geometry

### During Prototyping (Live ProBuilder Mesh)

Keep the `ProBuilderMesh` component for fast iteration:

```
Platform.prefab                    ← Root: logic scripts (PlatformController, Collider, Rigidbody)
└── Body/                          ← Child: ProBuilderMesh + MeshRenderer + MeshFilter
```

- Root holds Collider, Rigidbody, and any injected MonoBehaviours
- `Body/` holds the ProBuilder mesh — logic/visual separation applies even during prototyping
- **Never put ProBuilderMesh on the root GO** — it makes the root a visual object

### Before Shipping (Baked Mesh)

1. Bake: **Tools → ProBuilder → Export → Export Asset** → save to `_GameFolders/Arts/Meshes/<Domain>/`
2. Remove the `ProBuilderMesh` component
3. The prefab becomes a standard MeshFilter + MeshRenderer prefab
4. Assign a URP material from `_GameFolders/Arts/Materials/<Domain>/`

```
Platform.prefab                    ← Root: logic scripts only
└── Body/                          ← Child: MeshFilter + MeshRenderer (baked mesh)
```

---

## Material Rules

ProBuilder generates Built-in (Standard) shader materials by default. This project uses URP — replace them immediately.

```
_GameFolders/Arts/Materials/
├── Environment/
│   ├── Floor_Concrete.mat         ← URP/Lit
│   ├── Wall_Brick.mat             ← URP/Lit
│   └── Ceiling_Plain.mat          ← URP/Simple Lit
└── Props/
    └── Crate_Wood.mat             ← URP/Lit
```

**Steps after creating a ProBuilder mesh:**
1. Create a new material in `_GameFolders/Arts/Materials/<Domain>/`
2. Set shader to `Universal Render Pipeline/Lit`
3. Assign the material via `pbMesh.SetMaterial(pbMesh.faces, myMaterial)` or in the Inspector
4. Do NOT save the auto-generated ProBuilder material — delete it

---

## VContainer Integration

ProBuilder meshes do not interact with VContainer directly. If a ProBuilder-based mesh has associated game logic (e.g. a destructible wall service), follow standard VContainer patterns:

```csharp
// DestructibleWallService.cs — pure C# service, no ProBuilder dependency
public sealed class DestructibleWallService : IDestructibleWallService
{
    private readonly IEventBus _eventBus;

    public DestructibleWallService(IEventBus eventBus) => _eventBus = eventBus;

    public void Destroy(int wallId)
    {
        // Logic here — no ProBuilder API in the service
        _eventBus.Publish(new WallDestroyedEvent(wallId));
    }
}

// DestructibleWallProvider.cs — MonoBehaviour on the prefab root
public sealed class DestructibleWallProvider : MonoBehaviour, IDestructibleWallProvider
{
    [SerializeField] private MeshRenderer _body;   // Body/ child

    private IDestructibleWallService _service;

    [Inject]
    public void Construct(IDestructibleWallService service) => _service = service;

    public void TriggerDestroy(int wallId)
    {
        _body.enabled = false;      // visual off — Unity API stays in provider
        _service.Destroy(wallId);
    }
}
```

The Provider handles the Unity API (showing/hiding the mesh). The Service contains the business logic. ProBuilder API is only used in Editor scripts or during mesh authoring — never in runtime services.

---

## Level Design Workflow (Editor)

Standard greybox workflow with this project:

1. **Block out with ProBuilder shapes** — `ShapeGenerator.Generate*` or Tools → ProBuilder → New Shape
2. **Parent under `[Environment]`** as prefab instances
3. **Use ProGrids** (companion package `com.unity.progrids`) for snapping
4. **Assign placeholder URP materials** from `Arts/Materials/Environment/`
5. **Test gameplay feel** — iterate mesh shapes without leaving Unity
6. **Bake and hand off** — export `.asset` meshes, remove ProBuilder components, hand to artist for final texture

---

## Compliance Notes

| Issue | Severity | Fix |
|-------|----------|-----|
| ProBuilder mesh on Root GO (not Body/) | MUST-FIX | Move mesh to `Body/` child |
| Auto-generated Built-in material still assigned | MUST-FIX | Replace with URP material in `Arts/Materials/` |
| `ProBuilderMesh` component present in release build | MUST-FIX | Bake and strip before build |
| `new GameObject()` in Editor script creating mesh | WARNING | OK in Editor-only scripts; never in runtime code |
| Mesh .asset saved inside Prefabs/ folder | SHOULD-FIX | Move to `Arts/Meshes/<Domain>/` |
