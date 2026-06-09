# Performance Rules

## The Golden Rule

**Zero heap allocations in Update, FixedUpdate, and LateUpdate.**

Every allocation triggers GC, which causes frame spikes. Profile with Unity Profiler's GC Alloc column.

---

## Component References — Inspector Assignment First

Components on the same GameObject or its children must be assigned via `[SerializeField]` in the Inspector — **not** fetched with `GetComponent` at runtime, even in `Awake`.

```csharp
// BAD — runtime cost, hides dependency
private Rigidbody _rigidbody;
private Animator _animator;

private void Awake()
{
    _rigidbody = GetComponent<Rigidbody>();
    _animator  = GetComponentInChildren<Animator>();
}

// GOOD — zero runtime cost, dependency visible in Inspector
[SerializeField] private Rigidbody _rigidbody;
[SerializeField] private Animator  _animator;
```

Drag-drop the reference in the Inspector (or assign in a Prefab). No Awake code needed.

**When `GetComponent` in Awake IS acceptable:**
- The component is added dynamically at runtime (not present at edit time)
- The reference comes from a spawned/instantiated object you don't own

**Same prefab hierarchy — always `[SerializeField]`, never VContainer:**
Any component on the same GameObject, a child, or a grandchild within the same prefab does **not** need VContainer injection. Assign via `[SerializeField]` and drag-drop in the Inspector. VContainer is only for cross-prefab or cross-module dependencies.

**`transform` — serialize like any other component:**

```csharp
// BAD — bare transform property on hot path
private void Update() => transform.position += Vector3.forward;

// GOOD — [SerializeField], drag-drop the GameObject's Transform in Inspector
[SerializeField] private Transform _transform;
private void Update() => _transform.position += Vector3.forward;
```

`Transform` is a `UnityEngine.Object` — it serializes normally. Drag the GameObject onto the `_transform` field in the Inspector.

**Other calls — NEVER in Update/FixedUpdate/LateUpdate/Tick:**
- `Camera.main` (calls FindObjectOfType internally) → `[SerializeField] private Camera _camera`
- `Animator.StringToHash()` / `Shader.PropertyToID()` → `static readonly int` (PascalCase, cached at class level)

---

## Avoid Allocations

| Allocates | Use Instead |
|-----------|------------|
| `new List<T>()` in Update | Pre-allocate, reuse with `.Clear()` |
| `new WaitForSeconds(n)` | Cache as field |
| `string + string` | `StringBuilder` or `string.Format` |
| `foreach` on non-List | `for` loop with index |
| LINQ (`.Where`, `.Select`, `.Any`) | Manual loops |
| `FindObjectOfType` | Cached reference or injection |
| `tag == "tag"` | `CompareTag("tag")` |
| `SendMessage` / `BroadcastMessage` | Direct reference or IEventBus |
| `Physics.RaycastAll` | `Physics.RaycastNonAlloc` with pre-allocated array |

---

## Physics

- Use non-allocating variants: `OverlapSphereNonAlloc`, `RaycastNonAlloc`, `SphereCastNonAlloc`
- Pre-allocate result arrays: `private RaycastHit[] _hitBuffer = new RaycastHit[16]`
- Physics queries in `FixedUpdate`, not `Update`

---

## Object Lifecycle

- Pool frequently instantiated objects — `ObjectPool<T>` or custom pool
- `SetActive(false)` to return to pool, not `Destroy`
- `DontDestroyOnLoad` sparingly — prefer bootstrapper scene pattern

---

## Material Folder Structure (NON-NEGOTIABLE)

All material assets live under `Arts/Materials/`, grouped by domain — **never** inside `Prefabs/` or alongside prefab assets.

```
Arts/
├── Materials/
│   ├── Items/          ← Apple, Grape, Orange, Watermelon materials
│   ├── Environment/    ← Ground, Sky, Platform materials
│   ├── Characters/     ← Player, Enemy materials
│   ├── VFX/            ← Particle, Effect materials
│   └── UI/             ← UI-specific materials (rare)
├── Shaders/            ← all .shader (HLSL) and .shadergraph files
└── Textures/           ← textures by domain
```

- One subfolder per domain — mirrors `_GameFolders/Prefabs/<Domain>/` naming
- Material files (.mat) are never placed inside `Prefabs/` folders
- Shader files (.shader / .shadergraph) live in `_GameFolders/Arts/Shaders/` — never alongside materials or prefabs
- Textures that belong to a material live in `Arts/Textures/<Domain>/`

