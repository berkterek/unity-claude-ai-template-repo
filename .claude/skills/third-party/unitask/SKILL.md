---
name: unitask
description: "UniTask async/await for Unity — zero-alloc async, cancellation tokens, PlayerLoop integration, async LINQ. Use instead of coroutines for cancellation support and cleaner async code."
globs: ["**/UniTask*", "**/*Async*.cs", "**/Cysharp*"]
---

# UniTask — Zero-Allocation Async/Await for Unity

UniTask (Cysharp) provides async/await that integrates natively with Unity's PlayerLoop, produces zero GC allocations, and supports proper cancellation. Prefer UniTask over coroutines and `System.Threading.Tasks.Task` in all Unity projects.

## UniTask vs Coroutines vs System.Threading.Tasks.Task

| Feature | Coroutine | Task | UniTask |
|---------|-----------|------|---------|
| GC allocation | Enumerator + box | Task object + state machine | Zero (struct-based) |
| Cancellation | Manual flag | CancellationToken | CancellationToken |
| Return values | No | Yes | Yes |
| Exception handling | Swallowed silently | try/catch | try/catch |
| Runs on thread pool | No | Yes (dangerous in Unity) | No (PlayerLoop) |
| Awaitable | No | Yes | Yes |

## Basic Usage

### Method Signatures

```csharp
using Cysharp.Threading.Tasks;

// Awaitable, returns nothing
public async UniTask LoadLevelAsync(CancellationToken ct)
{
    await UniTask.Delay(1000, cancellationToken: ct);
}

// Awaitable, returns a value
public async UniTask<int> CalculateScoreAsync(CancellationToken ct)
{
    await UniTask.Yield(ct);
    return 100;
}

// Fire-and-forget (use sparingly, only at call boundaries)
public async UniTaskVoid OnButtonClickedAsync()
{
    await DoSomethingAsync(this.GetCancellationTokenOnDestroy());
}
```

### CRITICAL: Never Use async void

```csharp
// BAD — exceptions silently swallowed, no cancellation, GC allocation
public async void DoSomething() { ... }

// GOOD — proper error propagation, zero alloc
public async UniTask DoSomethingAsync(CancellationToken ct) { ... }

// GOOD — fire-and-forget with error logging
public async UniTaskVoid DoSomethingFireAndForget() { ... }
```

## Waiting and Delays

```csharp
// Time-based delays
await UniTask.Delay(1000, cancellationToken: ct);                    // Milliseconds
await UniTask.Delay(TimeSpan.FromSeconds(1.5f), cancellationToken: ct);

// Frame-based waits
await UniTask.Yield();                                                // Next frame
await UniTask.Yield(PlayerLoopTiming.FixedUpdate);                   // Next FixedUpdate
await UniTask.NextFrame(ct);                                          // Explicit next frame
await UniTask.DelayFrame(5, cancellationToken: ct);                  // Wait N frames

// Condition waits
await UniTask.WaitUntil(() => m_IsReady, cancellationToken: ct);
await UniTask.WaitWhile(() => m_IsLoading, cancellationToken: ct);
await UniTask.WaitUntilValueChanged(transform, t => t.position, cancellationToken: ct);

// Unity async operation wrappers
await SceneManager.LoadSceneAsync("GameScene").ToUniTask(cancellationToken: ct);
await Resources.LoadAsync<Texture2D>("myTexture").ToUniTask(cancellationToken: ct);
await UnityWebRequest.Get(url).SendWebRequest().ToUniTask(cancellationToken: ct);
```

## Cancellation Tokens

### CRITICAL: Always Pass Cancellation Tokens

Async operations that outlive their owning object cause `MissingReferenceException` and undefined behavior. Every async method must accept and respect a `CancellationToken`.

### Pattern 1: GetCancellationTokenOnDestroy (Simple)

```csharp
public class SimpleAsync : MonoBehaviour
{
    private async UniTaskVoid Start()
    {
        // Token auto-cancels when this MonoBehaviour is destroyed
        CancellationToken ct = this.GetCancellationTokenOnDestroy();

        await UniTask.Delay(2000, cancellationToken: ct);
        Debug.Log("This won't run if object was destroyed");
    }
}
```

### Pattern 2: Manual CancellationTokenSource (Enable/Disable)

```csharp
public class ManagedAsync : MonoBehaviour
{
    private CancellationTokenSource m_Cts;

    private void OnEnable()
    {
        m_Cts = new CancellationTokenSource();
        RunLoopAsync(m_Cts.Token).Forget();
    }

    private void OnDisable()
    {
        m_Cts?.Cancel();
        m_Cts?.Dispose();
        m_Cts = null;
    }

    private async UniTask RunLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await UniTask.Delay(1000, cancellationToken: ct);
            DoPeriodicWork();
        }
    }
}
```

