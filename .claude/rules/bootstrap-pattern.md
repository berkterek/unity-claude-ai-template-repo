# Bootstrap & Installer Pattern (NON-NEGOTIABLE)

## Cards

### Card 1: Module = Static Class, Not ScriptableObject

**WHEN:** Adding a new feature module (Audio, Player, Score, etc.).

**WRONG:**
```csharp
[CreateAssetMenu(menuName = "Game/Installers/Audio", fileName = "AudioInstaller")]
public sealed class AudioInstaller : ModuleInstaller
{
    [SerializeField] private AudioConfiguration _config;
    public override void Install(IContainerBuilder builder) { ... }
}
```

**RIGHT:**
```csharp
public static class AudioModule
{
    public static void Install(IContainerBuilder builder, AudioConfiguration config)
    {
        if (config == null) { Debug.LogError("[AudioModule] AudioConfiguration missing."); return; }
        builder.RegisterInstance(config);
        builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
    }
}
```

**GOTCHA:** No asset to create in the Editor. No drag-drop into a list. No merge-conflict-prone `.asset` file. New module = one static class + one line in `AppModules.Install()`.

---

### Card 2: AppModules Is the Module List — Not AppInstaller.asset

**WHEN:** Wiring all modules together at app scope.

**WRONG:** Opening `AppInstaller.asset` in the Inspector and dragging a new installer into the list.

**RIGHT:**
```csharp
public static class AppModules
{
    public static void Install(IContainerBuilder builder, ConfigCatalog configs)
    {
        EventBusModule.Install(builder);                    // FIRST — structural guarantee
        AudioModule.Install(builder, configs.Audio);
        PlayerModule.Install(builder, configs.Player);
        // New module: one line here
    }
}
```

**GOTCHA:** `EventBusModule` must be first — other modules may subscribe to events during `Initialize()`. If EventBus is not registered first, those subscriptions silently fail.

---

### Card 3: ConfigCatalog.Validate Before Installing

**WHEN:** AppScope.Configure() is called.

**WRONG:**
```csharp
AppModules.Install(builder, _configCatalog); // InstallS blindly — partial wiring if a field is null
```

**RIGHT:**
```csharp
if (!_configCatalog.Validate(out var missing))
{
    Debug.LogError($"[AppScope] ConfigCatalog missing fields: {string.Join(", ", missing)} — installation stopped.");
    return;
}
AppModules.Install(builder, _configCatalog);
```

**GOTCHA:** Without `Validate()`, a null config field is only caught inside the module's `Install()` — after some modules have already registered. The container ends up half-wired with no clear error. `Validate()` reports ALL missing fields at once before any registration runs.

---

### Card 4: GameScope Registers Scene Components Only — Use SceneModules for the Rest

**WHEN:** Deciding where to register a scene-lifetime pure C# service.

**WRONG:**
```csharp
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerController);
    builder.Register<LevelTimerService>(Lifetime.Scoped); // inline Register in GameScope — FORBIDDEN
}
```

**RIGHT:**
```csharp
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterComponent(_playerController);
    SceneModules.InstallGame(builder); // scene-lifetime pure C# services here
}
```

**GOTCHA:** Inline `builder.Register<T>()` in `GameScope` bypasses the module pattern. Scene-lifetime services become invisible to `/knowledge-graph` and impossible to reuse in test scopes.

---

### Card 5: TestScope Reuses Production Module — Never Hand-Copies Registrations

**WHEN:** Writing a PlayMode test scope.

**WRONG:**
```csharp
protected override void Configure(IContainerBuilder builder)
{
    builder.RegisterInstance(_testPlayerConfig);
    builder.Register<PlayerService>(Lifetime.Singleton).AsImplementedInterfaces(); // hand-copy
}
```

**RIGHT:**
```csharp
protected override void Configure(IContainerBuilder builder)
{
    PlayerModule.Install(builder, _testPlayerConfig);      // production wiring
    builder.Register<FakeInputService>(Lifetime.Singleton)
           .As<IInputService>();                           // only fakes override
}
```

