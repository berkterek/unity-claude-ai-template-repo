# C# Style — Unity Conventions

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: Naming — Game.Concretes.<Domain> Pattern

**WHEN:** Creating any new class in the project.

**WRONG:**
```csharp
namespace Scripts.Audio { public class AudioService { } }
namespace GameAudio { public sealed class AudioSvc { } }
```

**RIGHT:**
```csharp
namespace Game.Concretes.Audio { public sealed class AudioService : IAudioService { } }
namespace Game.Abstracts.Audio  { public interface IAudioService { } }
```

**GOTCHA:** The namespace follows the folder path — `_GameFolders/Scripts/Games/Concretes/Audio/` → `Game.Concretes.Audio`. Drop the underscore prefix, drop `Scripts/` and `Games/`.

---

### Card 1.1: Folder Names Are Domains, Not Layers

**WHEN:** Naming a domain folder under `Abstracts/`/`Concretes/`, or naming any class/interface.

**WRONG:**
```
Games/Concretes/Input/PlayerInputHandler.cs      // domain folder singular
Games/Concretes/Controllers/PlayerController.cs  // layer name, not a domain
Games/Concretes/Core/GameFlow.cs                 // catch-all, not a domain
Games/Concretes/PlayerService.cs                 // no domain folder at all

public sealed class Players { }                  // class name plural
```

**RIGHT:**
```
Games/Concretes/Inputs/PlayerInputHandler.cs      // domain folder plural
Games/Concretes/Enemies/EnemyController.cs        // domain folder plural
Games/Concretes/Audio/AudioService.cs             // mass noun stays singular
Games/Concretes/Players/Services/PlayerService.cs // layer name below a domain: fine

public sealed class Player { }                   // class singular
public sealed class Enemy { }                     // class singular
public sealed class PlayerController { }          // class singular
```

**GOTCHA:** Only the domain folder (and matching namespace segment, e.g. `Game.Concretes.Inputs`) is plural. The class/interface inside stays singular — `PlayerController.cs` never becomes `Controllers.cs`. This does not override the "one type per file, filename matches class name" rule. Plurality applies **only once the folder is already a domain** — a plural layer name (`Controllers/`, `Services/`) is still banned in the first position; the class keeps its layer suffix, the folder never takes one. Banned first-segment list: `rules/architecture.md` → Domain Folder Convention.

**Exception — static Extension classes:** the extension class itself (not a domain folder) is named in the plural, matching the type it extends: `Vector3Extensions`, `StringExtensions`, `TransformExtensions`. The file name matches the class name as usual (`Vector3Extensions.cs`).

---

### Card 2: Null Check — Never `?.` on UnityEngine.Object

**WHEN:** Null-checking any MonoBehaviour, Component, or other Unity object.

**WRONG:**
```csharp
_target?.TakeDamage(10);   // calls method on destroyed objects!
if (_target is null) return; // misses destroyed objects
```

**RIGHT:**
```csharp
if (_target == null) return;  // Unity overrides == for destroyed objects
_target.TakeDamage(10);
```

**GOTCHA:** `?.` uses C# reference equality — it does NOT return null for destroyed Unity objects. This is the #1 most subtle Unity bug.

> See also: `rules/event-patterns.md` → Pattern 4 note (field-assignment null-guard vs destroyed-object check)

---

### Card 3: UniTask Only — Never `Task` or `async void`

**WHEN:** Writing any asynchronous method.

**WRONG:**
```csharp
async Task LoadAsync() { }       // no Unity lifecycle integration
async void Initialize() { }     // swallows exceptions silently
IEnumerator Load() { yield return ...; } // coroutine — forbidden
```

**RIGHT:**
```csharp
async UniTask LoadAsync(CancellationToken ct) { }
// fire-and-forget:
LoadAsync(ct).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });
```

**GOTCHA:** `async void` cannot be awaited or cancelled, and any exception thrown inside it is unhandled — the game crashes silently in production.

---

### Card 4: #region Discipline — Required in _GameFolders/Scripts/

**WHEN:** Writing any class under `_GameFolders/Scripts/`.

**WRONG:** No regions, or regions named after types instead of roles.

**RIGHT:**
```csharp
#region Fields
#region Constructor
#region Lifecycle      // Awake, OnEnable, Start, OnDisable, OnDestroy
#region Public Methods
#region Private Methods
```