### Pattern 3: Linked Tokens (Combine Destroy + Manual Cancel)

```csharp
public class LinkedTokenExample : MonoBehaviour
{
    private CancellationTokenSource m_ActionCts;

    public async UniTask PerformActionAsync()
    {
        // Cancel previous action if still running
        m_ActionCts?.Cancel();
        m_ActionCts?.Dispose();
        m_ActionCts = new CancellationTokenSource();

        // Link with destroy token so it cancels on either condition
        CancellationToken destroyCt = this.GetCancellationTokenOnDestroy();
        CancellationTokenSource linked = CancellationTokenSource.CreateLinkedTokenSource(
            m_ActionCts.Token, destroyCt);

        try
        {
            await DoWorkAsync(linked.Token);
        }
        catch (OperationCanceledException)
        {
            // Expected on cancellation — do nothing
        }
        finally
        {
            linked.Dispose();
        }
    }
}
```

### Handling OperationCanceledException

```csharp
public async UniTask LoadDataAsync(CancellationToken ct)
{
    try
    {
        await SomeAsyncOperation(ct);
    }
    catch (OperationCanceledException)
    {
        // Normal cancellation — cleanup silently
        return;
    }
    catch (Exception ex)
    {
        // Actual error — log and handle
        Debug.LogException(ex);
    }
}
```

## PlayerLoop Integration

UniTask hooks into Unity's PlayerLoop for precise timing control.

```csharp
// Available timing points
await UniTask.Yield(PlayerLoopTiming.Initialization);
await UniTask.Yield(PlayerLoopTiming.EarlyUpdate);
await UniTask.Yield(PlayerLoopTiming.FixedUpdate);
await UniTask.Yield(PlayerLoopTiming.PreUpdate);
await UniTask.Yield(PlayerLoopTiming.Update);
await UniTask.Yield(PlayerLoopTiming.PreLateUpdate);
await UniTask.Yield(PlayerLoopTiming.PostLateUpdate);
await UniTask.Yield(PlayerLoopTiming.LastPostLateUpdate);

// Wait for specific timing in FixedUpdate
await UniTask.WaitForFixedUpdate(ct);

// Wait for end of frame (replacement for WaitForEndOfFrame coroutine)
await UniTask.Yield(PlayerLoopTiming.LastPostLateUpdate, ct);
```

## WhenAll / WhenAny — Parallel Execution

```csharp
// Wait for all tasks to complete (parallel)
(int score, string name) = await UniTask.WhenAll(
    LoadScoreAsync(ct),
    LoadNameAsync(ct)
);

// Wait for first task to complete
int winnerIndex = await UniTask.WhenAny(
    WaitForInputAsync(ct),
    WaitForTimeoutAsync(5f, ct)
);

// Typed WhenAny with result
(bool hasResult, int result) = await UniTask.WhenAny(
    FetchFromCacheAsync(ct),
    FetchFromNetworkAsync(ct)
);

// Load multiple assets in parallel
var textures = await UniTask.WhenAll(
    paths.Select(p => LoadTextureAsync(p, ct))
);
```

## Forget and Fire-and-Forget

```csharp
// Fire and forget — logs exceptions to Debug.LogException
DoSomethingAsync(ct).Forget();

// Suppress specific cancellation exceptions
DoSomethingAsync(ct).SuppressCancellationThrow().Forget();
```

## UniTaskCompletionSource — Manual Completion

For wrapping callback-based APIs or creating custom awaitable operations.

```csharp
public class DialogSystem : MonoBehaviour
{
    private UniTaskCompletionSource<DialogResult> m_DialogTcs;

    public async UniTask<DialogResult> ShowDialogAsync(string message, CancellationToken ct)
    {
        m_DialogTcs = new UniTaskCompletionSource<DialogResult>();

        // Register cancellation
        ct.Register(() => m_DialogTcs.TrySetCanceled());

        ShowDialogUI(message);
        return await m_DialogTcs.Task;
    }

    // Called by UI buttons
    public void OnConfirmClicked() => m_DialogTcs.TrySetResult(DialogResult.Confirm);
    public void OnCancelClicked() => m_DialogTcs.TrySetResult(DialogResult.Cancel);
}
```

## Async LINQ

UniTask provides async LINQ operators for event streams.

