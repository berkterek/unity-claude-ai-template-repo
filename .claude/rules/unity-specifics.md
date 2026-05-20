# Unity-Specific Rules

## Editor vs Runtime

```csharp
// Runtime code (Assets/Scripts/) — NEVER use UnityEditor unguarded
#if UNITY_EDITOR
using UnityEditor;
#endif

private void OnValidate()
{
    #if UNITY_EDITOR
    EditorUtility.SetDirty(this);
    #endif
}
```

- Code in `Editor/` folder: editor-only, excluded from builds automatically
- Code outside `Editor/`: must guard any `UnityEditor` usage with `#if UNITY_EDITOR`
- Forgetting the guard: compiles in Editor, **fails on build** with no warning until build time

## Platform Defines

```csharp
// GOOD — always provide fallback
#if UNITY_ANDROID
    string dataPath = Application.persistentDataPath;
#elif UNITY_IOS
    string dataPath = Application.persistentDataPath;
#else
    string dataPath = Application.dataPath;
#endif

// BAD — code silently excluded on other platforms
#if UNITY_ANDROID
    SetupMobileControls();
#endif
```

## The `?.` Operator Trap

```csharp
// DANGEROUS — bypasses Unity's destroyed-object detection
_target?.TakeDamage(10);  // Calls TakeDamage on destroyed objects!

// SAFE — Unity's == operator detects destroyed objects
if (_target != null)
{
    _target.TakeDamage(10);
}
```

Unity overrides `==` to return `true` when comparing destroyed objects to `null`. The `?.` operator uses C# reference equality, which does NOT detect destroyed objects. This is the #1 most subtle Unity bug.

## Lifecycle Order

```
Awake()       → called once when object is created (even if disabled)
OnEnable()    → called when object becomes active
Start()       → called once before first Update (only if enabled)
FixedUpdate() → physics tick (0.02s default)
Update()      → every frame
LateUpdate()  → every frame, after all Updates
OnDisable()   → called when object becomes inactive
OnDestroy()   → called when object is destroyed
```

- Don't depend on Awake order across objects — use `[DefaultExecutionOrder]` or explicit init
- `OnDisable` is called before `OnDestroy` — unsubscribe events in `OnDisable`
- `Start` is NOT called if the object is never enabled

## Threading

Unity API is main-thread only. Background threads cannot:
- Access `Transform`, `GameObject`, `Component`
- Call `Instantiate`, `Destroy`
- Access `Time`, `Input`, `Physics`

```csharp
// Return to main thread with UniTask:
await UniTask.SwitchToMainThread();

// Or with SynchronizationContext:
SynchronizationContext.Current.Post(_ => { /* Unity API here */ }, null);
```

## No Coroutines — Use UniTask

Do not use `StartCoroutine` / `IEnumerator` / `yield return`. Use UniTask for all async work.

Coroutine problems that UniTask solves:
- Coroutines stop silently when `gameObject.SetActive(false)` and don't resume
- Coroutines have no cancellation, error handling, or return values
- Coroutines allocate on the heap

```csharp
// BAD — coroutine
private IEnumerator WaitAndDo()
{
    yield return new WaitForSeconds(1f);
    DoSomething();
}

// GOOD — UniTask
private async UniTask WaitAndDoAsync(CancellationToken token)
{
    await UniTask.Delay(TimeSpan.FromSeconds(1), cancellationToken: token);
    DoSomething();
}
```

Always pass `CancellationToken`. In Views: `this.GetCancellationTokenOnDestroy()`. In Systems: own a `CancellationTokenSource` and cancel in `Dispose()`.

## DontDestroyOnLoad

Use sparingly. Prefer a bootstrapper scene pattern:
```
BootstrapScene (loads once, contains persistent services)
    → Additively loads GameScene, MenuScene, etc.
```

## Transform

- `transform.SetParent(parent, false)` — use `worldPositionStays: false` to preserve local transform
- `Application.isPlaying` — check in OnDisable/OnDestroy to avoid cleanup during editor domain reload

## Time

