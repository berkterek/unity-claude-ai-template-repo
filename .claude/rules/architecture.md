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
// AudioModule.cs
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

**GOTCHA:** If your service has `using UnityEngine`, you're leaking Unity API through the service layer. Move it to a Provider. Do NOT open a Provider for prefab-local Unity access — that is Handler's job (Tier 2).

---

### Card 2.1: Swappable Backend Pattern — Same Shape, Suffix by Domain

**WHEN:** A Service's job is inherently "call some external mechanism to do X" (load a scene, persist data, call a remote API) and more than one mechanism plausibly does it (SceneManager vs. Addressables; local JSON vs. cloud save; REST vs. gRPC).

This is Card 2 generalized beyond Unity API — the backend isn't always `UnityEngine`, but the shape is identical: Service (Tier 3, pure C#) depends on an interface; each mechanism is a separate implementation the Service never references by concrete type.

**WRONG:**
```csharp
// Backend mechanism hardcoded inside the service — swapping local↔cloud save means rewriting SaveLoadService
public sealed class SaveLoadService : ISaveLoadService
{
    public void Save(PlayerSaveData data) => File.WriteAllText(Application.persistentDataPath + "/save.json", JsonUtility.ToJson(data));
}
```

**RIGHT:**
```csharp
// Game.Abstracts.SaveLoad/ISaveLoadDal.cs — Tier 4 contract, one per backend mechanism
public interface ISaveLoadDal
{
    void Write(string key, string json);
    string Read(string key);
}

// Game.Concretes.SaveLoad/LocalSaveLoadDal.cs — Tier 4, file-system backend
public sealed class LocalSaveLoadDal : ISaveLoadDal
{
    public void Write(string key, string json) => File.WriteAllText(PathFor(key), json);
    public string Read(string key) => File.Exists(PathFor(key)) ? File.ReadAllText(PathFor(key)) : null;
    private static string PathFor(string key) => Path.Combine(Application.persistentDataPath, key + ".json");
}

// Game.Concretes.SaveLoad/SaveLoadService.cs — Tier 3, pure C#, never touches File/JsonUtility directly
public sealed class SaveLoadService : ISaveLoadService
{
    private readonly ISaveLoadDal _dal;
    public SaveLoadService(ISaveLoadDal dal) => _dal = dal;
    public void Save(PlayerSaveData data) => _dal.Write("save", JsonUtility.ToJson(data));
}
```

**Suffix by domain — pick the name that says what the backend actually does, don't force one suffix everywhere:**

| Domain | Backend interface suffix | Example |
|---|---|---|
| Scene loading | `*Loader` | `ISceneLoader` → `NormalSceneLoader`, `AddressableSceneLoader` |
| Data persistence | `*Dal` (Data Access Layer) | `ISaveLoadDal` → `LocalSaveLoadDal`, `CloudSaveLoadDal` |
| Unity API wrapping | `*Provider` | `IAudioProvider` → `BasicAudioProvider` |
| Remote/external service call | `*Client` | `IAnalyticsClient` → `FirebaseAnalyticsClient` |

**GOTCHA:** The Service class name and its public API never change when a new backend is added — that is the test of whether this pattern was applied correctly. If adding `CloudSaveLoadDal` requires touching `SaveLoadService`, the DIP boundary is in the wrong place. Do not invent a new suffix per module out of habit — check this table first; only add a new row when none of the four existing meanings fit.

**Two backends both active at once (different data categories) — split into two Service+Backend pairs, never a keyed factory:**

**WHEN:** Some data always goes to one backend and other data always goes to another (e.g. settings → local, player progress → cloud) — the choice is known statically by what is being saved, not decided at runtime per call.

**WRONG:**
```csharp
// Factory keyed by a string/enum — SaveLoadService now branches on backend type internally
public sealed class SaveLoadService : ISaveLoadService
{
    private readonly Func<SaveTarget, ISaveLoadDal> _dalFactory;
    public void Save(SaveTarget target, string key, string json) => _dalFactory(target).Write(key, json); // OCP violation: adding a 3rd target means a 3rd factory case
}
```