**GOTCHA:** Hand-copied registrations drift from production over time. Using `PlayerModule.Install()` directly means the test runs the real wiring code — if production breaks, the test breaks. That is the point.

---

### Card 6: Scene Loading Goes Through ISceneService → ISceneLoader — Never Raw SceneManager in a Service

**WHEN:** Writing anything that loads/activates/unloads a scene — including the Bootstrap → Game additive load.

**Structure (standard Service + Provider split, same as `IAudioService`/`IAudioProvider`):**

```
Game.Abstracts.Scenes/ISceneService.cs     ← Tier 3 contract (pure C#)
Game.Abstracts.Scenes/ISceneLoader.cs      ← Tier 4 contract (Unity API boundary)
Game.Concretes.Scenes/SceneService.cs      ← Tier 3: EntryPoint, pure C#, depends on ISceneLoader
Game.Concretes.Scenes/NormalSceneLoader.cs      ← Tier 4: SceneManager-backed ISceneLoader
Game.Concretes.Scenes/AddressableSceneLoader.cs ← Tier 4: Addressables-backed ISceneLoader (swap-in, no SceneService change)
Game.Concretes.Scenes/SceneModule.cs       ← static Install(): binds ISceneLoader, RegisterEntryPoint<SceneService>
```

**WRONG:**
```csharp
// SceneManager called directly inside the EntryPoint — no Provider boundary, no swap path to Addressables
public sealed class BootstrapSceneLoader : IAsyncStartable
{
    public async UniTask StartAsync(CancellationToken ct)
    {
        await SceneManager.LoadSceneAsync("Game", LoadSceneMode.Additive).ToUniTask(cancellationToken: ct);
        // Missing: SetActiveScene + unload Bootstrap — and this class can never become Addressables-backed without a rewrite
    }
}
```

**RIGHT:**
```csharp
// Game.Abstracts.Scenes/ISceneLoader.cs
public interface ISceneLoader
{
    UniTask LoadAdditiveAsync(string sceneName, CancellationToken ct);
    void ActivateAndUnload(Scene previousActive, string newActiveSceneName);
}

// Game.Concretes.Scenes/NormalSceneLoader.cs — Tier 4 Provider, Unity API lives here
public sealed class NormalSceneLoader : ISceneLoader
{
    public async UniTask LoadAdditiveAsync(string sceneName, CancellationToken ct)
        => await SceneManager.LoadSceneAsync(sceneName, LoadSceneMode.Additive).ToUniTask(cancellationToken: ct);

    public void ActivateAndUnload(Scene previousActive, string newActiveSceneName)
    {
        SceneManager.SetActiveScene(SceneManager.GetSceneByName(newActiveSceneName));
        SceneManager.UnloadSceneAsync(previousActive).ToUniTask().Forget();
    }
}

// Game.Concretes.Scenes/SceneService.cs — Tier 3, pure C#, no UnityEngine import beyond Scene as a plain handle type
public sealed class SceneService : ISceneService, IAsyncStartable
{
    private readonly ISceneLoader _loader;
    private readonly LifetimeScope _appScope;

    public SceneService(ISceneLoader loader, LifetimeScope appScope)
    {
        _loader   = loader;
        _appScope = appScope;
    }

    public async UniTask StartAsync(CancellationToken ct)
    {
        var bootstrapScene = _appScope.gameObject.scene; // capture BEFORE DontDestroyOnLoad
        Object.DontDestroyOnLoad(_appScope.gameObject);

        await _loader.LoadAdditiveAsync("Game", ct);
        _loader.ActivateAndUnload(bootstrapScene, "Game");
    }
}
```

