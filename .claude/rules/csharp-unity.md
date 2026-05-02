# C# Style — Unity Conventions

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

Format: `<Layer>.<Module>` — underscore prefix on folder names is dropped.

| Folder | Namespace |
|--------|-----------|
| `_Framework/Events/` | `Framework.Events` |
| `_Framework/Logging/` | `Framework.Logging` |
| `_GameFolders/Scripts/Games/` | `Game` |
| `_GameFolders/Scripts/Games/Abstracts/` | `Game.Abstracts` |
| `_GameFolders/Scripts/Games/Concretes/` | `Game.Concretes` |
| `_GameFolders/Scripts/Games/Ecs/` | `Game.Ecs` |
| `_GameFolders/Scripts/Games/Abstracts/<Module>/` | `Game.Abstracts.<Module>` |
| `_GameFolders/Scripts/Games/Concretes/<Module>/` | `Game.Concretes.<Module>` |

Namespace follows folder depth. Third-party libraries keep their own namespaces (`VContainer`, `UniTask`, etc.).

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

// [SerializeField] — only when a designer needs to configure in Inspector
[SerializeField] private float _moveSpeed = 5f;
[SerializeField] private AudioConfiguration _config;

// Public fields — only in [Serializable] data classes and ScriptableObject configs
public float SfxVolume = 1f;
public bool HapticOn = true;
```

---

## Encapsulation (NON-NEGOTIABLE)

Everything is `private` unless there is a concrete caller that requires otherwise.

- Fields: `private` by default. `[SerializeField]` only when a designer actually tweaks the value in Inspector — never speculatively.
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