```csharp
using Cysharp.Threading.Tasks.Linq;

// Async event stream from button clicks
button.OnClickAsAsyncEnumerable()
    .ForEachAsync(_ =>
    {
        Debug.Log("Clicked");
    }, ct);

// Throttled input
button.OnClickAsAsyncEnumerable()
    .ThrottleFirst(TimeSpan.FromSeconds(1))
    .ForEachAsync(_ => ProcessClick(), ct);

// Channel-based producer/consumer
var channel = Channel.CreateSingleConsumerUnbounded<int>();
channel.Writer.TryWrite(42);
await channel.Reader.ReadAllAsync(ct).ForEachAsync(item => Process(item));
```

## Integration with DOTween

Await DOTween animations using the DOTween-UniTask bridge.

```csharp
// Await a single tween
await transform.DOMove(targetPos, 1f)
    .SetEase(Ease.OutQuad)
    .ToUniTask(cancellationToken: ct);

// Await a sequence
Sequence seq = DOTween.Sequence();
seq.Append(transform.DOScale(1.2f, 0.2f));
seq.Append(transform.DOScale(1f, 0.2f));
await seq.ToUniTask(cancellationToken: ct);

// Sequential animation chain
await transform.DOMove(pointA, 0.5f).ToUniTask(cancellationToken: ct);
await transform.DOMove(pointB, 0.5f).ToUniTask(cancellationToken: ct);
await transform.DOMove(pointC, 0.5f).ToUniTask(cancellationToken: ct);
```

## Integration with Addressables

```csharp
// Load asset
GameObject prefab = await Addressables.LoadAssetAsync<GameObject>("EnemyPrefab")
    .ToUniTask(cancellationToken: ct);

// Instantiate
GameObject instance = await Addressables.InstantiateAsync("EnemyPrefab", position, rotation)
    .ToUniTask(cancellationToken: ct);

// Load scene
await Addressables.LoadSceneAsync("GameScene", LoadSceneMode.Additive)
    .ToUniTask(cancellationToken: ct);
```

## Common Patterns

### Async Initialization Chain

```csharp
public class GameBootstrap : MonoBehaviour
{
    private async UniTaskVoid Start()
    {
        CancellationToken ct = this.GetCancellationTokenOnDestroy();

        try
        {
            await InitializeServicesAsync(ct);
            await LoadPlayerDataAsync(ct);
            await PreloadAssetsAsync(ct);
            await LoadGameSceneAsync(ct);
        }
        catch (OperationCanceledException)
        {
            Debug.Log("Bootstrap cancelled");
        }
        catch (Exception ex)
        {
            Debug.LogException(ex);
        }
    }
}
```

### Async State Machine

```csharp
public class EnemyAI : MonoBehaviour
{
    private CancellationTokenSource m_Cts;

    private void OnEnable()
    {
        m_Cts = new CancellationTokenSource();
        RunAIAsync(m_Cts.Token).Forget();
    }

    private void OnDisable()
    {
        m_Cts?.Cancel();
        m_Cts?.Dispose();
    }

    private async UniTask RunAIAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await PatrolAsync(ct);
            await ChaseAsync(ct);
            await AttackAsync(ct);
            await UniTask.Yield(ct);
        }
    }

    private async UniTask PatrolAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !CanSeePlayer())
        {
            MoveToNextWaypoint();
            await UniTask.Delay(100, cancellationToken: ct);
        }
    }
}
```

### Timeout Wrapper

```csharp
public static async UniTask<T> WithTimeout<T>(
    UniTask<T> task,
    float timeoutSeconds,
    CancellationToken ct)
{
    int winnerIndex = await UniTask.WhenAny(
        task,
        UniTask.Delay(TimeSpan.FromSeconds(timeoutSeconds), cancellationToken: ct)
            .ContinueWith(() => default(T))
    );

    if (winnerIndex == 1)
        throw new TimeoutException($"Operation timed out after {timeoutSeconds}s");

    return await task;
}
```

### Debounced Input

```csharp
private async UniTask ProcessSearchInputAsync(TMP_InputField input, CancellationToken ct)
{
    string previousText = string.Empty;

    while (!ct.IsCancellationRequested)
    {
        await UniTask.WaitUntilValueChanged(input, i => i.text, cancellationToken: ct);

        // Debounce: wait 300ms after last change
        await UniTask.Delay(300, cancellationToken: ct);

        string currentText = input.text;
        if (currentText != previousText)
        {
            previousText = currentText;
            await PerformSearchAsync(currentText, ct);
        }
    }
}
```

## Anti-Patterns

### Do not use async void anywhere

```csharp
// BAD — exception vanishes, no cancellation
public async void OnButtonClicked() { ... }

// GOOD
public async UniTaskVoid OnButtonClickedAsync()
{
    CancellationToken ct = this.GetCancellationTokenOnDestroy();
    await HandleClickAsync(ct);
}
```

### Do not forget cancellation tokens

