---
name: vcontainer
description: VContainer dependency injection for Unity — scope hierarchy, the code-first module pattern ([Domain]Module → AppModules → AppScope), registration patterns, and DI failure diagnosis. Use whenever wiring a new service, writing a module, debugging injection errors, adding a module to AppModules, or designing scope structure. Trigger on any mention of AppScope, AppModules, LifetimeScope, [Inject], VContainer, DI registration, or "how do I add a new service/module".

user-invocable: true
model-tier: normal
---

# VContainer — Setup & Usage Guide

> For the full bootstrap pattern ([Domain]Module → AppModules → AppScope layer rules) see `rules/bootstrap-pattern.md` — it is the authority on anything below.

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
- `AppScope` registers global services via `AppModules` — never directly
- Child scopes resolve from parent — `GameScope` can use `IAudioService` registered in `AppScope`
- Sibling scopes are isolated — `MenuScope` cannot access `GameScope` registrations
- A scope disposes all its registrations when the scene unloads

---

## AppScope Pattern

`AppScope.cs` **never changes.** To add a new module, add one line to `AppModules.Install()`.

```csharp
public sealed class AppScope : LifetimeScope
{
    [SerializeField] private ConfigCatalog    _configCatalog;
    [SerializeField] private AppConfiguration _appConfiguration;

    protected override void Configure(IContainerBuilder builder)
    {
        if (_appConfiguration == null)
        {
            Debug.LogError("[AppScope] AppConfiguration reference is missing.");
            return;
        }

        if (_configCatalog == null)
        {
            Debug.LogError("[AppScope] ConfigCatalog reference is missing.");
            return;
        }

        if (!_configCatalog.Validate(out var missing))
        {
            Debug.LogError($"[AppScope] ConfigCatalog missing fields: {string.Join(", ", missing)} — installation stopped.");
            return;
        }

        builder.RegisterInstance(_appConfiguration);

        builder.RegisterComponentInHierarchy<UIRoot>();
        builder.RegisterComponentInHierarchy<AudioRoot>();

        AppModules.Install(builder, _configCatalog);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }
}
```

**Important:**
- `EventBus` is not registered directly here — `EventBusModule` does that, first in `AppModules`
- Scene components (`UIRoot`, `AudioRoot`) are found with `RegisterComponentInHierarchy`
- `ConfigCatalog.Validate()` runs before any module installs, so all missing fields are reported at once
- Null guards use `Debug.LogError + return` — not `throw`

---

## Module Layer

> **ScriptableObject installers were removed.** `ModuleInstaller` (abstract SO base) and `AppInstaller` (SO with a `_modules` list) no longer exist. A module is a static class; there is no asset to create, no list to drag into, and no merge-conflict-prone `.asset` file. `.claude/rules/bootstrap-pattern.md` is the authority.

### IInstaller

```csharp
// _Framework/Installers/IInstaller.cs
namespace Framework.Installers
{
    public interface IInstaller
    {
        void Install(IContainerBuilder builder);
    }
}
```

Kept for pure C# installer abstractions only — modules do not implement it.

### AppModules (the module list)

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs
public static class AppModules
{
    public static void Install(IContainerBuilder builder, ConfigCatalog configs)
    {
        EventBusModule.Install(builder);                 // FIRST — structural guarantee
        AudioModule.Install(builder, configs.Audio);
        PlayerModule.Install(builder, configs.Player);
        // New module: one line here
    }
}
```

`AppModules.cs` is the single source of truth for what is registered at app scope, and module order determines EntryPoint execution order.

---

## Writing a [Domain]Module

Each module is a static class. If it takes a config, a null guard is required.

```csharp
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
        builder.Register<AudioService>(Lifetime.Singleton)
            .AsImplementedInterfaces();  // IInitializable, IDisposable registered automatically
    }
}
```

### EventBusModule (required in every project)

```csharp
public static class EventBusModule
{
    public static void Install(IContainerBuilder builder)
    {
        builder.Register<EventBus>(Lifetime.Singleton)
            .AsImplementedInterfaces();
    }
}
```

Holds no config. **Always the first call in `AppModules.Install()`** — other modules may `Subscribe` during `Initialize()`, and those subscriptions silently fail if EventBus is not in the container yet.

### New module addition flow

1. Write `[Domain]Module.cs` — static class, `Install(IContainerBuilder builder, [Domain]Configuration config)`
2. Add the config field to `ConfigCatalog` — one `[SerializeField]` + property + `Validate()` null check
3. In Unity: create the config ScriptableObject asset and assign it in the `ConfigCatalog` Inspector
4. Add one line to `AppModules.Install()`
5. **Do not touch** `AppScope.cs`

---

## Registration Patterns

### Pure C# Service

```csharp
// GOOD — resolve through interface
builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>();

