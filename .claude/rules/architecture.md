# Architecture Rules

## Core Principle: Dependency Direction

```
Views/Providers → Services → Models/Interfaces
       ↓               ↓
   IEventBus  (decoupled cross-system communication)
```

- Services depend on interfaces, never concrete types
- MonoBehaviours (Views/Providers) depend on services via VContainer injection
- Models/data classes depend on nothing
- Cross-service communication goes through IEventBus, never direct references
- Assembly definitions enforce direction at compile time

---

## Layer Structure

```
_Framework/                               ← Never references _GameFolders or other project folders. Pure infrastructure.
  Events/FrameworkEventBus.asmdef        ← each subfolder has its OWN .asmdef
  Logging/FrameworkLogging.asmdef
  SaveLoadSystems/FrameworkSaveLoadSystems.asmdef
  Editors/FrameworkEditor.asmdef         ← Editor-only, includePlatforms: ["Editor"]

_GameFolders/        ← Depends on _Framework. All game-specific code.
  Scripts/
    Games/
      Abstracts/     ← interfaces and abstract base classes ONLY, organized by domain
        Players/     ← example domain folders (mirrors Concretes/ structure)
        Enemies/
        ...
      Concretes/     ← ALL concrete classes (pure C# or MonoBehaviour), organized by domain
        Players/     ← same domain folders as Abstracts/
        Enemies/
        ...          ← name subfolders by domain/feature, not by layer
      Ecs/           ← ECS DOTS systems, components, authorings (only if ECS enabled)
    Tests/
      [Project]EditModeTest/   ← Edit Mode tests (.asmdef includePlatforms: ["Editor"])
      [Project]PlayModeTest/   ← Play Mode tests (.asmdef all platforms)
    Editors/         ← Editor-only tools, custom inspectors
```

### Scripts/ Folder Rules (NON-NEGOTIABLE)

The **only** valid top-level folders under `Scripts/` are: `Games/`, `Tests/`, `Editors/`.

**Never create these under `Scripts/` directly — they belong inside `Games/`:**

| Forbidden folder | Correct location |
|-----------------|-----------------|
| `Scripts/Config/` | ScriptableObject configs → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/GameUnity/` | MonoBehaviour views/providers → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/Game/` | Services → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/Abstracts/` | Must be inside `Games/` → `Scripts/Games/Abstracts/` |
| `Scripts/Concretes/` | Must be inside `Games/` → `Scripts/Games/Concretes/` |
| `Scripts/Services/` | Services → `Scripts/Games/Concretes/<Domain>/` |

**Games/Concretes/ subfolder naming:** use domain/feature names (`Players/`, `Enemies/`, `UI/`, `Audio/`, `Handlers/`, `Controllers/`) — never layer names like `Services/`, `Views/`, `Providers/`.

**Rule:** `_Framework` never references `_GameFolders` or any other project folder. `_GameFolders` may reference `_Framework`.

### _Framework Assembly Definition Rules (NON-NEGOTIABLE)

- Every subfolder under `_Framework/` has its **own** `.asmdef` file
- **Never** create a single `.asmdef` at the `_Framework/` root that covers all subfolders
- **Never** delete an existing subfolder `.asmdef` and replace it with a root-level one
- Each `_Framework` assembly references only other `_Framework` assemblies — never `_GameFolders` assemblies

| Subfolder | Assembly name pattern |
|-----------|----------------------|
| `Events/` | `Framework.Events` (or `[Project].Framework.Events`) |
| `Logging/` | `Framework.Logging` |
| `SaveLoadSystems/` | `Framework.SaveLoadSystems` |
| `Editors/` | `Framework.Editor` — `includePlatforms: ["Editor"]` |

---

## Module Structure (NON-NEGOTIABLE)

Every service/system lives in its own folder and contains exactly these files:

```
Audio/
├── IAudioService.cs       ← The only public API contract
├── AudioService.cs        ← sealed implementation
├── AudioConfiguration.cs  ← ScriptableObject config
├── AudioInstaller.cs      ← VContainer registration
└── AudioEvents.cs         ← IEvent structs for this module (if any)
```

Provider implementations live **outside** the module folder:

```
_GameFolders/Scripts/Games/Concretes/Audio/
├── BasicAudioProvider.cs  ← IAudioProvider impl (Unity API here)
└── AudioRoot.cs           ← MonoBehaviour, scene object
```

**Why:** The module folder is portable — copy-paste to another project. Concrete Unity providers are project-specific.

### Module Portability Checklist

Before exporting a module:

| Check | Description |
|-------|-------------|
| `using` dependencies | Only `_Framework` types + own types |
| Cross-module dependencies | None — only interfaces consumed |
| `UnityEngine` import | Not in service class; moved to provider |
| Static service calls | None — constructor injection only |
| Config null guard | Present in `Install()` or `OnValidate` |
| Events in own file | `[Module]Events.cs` — not embedded in service |

---

## VContainer for Dependency Injection

VContainer is the **only** wiring mechanism. No singletons, no static access, no `FindObjectOfType`, no service locator.

### NO GameContext / Service Locator (NON-NEGOTIABLE)

Never create a `GameContext`, `ServiceLocator`, or `Dependencies` class that bundles multiple dependencies into one injectable object. Each class declares only its own dependencies.

```csharp
// BAD — hides real dependencies, breaks least-privilege
public class GameContext
{
    public PlayerModel Player { get; }
    public ScoreSystem Score { get; }
}

