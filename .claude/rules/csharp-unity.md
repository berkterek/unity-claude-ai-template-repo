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

**GOTCHA:** Interface files, single-member structs/enums, and helper classes with < 3 methods are exempt.

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

**GOTCHA:** Check domain name against UnityEngine types before creating the folder. Add the alias to every `.cs` file in that domain.

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

`Game.Concretes.<Domain>` namespace adı `UnityEngine` tip adlarıyla çakışabilir. Çakışma olduğunda C# derleyicisi hangi tipi kastettiğini bilemez ve ambiguous reference hatası verir.

**Bilinen çakışmalar:**

| Domain namespace | Çakışan UnityEngine tipi | Çözüm |
|-----------------|--------------------------|-------|
| `Game.Concretes.Camera` | `Camera` | `using UCamera = UnityEngine.Camera;` |
| `Game.Concretes.Random` | `Random` | `using URandom = UnityEngine.Random;` |

**Kural:** `Game.Concretes.<Domain>` namespace'i `UnityEngine` içinde aynı adlı bir tip barındırıyorsa, o domain'in **tüm** `.cs` dosyalarının en üstüne alias ekle:

```csharp
using UCamera = UnityEngine.Camera;
// using System.Random yerine:
using URandom = UnityEngine.Random;
```

**Plan aşamasında kontrol:** Yeni bir domain klasörü oluşturulmadan önce Researcher, domain adının (`Camera`, `Random`, `Object`, `Input`, `Physics`, `Collider`, `Transform`…) `UnityEngine` namespace'inde bir tiple eşleşip eşleşmediğini kontrol etmeli ve varsa alias'ı plana görev olarak eklemelidir.

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
```

---

## Encapsulation (NON-NEGOTIABLE)

Everything is `private` unless there is a concrete caller that requires otherwise.

- Fields: `private` by default. `[SerializeField]` for two cases only: (1) designer-configurable values, (2) component references on the same GO or its children — never speculatively. `GetComponent` in Awake is forbidden when the component exists at edit time; assign via Inspector instead.
- Methods: `public` only when another class actually calls it today.
- Properties: expose getter only when another class reads it; expose setter only when another class writes it.

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

**Exception:** Interface files, single-member structs/enums, and helper classes with fewer than 3 methods do not require `#region`.

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

### CancellationToken

Every async method takes a `CancellationToken`. Bind to lifecycle:

```csharp
public class StoreService : IInitializable, IDisposable
{
    private CancellationTokenSource _cts;

    public void Initialize()
    {
        _cts = new CancellationTokenSource();
        SetupAsync(_cts.Token).Forget();
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
```

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