// GOOD — lifecycle interfaces also included
builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();

// BAD — concrete dependency
builder.Register<AudioService>(Lifetime.Singleton);
```

### MonoBehaviour / Component

```csharp
// Present in scene — searches the hierarchy
builder.RegisterComponentInHierarchy<UIRoot>();

// Reference dragged from Inspector
builder.RegisterComponent(_audioRoot);

// Instantiate from prefab
builder.RegisterComponentInNewPrefab(prefab, Lifetime.Scoped);
```

### ScriptableObject Config

```csharp
builder.RegisterInstance(_appConfiguration);
```

`RegisterInstance` does not construct — the object already exists. Used for SOs and pre-built instances.

### Factory

```csharp
builder.RegisterFactory<EnemyService>(container =>
    new EnemyService(container.Resolve<IEventBus>(), container.Resolve<IPoolService>()));
```

---

## Lifetime Options

| Lifetime | Instances | When |
|----------|-----------|------|
| `Singleton` | 1 per scope | Application-wide services |
| `Scoped` | 1 per scope | Scene-specific services |
| `Transient` | New on each resolve | Stateless helpers |

In practice, use `Singleton` for services.

---

## Injection Methods

### Constructor Injection (preferred for pure C#)

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

VContainer resolves constructor parameters automatically — no attribute needed.

### Method Injection (for MonoBehaviour)

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

To register the MonoBehaviour with the scope:

```csharp
builder.RegisterComponentInHierarchy<PlayerView>();
```

### IInitializable / IDisposable Lifecycle

```csharp
public sealed class AudioService : IAudioService, IInitializable, IDisposable
{
    public void Initialize()
    {
        _eventBus.Subscribe<MuteChangedEvent>(OnMuteChanged);
    }

    public void Dispose()
    {
        _eventBus.Unsubscribe<MuteChangedEvent>(OnMuteChanged);
    }
}
```

`.AsImplementedInterfaces()` automatically registers `IInitializable` and `IDisposable`.

---

## Child Scope Setup

```csharp
public sealed class GameScope : LifetimeScope
{
    [SerializeField] private GameInstaller _gameInstaller;

    protected override void Configure(IContainerBuilder builder)
    {
        _gameInstaller.Install(builder);
    }
}
```

Set the `Parent` field to `AppScope` in the Inspector — global registrations are inherited.

---

## No GameContext / Service Locator (NON-NEGOTIABLE)

```csharp
// BAD — hidden dependency, every class gets everything
public class GameContext
{
    public IPlayerService Player { get; }
    public IScoreService Score { get; }
}

// GOOD — each class declares only what it needs
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(IScoreService score) { }
}
```

---

## Diagnosing DI Failures

### `VContainerException: Unable to find type registration`

1. Does the relevant `[Module]Installer.Install()` have `builder.Register<T>()`?
2. Is that module called from `AppModules.Install()`?
3. Can the scope requesting the dependency see the scope that registered it? (parent/child relationship)

### `[Inject] method never called`

The MonoBehaviour was not registered with the scope:
```csharp
builder.RegisterComponentInHierarchy<MyMonoBehaviour>();
```

### `IInitializable.Initialize()` never called

```csharp
builder.Register<MyService>(Lifetime.Singleton)
    .As<IMyService>()
    .AsImplementedInterfaces();
```

### Circular dependency

A → B → A. VContainer throws at build time. Solution: move the shared concern to a third service C, or use `IEventBus`.

### `RegisterBuildCallback`

To access resolved instances after the container build is complete:

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
| Use `.AsImplementedInterfaces()` | Automatically covers `IInitializable`, `IDisposable` lifecycles |
| Always register to interface | Caller depends on the contract, not the implementation |
| `AppScope.cs` never changes | New module → one line in `AppModules.Install()` |
| `EventBusModule.Install` first in `AppModules` | Other modules may subscribe during `Initialize()` — EventBus must exist first |
| Config null guard uses `LogError + return` | `throw` carries a crash risk in build context |
| Unsubscribe in `Dispose()` not `OnDestroy()` | VContainer disposes before scope destroy |
| Don't use `FindObjectOfType` / `GetComponent` for services | Bypasses DI, creates hidden coupling |