**GOTCHA:** `LoadSceneMode.Additive` never changes the active scene — the scene active before the load stays active after it. Without an explicit activate+unload step, the empty Bootstrap scene stays loaded **and** active indefinitely: new `Instantiate()` calls with no explicit scene default to it, and Lighting/Skybox/Fog settings are read from it instead of the gameplay scene. Capture `_appScope.gameObject.scene` **before** calling `DontDestroyOnLoad` — after that call the GameObject's `.scene` is the special `DontDestroyOnLoad` pseudo-scene, not Bootstrap. Putting the raw `SceneManager` calls inside `SceneService` instead of `ISceneLoader` is the same DIP violation as calling `AudioSource` directly from `AudioService` — it blocks ever adding `AddressableSceneLoader` without touching the service.

---

## Layer Structure

```
IInstaller (interface)          ← Framework layer — pure C# installer contract (optional)
    ↑
[Module]Module (static class)   ← Game layer — replaces ModuleInstaller SO
    ↑
AppModules (static class)       ← Game layer — replaces AppInstaller SO
    ↑
AppScope (LifetimeScope)        ← Bootstrap scene — calls AppModules, registers scene infrastructure
```

`ModuleInstaller` (abstract SO base) and `AppInstaller` (SO with `_modules` list) are **removed**.
`IInstaller` is kept for pure C# compatibility only — modules do not need to implement it.

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
- Modules do not extend this interface — it exists for pure C# installer abstractions only

---

## [Module]Module — Static Class

```csharp
// _GameFolders/Scripts/Games/Concretes/Audio/AudioModule.cs
using UnityEngine;
using VContainer;

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
```

**Rules:**
- Static class — not ScriptableObject, not abstract, not MonoBehaviour
- Signature: `Install(IContainerBuilder builder, <Config> config)`
- Null guard: `LogError` + `return` — do not use `throw` (risk of crash in build context)
- `.AsImplementedInterfaces()` covers `IInitializable`, `IDisposable`, `ITickable` automatically
- No `[CreateAssetMenu]` attribute
- Lives in `Game.Concretes.<Domain>`

---

## AppModules — Static Class

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppModules.cs
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class AppModules
    {
        public static void Install(IContainerBuilder builder, ConfigCatalog configs)
        {
            EventBusModule.Install(builder);                    // FIRST — structural guarantee
            AudioModule.Install(builder, configs.Audio);
            PlayerModule.Install(builder, configs.Player);
            // Adding a new module: one line here
        }
    }
}
```

**Rules:**
- `EventBusModule` is always first — not convention but structural guarantee: other modules may call `IEventBus.Subscribe` during `Initialize()`, so EventBus must exist in the container before any other `IInitializable` runs
- New module = one C# line — visible in git diff, hookable, no Editor action required
- Module order determines `IInitializable` / `ITickable` execution order (VContainer EntryPoint order)
- `AppModules.cs` is the single source of truth for what is registered at app scope

---

## ConfigCatalog — ScriptableObject

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/ConfigCatalog.cs
using System.Collections.Generic;
using UnityEngine;

namespace Game.Concretes.Infrastructure
{
    [CreateAssetMenu(menuName = "Game/Config Catalog", fileName = "ConfigCatalog")]
    public sealed class ConfigCatalog : ScriptableObject
    {
        #region Fields

        [SerializeField] private AudioConfiguration  _audio;
        [SerializeField] private PlayerConfiguration _player;

        #endregion

        #region Properties

        public AudioConfiguration  Audio  => _audio;
        public PlayerConfiguration Player => _player;

        #endregion

        #region Public Methods

        public bool Validate(out List<string> missing)
        {
            missing = new List<string>();
            if (_audio == null)  missing.Add(nameof(_audio));
            if (_player == null) missing.Add(nameof(_player));
            return missing.Count == 0;
        }

        #endregion
    }
}
```

**Rules:**
- One `[CreateAssetMenu]` asset in the project — single drag-drop point into `AppScope`
- `Validate()` is called in `AppScope.Configure()` before any module installation
- If the field count exceeds ~15, split into domain catalogs (`AudioConfigCatalog`, `PlayerConfigCatalog`)
- App-wide config never travels via `[SerializeField]` on individual prefabs — ConfigCatalog is the only path

---

