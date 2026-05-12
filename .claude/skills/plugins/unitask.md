---
name: unitask
description: UniTask usage pattern — async/await, CancellationToken, PlayerLoop integration, and common mistakes
model-tier: normal
---

# UniTask — Usage Pattern

## Namespace
```csharp
using Cysharp.Threading.Tasks;
```

## Core Rules (NON-NEGOTIABLE)

- Coroutines (`IEnumerator`, `StartCoroutine`) are forbidden — all async work uses `UniTask`
- `async void` is forbidden — use `async UniTask` only
- Every `async UniTask` method takes a `CancellationToken` parameter
- Use `.Forget()` for fire-and-forget — never `async void`

---

## Method Signatures

```csharp
// GOOD
public async UniTask InitializeAsync(CancellationToken ct) { }
public async UniTask<int> LoadScoreAsync(CancellationToken ct) { }

// BAD
public async void Initialize() { }        // async void — exceptions are swallowed
async Task Initialize() { }              // Task — no Unity lifecycle integration
IEnumerator Initialize() { yield return; } // coroutine — forbidden
```

---

## CancellationToken Management

### MonoBehaviour

```csharp
public sealed class PlayerView : MonoBehaviour
{
    private void Start()
    {
        // GetCancellationTokenOnDestroy() — auto-cancels when the object is destroyed
        LoadAsync(this.GetCancellationTokenOnDestroy()).Forget();
    }
}
```

### Plain C# Service (IInitializable / IDisposable)

```csharp
public sealed class StoreService : IStoreService, IInitializable, IDisposable
{
    private CancellationTokenSource _cts;

    public void Initialize()
    {
        _cts = new CancellationTokenSource();
        SetupAsync(_cts.Token).Forget();
    }

    public void Dispose()
    {
        _cts?.Cancel();
        _cts?.Dispose();
    }
}
```

---

## Waiting

```csharp
// Wait for a duration
await UniTask.Delay(TimeSpan.FromSeconds(1f), cancellationToken: ct);
await UniTask.Delay(1000, cancellationToken: ct); // ms

// Wait for frames
await UniTask.Yield();
await UniTask.NextFrame();
await UniTask.WaitForFixedUpdate();
await UniTask.WaitForEndOfFrame(this);

// Wait for a condition
await UniTask.WaitUntil(() => _isReady, cancellationToken: ct);
await UniTask.WaitWhile(() => _isLoading, cancellationToken: ct);
```

---

## Parallel and Sequential Execution

```csharp
// Parallel — both run simultaneously, continues when both finish
await UniTask.WhenAll(LoadAudioAsync(ct), LoadDataAsync(ct));

// First one to finish wins
await UniTask.WhenAny(WaitForInputAsync(ct), TimeoutAsync(ct));

// Sequential
await LoadAudioAsync(ct);
await LoadDataAsync(ct);
```

---

## Fire-and-Forget

```csharp
// GOOD
InitializeAsync(ct).Forget();

// BAD
async void Initialize() { await ...; }
```

---

## With Addressables

```csharp
// Use .ToUniTask() — not raw .Task
var prefab = await Addressables
    .LoadAssetAsync<GameObject>(address)
    .ToUniTask(cancellationToken: ct);
```

---

## Exception Handling

```csharp
public async UniTask LoadAsync(CancellationToken ct)
{
    try
    {
        await SomeOperationAsync(ct);
    }
    catch (OperationCanceledException)
    {
        // cancellation is normal flow — usually silently ignored
    }
    catch (Exception e)
    {
        DLog.Error(LogTag.General, e.Message);
    }
}
```

---

## In Test Assemblies

`[UnityTest]` requires `IEnumerator` due to Unity's test runner — this is the only exception:

```csharp
[UnityTest]
public IEnumerator MyTest()
{
    yield return SomeAsyncMethod(ct).ToCoroutine();
}
```
