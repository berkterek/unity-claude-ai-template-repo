# Architecture Rules

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: No Singletons

**WHEN:** Writing or refactoring any service that needs to be accessed from multiple call sites.

**WRONG:**
```csharp
public class AudioService : MonoBehaviour
{
    public static AudioService Instance { get; private set; }
    private void Awake() => Instance = this;
}
```

**RIGHT:**
```csharp
public interface IAudioService { void PlaySound(string id); }
public sealed class AudioService : IAudioService { /* ... */ }
// AudioInstaller.cs
builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
```

**GOTCHA:** `FindObjectOfType<AudioService>()` is a singleton in disguise — equally forbidden. Always resolve through constructor injection.

---

### Card 2: Provider Pattern for Unity API

**WHEN:** A service needs to call Unity API (Physics, AudioSource, Transform, Screen, etc.).

**WRONG:**
```csharp
public sealed class AudioService : IAudioService
{
    public void Play(string id) => AudioSource.PlayClipAtPoint(clip, Vector3.zero); // Unity API in service
}
```

**RIGHT:**
```csharp
public sealed class AudioService : IAudioService
{
    private readonly IAudioProvider _provider;
    public void Play(string id) => _provider.Play(id);
}
public sealed class BasicAudioProvider : MonoBehaviour, IAudioProvider
{
    [SerializeField] private AudioSource _source;
    public void Play(AudioClip clip) => _source.PlayOneShot(clip);
}
```

**GOTCHA:** If your service has `using UnityEngine`, you're leaking Unity API through the service layer. Move it to a Provider.

---

### Card 3: Module → Service → Installer → Scope Chain

**WHEN:** Adding a new feature module (Audio, Score, Shop, etc.).

**WRONG:** Registering directly in `AppScope.Configure()` or scattering registrations across multiple places.

**RIGHT:**
```
[Module]Installer (sealed SO) → AppInstaller._modules list → AppScope calls AppInstaller
```

**GOTCHA:** `AppScope.cs` never changes — add modules exclusively via `AppInstaller.asset`. Touching AppScope for every new module breaks the open/closed pattern.

---

### Card 4: EventBus Crosses Modules; Action Stays Local

**WHEN:** Deciding how two systems should communicate.

**WRONG:**
```csharp
// direct reference across modules
_scoreService.OnScoreChanged += UpdateUI; // tight coupling
```

**RIGHT:**
```csharp
// cross-module → IEventBus
_eventBus.Subscribe<ScoreChangedEvent>(OnScoreChanged);
// one-time callback → System.Action parameter
// internal module notification → C# event keyword
```

**GOTCHA:** `UnityEvent` is forbidden entirely — not a valid choice in this decision tree.

---

### Card 5: One-Caller Rule — Don't Abstract Too Early

**WHEN:** Tempted to create a new interface/module for a single caller.

**WRONG:**
```csharp
public interface IScoreDisplayService { void Display(int score); }
// Only ScoreView ever calls this — premature abstraction
```

**RIGHT:** Inject the concrete `ScoreModel` directly into `ScoreView` until a second caller exists.

**GOTCHA:** Interface with ≤1 method AND ≤1 caller AND no real lifecycle = over-engineering. Add the interface only when a second caller arrives.

---

### Card 6: Same-GameObject Scripts — No VContainer Needed

**WHEN:** Two scripts sit on the same GameObject (or parent-child within the same prefab).

**WRONG:**
```csharp
// Injecting a co-located component through VContainer
public sealed class PlayerController : MonoBehaviour
{
    private IPlayerProvider _provider;

    [Inject]
    public void Construct(IPlayerProvider provider) => _provider = provider;
}
// PlayerInstaller: builder.RegisterComponent(_playerProvider).As<IPlayerProvider>();
```

**RIGHT:**
```csharp
public sealed class PlayerController : MonoBehaviour
{
    [SerializeField] private PlayerProvider _provider; // drag-drop in Inspector
}
```

**GOTCHA:** VContainer injection is for **cross-module boundaries** — different prefabs, different scenes, different lifetimes. Scripts on the same prefab know each other by design; using `[SerializeField]` is explicit, zero-cost, and Inspector-visible.

**Boundary rule:**

| Relationship | Wire with |
|---|---|
| Same GameObject or same prefab hierarchy | `[SerializeField]` drag-drop |
| Different prefab / different module | VContainer injection (interface) |
| Cross-scene / global service | VContainer injection (AppScope) |

---

### Card 7: GameScope vs ModuleInstaller Boundary

**WHEN:** Deciding where to put a registration in the scene-specific scope.

**WRONG:**
```csharp
// GameScope doing service wiring (belongs in ModuleInstaller)
builder.Register<PlayerService>(Lifetime.Singleton);
```

**RIGHT:**
```csharp
// GameScope registers scene components only
builder.RegisterComponent(_playerView);    // scene MonoBehaviour
// Service wiring → PlayerInstaller via AppInstaller.asset
```

