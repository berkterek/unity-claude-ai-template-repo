# Addressables Rules

## Core Rule: No Resources.Load (NON-NEGOTIABLE)

`Resources.Load` and `Resources.LoadAsync` are **forbidden**. All runtime asset loading goes through Addressables.

```csharp
// BAD — Resources folder couples asset path to code, bloats build
var prefab = Resources.Load<GameObject>("Enemies/Dragon");

// GOOD — Addressables decouples address from asset location
var handle = Addressables.LoadAssetAsync<GameObject>("Enemies/Dragon");
await handle.Task;
```

**Why:** `Resources/` folder contents are always included in the build regardless of use. Addressables enables on-demand loading, asset bundling, and remote delivery.

---

## Async Loading — UniTask Only

Never use `Addressables.LoadAssetAsync(...).Task` directly with `await`. Use the UniTask extension:

```csharp
using Cysharp.Threading.Tasks;

// GOOD — UniTask integration
var prefab = await Addressables.LoadAssetAsync<GameObject>(address)
    .ToUniTask(cancellationToken: ct);

// BAD — raw Task, no cancellation support
var prefab = await Addressables.LoadAssetAsync<GameObject>(address).Task;
```

---

## Address Management

Never hardcode address strings inline. Centralize in a static class or ScriptableObject:

```csharp
// GOOD — addresses in one place
public static class AssetAddresses
{
    public const string EnemyDragon   = "Enemies/Dragon";
    public const string AudioBgMusic  = "Audio/BgMusic";
    public const string UIMainMenu    = "UI/MainMenu";
}

// Usage
var prefab = await Addressables.LoadAssetAsync<GameObject>(AssetAddresses.EnemyDragon)
    .ToUniTask(cancellationToken: ct);

// BAD — magic string
var prefab = await Addressables.LoadAssetAsync<GameObject>("Enemies/Dragon").ToUniTask(ct);
```

---

## Handle Lifecycle — Release Is Mandatory

Every `LoadAssetAsync` handle must be released. Unreleased handles = memory leak.

```csharp
public sealed class EnemySpawnerProvider : IAudioProvider, IDisposable
{
    private AsyncOperationHandle<GameObject> _handle;

    public async UniTask LoadAsync(CancellationToken ct)
    {
        _handle = Addressables.LoadAssetAsync<GameObject>(AssetAddresses.EnemyDragon);
        await _handle.ToUniTask(cancellationToken: ct);
    }

    public void Dispose()
    {
        if (_handle.IsValid())
            Addressables.Release(_handle);
    }
}
```

**Rules:**
- Store handle as a field when the asset will be used over time
- Release in `Dispose()` or when the owning scope ends
- `Addressables.InstantiateAsync` → release with `Addressables.ReleaseInstance`, not `Destroy`
- Check `handle.IsValid()` before releasing (prevents double-release crash)

---

## Instantiation

```csharp
// GOOD — Addressables manages the lifecycle
var instance = await Addressables.InstantiateAsync(address, parent).ToUniTask(ct);
// ...
Addressables.ReleaseInstance(instance); // NOT Destroy(instance)

// BAD — breaks Addressables reference counting
Destroy(instance); // use only for non-Addressables objects
```

---

## Preloading

For assets needed at scene start, preload in an init system before gameplay begins:

```csharp
public sealed class AssetPreloadService : IAssetPreloadService, IDisposable
{
    private readonly List<AsyncOperationHandle> _handles = new();

    public async UniTask PreloadAsync(IEnumerable<string> addresses, CancellationToken ct)
    {
        foreach (var address in addresses)
        {
            var handle = Addressables.LoadAssetAsync<Object>(address);
            _handles.Add(handle);
            await handle.ToUniTask(cancellationToken: ct);
        }
    }

    public void Dispose()
    {
        foreach (var handle in _handles)
            if (handle.IsValid()) Addressables.Release(handle);
        _handles.Clear();
    }
}
```

---

## Label-Based Group Loading

Load multiple related assets by label instead of individual addresses:

```csharp
// Load all assets tagged "EnemyPrefabs"
var handle = Addressables.LoadAssetsAsync<GameObject>("EnemyPrefabs",
    asset => { /* optional per-asset callback */ });
var enemies = await handle.ToUniTask(ct);
```

---

## Forbidden Patterns

| Forbidden | Use Instead |
|-----------|------------|
| `Resources.Load<T>` | `Addressables.LoadAssetAsync<T>` |
| `Resources.LoadAsync<T>` | `Addressables.LoadAssetAsync<T>` |
| Hardcoded address strings | `AssetAddresses` constants class |
| `Destroy` on Addressables instance | `Addressables.ReleaseInstance` |
| Loading without releasing | Store handle, release in `Dispose` |
| Raw `.Task` on handles | `.ToUniTask(cancellationToken: ct)` |