## EventBusModule — Always First

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/EventBusModule.cs
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class EventBusModule
    {
        public static void Install(IContainerBuilder builder)
        {
            builder.Register<EventBus>(Lifetime.Singleton).AsImplementedInterfaces();
        }
    }
}
```

**Rules:**
- No config — `EventBus` has no configuration
- Always first in `AppModules.Install()` — structural requirement, not convention
- `.AsImplementedInterfaces()` registers `IEventBus`, `IInitializable`, `IDisposable` all at once

---

## AppScope

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/AppScope.cs
using UnityEngine;
using VContainer;
using VContainer.Unity;

namespace Game.Concretes.Infrastructure
{
    public sealed class AppScope : LifetimeScope
    {
        #region Fields

        [SerializeField] private ConfigCatalog    _configCatalog;
        [SerializeField] private AppConfiguration _appConfiguration;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_configCatalog == null)
            {
                Debug.LogError("[AppScope] ConfigCatalog reference is missing.");
                return;
            }

            if (_appConfiguration == null)
            {
                Debug.LogError("[AppScope] AppConfiguration reference is missing.");
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

        #endregion
    }
}
```

**Rules:**
- `AppScope.cs` **never changes** — add modules via `AppModules.cs`
- `ConfigCatalog.Validate()` runs before any module installation — all missing fields reported at once
- Scene infrastructure (`UIRoot`, `AudioRoot`) is registered with `RegisterComponentInHierarchy` — these components are physically present in the scene
- Null guards use `Debug.LogError` + `return` — `Configure()` is left incomplete but Unity does not crash

---

## GameScope — Scene-Based Wiring (NON-NEGOTIABLE)

`GameScope` registers scene-specific MonoBehaviour references and delegates scene-lifetime pure C# services to `SceneModules`.

### AppScope vs GameScope Difference

| | AppScope | GameScope |
|--|----------|-----------|
| Reference type | `ConfigCatalog` (ScriptableObject asset) | Prefab instance on the scene |
| Saved as prefab? | Yes — `Prefabs/Bootstrap/` | Yes — `Prefabs/Bootstrap/` |
| Where are references assigned? | On the prefab (asset dragged in Inspector) | On the scene instance (scene object dragged in Inspector) |
| `Configure()` content | `AppModules.Install(builder, _configCatalog)` + infrastructure | `builder.RegisterComponent(...)` + `SceneModules.Install*(builder)` |
| Does it change? | `AppScope.cs` never changes | A `[SerializeField]` is added when a new scene object must be registered |