**RIGHT:**
```csharp
// Two independent domains — each with its own Service + Dal pair, per Card 2.1's normal shape
Game.Abstracts.SaveLoad/ILocalSaveLoadService.cs  → Game.Abstracts.SaveLoad/ILocalSaveLoadDal.cs  → LocalSaveLoadDal
Game.Abstracts.SaveLoad/ICloudSaveLoadService.cs  → Game.Abstracts.SaveLoad/ICloudSaveLoadDal.cs  → FirestoreSaveLoadDal

// Callers inject exactly the one they need — the choice already happened at the injection site
public sealed class SettingsController : MonoBehaviour
{
    [Inject] public void Construct(ILocalSaveLoadService localSave) { /* settings are always local */ }
}
public sealed class ProgressService : IProgressService
{
    public ProgressService(ICloudSaveLoadService cloudSave) { /* progress is always cloud */ } // constructor injection — Tier 3 service
}
```

**GOTCHA:** A factory keyed by category (`"local"`/`"cloud"`, or an enum) just moves the `if/switch` from outside the service to inside it — still an OCP violation, still couples the service to every backend it might route to. Two separate interface pairs mean adding a third category (e.g. `ISessionCacheService`) is a new pair, not a new branch anywhere.

**Same data, runtime-routed to one or the other (e.g. online/offline sync) — Composite Dal, not a factory:**

If the same save call must go to Local **and conditionally** Cloud based on runtime state (connectivity), wrap both behind a third `ISaveLoadDal` implementation instead of asking the Service to choose:

```csharp
public sealed class SyncingSaveLoadDal : ISaveLoadDal
{
    private readonly LocalSaveLoadDal _local;
    private readonly FirestoreSaveLoadDal _cloud;
    private readonly IConnectivityProvider _connectivity;

    public void Write(string key, string json)
    {
        _local.Write(key, json);                         // always write local first — offline-safe
        if (_connectivity.IsOnline) _cloud.Write(key, json); // best-effort cloud sync
    }
}
```

`SaveLoadService` still depends on a single `ISaveLoadDal` and never learns that syncing happens — the routing logic lives entirely inside the Dal implementation, not in a factory the Service calls into.

---

### Card 3: Module → Static Install Method → AppModules → AppScope

**WHEN:** Adding a new feature module (Audio, Score, Shop, etc.).

**WRONG:** Registering directly in `AppScope.Configure()`, creating ScriptableObject installer assets, or scattering registrations across multiple places.

**RIGHT:**
```
[X]Module.Install() → AppModules.Install() → AppScope calls AppModules
```

```csharp
// One new line in AppModules.cs — no Editor asset work
AudioModule.Install(builder, configs.Audio);
```

**GOTCHA:** `AppScope.cs` never changes. Add modules by adding one line to `AppModules.Install()`. There are no ScriptableObject installer assets, no `_modules` list, no Editor drag-and-drop for wiring modules.

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

### Card 5: One-Caller Rule — Postpone MODULE Ceremony, Never Postpone the Interface

**WHEN:** Tempted to create a full module registration ceremony for a single caller.

**WRONG:**
```csharp
// Creating an entire AudioModule with installer just for one sound effect in one class
// — the module ceremony overhead is unjustified for a single caller
```

**RIGHT:** Register the handler or helper directly in the parent module's `Install()` without creating a separate module file for it.

**GOTCHA:** This rule postpones **module + installer ceremony** — it does NOT postpone interfaces. Every injectable layer (Handler, Service, Provider) always gets an interface. The test is a caller. Interface with a single production caller is correct and expected: `IMoveHandler` with only `PlayerController` as caller is not over-engineering — the test suite is the second caller.

---

### Card 6: Same Prefab Hierarchy — SerializeField + Handler, Not VContainer