- `Time.deltaTime` in `Update` and `LateUpdate`
- `Time.fixedDeltaTime` in `FixedUpdate`
- Never use `Time.deltaTime` in `FixedUpdate` (it equals `fixedDeltaTime` there, but it's confusing)
- `Time.unscaledDeltaTime` for pause-independent logic (UI animations, etc.)

## Component Attributes

```csharp
[RequireComponent(typeof(Rigidbody))]        // Auto-adds Rigidbody, prevents removal
[DisallowMultipleComponent]                   // Prevents duplicate components
[DefaultExecutionOrder(-100)]                 // Runs before default scripts
[SelectionBase]                               // Click selects this object, not children
```

## Input System (NON-NEGOTIABLE)

The New Input System package is **mandatory**. Legacy `Input.GetKey`/`Input.GetAxis` is **BLOCKED** by hooks.

### Generated C# Class (Preferred Approach)

1. Create `Assets/Input/PlayerControls.inputactions` — define all action maps
2. Enable "Generate C# Class" in the asset inspector → generates `PlayerControls.cs`
3. Use the generated class in InputView (see architecture rules)

### Critical Lifecycle Rules

```csharp
// InputView — the ONLY place that touches PlayerControls
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private PlayerSystem _playerSystem;

    private void Awake()
    {
        _controls = new PlayerControls();
    }

    [Inject]
    public void Construct(PlayerSystem playerSystem)
    {
        _playerSystem = playerSystem;
    }

    // MANDATORY: Enable actions in OnEnable
    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
        _controls.Player.Attack.performed += OnAttack;
    }

    // MANDATORY: Disable actions and unsubscribe in OnDisable
    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Attack.performed -= OnAttack;
        _controls.Player.Disable();
    }

    // Read continuous input in Update, cache for systems
    private void Update()
    {
        Vector2 moveInput = _controls.Player.Move.ReadValue<Vector2>();
        _playerSystem.SetMoveInput(moveInput);
    }

    private void OnJump(InputAction.CallbackContext ctx) => _playerSystem.Jump();
    private void OnAttack(InputAction.CallbackContext ctx) => _playerSystem.Attack();
}
```

### Rules

| Rule | Why |
|------|-----|
| **Enable in OnEnable, Disable in OnDisable** | Missing Enable = zero input received. Missing Disable = ghost callbacks, leaks |
| **Subscribe in OnEnable, unsubscribe in OnDisable** | Every `+=` must have a matching `-=` in OnDisable |
| **Read continuous input in Update** | FixedUpdate runs at different rate — input can be missed |
| **Cache input, apply in FixedUpdate** | Physics forces use cached values, not raw reads |
| **Never use legacy Input API** | `Input.GetKey`, `Input.GetAxis`, `Input.GetButton` are BLOCKED |
| **InputView is a View** | Pure thin adapter — reads input, calls Systems. Zero logic |
| **One InputView per scene** | Centralized input reading prevents duplicate subscriptions |

### Action Map Switching

```csharp
// Gameplay → UI (e.g., opening pause menu)
_controls.Player.Disable();
_controls.UI.Enable();

// UI → Gameplay (closing menu)
_controls.UI.Disable();
_controls.Player.Enable();
```

Always disable the current map **before** enabling the next. Never leave multiple gameplay maps enabled simultaneously.

## Prefab Rules (NON-NEGOTIABLE)

Every GameObject placed in a scene must be an instance of a prefab. Bare (non-prefab) GameObjects are forbidden — except scene separators/organizers (empty GameObjects used purely as hierarchy dividers with no components).

**Why:** Bare GameObjects cannot be reused, are hard to maintain across scenes, and break Addressables-based spawning.

### new GameObject() is Forbidden (NON-NEGOTIABLE)

`new GameObject()` is forbidden in all runtime code — no exceptions. This includes Pool, Factory, and Spawner classes. Every GameObject must originate from a prefab.

```csharp
// BAD — forbidden everywhere in runtime code
var go = new GameObject("Enemy");
var go = new GameObject("Bullet", typeof(Rigidbody));

// GOOD — instantiate from prefab
var instance = Instantiate(_prefab, position, rotation);
var instance = Instantiate(_prefab, parent, false);

// GOOD — Addressables
var instance = await Addressables.InstantiateAsync(address).ToUniTask(ct);
```

**Why:** `new GameObject()` produces a bare object with no prefab backing — it cannot be tracked by Addressables, has no variant chain, and breaks the single-source-of-truth prefab model. Even pools and factories must instantiate from a prefab; they just manage the lifecycle of those instances.

The `check-no-runtime-instantiate` hook blocks this with exit 2 on every Write/Edit.

### Destroy() Rules

`Destroy()` usage depends on context:

**Outside Pool/Manager/Spawner classes — warn:**
If an object is pool-managed, call `pool.Return()` or `SetActive(false)` instead of `Destroy()`. The hook warns when `Destroy()` is found outside Pool/Manager/Spawner files.

**Inside Pool/Manager/Spawner classes — two allowed cases:**

```csharp
// Case 1 — Pool capacity trim: pool exceeds max capacity, destroy the excess
// Rule: never destroy below the capacity limit (e.g. 50)
public void ReturnToPool(GameObject obj)
{
    if (_pool.Count >= MAX_CAPACITY)
        Destroy(obj);       // over capacity — destroy the excess
    else
        _pool.Enqueue(obj); // under limit — keep it
}

// Case 2 — Manager shutdown: the pool/manager is no longer needed (e.g. level change)
// Destroy the manager and all its children together
public void Shutdown()
{
    Destroy(gameObject); // destroys manager + all pooled children
}
```

**Rules:**
- Pool capacity limit is defined as a constant in the pool class (`private const int MAX_CAPACITY = 50`)
- Never destroy pooled objects below the capacity limit — return them to the pool instead
- Manager shutdown (`Destroy(gameObject)`) is only valid when the entire pool is being decommissioned — never use it to release individual objects

### Prefab Variants for Shared Behavior

When multiple objects share a common base, create a base prefab and derive variants from it. Never duplicate prefabs manually.

```
BaseEnemy.prefab          ← base: shared components, default values
├── FastEnemy.prefab      ← variant: overrides Speed, visual
└── TankEnemy.prefab      ← variant: overrides Health, Size, visual
```

- Variants inherit all components and values from the base
- Only override what actually differs — keep overrides minimal
- Never copy-paste a prefab and tweak it — use Prefab Variants

### Folder Structure

All prefabs live under `_GameFolders/Prefabs/`, grouped by domain:

```
_GameFolders/
└── Prefabs/
    ├── Enemies/
    │   ├── BaseEnemy.prefab
    │   ├── FastEnemy.prefab
    │   └── TankEnemy.prefab
    ├── UI/
    │   ├── Canvases/      ← full-screen Canvas prefabs (MainMenuCanvas, GameCanvas…)
    │   ├── Popups/        ← popup and dialog prefabs
    │   ├── Panels/        ← panel prefabs
    │   └── Utilities/     ← single reusable elements (Button, Icon, Label…)
    ├── VFX/
    │   └── ExplosionEffect.prefab
    └── Environment/
        └── Platform.prefab
```

- One subfolder per domain — never dump prefabs directly into `Prefabs/`
- Subfolder name matches the domain (Enemies, UI, VFX, Environment, Player, Projectiles…)
- Base prefabs and their variants live in the same subfolder

### Logic vs Visual Separation (NON-NEGOTIABLE)

Every prefab separates logic components from visual components across two levels:

```
Player.prefab                  ← Root: logic components only
├── PlayerProvider.cs
├── PlayerController.cs
└── Body/                      ← Child: visual components only
    ├── MeshRenderer
    ├── Animator
    └── SkinnedMeshRenderer
```

- **Root GameObject** — holds Provider, Controller, Collider, Rigidbody, and any injected MonoBehaviours
- **`Body` child** (or `Visual`, `Mesh` — be consistent per project) — holds Renderer, Animator, particle systems, and any purely visual components
- Logic scripts never sit on the same GameObject as a Renderer
- Visual child has no logic scripts; root has no Renderer components

**Why:** Swapping visuals (skin, LOD, VFX) never touches logic. Animating, hiding, or replacing the visual subtree is isolated — root stays stable.

```
Enemy.prefab
├── EnemyProvider.cs
├── CapsuleCollider
└── Body/
    ├── SkinnedMeshRenderer
    └── Animator

Tower.prefab
├── TowerProvider.cs
├── BoxCollider
└── Body/
    ├── MeshRenderer
    └── ParticleSystem (muzzle flash)
```

### Rules Summary

| Rule | Why |
|------|-----|
| Every scene GameObject is a prefab instance | Reusability, Addressables compatibility |
| Shared-base objects use Prefab Variants | Single source of truth, easier iteration |
| Prefabs grouped by domain under `_GameFolders/Prefabs/` | Predictable location, clean Project window |
| Never duplicate a prefab manually | Use Prefab Variants instead |
| Empty hierarchy organizers are the only bare GameObjects allowed | No components = no logic = no maintenance cost |
| Logic components on root, visual components on `Body` child | Decouples visual swaps from logic, clear responsibility |
| `AppScope` / `LifetimeScope` with only ScriptableObject refs → `Prefabs/Bootstrap/` | Asset refs are stored on the prefab; no scene-time drag-and-drop needed |
| `EventSystem` and `MainCamera` → `Prefabs/CoreObjects/`, same prefab in every scene | Consistent settings, single source of truth across all scenes |

## Prefab Duplication from Third-Party Packages (NON-NEGOTIABLE)

Prefabs that ship inside a third-party UPM package (under `Library/PackageCache/<name>@<version>/`) or an Asset Store package (under `Assets/Plugins/<vendor>/`) must NEVER be referenced directly from a scene, a Resources reference, an Addressables entry, or another prefab.

**Why:** Package contents are immutable from the project's perspective — UPM rewrites `Library/PackageCache/` on every resolve, and Asset Store updates overwrite `Assets/Plugins/`. Any in-scene reference to a package GUID breaks with a "missing prefab" error on version bump; any in-package edit is silently lost.

### Procedure

1. Identify the source prefab inside the package directory.
2. Choose a category folder under `_GameFolders/Prefabs/<Category>/` matching the existing domain folders (Enemies, UI, VFX, Environment, …). Use a `<Category>/<PackageSlug>/` subfolder when the package contributes more than one prefab.
3. Duplicate the prefab into that destination using **Project window → right-click → Duplicate**. Do NOT copy `.meta` files from the package — Unity will mint a fresh GUID on duplication.
4. Replace any in-scene/in-prefab reference to the package GUID with the new GUID from the duplicate.
5. Apply the Logic vs Visual Separation rule to the duplicate: logic components on the root GameObject, visual/renderer components on a `Body` child. See "Prefab Rules (NON-NEGOTIABLE)" for the full separation convention.

### Rules

| Rule | Why |
|------|-----|
| Never drag a `Library/PackageCache/...` prefab into a scene | Reference breaks on package upgrade |
| Always duplicate into `_GameFolders/Prefabs/<Category>/` first | Project owns the GUID and the asset lifecycle |
| Never edit a package prefab in place | UPM resolve overwrites it; Asset Store update overwrites it |
| Never copy `.meta` files from the package source | Forces Unity to assign a fresh GUID; old references stay scoped to the package |
| Place duplicates by category, not by package | Keeps the project-side prefab tree organized by domain, not by vendor |

See also: "Prefab Rules (NON-NEGOTIABLE)" in this file for folder structure, Prefab Variants, and Logic vs Visual Separation rules that apply after duplication.
See also: `/discover` writes the per-package duplication plan into `.claude/skills/plugins/<package>/SKILL.md` under the `## Prefabs` section.

## .meta Files

- NEVER edit manually
- ALWAYS commit alongside their asset
- Missing .meta = Unity regenerates GUID = all references break
- Orphaned .meta = clutter and potential conflicts
