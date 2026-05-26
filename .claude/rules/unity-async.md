# Unity Async Rules — UniTask

## No Coroutines — Use UniTask

Do not use `StartCoroutine` / `IEnumerator` / `yield return`. Use UniTask for all async work.

Coroutine problems that UniTask solves:
- Coroutines stop silently when `gameObject.SetActive(false)` and don't resume
- Coroutines have no cancellation, error handling, or return values
- Coroutines allocate on the heap

```csharp
// BAD — coroutine
private IEnumerator WaitAndDo()
{
    yield return new WaitForSeconds(1f);
    DoSomething();
}

// GOOD — UniTask
private async UniTask WaitAndDoAsync(CancellationToken token)
{
    await UniTask.Delay(TimeSpan.FromSeconds(1), cancellationToken: token);
    DoSomething();
}
```

Always pass `CancellationToken`. In Views: `this.GetCancellationTokenOnDestroy()`. In Systems: own a `CancellationTokenSource` and cancel in `Dispose()`.

**Exception — Test Assemblies:** `[UnityTest]` requires `IEnumerator` by Unity's test runner. This is a technical constraint, not a violation of the rule.

## Fire-and-Forget

`.Forget()` discards the returned `UniTask` so the call site doesn't have to `await`. **Naked `.Forget()` swallows every exception** — including `NullReferenceException` from destroyed objects. Always pair it with an exception handler.

```csharp
// BAD — silently swallows all exceptions, impossible to debug
InitializeAsync(ct).Forget();

// BAD — async void cannot be awaited or cancelled
async void Initialize() { }

// GOOD — log unexpected failures, ignore expected cancellations
InitializeAsync(ct).Forget(ex =>
{
    if (ex is OperationCanceledException) return;
    Debug.LogException(ex);
});
```

If a method is genuinely throw-proof (e.g. only `await UniTask.Yield()`), a bare `.Forget()` is acceptable — leave a `// safe: throw-proof body` comment.

## CancellationToken — Mandatory Pattern

Every async method takes a `CancellationToken`. Bind to lifecycle:

```csharp
public class StoreService : IInitializable, IDisposable
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

## DontDestroyOnLoad

Use sparingly. Prefer a bootstrapper scene pattern:

```
BootstrapScene (loads once, contains persistent services)
    → Additively loads GameScene, MenuScene, etc.
```