### GameScope Example

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

        [SerializeField] private PlayerController _playerController;
        [SerializeField] private UIRoot           _uiRoot;

        #endregion

        #region Lifecycle

        protected override void Configure(IContainerBuilder builder)
        {
            if (_playerController == null)
            {
                Debug.LogError("[GameScope] PlayerController is missing.");
                return;
            }

            builder.RegisterComponent(_playerController);   // scene MonoBehaviour
            builder.RegisterComponent(_uiRoot);             // scene MonoBehaviour

            SceneModules.InstallGame(builder);              // scene-lifetime pure C# services
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

- Inline `builder.Register<T>(...)` in `GameScope` is **forbidden** — scene-lifetime pure C# services go through `SceneModules`
- `GameScope` only uses `builder.RegisterComponent(...)` for scene MonoBehaviours
- `[SerializeField]` fields on the prefab remain empty; they are filled per-scene on the instance
- `Debug.LogError` + `return` guard — a null scene object must not silently produce a half-wired container

---

## SceneModules — Scene-Lifetime Pure C# Services

```csharp
// _GameFolders/Scripts/Games/Concretes/Infrastructure/SceneModules.cs
using VContainer;

namespace Game.Concretes.Infrastructure
{
    public static class SceneModules
    {
        public static void InstallGame(IContainerBuilder builder)
        {
            // Scene-lifetime pure C# services (e.g. LevelTimerModule.Install(builder))
            // Leave empty until a scene-local service is needed
        }

        public static void InstallMenu(IContainerBuilder builder)
        {
            // Menu-scene services
        }
    }
}
```

**Rules:**
- Scene-lifetime services registered here resolve AppScope services (e.g. `IEventBus`) through the parent scope — VContainer scope hierarchy handles this automatically
- Services registered in `SceneModules` are disposed when the scene's `GameScope` is destroyed
- Leave `InstallGame` / `InstallMenu` empty until a real need exists — empty scaffolding is not a violation
- Never add app-lifetime services here — they belong in `AppModules`

---

## TestScope — Production Module Reuse

Test scopes call the production module's `Install()` method directly. They do not hand-copy registrations.

```csharp
// PlayerMovementTestScope.cs
public sealed class PlayerMovementTestScope : LifetimeScope
{
    [SerializeField] private PlayerConfiguration _testPlayerConfig;

    protected override void Configure(IContainerBuilder builder)
    {
        PlayerModule.Install(builder, _testPlayerConfig);       // production wiring code itself
        builder.Register<FakeInputService>(Lifetime.Singleton)
               .As<IInputService>();                            // only fakes override
    }
}
```

**Rules:**
- Call `ProductionModule.Install(builder, testConfig)` — never copy individual `builder.Register` lines
- Only inject fakes for dependencies the scenario specifically needs to control
- `TestScope` never extends `AppScope` — it is a root scope (isolated, no global state)
- If a production module's wiring changes, tests automatically reflect the change — no sync needed

---

## New Module Addition Flow (NON-NEGOTIABLE)

1. Create `[Module]Module.cs` — static class, `Install(IContainerBuilder builder, Config config)` signature
2. Add config field to `ConfigCatalog` — one `[SerializeField]` + property + `Validate()` null check
3. In Unity: create the config ScriptableObject asset, assign it in the `ConfigCatalog` Inspector
4. Open `AppModules.cs` → add one line: `[Module]Module.Install(builder, configs.[Module]);`
5. **Do not touch** `AppScope.cs`

No longer required: creating a ScriptableObject installer asset, dragging it into an `AppInstaller` list.

---

## Folder Structure

```
_Framework/
└── Installers/
    └── IInstaller.cs              ← interface (optional — modules do not implement it)
    (ModuleInstaller.cs — REMOVED)

_GameFolders/
├── Scripts/Games/Concretes/Infrastructure/
│   ├── AppModules.cs              ← module list (replaces AppInstaller.cs)
│   ├── AppScope.cs                ← bootstrap scope (unchanged by new modules)
│   ├── ConfigCatalog.cs           ← config aggregator ScriptableObject
│   ├── EventBusModule.cs          ← always first in AppModules.Install()
│   └── SceneModules.cs            ← scene-lifetime pure C# services
└── Scripts/Games/Concretes/<Domain>/
    └── [Domain]Module.cs          ← domain-specific static installer
```

---

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| Creating a `ModuleInstaller` SO for a new module | Create a static `[Domain]Module.cs` instead |
| Dragging an installer into `AppInstaller.asset` | Add one line to `AppModules.Install()` |
| Modifying `AppScope.cs` to register a new module | Add the module to `AppModules.cs` — `AppScope.cs` never changes |
| Inline `builder.Register<T>()` in `GameScope` | Use `SceneModules.InstallGame(builder)` for scene-lifetime pure C# services |
| Hand-copying registrations in `TestScope` | Call `ProductionModule.Install(builder, testConfig)` and only override with fakes |
| `ConfigCatalog.Validate()` not called before `Install()` | Always call `Validate()` first in `AppScope.Configure()` — partial wiring is worse than no wiring |
| `EventBus` registered after another module | `EventBusModule.Install` must be the first call in `AppModules.Install()` |
| `throw` used in module null guard | Use `Debug.LogError` + `return` — `throw` crashes the build context |
| Single interface registered with `.As<IEventBus>()` | Use `.AsImplementedInterfaces()` — also covers `IInitializable`, `IDisposable`, `ITickable` |