// GOOD — each class declares exactly what it needs
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(ScoreModel model) { }
}
```

### Scene Scope Hierarchy

```
AppScope (Bootstrap scene — DontDestroyOnLoad, persistent root)
├── MenuScope  (Menu scene — child of AppScope)
└── GameScope  (Game scene — child of AppScope)
```

- Bootstrap scene opens once (Build index 0), never returns
- `AppScope` registers all global services (Audio, EventBus, SaveLoad…)
- `MenuScope` / `GameScope` register scene-local dependencies
- A scope cannot access sibling scope services — only parent scope

### AppScope Pattern

```csharp
// AppScope.cs — Bootstrap scene (this file never changes)
public sealed class AppScope : LifetimeScope
{
    [SerializeField] private AppInstaller _appInstaller;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<EventBus>(Lifetime.Singleton).As<IEventBus>();

        _appInstaller?.Install(builder);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }
}
```

Adding a new module = create a new `ModuleInstaller` asset → drag into `AppInstaller.asset` Modules list. `AppScope.cs` never changes.

### ModuleInstaller Pattern

```csharp
public class AudioInstaller : ModuleInstaller
{
    [SerializeField] private AudioConfiguration _config;

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
            throw new InvalidOperationException($"{nameof(AudioInstaller)}: _config is not assigned.");

        builder.RegisterInstance(_config);
        builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>();
    }
}
```

### Interface-First Registration

```csharp
// GOOD
builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>();

// BAD — concrete dependency
builder.Register<AudioService>(Lifetime.Singleton);
```

---

## IEvent System for Communication

`IEventBus` is the **only** cross-system communication channel. No C# static events, no UnityEvents, no direct cross-module calls.

```csharp
// Define events as readonly structs — zero allocation
public struct LevelStartedEvent : IEvent { }

public struct CoinsChangedEvent : IEvent
{
    public readonly int NewAmount;
    public CoinsChangedEvent(int amount) => NewAmount = amount;
}

// Publishing
_eventBus.Publish(new LevelStartedEvent());

// Subscribing — in Initialize(), unsubscribe in Dispose()
public void Initialize()
{
    _eventBus.Subscribe<LevelStartedEvent>(OnLevelStarted);
}

public void Dispose()
{
    _eventBus.Unsubscribe<LevelStartedEvent>(OnLevelStarted);
}
```

### Subscribe / Unsubscribe Rules

| Class type | Subscribe | Unsubscribe |
|-----------|-----------|-------------|
| Plain C# (`IInitializable`, `IDisposable`) | `Initialize()` | `Dispose()` |
| MonoBehaviour — registered via `RegisterComponent` | `Initialize()` | `Dispose()` |
| MonoBehaviour — can be enabled/disabled | `OnEnable()` | `OnDisable()` |

Never unsubscribe in `OnDestroy()` for VContainer-managed types — conflicts with VContainer lifecycle.

---

## Provider Pattern

Domain services never touch Unity API. Unity calls stay at the provider boundary:

```csharp
// Domain service — pure C#, no UnityEngine import
public sealed class AudioService : IAudioService
{
    private readonly IAudioProvider _provider;
    public AudioService(IAudioProvider provider) => _provider = provider;
    public void PlaySound(string id) => _provider.Play(id);
}