**GOTCHA:** If the registration doesn't reference a scene object (`RegisterComponent`), it belongs in a `ModuleInstaller`, not `GameScope`.

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

Every service/system spans two folders — one for the portable domain layer, one for Unity-specific providers:

```
_GameFolders/Scripts/Games/Abstracts/Audio/
└── IAudioService.cs           ← The only public API contract (interface only)

_GameFolders/Scripts/Games/Concretes/Audio/
├── AudioService.cs            ← sealed implementation
├── AudioConfiguration.cs      ← ScriptableObject config
├── AudioInstaller.cs          ← VContainer registration
├── AudioEvents.cs             ← IEvent structs for this module (if any)
├── BasicAudioProvider.cs      ← IAudioProvider impl (Unity API here)
└── AudioRoot.cs               ← MonoBehaviour, scene object
```

**`AudioEvents.cs` must live inside `Concretes/<Domain>/` (or a subfolder within it). NEVER outside `Concretes/` — do not create a top-level `Scripts/Games/Events/` or `Scripts/Events/` folder.**

**Why:** The interface lives in `Abstracts/` so other modules depend on the contract, not the implementation. Everything else — service, config, installer, events, and Unity providers — belongs in the same `Concretes/<Domain>/` folder. Splitting events into a sub-subfolder (`Concretes/Audio/Events/`) adds unnecessary nesting with no benefit.

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

### Avoid One-Caller Overfitting — When NOT to Create a Module

Do NOT create a new module, interface, or installer just because one caller exists. Overfitting produces unnecessary boilerplate and makes the codebase harder to navigate.

**Create a module/interface only when:**
- At least 2 independent callers exist, OR
- The service has its own lifecycle (async setup, pooling, Dispose), OR
- A provider is needed to hide Unity API behind a pure C# boundary

**Red flags for premature abstraction:**
- Interface has ≤1 public method
- Only one caller in the entire codebase
- Implementation has ≤1 meaningful line of code
- No real decoupling — the interface is only a constructor parameter alias

```csharp
// BAD — IScoreDisplayService used only by ScoreView, wraps one Debug.Log
public interface IScoreDisplayService { void Display(int score); }
public sealed class ScoreDisplayService : IScoreDisplayService
{
    public void Display(int score) => Debug.Log($"Score: {score}");
}

// GOOD — ScoreView injects ScoreModel directly; no intermediate service needed
// Note: injecting the concrete ScoreModel here is intentional — the point of this rule
// is that no interface wrapper is needed when only one caller exists. If ScoreModel were
// shared across modules, IAudioService-style interface-first registration would apply.
public sealed class ScoreView : MonoBehaviour
{
    private ScoreModel _model;

    [Inject]
    public void Construct(ScoreModel model) => _model = model;

    private void OnEnable()  => _model.OnScoreChanged += Display;
    private void OnDisable() => _model.OnScoreChanged -= Display;
    private void Display(int score) => _scoreLabel.text = score.ToString();
}
```

**Rule: Make it concrete. Add the interface only when a second caller arrives or a real boundary is needed.**

---

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

### AppScope / GameScope / ModuleInstaller Patterns

> Full patterns, code examples, and rules: see `bootstrap-pattern.md`.

Key points:
- `AppScope.cs` never changes — add modules via `AppInstaller.asset`
- `GameScope` uses only `builder.RegisterComponent(...)` with `[SerializeField]` scene refs
- `ModuleInstaller` subclasses register a single module's dependencies

### GameScope Wiring: Complex Orchestration Belongs in ModuleInstaller

`GameScope` is for scene-specific registration only: binding scene components to their interfaces via `RegisterComponent`. Complex orchestration — service wiring, factory setup, conditional dependencies — belongs in `ModuleInstaller` subclasses.

| Task | Location | Why |
|------|----------|-----|
| Register a scene-local MonoBehaviour | `GameScope` | Tied to scene hierarchy |
| Wire services and factories | `ModuleInstaller` | Reusable, testable, scene-independent |
| Conditional setup (difficulty, feature flags) | `ModuleInstaller` | Co-located with the module it configures |
| Register a provider that depends on a scene object | `GameScope` via `RegisterComponent` | Scene ref required |

```csharp
// BAD — GameScope doing orchestration
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerView);
    builder.Register<PlayerService>(Lifetime.Singleton);           // ← belongs in PlayerInstaller
    builder.Register<BattleOrchestrator>(Lifetime.Singleton);     // ← belongs in BattleInstaller
}

// GOOD — GameScope registers scene components only
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerView);   // scene object
    builder.RegisterComponent(_uiRoot);       // scene object
    // Service wiring is in PlayerInstaller, BattleInstaller (via AppInstaller.asset)
}
```

**Rule: If the wiring logic does not directly reference a scene object, it belongs in a `ModuleInstaller`.**

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
