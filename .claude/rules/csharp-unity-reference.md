---
paths:
  - "**/Abstracts/**"
  - "**/*Pool*.cs"
---
# C# Style — Reference

> Full examples behind `rules/csharp-unity.md`. Every rule is stated there; this file only shows it. Loads when an
> `Abstracts/` file or a pool is touched.

## Card 1 / 1.1: Naming — examples

```csharp
// WRONG
namespace Scripts.Audio { public class AudioService { } }
namespace GameAudio { public sealed class AudioSvc { } }
// RIGHT
namespace Game.Concretes.Audio { public sealed class AudioService : IAudioService { } }
namespace Game.Abstracts.Audio  { public interface IAudioService { } }
```

```
WRONG
Games/Concretes/Input/PlayerInputHandler.cs      // domain folder singular
Games/Concretes/Controllers/PlayerController.cs  // layer name, not a domain
Games/Concretes/Core/GameFlow.cs                 // catch-all, not a domain
Games/Concretes/PlayerService.cs                 // no domain folder at all
public sealed class Players { }                  // class name plural

RIGHT
Games/Concretes/Inputs/PlayerInputHandler.cs      // domain folder plural
Games/Concretes/Enemies/EnemyController.cs        // domain folder plural
Games/Concretes/Audio/AudioService.cs             // mass noun stays singular
Games/Concretes/Players/Services/PlayerService.cs // layer name below a domain: fine
public sealed class Player { }                    // class singular
```

## Card 5: Namespace Collision — example

```csharp
// WRONG — ambiguous: Game.Concretes.Camera vs UnityEngine.Camera
namespace Game.Concretes.Camera
{
    public sealed class CameraService : ICameraService { private Camera _cam; }
}

// RIGHT
using UCamera = UnityEngine.Camera;
namespace Game.Concretes.Camera
{
    public sealed class CameraService : ICameraService { private UCamera _cam; }
}
```

## Card 6: Reuse Before You Hand-Roll — pool example

```csharp
// WRONG — hand-rolled pool, 40 lines that Unity already ships
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

// RIGHT — UnityEngine.Pool.ObjectPool<T>: capacity limits, leak detection, Dispose all built in
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

## Field Declarations — examples

```csharp
// Private — underscore + camelCase
private IAudioService _audioService;
private readonly IEventBus _eventBus;

// Static readonly — PascalCase
private static readonly int JumpHash = Animator.StringToHash("Jump");

// Constant — SCREAMING_SNAKE_CASE
private const int MAX_RETRY_COUNT = 3;

// [SerializeField] — designer values, or component refs on the same GO / children (assigned in Inspector)
[SerializeField] private float _moveSpeed = 5f;
[SerializeField] private Rigidbody _rigidbody;

// Public fields — only in [Serializable] data classes and ScriptableObject configs
public float SfxVolume = 1f;

// [field: SerializeField] — data classes / SO configs only
[field: SerializeField] public float MoveSpeed { get; private set; } = 5f;

// Preferred in MonoBehaviour and service classes
[SerializeField] private float _moveSpeed = 5f;
public float MoveSpeed => _moveSpeed;
```

## Encapsulation / Constructor Injection — examples

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

## #region — full example

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

## UI Panel exception — example

```csharp
// HomePanel.cs — Panel class, UIData class and UITypes partial may share one file
public class HomePanel : UIPanel<HomePanelUIData> { }
public class HomePanelUIData : IBaseUIData { }
public partial class UITypes { public static UIType HomePanel = new UIType("HomePanel"); }
```

## Control Flow — guard clauses

```csharp
// GOOD
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

## Interface Contract Documentation — example

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
