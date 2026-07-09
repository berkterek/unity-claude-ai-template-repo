# Unity Async Rules — UniTask

> Read the **Cards** section first. The prose below is reference detail.

## Cards

### Card 1: No Coroutines — UniTask Only

**WHEN:** Any async operation: delays, loading, HTTP calls, waiting for conditions.

**WRONG:**
```csharp
private IEnumerator WaitAndDo() { yield return new WaitForSeconds(1f); DoSomething(); }
StartCoroutine(WaitAndDo());
```

**RIGHT:**
```csharp
private async UniTask WaitAndDoAsync(CancellationToken ct)
{
    await UniTask.Delay(TimeSpan.FromSeconds(1), cancellationToken: ct);
    DoSomething();
}
```

**GOTCHA:** Coroutines stop silently when `gameObject.SetActive(false)` and don't resume. UniTask throws `OperationCanceledException` instead, which is catchable and auditable.

---

### Card 2: Always Pass CancellationToken

**WHEN:** Writing any `async UniTask` method.

**WRONG:**
```csharp
public async UniTask LoadAsync() { await UniTask.Delay(1000); } // no cancellation
```

**RIGHT:**
```csharp
public async UniTask LoadAsync(CancellationToken ct)
{
    await UniTask.Delay(1000, cancellationToken: ct);
}
// In MonoBehaviour: this.GetCancellationTokenOnDestroy()
// In service: own a CancellationTokenSource, cancel in Dispose()
```

**GOTCHA:** Without a token, async tasks outlive their owning object. If the object is destroyed mid-task, you get NullReferenceException on the next Unity API call inside the task.

---

### Card 3: Naked .Forget() Swallows Exceptions

**WHEN:** Fire-and-forget async calls.

**WRONG:**
```csharp
InitializeAsync(ct).Forget(); // swallows ALL exceptions including NullReferenceException
```

**RIGHT:**
```csharp
InitializeAsync(ct).Forget(ex =>
{
    if (ex is OperationCanceledException) return; // expected on scope dispose
    Debug.LogException(ex);
});
```

**GOTCHA:** A naked `.Forget()` is only acceptable for throw-proof bodies (e.g. `await UniTask.Yield()` only). Add `// safe: throw-proof body` comment when you intentionally omit the handler.

---

### Card 4: async void is Forbidden

**WHEN:** Declaring any fire-and-forget async method.

**WRONG:**
```csharp
async void Initialize() { await LoadAsync(_ct); } // exception silently crashes the game
```

**RIGHT:**
```csharp
// Option A — return UniTask, let the caller await or Forget() with handler
private async UniTask InitializeAsync(CancellationToken ct) { }

// Option B — fire-and-forget with explicit error handling
private void StartLoad() => LoadAsync(_cts.Token).Forget(ex => Debug.LogException(ex));
```

**GOTCHA:** `async void` is only allowed on Unity lifecycle methods (`Awake`, `Start`, `OnEnable`, `OnDisable`, `OnDestroy`) when the framework requires it. `check-async-void.sh` warns on all other uses.

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

Additive loading never changes the active scene. After the additive load completes, explicitly call `SceneManager.SetActiveScene(...)` on the newly loaded scene and `SceneManager.UnloadSceneAsync(...)` on the now-empty Bootstrap scene — otherwise Bootstrap stays loaded and active forever with nothing in it. Full pattern and code: `rules/bootstrap-pattern.md` → Card 6.