**GOTCHA:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods total (all access levels combined) are exempt. At 3 or more methods, `#region` is required regardless of visibility.

---

### Card 5: Namespace Collision — UnityEngine Type Aliases

**WHEN:** Creating a domain folder whose name matches a UnityEngine type (Camera, Random, Object, Input, Physics, Collider, Transform…).

**WRONG:**
```csharp
namespace Game.Concretes.Camera
{
    public sealed class CameraService : ICameraService
    {
        private Camera _cam; // ambiguous — compiler can't distinguish Game.Concretes.Camera.Camera from UnityEngine.Camera
    }
}
```

**RIGHT:**
```csharp
using UCamera = UnityEngine.Camera;
namespace Game.Concretes.Camera
{
    public sealed class CameraService : ICameraService
    {
        private UCamera _cam;
    }
}
```

**GOTCHA:** Check domain name against UnityEngine types before creating the folder. Consult the full collision table in `### Namespace Collision Rule`. Add the alias to every `.cs` file in that domain.

---

### Card 6: Reuse Before You Hand-Roll

**WHEN:** You are about to write a pool, timer, parser, smoothing helper, or registry.

**WRONG:**
```csharp
// Hand-rolled pool — 40 lines that Unity already ships
public sealed class BulletPool
{
    private readonly Queue<GameObject> _available = new();

    public GameObject Get()
    {
        var go = _available.Count > 0 ? _available.Dequeue() : Object.Instantiate(_prefab);
        go.SetActive(true);
        return go;
    }

    public void Return(GameObject go)
    {
        go.SetActive(false);
        _available.Enqueue(go);
    }
}
```

**RIGHT:**
```csharp
// UnityEngine.Pool.ObjectPool<T> — capacity limits, leak detection, Dispose all built in
private readonly ObjectPool<GameObject> _pool;

public BulletPool(GameObject prefab)
{
    _pool = new ObjectPool<GameObject>(
        createFunc:       () => Object.Instantiate(prefab),
        actionOnGet:      go => go.SetActive(true),
        actionOnRelease:  go => go.SetActive(false),
        actionOnDestroy:  Object.Destroy,
        defaultCapacity:  20,
        maxSize:          100);
}
```

| Instead of hand-rolling | Use |
|---|---|
| `Queue<GameObject>` pool | `UnityEngine.Pool.ObjectPool<T>` |
| manual timer field / `WaitForSeconds` coroutine | `UniTask.Delay` |
| string-splitting JSON parser | `JsonUtility` |
| custom lerp / damping smoothing | `Mathf.SmoothDamp` |
| custom registry, service locator, static instance dictionary | VContainer |

**GOTCHA:** Hand-rolling is permitted only when the built-in **demonstrably** cannot meet a measured requirement — not when it merely feels heavy. When you do hand-roll, the reason goes in a code comment or an ADR; silence is not a justification. A reviewer finding a hand-rolled equivalent with no stated reason returns CHANGES NEEDED.

## Naming Summary