```csharp
// BAD — runs forever even after object is destroyed
public async UniTask BadMethod()
{
    await UniTask.Delay(5000);
    transform.position = Vector3.zero; // MissingReferenceException if destroyed
}

// GOOD
public async UniTask GoodMethod(CancellationToken ct)
{
    await UniTask.Delay(5000, cancellationToken: ct);
    transform.position = Vector3.zero;
}
```

### Do not use Task.Run or Task.Delay in Unity

```csharp
// BAD — runs on thread pool, not main thread
await Task.Run(() => transform.position = Vector3.zero);

// BAD — System.Threading timer, not Unity time-aware
await Task.Delay(1000);

// GOOD
await UniTask.SwitchToMainThread();
await UniTask.Delay(1000);
```

## Extended Reference

- [PITFALLS.md](./PITFALLS.md) — 30 concrete hallucination/runtime pitfalls with source anchors (double-await, forgotten Forget, WebGL threadpool, wrong PlayerLoopTiming)
- [CANCELLATION.md](./CANCELLATION.md) — CancellationToken patterns, GetCancellationTokenOnDestroy, AttachExternalCancellation, CancelAfterSlim
---

# UniTask Pitfalls

Sub-doc of [unitask-design](./SKILL.md). Every item below is a real pattern that breaks in production. Read this before reviewing a PR that touches async code.

Format: ❌ wrong → ✅ right, with a short WHY.

---

### 1. Awaiting the same UniTask variable twice

```csharp
var t = LoadAsync();
await t;
await t; // ❌ InvalidOperationException: Already continuation registered
```

```csharp
var t = LoadAsync().Preserve();
await t;
await t; // ✅ Preserve memoizes the source
```

