---
name: bootstrap-pattern
description: Bootstrap & Installer layer structure — IInstaller → ModuleInstaller → [Module]Installer → AppInstaller → AppScope hierarchy, new module addition flow, EventBusInstaller requirement. Use this skill when adding a new module, writing an installer, considering touching AppScope or AppInstaller, or setting up VContainer registration structure. AppScope.cs never changes — only AppInstaller.asset is updated.
model-tier: normal
---

# Bootstrap & Installer Pattern

## Layer Structure

```
IInstaller (interface)          ← _Framework/Installers/
    ↑
ModuleInstaller (abstract SO)   ← _Framework/Installers/
    ↑
[Module]Installer (sealed SO)   ← _GameFolders/Scripts/Games/Concretes/[Domain]/
    ↑
AppInstaller (sealed SO)        ← _GameFolders/Scripts/Games/Concretes/Infrastructure/
    ↑
AppScope (LifetimeScope)        ← Bootstrap scene — calls AppInstaller
```

## IInstaller

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

## ModuleInstaller

```csharp
// _Framework/Installers/ModuleInstaller.cs
public abstract class ModuleInstaller : ScriptableObject, IInstaller
{
    public abstract void Install(IContainerBuilder builder);
}
```

Lives under `_Framework/Installers/` because it contains `ScriptableObject` — not `Games/Abstracts/`.

## [Module]Installer

```csharp
[CreateAssetMenu(menuName = "Game/Installers/Audio", fileName = "AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
{
    #region Fields

    [SerializeField] private AudioConfiguration _config;

    #endregion

    #region ModuleInstaller

    public override void Install(IContainerBuilder builder)
    {
        if (_config == null)
        {
            Debug.LogError("[AudioInstaller] AudioConfiguration is missing.", this);
            return;
        }

        builder.RegisterInstance(_config);
        builder.Register<AudioService>(Lifetime.Singleton)
            .AsImplementedInterfaces();
    }

    #endregion
}
```

**Rules:**
- Config null → `Debug.LogError` + `return` (not throw)
- `.AsImplementedInterfaces()` — automatically covers lifecycle interfaces
- `[CreateAssetMenu]` format: `"Game/Installers/[ModuleName]"`

## EventBusInstaller (required in every project, first in the list)

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

**Always first in the `AppInstaller._modules` list.**

## AppInstaller

```csharp
[CreateAssetMenu(menuName = "Game/Infrastructure/App Installer", fileName = "AppInstaller")]
public sealed class AppInstaller : ScriptableObject, IInstaller
{
    #region Fields

    [SerializeField] private List<ModuleInstaller> _modules = new();

    #endregion

    #region Public Methods

    public void Install(IContainerBuilder builder)
    {
        foreach (var module in _modules)
        {
            if (module == null) continue;
            module.Install(builder);
        }
    }

    #endregion
}
```

`List<ModuleInstaller>` is used (not an array) — for easy reordering in the Inspector.

## AppScope

```csharp
public sealed class AppScope : LifetimeScope
{
    #region Fields

    [SerializeField] private AppInstaller     _appInstaller;
    [SerializeField] private AppConfiguration _appConfiguration;

    #endregion

    #region Lifecycle

    protected override void Configure(IContainerBuilder builder)
    {
        if (_appConfiguration == null) { Debug.LogError("[AppScope] AppConfiguration missing."); return; }
        if (_appInstaller == null)     { Debug.LogError("[AppScope] AppInstaller missing."); return; }

        builder.RegisterInstance(_appConfiguration);
        builder.RegisterComponentInHierarchy<UIRoot>();
        builder.RegisterComponentInHierarchy<AudioRoot>();

        _appInstaller.Install(builder);

        builder.RegisterBuildCallback(container =>
        {
            EventBusAccessor.Initialize(container.Resolve<IEventBus>());
        });
    }

    #endregion
}
```

**AppScope.cs never changes** — to add a new module, add the installer to `AppInstaller.asset`.

## New Module Addition Flow

1. Write `[Module]Installer.cs` — derive from `ModuleInstaller`, add `[CreateAssetMenu]`
2. Create the asset in Unity: `Assets → Create → Game/Installers/[ModuleName]`
3. Assign the config ScriptableObject in the Inspector
4. Open `AppInstaller.asset` → add to the `_modules` list
5. **Do not touch** `AppScope.cs`

## Folder Structure

```
_Framework/Installers/
├── IInstaller.cs
└── ModuleInstaller.cs

_GameFolders/Scripts/Games/Concretes/Infrastructure/
├── AppInstaller.cs
└── AppScope.cs

_GameFolders/Scripts/Games/Concretes/[Domain]/
└── [Domain]Installer.cs
```

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| `EventBus` registered directly in `AppScope.Configure()` | Create `EventBusInstaller`, put it first in the list |
| `AppScope.cs` is modified to add a new module | Add the installer to `AppInstaller.asset` — `AppScope.cs` never changes |
| `ModuleInstaller` placed under `GameFolders/Abstracts/` | It contains `ScriptableObject` so it must be under `_Framework/Installers/` |
| Null guard uses `throw` | Use `Debug.LogError` + `return` |
| Single interface registered with `.As<IEventBus>()` | Use `.AsImplementedInterfaces()` |