// Provider — Unity API lives here
public sealed class BasicAudioProvider : IAudioProvider
{
    private readonly AudioSource _source;
    public void Play(string id) => _source.PlayOneShot(GetClip(id));
}
```

---

## Input System Architecture (NON-NEGOTIABLE)

Input is a View-layer concern. InputView reads raw input and calls Services. Services never touch Unity Input directly.

```csharp
public sealed class InputView : MonoBehaviour
{
    private PlayerControls _controls;
    private IPlayerService _playerService;

    private void Awake() => _controls = new PlayerControls();

    [Inject]
    public void Construct(IPlayerService playerService) => _playerService = playerService;

    private void OnEnable()
    {
        _controls.Player.Enable();
        _controls.Player.Jump.performed += OnJump;
    }

    private void OnDisable()
    {
        _controls.Player.Jump.performed -= OnJump;
        _controls.Player.Disable();
    }

    private void Update()
    {
        _playerService.SetMoveInput(_controls.Player.Move.ReadValue<Vector2>());
    }

    private void OnJump(InputAction.CallbackContext ctx) => _playerService.Jump();
}
```

**Rules:**
- InputView owns `PlayerControls` — no other class creates one
- Enable in `OnEnable`, disable + unsubscribe in `OnDisable` (mandatory)
- Continuous input (`ReadValue`) in `Update`, cached for physics in `FixedUpdate`
- Discrete input (button press) via `performed` callbacks
- Services are input-agnostic — they expose `SetMoveInput(Vector2)`, `Jump()`, etc.
- Legacy `Input.GetKey` / `Input.GetAxis` is BLOCKED

---

## ScriptableObjects for Config

All configuration data as ScriptableObjects. Runtime mutable state stays in service/model classes.

```csharp
[CreateAssetMenu(menuName = "Game/Audio Configuration")]
public sealed class AudioConfiguration : ScriptableObject
{
    [SerializeField] private float _masterVolume = 1f;
    [SerializeField] private float _sfxVolume = 1f;
    public float MasterVolume => _masterVolume;
    public float SfxVolume => _sfxVolume;
}
```

---

## No Singletons

VContainer replaces all singleton patterns.

- App-wide → register in `AppScope`
- Per-scene → register in `MenuScope` / `GameScope`
- No `Instance`, no `static` mutable state, no `FindObjectOfType`

---

## EventBusAccessor — ECS ↔ Mono Static Bridge (APPROVED EXCEPTION)

ECS systems (`ISystem`, `SystemBase`) cannot receive VContainer injection. The only approved static accessor is `EventBusAccessor` in `_Framework/Events/`.

```csharp
// _Framework/Events/EventBusAccessor.cs — pure C#, no UnityEngine
public static class EventBusAccessor
{
    private static IEventBus _instance;
    public static IEventBus Instance => _instance
        ?? throw new InvalidOperationException("EventBusAccessor not initialized. Call Initialize() in AppScope.");

    public static void Initialize(IEventBus bus) => _instance = bus;
}
```

```csharp
// AppScope.cs — initialize the accessor after VContainer resolves
protected override void Configure(IContainerBuilder builder)
{
    // ... other registrations
    builder.RegisterBuildCallback(container =>
    {
        EventBusAccessor.Initialize(container.Resolve<IEventBus>());
    });
}
```

```csharp
// ECS System — uses static accessor
public partial class EnemyDeathSystem : SystemBase
{
    protected override void OnUpdate()
    {
        // VContainer injection not available here — accessor is the bridge
        EventBusAccessor.Instance.Publish(new EnemyDiedEvent { ... });
    }
}
```

**Rules:**
- Only `EventBusAccessor` is an approved static accessor — no new ones without explicit design decision
- `EventBusAccessor` lives in `_Framework/Events/` — pure C#, no UnityEngine import
- MonoBehaviours and services always receive `IEventBus` via VContainer constructor injection
- ECS systems use `EventBusAccessor.Instance` directly
- `check-vcontainer-singleton.sh` hook blocks all other static singleton patterns
