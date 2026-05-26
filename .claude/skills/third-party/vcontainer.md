---
name: vcontainer
description: VContainer dependency injection for Unity — scope hierarchy, installer pattern (IInstaller → ModuleInstaller → AppInstaller → AppScope), registration patterns, and DI failure diagnosis. Use whenever wiring a new service, creating an installer, debugging injection errors, adding a module to AppInstaller, or designing scope structure. Trigger on any mention of AppScope, ModuleInstaller, AppInstaller, LifetimeScope, [Inject], VContainer, DI registration, or "how do I add a new service/module".

user-invocable: true
model-tier: normal
---

# VContainer — Setup & Usage Guide

> For the full bootstrap/installer pattern (IInstaller → ModuleInstaller → AppInstaller → AppScope layer rules) see `rules/bootstrap-pattern.md`.

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
- `AppScope` registers global services via `AppInstaller` — never directly
- Child scopes resolve from parent — `GameScope` can use `IAudioService` registered in `AppScope`
- Sibling scopes are isolated — `MenuScope` cannot access `GameScope` registrations
- A scope disposes all its registrations when the scene unloads

---

## AppScope Pattern

`AppScope.cs` **never changes.** To add a new module, add a new installer to `AppInstaller.asset`.

```csharp
public sealed class AppScope : LifetimeScope
{
    [SerializeField] private AppInstaller     _appInstaller;
    [SerializeField] private AppConfiguration _appConfiguration;

    protected override void Configure(IContainerBuilder builder)
    {
        if (_appConfiguration == null)
        {
            Debug.LogError("[AppScope] AppConfiguration reference is missing.");
            return;
        }

        if (_appInstaller == null)
        {
            Debug.LogError("[AppScope] AppInstaller reference is missing.");
            return;
        }

        builder.RegisterInstance(_appConfiguration);

        builder.RegisterComponentInHierarchy<UIRoot>();
        builder.RegisterComponentInHierarchy<AudioRoot>();

        _appInstaller.Install(builder);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }
}
```

**Important:**
- `EventBus` is not registered directly here — `EventBusInstaller` does that
- Scene components (`UIRoot`, `AudioRoot`) are found with `RegisterComponentInHierarchy`
- Null guards use `Debug.LogError + return` — not `throw`

---

## Installer Layer

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

### ModuleInstaller (abstract base)

```csharp
// _Framework/Installers/ModuleInstaller.cs
using UnityEngine;
using VContainer;

namespace Framework.Installers
{
    public abstract class ModuleInstaller : ScriptableObject, IInstaller
    {
        public abstract void Install(IContainerBuilder builder);
    }
}
```

### AppInstaller (module list)

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs
[CreateAssetMenu(menuName = "Game/Infrastructure/App Installer", fileName = "AppInstaller")]
public sealed class AppInstaller : ScriptableObject, IInstaller
{
    [SerializeField] private List<ModuleInstaller> _modules = new();

    public void Install(IContainerBuilder builder)
    {
        foreach (var module in _modules)
        {
            if (module == null) continue;
            module.Install(builder);
        }
    }
}
```

- Use `List<ModuleInstaller>` — not array (for reordering in the Inspector)
- `EventBusInstaller` **is always the first element in the list**

---

## Writing [Module]Installer

Each module has its own installer. If there is a config, a null guard is required.

```csharp
[CreateAssetMenu(menuName = "Game/Installers/Audio", fileName = "AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
{
    [SerializeField] private AudioConfiguration _config;

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
        {
            Debug.LogError("[AudioInstaller] AudioConfiguration is missing.", this);
            return;
        }

        builder.RegisterInstance(_config);
        builder.Register<AudioService>(Lifetime.Singleton)
            .AsImplementedInterfaces();  // IInitializable, IDisposable registered automatically
    }
}
```

### EventBusInstaller (required in every project)

```csharp
[CreateAssetMenu(menuName = "Game/Installers/EventBus", fileName = "EventBusInstaller")]
public sealed class EventBusInstaller : ModuleInstaller
{
    public override void Install(IContainerBuilder builder)
    {
        builder.Register<EventBus>(Lifetime.Singleton)
            .AsImplementedInterfaces();
    }
}
```

Holds no config. **Always first in the `AppInstaller._modules` list.**

### New module addition flow

1. Write `[Domain]Installer.cs`, derive from `ModuleInstaller`
2. Create the asset in Unity: `Assets → Create → Game/Installers/[Domain]`
3. Assign the config SO in the Inspector
4. Open `AppInstaller.asset` → add the new installer to the `_modules` list
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
builder.RegisterComponentInHierarchy<InputView>();

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
2. Is that installer in the `AppInstaller.asset → _modules` list?
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
| `AppScope.cs` never changes | New module → add installer to `AppInstaller.asset` |
| `EventBusInstaller` first in list | All other modules depend on `IEventBus` — it must be registered first |
| Config null guard uses `LogError + return` | `throw` carries a crash risk in build context |
| Unsubscribe in `Dispose()` not `OnDestroy()` | VContainer disposes before scope destroy |
| Don't use `FindObjectOfType` / `GetComponent` for services | Bypasses DI, creates hidden coupling |
