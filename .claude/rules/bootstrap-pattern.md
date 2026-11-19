# Bootstrap & Installer Pattern (NON-NEGOTIABLE)

> Short form — every rule is here. Full WRONG/RIGHT code and the reference sections (AppScope, GameScope —
> Scene-Based Wiring, SceneModules, TestScope, folder layout): `rules/bootstrap-pattern-reference.md`. It loads
> when you touch a bootstrap file; **Read it yourself before designing a new module or a scope's wiring.**

## Cards

### Card 1: Module = Static Class, Not ScriptableObject

**WHEN:** Adding a new feature module (Audio, Player, Score, etc.).

**WRONG:** a `ModuleInstaller` ScriptableObject with `[CreateAssetMenu]` and a `[SerializeField]` config.

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

**GOTCHA:** New module = one static class in `Game.Concretes.<Domain>` + one line in `AppModules.Install()`. No asset,
no drag-drop. Null guard is `Debug.LogError` + `return`, **never `throw`** (crashes the build context). Register with
`.AsImplementedInterfaces()`, never a single `.As<IFoo>()` — it also covers `IInitializable` / `IDisposable`.

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
        // New module: one line here
    }
}
```

**GOTCHA:** `EventBusModule` must be first — other modules subscribe during `Initialize()`; registered later, those
subscriptions silently fail. Module order is `IInitializable` / `IStartable` order. **`AppScope.cs` never changes** —
it validates the catalog, registers scene infrastructure (`RegisterComponentInHierarchy<UIRoot>()` …), calls
`AppModules.Install`, and initializes `EventBusAccessor` in `RegisterBuildCallback`.

---

### Card 3: ConfigCatalog.Validate Before Installing

**WHEN:** AppScope.Configure() is called.

**WRONG:** `AppModules.Install(builder, _configCatalog);` with no validation — partial wiring if a field is null.

**RIGHT:**
```csharp
if (!_configCatalog.Validate(out var missing))
{
    Debug.LogError($"[AppScope] ConfigCatalog missing fields: {string.Join(", ", missing)} — installation stopped.");
    return;
}
AppModules.Install(builder, _configCatalog);
```

**GOTCHA:** `Validate()` reports ALL missing fields before any registration runs; without it the container ends up
half-wired with no clear error. `ConfigCatalog` is the one `[CreateAssetMenu]` asset and the only path for app-wide
config — never a `[SerializeField]` config on individual prefabs. A new config = field + property + `Validate()` null
check. Past ~15 fields, split into domain catalogs.

---

### Card 4: GameScope Registers Scene Components Only — Use SceneModules for the Rest

**WHEN:** Deciding where to register a scene-lifetime pure C# service.

**WRONG:** `builder.Register<LevelTimerService>(Lifetime.Scoped);` inline in `GameScope.Configure()`.

**RIGHT:** `GameScope` only calls `builder.RegisterComponent(_sceneObject)` for scene MonoBehaviours, then
`SceneModules.InstallGame(builder)` for scene-lifetime pure C# services.

**GOTCHA:** Inline registration in `GameScope` hides services from `/knowledge-graph` and from test scopes.
`SceneModules` never takes app-lifetime services — those go in `AppModules`. GameScope is a prefab under
`Prefabs/Bootstrap/` with `Parent` = AppScope; its `[SerializeField]` fields stay empty on the prefab and are filled
on the **scene instance**. Null scene object → `LogError` + `return`.

---

### Card 5: TestScope Reuses Production Module — Never Hand-Copies Registrations

**WHEN:** Writing a PlayMode test scope.

**WRONG:** copying `builder.Register<PlayerService>(…)` lines from the production module into the test scope.

**RIGHT:** `PlayerModule.Install(builder, _testPlayerConfig);` then override only the fakes the scenario controls
(`builder.Register<FakeInputService>(Lifetime.Singleton).As<IInputService>();`).

**GOTCHA:** Hand-copied registrations drift from production; calling the real `Install()` makes the test break when
production wiring breaks. A TestScope **never extends AppScope** — it is an isolated root scope.

---

### Card 6: Scene Loading Goes Through ISceneService → ISceneLoader — Never Raw SceneManager in a Service

**WHEN:** Writing anything that loads a scene — including the first Bootstrap → Game load.

**RIGHT:** `ISceneService` (Tier 3, pure C#, `IAsyncStartable`) depends on `ISceneLoader` (Tier 4). Every
`SceneManager` call lives in `NormalSceneLoader`; `AddressableSceneLoader` swaps in without touching `SceneService`.
`SceneModule.Install()` binds the loader and calls `RegisterEntryPoint<SceneService>()`.

**GOTCHA:**
- **AppScope is `DontDestroyOnLoad`; every swap is `LoadSceneMode.Single`.** `AppScope.Awake` calls
  `DontDestroyOnLoad(transform.root.gameObject)` before `base.Awake()` — AppScope sits under `[Setup]`, and DDOL
  works only on a root (on a child it warns and does nothing). The first swap unloads Bootstrap; `[Setup]` survives.
  Single unloads the old scene and activates the new one itself: no unload step, no `SetActiveScene`, no `Scene`
  to cache, and a stray `Single` load elsewhere cannot kill the app scope.
- **Everything app-lifetime is a child of the AppScope GameObject** (`UIRoot`, `AudioRoot`, the loading overlay).
  A sibling root object in Bootstrap dies with Bootstrap on the first swap.
- **Bootstrap is loaded exactly once, at startup.** Nothing loads build index 0 again — a second load builds a
  second AppScope next to the surviving one (two containers, two `IEventBus`). PlayMode tests that load it destroy
  the AppScope in `TearDown`.
- `LoadSceneAsync` returns `null` on a scene not in the build; throw `InvalidOperationException` naming it —
  never log-and-return, the awaiting caller would take it as success.
- `NormalSceneLoader` gets a PlayMode test (`testing.md`): Bootstrap → Game, then Game → Game — exactly one Game
  scene, Game active, exactly one AppScope, exactly one GameScope. Full code: reference file → Card 6.
- **History:** 2026-11-18 → 11-19 this card used a never-unloaded Bootstrap holder scene (no DDOL). Reverted: it
  made a stray `Single` load fatal and made unparented `Instantiate` leak into Bootstrap. The real word-soda bug
  of that day was a cached `Scene` field, which `Single` makes impossible.

---

### Card 7: Scene Transitions Are a Command; Cross-Scene Data Lives in an App-Scope Service

**WHEN:** A button changes scene, or the next scene needs a value chosen in the current one.

**WRONG:** `_eventBus.Publish(new StartGameRequestedEvent())` or `Publish(new LevelSelectedEvent(3))` before the load.

**RIGHT:** write the choice to an app-lifetime service (`_levelSession.Select(3)`), then
`await _sceneService.LoadAsync(SceneIds.GAME, ct)`; the next scene reads it in `Initialize()`.

**GOTCHA:**
- Changing scene is a command (one receiver, an awaited result) — an interface call, never an event. `IEventBus` is
  for "it happened" notifications published after the scene is up.
- `ISceneService.LoadAsync` ignores a call while loading and returns at once (the caller does not wait for the running
  load — the interface remarks say so); the View binds `IsLoading` to the button.
- `SceneModule` is installed from `AppModules`, never `SceneModules`, and finishes the swap on its own app-lifetime
  token — the caller's View is destroyed by the unload.
- Cross-scene data is an app-lifetime service — never an event, static field or load parameter. An event published
  before the load reaches nobody: the next scene's services do not exist yet. Full code: reference file → Card 7.