## URP Shader Rule (NON-NEGOTIABLE)

This project uses **Universal Render Pipeline (URP)**. All materials must use URP shaders — never Built-in (Standard) shaders.

| Correct | Forbidden |
|---------|-----------|
| `Universal Render Pipeline/Lit` | `Standard` |
| `Universal Render Pipeline/Simple Lit` | `Legacy Shaders/...` |
| `Universal Render Pipeline/Unlit` | `Particles/Standard Surface` |
| `Universal Render Pipeline/Particles/Lit` | `Mobile/...` (Built-in) |

**Why:** Built-in Standard shader does not render correctly in URP — objects appear magenta/pink or use incorrect lighting. Every new material must be created with a URP shader from the start. Never convert a Built-in material to URP with the migration tool unless it is an existing asset — new materials must start as URP.

When creating materials via MCP or Editor:
1. Create the material asset in `Arts/Materials/<Domain>/`
2. Set shader to `Universal Render Pipeline/Lit` (or `Simple Lit` for mobile performance)
3. Assign the material to the prefab — **do not save the .mat file inside the Prefabs folder**

---

## Rendering & Draw Calls

Fewer draw calls = better performance. Every unique Material + Mesh combination = 1 draw call.

### Material Sharing

```csharp
// BAD — clones the material and breaks batching
renderer.material.color = Color.red;

// GOOD — shared material + MaterialPropertyBlock
private static readonly int ColorId = Shader.PropertyToID("_Color");
private MaterialPropertyBlock _propBlock;

private void Awake() => _propBlock = new MaterialPropertyBlock();

public void SetColor(Color color)
{
    _propBlock.SetColor(ColorId, color);
    _renderer.SetPropertyBlock(_propBlock);
}
```

- NEVER access `renderer.material` — it clones the material
- Use `renderer.sharedMaterial` for read-only access
- Use `MaterialPropertyBlock` for per-instance changes

### Batching

- **URP**: Ensure SRP Batcher is enabled (Project Settings → Graphics)
- **3D repeated meshes**: Enable GPU Instancing on materials
- **Static objects**: Mark as "Batching Static"
- **Dynamic objects**: Keep same material + mesh (< 300 vertices) for dynamic batching

### UI Canvas Optimization

Split Canvases by update frequency — a single changing element rebuilds the entire Canvas mesh:

```
Canvas_HUD         ← updates every frame (health, timer, score)
Canvas_Static      ← rarely changes (backgrounds, static labels)
Canvas_Popups      ← dynamic elements (damage numbers, notifications)
```

- Use `CanvasGroup.alpha = 0` + `blocksRaycasts = false` instead of `SetActive(false)` to avoid rebuild on re-enable
- Pool UI elements — don't Instantiate/Destroy them

### RaycastTarget Rules (NON-NEGOTIABLE)

Every `Image` and `TextMeshProUGUI` component must have `Raycast Target` disabled unless it explicitly needs to receive pointer events.

**`TextMeshProUGUI` — `true` only when the same GameObject or its parent has a `Button` component, otherwise always `false`.**

**`Image` — `true` only when:**
- The same GameObject has a `Button` component, OR
- The Image is intentionally used as a full-screen raycast blocker (e.g. modal overlay, `BlockerPanel`)

**All other `Image` components — `false`.**

```
// Inspector checklist when adding a UI prefab:
✓ TextMeshProUGUI → Raycast Target: OFF
✓ Image (decorative, background, icon) → Raycast Target: OFF
✓ Image + Button → Raycast Target: ON
✓ Image (modal blocker) → Raycast Target: ON, document why with a comment on the GO name
```

**Why:** Every enabled `Raycast Target` is tested on every pointer event. In a complex UI with 50+ elements, this adds up to hundreds of unnecessary hit-tests per frame. Disabling on non-interactive elements is free performance.

### Overdraw

- Minimize overlapping transparent sprites
- Use opaque sprites where possible (no alpha)
- Check with Scene View → Overdraw visualization mode

---

## Debug

- No `Debug.Log` in production — use `[Conditional("UNITY_EDITOR")]` wrapper
- Strip debug code with scripting defines, not runtime checks
