---
name: vcontainer
description: VContainer dependency injection setup, registration patterns, scope hierarchy, and diagnosis for Unity projects. Use when wiring dependencies, debugging DI failures, or designing scope structure.

user-invocable: true
model-tier: normal
---

# VContainer — Setup & Usage Guide

## What VContainer Does

VContainer is a fast, zero-allocation dependency injection container for Unity. It replaces singletons, static accessors, and `FindObjectOfType` with explicit constructor injection wired at scope boundaries.

---

## Scope Hierarchy

```
AppScope (Bootstrap scene — DontDestroyOnLoad)
├── MenuScope  (Menu scene — child of AppScope)
└── GameScope  (Game scene — child of AppScope)
```

- Bootstrap scene (Build index 0) loads once and never unloads
- `AppScope` registers global services (Audio, EventBus, SaveLoad, etc.)
- Child scopes resolve from parent — `GameScope` can use `IAudioService` registered in `AppScope`
- Sibling scopes are isolated — `MenuScope` cannot access `GameScope` registrations
- A scope disposes all its registrations when the scene unloads

---

## AppScope Pattern

`AppScope.cs` never changes. Add new modules by creating a `ModuleInstaller` asset and dragging it into `AppInstaller.asset`.

```csharp
public sealed class AppScope : LifetimeScope
{
    [SerializeField] private AppInstaller     _appInstaller;
    [SerializeField] private AppConfiguration _appConfiguration;

    [Header("Scene Infrastructure")]
    [SerializeField] private UIRoot    _uiRoot;
    [SerializeField] private AudioRoot _audioRoot;

    protected override void Configure(IContainerBuilder builder)
    {
        builder.RegisterInstance(_appConfiguration);
        builder.RegisterComponent(_uiRoot);
        builder.RegisterComponent(_audioRoot);

        _appInstaller.Install(builder);
    }
}
```

---

## Registration Patterns

### Pure C# Service (most common)

```csharp
// Register implementation, resolve via interface
builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>();

// WRONG — resolves as concrete, breaks interface-first architecture
builder.Register<AudioService>(Lifetime.Singleton);
```

### MonoBehaviour / Component

```csharp
// Scene object — drag into Inspector
builder.RegisterComponent(_audioRoot);

// Find in hierarchy at scope build time
builder.RegisterComponentInHierarchy<InputView>();

// From prefab — instantiates the prefab
builder.RegisterComponentInNewPrefab(prefab, Lifetime.Scoped);
```

### ScriptableObject Config

```csharp
builder.RegisterInstance(_appConfiguration);
```

`RegisterInstance` skips construction — the object already exists. Use for ScriptableObjects and pre-built instances.

### Factory

```csharp
builder.RegisterFactory<EnemyService>(container =>
    new EnemyService(container.Resolve<IEventBus>(), container.Resolve<IPoolService>()));
```

---

## Lifetime Options

| Lifetime | Instances | When to use |
|----------|-----------|-------------|
| `Singleton` | 1 per scope | Services used across the whole scene/app |
| `Scoped` | 1 per scope (same as Singleton inside one scope) | Prefer for most game services |
| `Transient` | New instance per resolve | Stateless helpers, factories |

In practice: use `Singleton` for services. `Transient` only when multiple independent instances are needed.

---

## ModuleInstaller Pattern

Each module has its own `ModuleInstaller` ScriptableObject. `AppScope` never lists modules directly — it delegates to `AppInstaller` which holds a list of `ModuleInstaller` assets.

```csharp
[CreateAssetMenu(menuName = "Installers/AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
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

**Adding a new module:**
1. Create `[Module]Installer.asset` via `Assets → Create → Installers → [Module]Installer`
2. Assign the config ScriptableObject in the Inspector
3. Open `AppInstaller.asset` → drag the new installer into the Modules list
4. `AppScope.cs` does not change

---

## Injection Methods

### Constructor Injection (preferred for pure C# classes)

```csharp
public sealed class ScoreService : IScoreService
{
    private readonly IEventBus _eventBus;
    private readonly ScoreConfiguration _config;