| Construct | Style | Example |
|-----------|-------|---------|
| Class, struct, enum | PascalCase | `AudioService`, `ProductType` |
| Interface | `I` + PascalCase | `IAudioService` |
| Method, property | PascalCase | `PlaySound()`, `IsPlaying` |
| Private / protected field | `_` + camelCase | `_audioService`, `_isInitialized` |
| Public field (`[Serializable]` data classes only) | PascalCase | `SfxVolume`, `HapticOn` |
| Local variable, parameter | camelCase | `currentLevel`, `audioService` |
| Constant | `SCREAMING_SNAKE_CASE` | `MAX_RETRY_COUNT` |
| `static readonly` | PascalCase | `JumpHash`, `DefaultColor` |
| IEvent implementation | PascalCase + past tense + `Event` suffix | `LevelStartedEvent`, `CoinsChangedEvent` |
| MonoBehaviour — UI/Canvas only | PascalCase + `View` suffix | `HUDView`, `PopupView`, `SliderView` |
| MonoBehaviour — gameplay/character/physics | PascalCase + `Controller` suffix | `PlayerController`, `ItemController` |
| MonoBehaviour — Unity API abstraction | PascalCase + `Provider` suffix | `AudioProvider`, `PhysicsProvider` |
| `*Handler` (pure C# class, prefab-local) | PascalCase + `Handler` suffix | `MoveHandler`, `JumpHandler` |
| Interface for Handler | `I` + PascalCase + `Handler` | `IMoveHandler`, `IJumpHandler` |
| Static installer class | PascalCase + `Module` suffix | `AudioModule`, `PlayerModule`, `AppModules` |
| Runtime state class | PascalCase + `Model` suffix | `ScoreModel`, `HealthModel` |
| Serializable save data class | PascalCase + `SaveData` suffix | `PlayerSaveData`, `GameSaveData` |
| ScriptableObject | PascalCase + descriptive suffix | `AudioConfiguration`, `ProductCatalog` |
| Installer | PascalCase + `Installer` suffix | `AudioInstaller`, `StoreInstaller` |
| Namespace | `<Layer>.<Module>` | `Framework.Events`, `Game.Concretes` |
| Test class | PascalCase + `Tests` suffix | `EnemySpawnerTests` |
| Test method | `MethodName_WhenCondition_ExpectedBehavior` | `TakeDamage_WhenZeroHealth_RaisesEvent` |
| ECS data component | PascalCase, no suffix | `HealthData`, `MoveSpeed` |
| ECS tag component | PascalCase + `Tag` suffix | `EnemyEntityTag`, `DestroyEntityTag` |
| ECS cleanup component | PascalCase + `CleanupData` suffix | `EnemyCleanupData` |
| ECS managed reference | PascalCase + `Reference` suffix (class) | `EnemyVisualReference` |
| ECS Authoring | PascalCase + `Authoring` suffix | `EnemyAuthoring` |

---

## Namespace Convention

Format: `<Layer>.<Domain>` — underscore prefix on folder names is dropped.

| Folder | Namespace |
|--------|-----------|
| `_Framework/Events/` | `Framework.Events` |
| `_Framework/Logging/` | `Framework.Logging` |
| `_GameFolders/Scripts/Games/Abstracts/` | `Game.Abstracts` |
| `_GameFolders/Scripts/Games/Abstracts/<Domain>/` | `Game.Abstracts.<Domain>` |
| `_GameFolders/Scripts/Games/Concretes/` | `Game.Concretes` |
| `_GameFolders/Scripts/Games/Concretes/<Domain>/` | `Game.Concretes.<Domain>` |
| `_GameFolders/Scripts/Games/Ecs/` | `Game.Ecs` |
| `_GameFolders/Scripts/Tests/` | `Game.Tests` |
| `_GameFolders/Scripts/Editors/` | `Game.Editors` |

Namespace follows folder depth. Third-party libraries keep their own namespaces (`VContainer`, `UniTask`, etc.).

### Namespace Collision Rule (NON-NEGOTIABLE)

The `Game.Concretes.<Domain>` namespace can collide with `UnityEngine` type names. When a collision exists the C# compiler cannot resolve which type is intended and raises an ambiguous reference error.

**Known collisions:**

| Domain namespace | Colliding UnityEngine type | Alias |
|-----------------|---------------------------|-------|
| `Game.Concretes.Camera` | `UnityEngine.Camera` | `using UCamera = UnityEngine.Camera;` |
| `Game.Concretes.Random` | `UnityEngine.Random` | `using URandom = UnityEngine.Random;` |
| `Game.Concretes.Object` | `UnityEngine.Object` | `using UObject = UnityEngine.Object;` |
| `Game.Concretes.Input` | `UnityEngine.Input` | `using UInput = UnityEngine.Input;` |
| `Game.Concretes.Physics` | `UnityEngine.Physics` | `using UPhysics = UnityEngine.Physics;` |
| `Game.Concretes.Collider` | `UnityEngine.Collider` | `using UCollider = UnityEngine.Collider;` |
| `Game.Concretes.Transform` | `UnityEngine.Transform` | `using UTransform = UnityEngine.Transform;` |
| `Game.Concretes.Time` | `UnityEngine.Time` | `using UTime = UnityEngine.Time;` |
| `Game.Concretes.Component` | `UnityEngine.Component` | `using UComponent = UnityEngine.Component;` |

**Rule:** When `Game.Concretes.<Domain>` contains a type whose name matches a `UnityEngine` type, add the alias at the top of **every** `.cs` file in that domain.

**Pre-plan check:** Before creating a new domain folder, the Researcher must verify that the domain name does not match a `UnityEngine` type. If a match exists, add an alias task to the plan.

---

## Field Declarations

```csharp
// Private — underscore + camelCase
private IAudioService _audioService;
private bool _isInitialized;
private readonly IEventBus _eventBus;

// Static readonly — PascalCase
private static readonly int JumpHash = Animator.StringToHash("Jump");
private static readonly int ColorId  = Shader.PropertyToID("_Color");

// Constant — SCREAMING_SNAKE_CASE
private const int    MAX_RETRY_COUNT   = 3;
private const string DEFAULT_SOUND_ID  = "tap";

// [SerializeField] — two valid uses:
//   1. Designer-configurable values (floats, curves, SO configs)
//   2. Component references on the same GO or its children (Rigidbody, Animator, Transform…)
[SerializeField] private float _moveSpeed = 5f;
[SerializeField] private AudioConfiguration _config;
[SerializeField] private Rigidbody _rigidbody;    // assigned in Inspector, not GetComponent
[SerializeField] private Transform _transform;    // assigned in Inspector, not cached in Awake

// Public fields — only in [Serializable] data classes and ScriptableObject configs
public float SfxVolume = 1f;
public bool HapticOn = true;

// [field: SerializeField] — auto-property with Inspector serialization.
// Use when a public getter with Inspector visibility is needed on a data class or ScriptableObject.
[field: SerializeField] public float MoveSpeed { get; private set; } = 5f;

// Equivalent explicit form (preferred in most cases):
[SerializeField] private float _moveSpeed = 5f;
public float MoveSpeed => _moveSpeed;
```

**Rule:** Prefer the explicit backing-field form (`_moveSpeed` + read-only property) in `MonoBehaviour` and service classes — it keeps the underscore naming convention, is easier to debug in the Inspector, and works on all Unity versions. Use `[field: SerializeField]` only in `[Serializable]` data classes or `ScriptableObject` configs where a clean public getter is the primary API.

> See also: `rules/architecture.md` → Card 6 (Same Prefab SerializeField rule); `rules/performance.md` → Component References section

---

## Data Taxonomy

| Data type | Author | Form | Suffix | Example |
|-----------|--------|------|--------|---------|
| Config — designer-set, runtime read-only | Designer, edit-time | `ScriptableObject` (in ConfigCatalog) | `*Configuration` | `AudioConfiguration` |
| Save data — written to disk (JSON) | Runtime, persisted | `[Serializable]` plain class — no UnityEngine types | `*SaveData` | `PlayerSaveData` |
| Runtime state — session-only mutable | Runtime, not persisted | plain class (held by service/model) | `*Model` | `ScoreModel` |
| Event payload — single-frame message | Publish time | `readonly struct : IEvent` | `*Event` | `CoinsChangedEvent` |
| ECS component | System | `struct : IComponentData` | see ecs-dots.md | `HealthData` |

**Decision test:** Who writes it, and does it need disk?
- Designer writes it, runtime reads it → ScriptableObject
- Runtime writes it, goes to disk → `[Serializable]` class
- Runtime writes it, dies with session → Model class
- Created once, distributed → readonly struct

**Rules:**
- ScriptableObject is NEVER mutated at runtime (NON-NEGOTIABLE).
  Classic trap: Editor SO mutation writes permanently to asset; build resets it → two environments differ.
  If a config value must change at runtime: copy from SO to Model, mutate the Model.
- SaveData classes contain NO UnityEngine types (Vector3, Color, etc.) — use plain float fields or
  your own `[Serializable]` equivalents. Reason: JSON serializer independence + pure C# testability (EditMode).
- Every SaveData root class has an `int Version` field for forward migration.
- App-wide config (AudioConfiguration etc.) travels via ConfigCatalog → DI only.
  Holding a config SO in a MonoBehaviour `[SerializeField]` is an anti-pattern for app-wide config —
  same SO dragged onto N prefabs → one forgotten = silent null.
  Exception: prefab-local designer tweaks (variant stats) — the shell holds `[SerializeField]`
  for its own prefab's config only.

---

## Encapsulation (NON-NEGOTIABLE)

Everything is `private` unless there is a concrete caller that requires otherwise.

- Fields: `private` by default. `[SerializeField]` for two cases only: (1) designer-configurable values, (2) component references on the same GO or its children — never speculatively. `GetComponent` in Awake is forbidden when the component exists at edit time; assign via Inspector instead.
- Methods: `public` only when another class actually calls it today.
- Properties: expose getter only when another class reads it; expose setter only when another class writes it.

### Constructor Injection Rule — No `new *Service()` or `new *Provider()`

No `new *Service()` or `new *Provider()` in any class — always constructor-injected via VContainer.
Exception: `new *Handler(...)` is allowed ONLY inside a `*Controller` or `*View` class (the Mono shell) — handlers are wired by the shell, not by VContainer directly.

```csharp
// BAD — Service constructed directly
private void Awake() => _audioService = new AudioService(_provider);

// GOOD — Handler constructed by shell (no container dep)
private void Awake() => _moveHandler = new MoveHandler(_rigidbody, _moveConfig);

// GOOD — Service injected via VContainer
[Inject]
public void Construct(IAudioService audioService) => _audioService = audioService;
```

```csharp
// BAD — speculative public API
public class EnemyService
{
    public EnemyModel Model;
    public void Initialize() { }
    public int CalculateDamage() { return 5; }
}

// GOOD — minimum visibility
public sealed class EnemyService
{
    private readonly EnemyModel _model;
    private void Initialize() { }
    private int CalculateDamage() => 5;
    public void TakeDamage(int amount) { }  // CombatService calls this
}
```

---

## Script Structure — #region (Required in `_GameFolders/Scripts/`)

Every `.cs` file under `_GameFolders/Scripts/` must use `#region` tags in this order.

**Exception:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods total (all access levels combined) do not require `#region`. At 3 or more methods, regions are mandatory.

```csharp
public class ExampleService : IExampleService, IInitializable, IDisposable
{
    #region Fields

    private readonly IEventBus _eventBus;
    private bool _isDisposed;

    #endregion

    #region Constructor

    public ExampleService(IEventBus eventBus)
    {
        _eventBus = eventBus;
    }

    #endregion

    #region Lifecycle

    public void Initialize() { }
    public void Dispose() { }

    #endregion

    #region Public Methods

    public void DoSomething() { }

    #endregion

    #region Private Methods

    private void InternalHelper() { }

    #endregion
}
```

---

## Access Modifier Order

```
1. public
2. internal  (avoid)
3. protected
4. private

Within each level: static → readonly → normal
```

---

## Null Check Rules

```csharp
// Plain C# objects — standard C# null operators are fine
_eventBus?.Publish(new LevelStartedEvent());
_buttonStyle ??= new GUIStyle(EditorStyles.toolbarButton);
if (_provider == null) return;

// Unity objects (MonoBehaviour, ScriptableObject, etc.) — MUST use == null
// Unity overrides == to detect destroyed objects; ?. and is null bypass this
if (_target == null) return;      // CORRECT
if (_target is null) return;      // WRONG — misses destroyed objects
_target?.TakeDamage(10);          // WRONG — calls method on destroyed objects
```

---

## Async Rules

### UniTask — No coroutines

```csharp
// GOOD
public async UniTask InitializeAsync(CancellationToken ct)
{
    await UniTask.Delay(1000, cancellationToken: ct);
}

// BAD — coroutine
IEnumerator Initialize() { yield return new WaitForSeconds(1f); }

// BAD — async Task (no Unity lifecycle integration)
async Task Initialize() { }
```

**Exception — Test Assemblies:** `[UnityTest]` requires `IEnumerator` by Unity's test runner. This is a technical constraint, not a violation of the rule.

### Fire-and-forget

```csharp
// GOOD
InitializeAsync(ct).Forget();

// BAD
async void Initialize() { }
```

**Handler rule:**
- **Full handler (default):** Use when the async method can propagate non-cancellation exceptions.
  ```csharp
  LoadAsync(ct).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });
  ```
- **Bare `.Forget()` (exception only):** Acceptable only when exceptions are caught internally by the method. Add a comment: `// safe: exceptions handled internally`.

When in doubt, use the full handler. Bare `.Forget()` that silently drops exceptions is equivalent to an empty catch block.

### CancellationToken

Every async method takes a `CancellationToken`. Bind to lifecycle:

```csharp
public sealed class StoreService : IInitializable, IDisposable
{
    private CancellationTokenSource _cts;

    public void Initialize()
    {
        _cts = new CancellationTokenSource();
        SetupAsync(_cts.Token).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
```

**CancellationTokenSource ownership rules:**

| Rule | Detail |
|------|--------|
| Creator owns it | The class that calls `new CancellationTokenSource()` is responsible for `.Cancel()` and `.Dispose()` |
| Cancel before Dispose | Always call `_cts.Cancel()` before `_cts.Dispose()` — cancels in-flight tasks first |
| Dispose in `Dispose()` | For `IDisposable` classes: `Dispose()`. For MonoBehaviour: `OnDestroy()` |
| Never pass the CTS | Pass only `_cts.Token` to callees — never the `CancellationTokenSource` itself |
| Null-guard before use | `_cts?.Cancel(); _cts?.Dispose();` — CTS may be null if `Initialize()` was never called |

---

## Types and File Rules

- `sealed` by default — only unseal when inheritance is explicitly designed
- One type per file — file name MUST match the primary class/struct name
- Explicit access modifiers everywhere — no implicit `private`
- Use `var` when the type is obvious from the right-hand side

**Exception — UI Panel files:** Panel class, UIData class, and UITypes partial class may share one file.

```csharp
// HomePanel.cs
public class HomePanel : UIPanel<HomePanelUIData> { }
public class HomePanelUIData : IBaseUIData { }
public partial class UITypes { public static UIType HomePanel = new UIType("HomePanel"); }
```

---

## Control Flow

- Braces always, even for single-line `if`/`for`/`while`
- Early return over deep nesting (guard clauses)
- `for` over `foreach` in hot paths (Update, FixedUpdate)
- No magic strings — use `nameof()`, `Animator.StringToHash()`, `Shader.PropertyToID()`
- No LINQ in gameplay code
- `CompareTag("tag")` not `tag == "tag"`

```csharp
// GOOD — guard clauses
public void OnPointerDown(Vector2 pos)
{
    if (!_isEnabled) return;
    if (_isBlocked) return;
    ProcessInput(pos);
}

// BAD — nested ifs
public void OnPointerDown(Vector2 pos)
{
    if (_isEnabled)
        if (!_isBlocked)
            ProcessInput(pos);
}
```

---

## Interface Contract Documentation

Every public interface method must document its contract where it is non-obvious. Only document fields that add real information — skip trivial ones (e.g. "Thread-safe: No" is obvious for all Unity API; "Throws: Never" adds noise if the method clearly cannot fail).

**Document these fields when non-obvious:**

| Field | When to include |
|-------|----------------|
| `Precondition:` | Input has constraints (range, non-null, must-be-registered) |
| `Postcondition:` | Guaranteed state after the call that a caller would rely on |
| `Side effect:` | Other state changes beyond the obvious return value |
| `Idempotent:` | When calling twice has a different outcome than calling once |
| `Throws:` | Which exception and under what condition |

```csharp
public interface IAudioService
{
    /// <summary>Plays a sound effect by registered ID.</summary>
    /// <remarks>
    /// Precondition: soundId must exist in AudioConfiguration.
    /// Postcondition: Sound plays from frame N+1 at configured SFX volume.
    /// Side effect: If soundId already playing, stops and restarts it.
    /// Idempotent: No — two calls play the sound twice if engine allows overlap.
    /// Throws: InvalidOperationException if soundId not found in configuration.
    /// </remarks>
    void PlaySound(string soundId);

    /// <summary>Sets master volume; applied immediately to all active sounds.</summary>
    /// <remarks>
    /// Precondition: None — any float accepted, clamped to [0, 1] internally.
    /// Side effect: Persists until next SetMasterVolume call.
    /// </remarks>
    void SetMasterVolume(float volume);
}
```

**Rule: Document contracts where silence would cause caller surprise. Skip fields that state the obvious.**

> See also: `rules/event-patterns.md` → Pattern 4 note (field-assignment null-guard vs destroyed-object check)
