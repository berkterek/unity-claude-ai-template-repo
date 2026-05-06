# Unity 6 — Current Best Practices

## Dependency Injection

- **VContainer** over manual singletons or `FindObjectOfType`
- Register in `AppScope` (global) or scene-scoped `LifetimeScope`
- Always register as interface: `builder.Register<AudioService>(Lifetime.Singleton).As<IAudioService>()`

## Async

- **UniTask** everywhere — no coroutines, no `Task`, no `async void`
- Always pass `CancellationToken` — bind to `this.GetCancellationTokenOnDestroy()` in Views
- Fire-and-forget: `UniTask.Void(async () => { ... })` or `.Forget()` with error handler

## ECS / DOTS

- `ISystem` + `IJobEntity` for Burst-compiled simulation
- `SystemBase` as managed bridge only (for MonoBehaviour/MCP calls)
- `EntityCommandBuffer` for all structural changes (add/remove/destroy) — never inline
- `IEnableableComponent` for toggling without structural change
- Always declare `[UpdateInGroup]` explicitly

## Input

- New Input System only — `PlayerControls` owned solely by `InputView`
- Enable in `OnEnable`, disable + unsubscribe in `OnDisable` — symmetric always
- Continuous input in `Update`, cached and applied in `FixedUpdate`

## Asset Loading

- `Addressables.LoadAssetAsync<T>().ToUniTask(cancellationToken: ct)` — always pass CT
- Store handle as field, release in `Dispose()` with `IsValid()` guard
- `Addressables.ReleaseInstance()` for instantiated objects — not `Destroy()`

## Rendering

- SRP Batcher: ensure materials use `[PerRendererData]` properties for instancing
- Sprite atlases for all 2D sprites — no loose sprites in production builds
- `MaterialPropertyBlock` for per-instance color/texture changes
- UI: split Canvas by update frequency (HUD / Static / Popups)