    public ScoreService(IEventBus eventBus, ScoreConfiguration config)
    {
        _eventBus = eventBus;
        _config   = config;
    }
}
```

VContainer resolves constructor parameters automatically — no attributes needed.

### Method Injection (for MonoBehaviours)

MonoBehaviours cannot use constructor injection. Use `[Inject]` on a method:

```csharp
public sealed class PlayerView : MonoBehaviour
{
    private IPlayerService _playerService;

    [Inject]
    public void Construct(IPlayerService playerService)
    {
        _playerService = playerService;
    }
}
```

Register the MonoBehaviour so VContainer knows to inject it:

```csharp
builder.RegisterComponentInHierarchy<PlayerView>();
```

### IInitializable / IDisposable Lifecycle

```csharp
public sealed class AudioService : IAudioService, IInitializable, IDisposable
{
    public void Initialize()
    {
        // Called by VContainer after all dependencies are resolved
        _eventBus.Subscribe<MuteChangedEvent>(OnMuteChanged);
    }

    public void Dispose()
    {
        // Called by VContainer when the scope is disposed (scene unload)
        _eventBus.Unsubscribe<MuteChangedEvent>(OnMuteChanged);
    }
}
```

Register lifecycle interfaces:

```csharp
builder.Register<AudioService>(Lifetime.Singleton)
    .As<IAudioService>()
    .AsImplementedInterfaces();  // registers IInitializable and IDisposable automatically
```

Or explicitly:

```csharp
builder.Register<AudioService>(Lifetime.Singleton)
    .As<IAudioService, IInitializable, IDisposable>();
```

---

## Child Scope Setup

```csharp
// GameScope.cs — registered in the Game scene
public sealed class GameScope : LifetimeScope
{
    [SerializeField] private GameInstaller _gameInstaller;

    protected override void Configure(IContainerBuilder builder)
    {
        _gameInstaller.Install(builder);
    }
}
```

Set `Parent` in the Inspector to `AppScope` so the child scope inherits global registrations.

---

## No GameContext / Service Locator (NON-NEGOTIABLE)

Never bundle dependencies into a context object:

```csharp
// BAD — hides real dependencies, every class gets everything
public class GameContext
{
    public IPlayerService Player { get; }
    public IScoreService Score { get; }
    public IAudioService Audio { get; }
}

// GOOD — each class declares only what it actually needs
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(IScoreService score) { }
}
```

---

## Diagnosing DI Failures

### `VContainerException: Unable to find type registration`

The type was not registered in the container. Fix:
1. Check the relevant `ModuleInstaller.Install()` has `builder.Register<T>()` for that type
2. Check the installer asset is in `AppInstaller.asset` → Modules list
3. Check the scope asking for the dependency can see the scope that registered it (parent/child relationship)

### `[Inject] method never called` on a MonoBehaviour

The MonoBehaviour is not registered. Fix:
```csharp
builder.RegisterComponentInHierarchy<MyMonoBehaviour>();
// or
builder.RegisterComponent(_myMonoBehaviour);  // drag reference from Inspector
```

### `IInitializable.Initialize()` never called

The service was not registered with `IInitializable`. Fix:
```csharp
builder.Register<MyService>(Lifetime.Singleton)
    .As<IMyService>()
    .AsImplementedInterfaces();
```

### Circular dependency

A → B → A. VContainer throws at container build time (not at runtime). Fix by extracting the shared concern into a third service C that neither A nor B depends on, or by using `IEventBus` for the communication instead of a direct reference.

### `RegisterBuildCallback` — post-build initialization

Use when you need access to resolved instances after the container is built (e.g., initializing a static accessor):

```csharp
builder.RegisterBuildCallback(container =>
{
    EventBusAccessor.Initialize(container.Resolve<IEventBus>());
});
```

---

## Rules (Non-Negotiable)

| Rule | Why |
|------|-----|
| Always register as interface: `.As<IService>()` | Callers depend on contracts, not implementations |
| No `FindObjectOfType` / `GetComponent` for services | Breaks DI — use constructor injection |
| No static mutable state / singletons | VContainer manages lifetime; statics cause hidden coupling |
| One `LifetimeScope` per scene | Mixing multiple scopes in one scene causes double-registration |
| `AppScope` never changes | New modules are added via installer assets only |
| Unsubscribe events in `Dispose()`, not `OnDestroy()` | VContainer disposes before Unity destroys — `OnDestroy` fires after scope is already gone |