**Why**: `UniTask` is a struct wrapping `(IUniTaskSource, token)`. After the first await, the source is returned to a pool and the token is stale. Source: [UniTask.cs:34-113](./BASICS.md#struct-trap-single-await-semantics).

---

### 2. Returning `UniTask` and neither awaiting nor calling `.Forget()`

```csharp
void Start() { DoLater(); } // ❌ exception swallowed
async UniTask DoLater() { await UniTask.Delay(1000); throw new Exception(); }
```

```csharp
void Start() { DoLater().Forget(); } // ✅ exception goes to UnobservedTaskException
```

**Why**: `async UniTask` fire-and-forget silently drops results. `UniTask Analyzer` warns; make sure analyzers are enabled in CI.

---

### 3. Using `async void` instead of `async UniTaskVoid`

```csharp
async void Fire() { await UniTask.Yield(); } // ❌ exceptions are unobservable; harder to track
```

```csharp
async UniTaskVoid Fire() { await UniTask.Yield(); }
void Start() => Fire().Forget(); // ✅
```

**Why**: `async void` exceptions unwind on the SynchronizationContext — on Unity that's the main thread, but exceptions bypass UniTaskScheduler's handler.

---

### 4. Forgetting to pass `CancellationToken` through the call chain

```csharp
async UniTask Outer(CancellationToken ct)
{
    await Inner(); // ❌ Inner has no token — outlives cancellation
}
```

```csharp
async UniTask Outer(CancellationToken ct)
{
    await Inner(ct); // ✅
}
```

**Why**: UniTask does NOT auto-propagate cancellation. See [CANCELLATION.md](./CANCELLATION.md).

---

### 5. `this.GetCancellationTokenOnDestroy()` on a plain C# class

```csharp
public class Service // not a MonoBehaviour
{
    public async UniTask Run()
    {
        var ct = this.GetCancellationTokenOnDestroy(); // ❌ compile error
    }
}
```

```csharp
public class Service : IDisposable
{
    readonly CancellationTokenSource _cts = new();
    public async UniTask Run() { await UniTask.Delay(1000, cancellationToken: _cts.Token); }
    public void Dispose() { _cts.Cancel(); _cts.Dispose(); }
}
```

**Why**: The extension exists only for `MonoBehaviour / GameObject / Component` at `Triggers/AsyncTriggerExtensions.cs:14,22,28`.

---

### 6. `UniTask.Delay(0)` expecting same-frame yield

```csharp
await UniTask.Delay(0); // ❌ still passes through PlayerLoop — one frame delay
```

```csharp
await UniTask.Yield(); // ✅ explicit single yield
```

**Why**: `Delay(0)` allocates a NextFramePromise and pumps through PlayerLoop. Semantically close but not identical to `Yield`.

---

### 7. Wrong `PlayerLoopTiming` for physics work

```csharp
await UniTask.Yield(PlayerLoopTiming.Update);
rigidbody.AddForce(v); // ❌ applied in Update, not FixedUpdate — stutter
```

```csharp
await UniTask.Yield(PlayerLoopTiming.FixedUpdate);
rigidbody.AddForce(v); // ✅
```

**Why**: Physics integrates on `FixedUpdate`. Force applied in `Update` gets integrated on the NEXT FixedUpdate — fine for most cases but wrong if you're coordinating with multi-step physics.

---

### 8. `WaitForEndOfFrame` without `coroutineRunner` on Unity < 2023.1

```csharp
await UniTask.WaitForEndOfFrame(); // ❌ compile error on 2022.3
```

```csharp
await UniTask.WaitForEndOfFrame(this); // ✅ pre-2023.1
await UniTask.WaitForEndOfFrame();     // ✅ 2023.1+
```

**Why**: The parameterless overload is gated by `#if UNITY_2023_1_OR_NEWER` at `UniTask.Delay.cs:78-89`.

---

### 9. `UniTask.Run` / `SwitchToThreadPool` on WebGL

```csharp
await UniTask.RunOnThreadPool(() => Compute()); // ❌ NotSupportedException on WebGL
```

```csharp
#if UNITY_WEBGL && !UNITY_EDITOR
    var result = Compute();
#else
    var result = await UniTask.RunOnThreadPool(() => Compute());
#endif
```

**Why**: WebGL is single-threaded. Source: `UniTask.Threading.cs:57`.

---

### 10. Accessing Unity API after `SwitchToThreadPool`

```csharp
await UniTask.SwitchToThreadPool();
var pos = transform.position; // ❌ UnityException: get_position can only be called from the main thread
```

```csharp
await UniTask.SwitchToThreadPool();
var data = ExpensiveCompute();
await UniTask.SwitchToMainThread();
transform.position = data.Result; // ✅
```

---

### 11. Yielding a UniTask from a Coroutine

```csharp
IEnumerator Legacy()
{
    yield return SomeUniTask(); // ❌ Coroutine doesn't understand UniTask
}
```

```csharp
IEnumerator Legacy()
{
    yield return SomeUniTask().ToCoroutine();
}
```

**Why**: UniTask is not `IEnumerator` — must be adapted. See [CONVERSION.md](./CONVERSION.md).

---

### 12. `WaitUntil` with a predicate that never yields to PlayerLoop

```csharp
await UniTask.WaitUntil(() => _flag); // ❌ if _flag is flipped from async context on WebGL without yielding, deadlock
```

```csharp
await UniTask.WaitUntil(() => _flag);
// or ensure the setter runs on a PlayerLoop-pumped path
```

**Why**: `WaitUntil` polls on every `PlayerLoopTiming.Update`. WebGL has only one thread, so predicate + setter must share the pump.

---

### 13. Tree-shaking kills `Preserve()` users

```csharp
var t = LoadAsync();
await UniTask.WhenAll(Use1(t), Use2(t)); // ❌ each WhenAll takes ownership — second await fails
```

```csharp
var t = LoadAsync().Preserve();
await UniTask.WhenAll(Use1(t), Use2(t)); // ✅
```

---

### 14. `AsyncReactiveProperty` left undisposed

```csharp
var hp = new AsyncReactiveProperty<int>(100);
hp.ForEachAsync(v => _bar.value = v, ct).Forget();
// ❌ hp never disposed — subscribers reference leaked
```

```csharp
using var hp = new AsyncReactiveProperty<int>(100);
// ...
```

---

### 15. `.Subscribe()` return value ignored

```csharp
stream.Subscribe(x => Handle(x)); // ❌ runs until stream completes — may be never
```

```csharp
stream.Subscribe(x => Handle(x)).AddTo(ct); // ✅ disposes on cancel
```

---

### 16. `UniTaskTracker` window shipped in release builds

The `UniTask Tracker` editor window (Window → UniTask → Tracker) relies on `TaskTracker.cs` which wraps every UniTask in a linked-list entry. `TaskTracker.EnableTracking = false` by default in release — ensure it stays false and not toggled at runtime in shipped builds.

---

### 17. `UniTask.Void` with a method that throws before first `await`

```csharp
UniTask.Void(async () => { throw new Exception("boom"); }); // ❌ thrown synchronously, goes to UnobservedTaskException
```

`UniTask.Void` routes through `.Forget()`, so exceptions DO go through the scheduler's handler — but the caller is not notified. Use only for deliberately isolated work.

---

### 18. DOTween tween via `AsyncWaitForCompletion` instead of `.ToUniTask()`

```csharp
await tween.AsyncWaitForCompletion(); // ❌ returns Task — allocates
```

```csharp
await tween.ToUniTask(TweenCancelBehaviour.KillAndCancelAwait, ct); // ✅ UniTask-native
```

**Why**: `AsyncWaitForCompletion` lives in DOTween's Module file (`DOTweenModuleUnityVersion.cs:216`). The UniTask bridge is `External/DOTween/DOTweenAsyncExtensions.cs:54`.

---

### 19. `SendWebRequest().ToUniTask()` with `null` progress when caller expected progress

```csharp
await UnityWebRequest.Get(url).SendWebRequest().ToUniTask(); // ❌ no progress
```

```csharp
await UnityWebRequest.Get(url).SendWebRequest().ToUniTask(
    progress: Progress.Create<float>(p => _bar.value = p));
```

---

### 20. Mixing `try/finally` cleanup with cancellation

```csharp
try
{
    await UniTask.Delay(10000, cancellationToken: ct);
    File.WriteAllText(path, "done");
}
finally
{
    // ❌ runs on cancel too — writes partial state
    File.WriteAllText(path, "done"); // wrong copy!
}
```

Always check token state in finally:

```csharp
finally
{
    if (!ct.IsCancellationRequested) File.WriteAllText(path, "done");
}
```

---

### 21. Test using real `UniTask.Delay` blocks test runner

```csharp
[Test]
public async Task MyTest()
{
    await UniTask.Delay(5000); // ❌ actually waits 5s
}
```

```csharp
[Test]
public async Task MyTest()
{
    await UniTask.DelayFrame(1); // or use EditMode-friendly mock clock
}
```

---

### 22. PlayerLoop not registered after Enter Play Mode (fast mode)

With Enter Play Mode Options → Reload Domain: Off, UniTask's static state may not re-initialize. Source: `PlayerLoopHelper.cs` registers via `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]`. Ensure this attribute is present on your custom PlayerLoop registrations too.

---

### 23. Custom `SynchronizationContext` fighting `UniTaskSynchronizationContext`

If your code calls `SynchronizationContext.SetSynchronizationContext(mine)` before UniTask initializes, UniTask's continuations may run on the wrong context. UniTask sets its own on startup — don't override it.

---

### 24. `async void` handler attached to `Button.onClick`

```csharp
button.onClick.AddListener(async () => await DoWork()); // ❌ async void semantics
```

```csharp
button.onClick.AddListener(() => DoWork().Forget());
// or
button.OnClickAsAsyncEnumerable().ForEachAsync(_ => DoWorkHandler(), ct).Forget();
```

---

### 25. Chain-`.Forget()`ing a UniTask you wanted to await

```csharp
await LoadAsync().Forget(); // ❌ .Forget returns void — compile error
```

```csharp
await LoadAsync(); // ✅
// or
LoadAsync().Forget(); // fire and forget
```

---

### 26. Deep `async UniTask` stack traces missing frames

UniTask's struct-based state machine trims stack traces more aggressively than `Task`. Enable `DEBUG_SYMBOLS` on the UniTask assembly in development builds to preserve more frames. Source: `Internal/DiagnosticsExtensions.cs`.

---

### 27. Addressables / YooAsset adapter version drift

`External/Addressables/AddressablesAsyncExtensions.cs:3` is gated by `#if UNITASK_ADDRESSABLE_SUPPORT` (singular `ADDRESSABLE`, NOT `ADDRESSABLES`). The asmdef Version Defines must pick up the Addressables package — if your project uses a forked or custom-named package, the define is not set and the extension disappears silently.

---

### 28. `GetCancellationTokenOnDestroy` vs `GetAsyncDestroyToken`

Both exist and return the same token in practice, but the `GetAsyncDestroyToken` naming appears in older docs. Use `GetCancellationTokenOnDestroy` — that's the name in current source at `AsyncTriggerExtensions.cs:14`.

---

### 29. Using UniTask inside a Job System `IJob`

```csharp
public struct MyJob : IJob
{
    public async UniTask Execute() { ... } // ❌ Burst / Jobs require pure struct, no async state machine
}
```

Jobs must be synchronous, unmanaged-compatible structs. UniTask is a managed async primitive — incompatible. Bridge via a MonoBehaviour that schedules jobs and awaits `JobHandle.Complete()`.

---

### 30. `UniTask.FromException` fires UnobservedTaskException handler

```csharp
UniTask.FromException(ex).Forget(); // ❌ still routes to UnobservedTaskException because no one awaited
```

If you want exception handling, await or pass a handler to `Forget(ex => ...)`.

---

## How to use this list

- **Code review**: Open a PR diff and scan for any of these patterns.
- **CI**: Configure the `UniTask.Analyzer` Roslyn analyzer to catch #2, #3, #24 automatically.
- **Onboarding**: New team members read this list once before writing their first `async UniTask` method.

When one of these bites you anyway, add the reproduction to your project's `docs/async-incidents.md` with a link back to the rule above.

---

# UniTask Cancellation

Sub-doc of [unitask-design](./SKILL.md). Cancellation is the part of UniTask most often done wrong. The source lives in `CancellationTokenExtensions.cs`, `CancellationTokenSourceExtensions.cs`, and `Triggers/AsyncTriggerExtensions.cs`.

## The core model

UniTask uses standard `System.Threading.CancellationToken` / `CancellationTokenSource`. When a token is canceled:

1. If a UniTask method observes it via `token.ThrowIfCancellationRequested()` or uses it in an API that does (`Delay`, `WaitUntil`, etc.), it throws `OperationCanceledException`.
2. `OperationCanceledException` propagates up the `async` stack like any exception.
3. The final `await` in the chain sees the exception. Callers choose to catch, rethrow, or suppress.

UniTask does NOT automatically cascade cancellation into child tasks. If you call `await ChildAsync()` without passing the token, the child runs to completion even after the parent's token is canceled.

## `CancellationTokenOnDestroy` — MonoBehaviour integration

Defined in `Triggers/AsyncTriggerExtensions.cs:14,22,28`:

```csharp
public static CancellationToken GetCancellationTokenOnDestroy(this MonoBehaviour monoBehaviour);
public static CancellationToken GetCancellationTokenOnDestroy(this GameObject gameObject);
public static CancellationToken GetCancellationTokenOnDestroy(this Component component);
```

Implementation detail: the extension attaches a hidden `AsyncDestroyTrigger` component to the GameObject that signals cancellation on `OnDestroy`. The trigger is cached so repeated calls return the same token.

```csharp
public class Enemy : MonoBehaviour
{
    async UniTaskVoid Start()
    {
        // Token is canceled when this GameObject is destroyed
        var ct = this.GetCancellationTokenOnDestroy();
        await RoamAsync(ct);
    }
}
```

**Non-MonoBehaviour classes do NOT have this extension** — `this.GetCancellationTokenOnDestroy()` on a plain C# class is a compile error. Pattern for plain classes:

```csharp
public class EnemyAI : IDisposable
{
    readonly CancellationTokenSource _cts = new();
    public CancellationToken Token => _cts.Token;

    public async UniTask RunAsync()
    {
        await UniTask.Delay(1000, cancellationToken: _cts.Token);
    }

    public void Dispose()
    {
        _cts.Cancel();
        _cts.Dispose();
    }
}
```

## Passing tokens through the call chain

**Rule**: Every `async UniTask` method that eventually calls a cancellation-aware primitive (`Delay`, `WaitUntil`, `AsyncOperation.ToUniTask`, etc.) must accept a `CancellationToken` parameter and pass it down.

```csharp
// ❌ Token is not forwarded — Delay ignores cancellation
async UniTask BadChain(CancellationToken ct)
{
    await UniTask.Delay(1000); // no ct!
}

// ✅ Forward explicitly
async UniTask GoodChain(CancellationToken ct)
{
    await UniTask.Delay(1000, cancellationToken: ct);
    await SomeOtherAsync(ct);
}
```

`ct.ThrowIfCancellationRequested()` after every yield is idiomatic defensive practice:

```csharp
while (!ct.IsCancellationRequested)
{
    await UniTask.Yield(ct);
    DoWork();
}
ct.ThrowIfCancellationRequested();
```

## `AttachExternalCancellation` — wrap an uncancelable UniTask

For third-party UniTask returns that don't accept a token:

```csharp
// LibraryMethod returns UniTask without a token parameter
await thirdParty.LibraryMethodAsync().AttachExternalCancellation(ct);
```

This wraps the original UniTask and throws `OperationCanceledException` on the outer `await` if the token fires before the inner task completes. The inner task continues running to completion in the background — `AttachExternalCancellation` does NOT cancel the underlying operation, it only cancels the *wait*.

## `SuppressCancellationThrow` — cancel-aware return

Instead of throwing, return a `UniTask<bool>` indicating whether cancellation happened:

```csharp
bool isCanceled = await SomeAsync(ct).SuppressCancellationThrow();
if (isCanceled) { /* handle */ }
```

For `UniTask<T>`, the return is `UniTask<(bool IsCanceled, T Result)>`. Source: `UniTask.cs:68-74` and the `IsCanceledSource` type.

## `WaitUntilCanceled` — turn token into awaitable

```csharp
// CancellationTokenExtensions.cs:80-83
public static CancellationTokenAwaitable WaitUntilCanceled(this CancellationToken ct);
```

```csharp
// Run forever, complete when token fires
await ct.WaitUntilCanceled();
Debug.Log("Shutting down");
```

## `CancelAfterSlim` — low-alloc timeout

Source: `CancellationTokenSourceExtensions.cs:22,27`:

```csharp
public static IDisposable CancelAfterSlim(this CancellationTokenSource cts,
    int millisecondsDelay,
    DelayType delayType = DelayType.DeltaTime,
    PlayerLoopTiming delayTiming = PlayerLoopTiming.Update);

public static IDisposable CancelAfterSlim(this CancellationTokenSource cts,
    TimeSpan delayTimeSpan,
    DelayType delayType = DelayType.DeltaTime,
    PlayerLoopTiming delayTiming = PlayerLoopTiming.Update);
```

Both overloads return an `IDisposable` you can dispose to cancel the pending timer (e.g., when the work finished before the timeout). Internally routes through `PlayerLoopTimer.StartNew`, so it uses UniTask's PlayerLoop pump — zero `System.Threading.Timer` allocation.

```csharp
using var cts = new CancellationTokenSource();
var timer = cts.CancelAfterSlim(TimeSpan.FromSeconds(5));
try
{
    await DoLongWorkAsync(cts.Token);
    timer.Dispose(); // cancel the timer if work finished in time
}
catch (OperationCanceledException) { /* timeout fired */ }
```

Equivalent intent to `cts.CancelAfter(5000)` but uses UniTask's PlayerLoop-based timer instead of `System.Threading.Timer`.

## `RegisterRaiseCancelOnDestroy` — tie CTS to a GameObject

`CancellationTokenSourceExtensions.cs:32,37`:

```csharp
public static void RegisterRaiseCancelOnDestroy(this CancellationTokenSource cts, Component component);
public static void RegisterRaiseCancelOnDestroy(this CancellationTokenSource cts, GameObject gameObject);
```

Attaches an `AsyncDestroyTrigger` to the GameObject so its `OnDestroy` calls `cts.Cancel()`. Useful when you own a CTS (for composed work) but want Unity destruction to feed into it automatically.

## `AddTo` — dispose on cancel

```csharp
// CancellationTokenExtensions.cs:129-132
public static CancellationTokenRegistration AddTo(this IDisposable disposable, CancellationToken cancellationToken);
```

```csharp
// Dispose the subscription when ct is canceled
someDisposable.AddTo(ct);
```

Useful for releasing `IAsyncDisposable` wrappers, `IUniTaskAsyncEnumerable<T>` subscriptions, or UniRx-style resources.

## `ToCancellationToken` — UniTask → token

```csharp
// CancellationTokenExtensions.cs:14-47
public static CancellationToken ToCancellationToken(this UniTask task);
public static CancellationToken ToCancellationToken(this UniTask task, CancellationToken linkToken);
public static CancellationToken ToCancellationToken<T>(this UniTask<T> task);
public static CancellationToken ToCancellationToken<T>(this UniTask<T> task, CancellationToken linkToken);
```

Creates a token that cancels when the UniTask completes (success, fault, or cancel). Useful for "cancel when X finishes" patterns.

## `CreateLinkedTokenSource` — combine tokens

Standard BCL API (`CancellationTokenSource.CreateLinkedTokenSource`) composes well:

```csharp
using var linked = CancellationTokenSource.CreateLinkedTokenSource(
    this.GetCancellationTokenOnDestroy(),
    externalCts.Token);
await DoWorkAsync(linked.Token);
```

## Lifecycle checklist

- [ ] Every `async UniTask` method that calls a cancellation-aware primitive accepts `CancellationToken` and forwards it.
- [ ] Non-MonoBehaviour classes that need destruction-aware cancellation own their own `CancellationTokenSource` and dispose it.
- [ ] `CancellationTokenSource` created inside a method is disposed in `finally` (or `using var`).
- [ ] Caller-side handling of `OperationCanceledException` is intentional — catch and log (for UI) vs. let propagate (for fire-and-forget).
- [ ] Timeouts use `CancelAfterSlim` (UniTask-native) rather than `CancellationTokenSource.CancelAfter` (which allocates a `System.Threading.Timer`).
- [ ] External disposables are tied to tokens via `.AddTo(ct)` when lifetime is token-scoped.

## Common pitfalls (full list in [PITFALLS.md](./PITFALLS.md))

- Forgetting to pass the token — child operation outlives parent cancellation.
- Calling `GetCancellationTokenOnDestroy()` on a plain C# class — compile error.
- Disposing a CTS that has outstanding registrations without a try/finally — ObjectDisposedException on cancel.
- Canceling a CTS twice — second `Cancel()` is a no-op but `Dispose()` on an already-disposed CTS throws.