**WHEN:** A script needs a reference to a component on the same GameObject, a child, or any GameObject within the same prefab.

**WRONG:**
```csharp
// Injecting a co-located component through VContainer — unnecessary overhead
public sealed class PlayerController : MonoBehaviour
{
    private IPlayerProvider _provider;

    [Inject]
    public void Construct(IPlayerProvider provider) => _provider = provider;
}
// PlayerModule: builder.RegisterComponent(_playerProvider).As<IPlayerProvider>();
```

**RIGHT — Pattern A: Handler needs no container dependencies (plain new):**
```csharp
public sealed class PlayerController : MonoBehaviour
{
    #region Fields

    [SerializeField] private Rigidbody        _rigidbody;
    [SerializeField] private MoveConfiguration _moveConfig;

    private IMoveHandler _moveHandler;

    #endregion

    #region Lifecycle

    private void Awake()
    {
        // Plain new — no container dependencies needed
        _moveHandler = new MoveHandler(_rigidbody, _moveConfig);
    }

    private void Update()
    {
        _moveHandler.Tick(Time.deltaTime);
    }

    #endregion
}
```

**RIGHT — Pattern B: Handler needs a container dependency (Func factory):**
```csharp
public sealed class PlayerController : MonoBehaviour
{
    #region Fields

    [SerializeField] private Rigidbody _rigidbody;

    private IMoveHandler _moveHandler;

    #endregion

    #region Lifecycle

    [Inject]
    public void Construct(Func<Rigidbody, IMoveHandler> moveFactory)
    {
        _moveHandler = moveFactory(_rigidbody);
    }

    private void Update() => _moveHandler.Tick(Time.deltaTime);

    #endregion
}
```

Use Pattern A when the handler only needs prefab-local references (`[SerializeField]` fields). Use Pattern B when the handler also needs a container-registered dependency (IEventBus, a configuration SO from ConfigCatalog, etc.).

**GOTCHA:** VContainer injection is for **cross-module boundaries**. Everything inside the same prefab (root, children, grandchildren) wires via `[SerializeField]`. Handlers are pure C# — never registered with VContainer directly; the Controller creates them.

**Boundary rule:**

