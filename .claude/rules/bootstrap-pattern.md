# Bootstrap & Installer Pattern (NON-NEGOTIABLE)

## Layer Structure

```
IInstaller (interface)          ← Framework layer
    ↑
ModuleInstaller (abstract SO)   ← Framework layer — ScriptableObject + IInstaller
    ↑
[Module]Installer (sealed SO)   ← Game layer — registers a single module's dependencies
    ↑
AppInstaller (sealed SO)        ← Game layer — lists modules, calls them in order
    ↑
AppScope (LifetimeScope)        ← Bootstrap scene — calls AppInstaller, registers scene infrastructure
```

---

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

- Pure C# interface — `using VContainer` is not needed, the `IContainerBuilder` parameter is sufficient
- Both `ModuleInstaller` and `AppInstaller` implement this interface

---

## ModuleInstaller

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

- Lives under `_Framework/Installers/` because it contains `ScriptableObject` (not `Games/Abstracts/` — `check-pure-csharp.sh` would block it)
- Every `[Module]Installer` derives from this class
- Abstract — cannot be instantiated directly

---

## AppInstaller

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppInstaller.cs
using System.Collections.Generic;
using Framework.Installers;
using UnityEngine;
using VContainer;

namespace Game.Concretes.Infrastructure
{
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
}
```

**Rules:**
- `AppInstaller` only iterates the list — it does not register anything directly
- Module order matters: `EventBusInstaller` is always the **first** element in the list
- Null modules are silently skipped — a missing slot does not crash the build
- `List<ModuleInstaller>` is used, not an array — for easy reordering in the Inspector

---

## [Module]Installer

Her modülün kendi `ModuleInstaller` alt sınıfı vardır.

```csharp
// _GameFolders/Scripts/Games/Concretes/Audio/AudioInstaller.cs
using Framework.Installers;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Audio
{
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
}
```

**Rules:**
- If config is null: `Debug.LogError` + `return` — do not use `throw` (we don't want a crash in build context)
- Use `.AsImplementedInterfaces()` — automatically registers lifecycle interfaces like `IInitializable`, `IDisposable`
- `[CreateAssetMenu]` path format: `"Game/Installers/[ModuleName]"`
- An installer registers only its own module's dependencies — it does not touch other modules

### EventBusInstaller (required in every project, first in the list)

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

- Holds no config — `EventBus` has no config
- `.AsImplementedInterfaces()` registers `IEventBus`, `IInitializable`, `IDisposable` all at once
- **Always first in the `AppInstaller._modules` list**

---

## AppScope

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppScope.cs
using Framework.Bootstrap;
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class AppScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private AppInstaller     _appInstaller;
        [SerializeField] private AppConfiguration _appConfiguration;

        #endregion

        #region Lifecycle

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

        #endregion
    }
}
```

**Rules:**
- `AppScope.cs` **never changes** — to add a new module, add it to `AppInstaller.asset`
- `EventBus` is not registered directly here — `EventBusInstaller` does that
- Scene infrastructure (`UIRoot`, `AudioRoot`) is registered with `RegisterComponentInHierarchy` — these components are physically present in the scene
- Null guards use `Debug.LogError` + `return` — `Configure()` is left incomplete but Unity does not crash

---

## GameScope — Scene-Based Wiring (NON-NEGOTIABLE)

`GameScope` registers Game-scene-specific dependencies (prefab references on the scene). Unlike AppScope, **all references are assigned manually in the scene via `[SerializeField]`** — it does not take ScriptableObjects.

### AppScope vs GameScope Difference

| | AppScope | GameScope |
|--|----------|-----------|
| Reference type | ScriptableObject (asset) | Prefab instance on the scene |
| Saved as prefab? | Yes — `Prefabs/Bootstrap/` | Yes — `Prefabs/Bootstrap/` |
| Where are references assigned? | On the prefab (asset dragged in Inspector) | On the scene instance (scene object dragged in Inspector) |
| `Configure()` content | `_appInstaller.Install(builder)` + infrastructure registrations | `[SerializeField]` fields are registered directly with `builder.RegisterInstance(...)` |
| Does it change? | `AppScope.cs` never changes | A `[SerializeField]` is added to `GameScope.cs` when a new module is added |

### GameScope Örneği

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/GameScope.cs
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class GameScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private PlayerProvider _playerProvider;
        [SerializeField] private UIRoot         _uiRoot;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_playerProvider == null)
            {
                Debug.LogError("[GameScope] PlayerProvider is missing.");
                return;
            }

            builder.RegisterComponent(_playerProvider);
            builder.RegisterComponent(_uiRoot);
        }

        #endregion
    }
}
```

### Setup Flow

1. Create `GameScope.prefab` → save it under `_GameFolders/Prefabs/Bootstrap/`
2. On the prefab, set the `Parent` field to `AppScope` (VContainer parent scope)
3. Place a `GameScope.prefab` instance in the Game scene → under the `[Setup]` container
4. **On the scene instance**, populate the `[SerializeField]` fields with scene objects — not on the prefab
5. When a new scene object is added: add a new `[SerializeField]` to `GameScope.cs` → update the scene instance

### Rules

- `builder.Register<T>(...)` is **forbidden** in `GameScope.cs` — pure C# services are registered via `AppInstaller` through AppScope
- `GameScope` only uses `builder.RegisterComponent(...)` — it registers MonoBehaviours on the scene into the container
- `[SerializeField]` fields on the prefab remain empty; they are filled per-scene on the instance
- `Debug.LogError` + `return` guard — a null scene object should not crash the build

---

## New Module Addition Flow (NON-NEGOTIABLE)

1. Write `[Module]Installer.cs` — derive from `ModuleInstaller`, add `[CreateAssetMenu]`
2. Create the asset in Unity: `Assets → Create → Game/Installers/[ModuleName]`
3. Assign the config ScriptableObject in the Inspector
4. Open `AppInstaller.asset` → add the new installer to the `_modules` list
5. **Do not touch** `AppScope.cs`

---

## Folder Structure

```
_Framework/
└── Installers/
    ├── IInstaller.cs          ← interface
    └── ModuleInstaller.cs     ← abstract base

_GameFolders/
├── Scripts/Games/Concretes/Infrastructure/
│   ├── AppInstaller.cs        ← module list
│   └── AppScope.cs            ← bootstrap scope
└── Scripts/Games/Concretes/[Domain]/
    └── [Domain]Installer.cs   ← domain-specific installer
```

---

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| `EventBus` is registered directly inside `AppScope.Configure()` | Create `EventBusInstaller`, add it first in the `AppInstaller` list |
| `AppScope` is modified to register a new module | Add the new installer to `AppInstaller.asset` — `AppScope.cs` never changes |
| `ModuleInstaller` is placed under `GameFolders/Abstracts/` | It contains `ScriptableObject` so it must live under `_Framework/Installers/` |
| `throw` is used instead of `Debug.LogError` | Use `return` + `LogError` in the config null guard — risk of crash in build context |
| Single interface registered with `.As<IEventBus>()` | Use `.AsImplementedInterfaces()` — also covers lifecycle interfaces |
| `AppInstaller._modules` is declared as an array | Use `List<ModuleInstaller>` — for reordering support in the Inspector |
