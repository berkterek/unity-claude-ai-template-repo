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

- Disable `Raycast Target` on non-interactive elements
- Use `CanvasGroup.alpha = 0` + `blocksRaycasts = false` instead of `SetActive(false)` to avoid rebuild on re-enable
- Pool UI elements — don't Instantiate/Destroy them

### Overdraw

- Minimize overlapping transparent sprites
- Use opaque sprites where possible (no alpha)
- Check with Scene View → Overdraw visualization mode

---

## Debug

- No `Debug.Log` in production — use `[Conditional("UNITY_EDITOR")]` wrapper
- Strip debug code with scripting defines, not runtime checks