| Relationship | Wire with |
|---|---|
| Same GameObject | `[SerializeField]` drag-drop |
| Child or grandchild within the same prefab | `[SerializeField]` drag-drop |
| Handler (prefab-local logic, pure C#) | `new` in Awake OR `Func<>` factory inject |
| Different prefab / different module | VContainer injection (interface) |
| Cross-scene / global service | VContainer injection (AppScope) |

---

### Card 7: GameScope vs Module Boundary

**WHEN:** Deciding where to put a registration in the scene-specific scope.

**WRONG:**
```csharp
// GameScope doing service wiring (belongs in a Module)
builder.Register<PlayerService>(Lifetime.Singleton);
```

**RIGHT:**
```csharp
// GameScope registers scene components only
builder.RegisterComponent(_playerView);    // scene MonoBehaviour
// Service wiring → PlayerModule.Install() via AppModules
```

**GOTCHA:** If the registration doesn't reference a scene object (`RegisterComponent`), it belongs in a module's `Install()` method, not `GameScope`.

---

## Core Principle: Dependency Direction

```
Tier 1 (Mono Shell: Controller/View) → Tier 2 (Handler) → Tier 3 (Service + EntryPoint)
                                                                    ↓
                                                               IEventBus
                                                                    ↓
                                                          Tier 4 (Provider)
```

- Services depend on interfaces, never concrete types
- Mono shells (Controller/View) depend on services via VContainer injection and on Handlers via direct `new` or `Func<>` factory
- Cross-service communication goes through IEventBus, never direct references
- Assembly definitions enforce direction at compile time

> Full tier definitions and rules: see `rules/solid-oop.md` → 4-Tier Architecture

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

Every feature module spans two folders — one for the portable domain layer, one for Unity-specific providers:

```
_GameFolders/Scripts/Games/Abstracts/Audio/
├── IAudioService.cs           ← service contract (interface only)
└── IAudioProvider.cs          ← provider contract (interface only)

_GameFolders/Scripts/Games/Abstracts/Players/
├── IPlayerService.cs          ← service contract
└── IMoveHandler.cs            ← handler contract (NEW — pure C# NSubstitute seam)

_GameFolders/Scripts/Games/Concretes/Audio/
├── AudioService.cs            ← sealed service (Tier 3)
├── AudioConfiguration.cs      ← ScriptableObject config
├── AudioModule.cs             ← static install method (replaces AudioInstaller SO)
├── AudioEvents.cs             ← IEvent structs for this module (if any)
└── BasicAudioProvider.cs      ← IAudioProvider impl — Unity API here (Tier 4)

_GameFolders/Scripts/Games/Concretes/Players/
├── PlayerController.cs        ← Mono shell, Tier 1
├── MoveHandler.cs             ← pure C# handler, Tier 2
├── PlayerService.cs           ← sealed service, Tier 3
├── PlayerConfiguration.cs     ← ScriptableObject config
├── PlayerModule.cs            ← static install method
└── PlayerEvents.cs            ← IEvent structs
```

**`[Module]Events.cs` must live inside `Concretes/<Domain>/`. NEVER outside `Concretes/` — do not create a top-level `Scripts/Games/Events/` or `Scripts/Events/` folder.**

**Why:** Interfaces live in `Abstracts/` so other modules depend on contracts, not implementations. Everything else — service, handler, config, module installer, events, and Unity providers — belongs in the same `Concretes/<Domain>/` folder.

### Module Portability Checklist

Before exporting a module:

| Check | Description |
|-------|-------------|
| `using` dependencies | Only `_Framework` types + own types |
| Cross-module dependencies | None — only interfaces consumed |
| `UnityEngine` import | Not in service class; moved to provider |
| Static service calls | None — constructor injection only |
| Config null guard | Present in `Install()` |
| Events in own file | `[Module]Events.cs` — not embedded in service |
| Handler interface | `I[X]Handler` in `Abstracts/<Domain>/` |

---

## VContainer for Dependency Injection

VContainer is the **only** wiring mechanism. No singletons, no static access, no `FindObjectOfType`, no service locator.

### Code-First Static Module Pattern (NON-NEGOTIABLE)

Modules are registered via static `Install()` methods — no ScriptableObject installer assets, no `ModuleInstaller` subclasses, no `AppInstaller.asset`.

```csharp
// Game/Concretes/Audio/AudioModule.cs — pure C# static class
namespace Game.Concretes.Audio
{
    public static class AudioModule
    {
        public static void Install(IContainerBuilder builder, AudioConfiguration config)
        {
            if (config == null)
            {
                Debug.LogError("[AudioModule] AudioConfiguration missing.");
                return;
            }

            builder.RegisterInstance(config);
            builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
        }
    }
}

// Game/Concretes/Infrastructure/AppModules.cs — single wiring point
namespace Game.Concretes.Infrastructure
{
    public static class AppModules
    {
        public static void Install(IContainerBuilder builder, ConfigCatalog configs)
        {
            EventBusModule.Install(builder);                     // FIRST — structural guarantee
            AudioModule.Install(builder, configs.Audio);
            PlayerModule.Install(builder, configs.Player);
            // New module = one line here — visible in git diff, hookable
        }
    }
}
```

Adding a new module: add one static class with `Install()` and one call line in `AppModules`. No Editor asset work. `EventBusModule` is always first — enforced by code position, not convention.

### AppScope — Uses AppModules (NON-NEGOTIABLE)

```csharp
// Game/Concretes/Infrastructure/AppScope.cs
namespace Game.Concretes.Infrastructure
{
    public sealed class AppScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private ConfigCatalog _configCatalog;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_configCatalog == null)
            {
                Debug.LogError("[AppScope] ConfigCatalog missing.");
                return;
            }

            builder.RegisterInstance(_configCatalog);
            builder.RegisterComponentInHierarchy<UIRoot>();

            AppModules.Install(builder, _configCatalog);

            builder.RegisterBuildCallback(c =>
                EventBusAccessor.Initialize(c.Resolve<IEventBus>()));
        }

        #endregion
    }
}
```

`AppScope.cs` **never changes** — to add a module, add one line to `AppModules.Install()`.

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

### Avoid One-Caller Overfitting — When NOT to Create a Separate Module

Do NOT create a new module file and wiring ceremony just because one production caller exists. Overfitting produces unnecessary boilerplate.

**Create a separate module only when:**
- At least 2 independent production callers exist, OR
- The service has its own lifecycle (async setup, pooling, Dispose), OR
- A provider is needed to hide Unity API behind a pure C# boundary

**The one-caller rule does NOT apply to interfaces.** Every injectable layer (Handler, Service, Provider) always gets an interface — the test suite is the second caller, always. Delaying the interface prevents TDD and NSubstitute seam creation.

```csharp
// BAD — creating a full ScoreDisplayModule for a helper used by one class
// (module ceremony is unjustified; register directly in ScoreModule.Install())
public static class ScoreDisplayModule
{
    public static void Install(IContainerBuilder builder) { /* one line */ }
}

// GOOD — register the helper directly in the parent module
public static class ScoreModule
{
    public static void Install(IContainerBuilder builder, ScoreConfiguration config)
    {
        builder.Register<ScoreService>(Lifetime.Singleton).AsImplementedInterfaces();
        builder.Register<ScoreDisplayHelper>(Lifetime.Singleton).AsImplementedInterfaces(); // one caller — no separate module needed
    }
}
```

**Rule: Postpone module ceremony. Never postpone the interface.**

---

### Handler Factory — VContainer Func<> Pattern

When a Handler needs a container dependency (IEventBus, config SO), register a factory so the Controller can receive it:

```csharp
// In PlayerModule.Install():
builder.RegisterFactory<Rigidbody, IMoveHandler>(
    container => rigidbody =>
        new MoveHandler(rigidbody, container.Resolve<MoveConfiguration>()),
    Lifetime.Singleton  // singleton = one factory delegate; each call produces a new handler instance
);

// In PlayerController — receives the factory via [Inject]:
[Inject]
public void Construct(Func<Rigidbody, IMoveHandler> moveFactory)
{
    _moveHandler = moveFactory(_rigidbody);
}
```

If the Handler needs **no** container dependencies, use plain `new` in Awake — no factory needed. Forcing a factory on every Handler reintroduces installer ceremony.

---

### EntryPoint — ITickable for Pure C# Update

When a pure C# service needs a frame update, use `ITickable`. "I need Update" is never a reason to make something a MonoBehaviour.

```csharp
// Game/Concretes/Waves/WaveDirectorService.cs
namespace Game.Concretes.Waves
{
    public sealed class WaveDirectorService : IWaveDirectorService, ITickable, IInitializable, IDisposable
    {
        #region Fields

        private readonly IEventBus _eventBus;
        private CancellationTokenSource _cts;

        #endregion

        #region Constructor

        public WaveDirectorService(IEventBus eventBus)
        {
            _eventBus = eventBus;
        }

        #endregion

        #region Lifecycle

        public void Initialize()
        {
            _cts = new CancellationTokenSource();
        }

        // VContainer calls every frame — no MonoBehaviour needed
        public void Tick()
        {
            /* wave progression logic */
        }

        public void Dispose()
        {
            _cts?.Cancel();
            _cts?.Dispose();
        }

        #endregion
    }
}

// In WaveModule.Install():
builder.RegisterEntryPoint<WaveDirectorService>().AsImplementedInterfaces();
```

| Interface | Called by VContainer | Replaces |
|---|---|---|
| `ITickable` | Every frame (Update equivalent) | `MonoBehaviour.Update` |
| `IFixedTickable` | Every fixed frame (FixedUpdate) | `MonoBehaviour.FixedUpdate` |
| `IStartable` | Once on scope start | `MonoBehaviour.Start` |
| `IAsyncStartable` | Once on scope start (async) | Async `MonoBehaviour.Start` |

Use `RegisterEntryPoint<T>()` — this wires lifecycle interfaces automatically.

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

### GameScope — Scene Component Registration Only

`GameScope` registers MonoBehaviours that are present in the scene and need to be injected across the module boundary. It does NOT wire services or factories.

```csharp
// GOOD — GameScope registers scene components only
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerView);   // scene object
    builder.RegisterComponent(_uiRoot);       // scene object
    // Service wiring is in PlayerModule, BattleModule (via AppModules)
}

// BAD — GameScope doing service wiring
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerView);
    builder.Register<PlayerService>(Lifetime.Singleton);       // belongs in PlayerModule
    builder.Register<BattleOrchestrator>(Lifetime.Singleton);  // belongs in BattleModule
}
```

| Task | Location | Why |
|------|----------|-----|
| Register a scene-local MonoBehaviour | `GameScope` | Tied to scene hierarchy |
| Wire services and factories | Module `Install()` | Reusable, testable, scene-independent |
| Conditional setup (difficulty, feature flags) | Module `Install()` | Co-located with the module it configures |
| Register a provider that depends on a scene object | `GameScope` via `RegisterComponent` | Scene ref required |

**Rule: If the wiring logic does not directly reference a scene object, it belongs in a module's `Install()` method.**

### Interface-First Registration

```csharp
// GOOD
builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();

// BAD — concrete dependency leaks through the container
builder.Register<AudioService>(Lifetime.Singleton);
```

Handler interfaces (`IMoveHandler`) follow the same rule — always interface-first for the NSubstitute seam. Handlers are NOT registered with VContainer directly; they are created by the Controller via `new` or `Func<>` factory.

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
| MonoBehaviour — runtime instantiated (Instantiate, not VContainer-registered) | `OnEnable()` | `OnDisable()` |

Never unsubscribe in `OnDestroy()` for VContainer-managed types — conflicts with VContainer lifecycle.

> **Dynamic instances:** MonoBehaviours created via `Instantiate()` are not registered with VContainer and have no `Initialize()`/`Dispose()` lifecycle. Use `OnEnable()`/`OnDisable()` — `OnDisable` is called before `OnDestroy`, so unsubscribing there is safe. Do NOT rely solely on `OnDestroy()` for IEventBus unsubscription.

> See also: `rules/event-patterns.md` → Decision Tree, Pattern 1 (IEventBus), Pattern 4 (UGUI Button)

---

## Provider Pattern

Domain services never touch Unity API. Unity calls stay at the Provider boundary (Tier 4):

```csharp
// Domain service — pure C#, no UnityEngine import (Tier 3)
public sealed class AudioService : IAudioService
{
    private readonly IAudioProvider _provider;
    public AudioService(IAudioProvider provider) => _provider = provider;
    public void PlaySound(string id) => _provider.Play(id);
}

// Provider — Unity API lives here (Tier 4)
public sealed class BasicAudioProvider : MonoBehaviour, IAudioProvider
{
    [SerializeField] private AudioSource _source;
    public void Play(AudioClip clip) => _source.PlayOneShot(clip);
}
```

Do NOT open a Provider for prefab-local Unity access — that is Handler's job. Provider is the cross-module Unity API boundary.

> See also: `rules/solid-oop.md` → 4-Tier Architecture

---

## Input System Architecture

Input is handled via an `InputService` (pure C#, `ITickable`) paired with per-prefab `InputHandler` classes. Services never touch Unity Input directly.

> See `rules/unity-input.md` for the full `InputView` pattern, generated C# class usage, action map switching, and enforcement rules.

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

- App-wide → register in `AppScope` (via `AppModules`)
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
