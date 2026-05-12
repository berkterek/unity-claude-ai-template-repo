---
name: unitask
description: UniTask kullanım paterni — async/await, CancellationToken, PlayerLoop entegrasyonu ve yaygın hatalar
model-tier: normal
---

# UniTask — Kullanım Paterni

## Namespace
```csharp
using Cysharp.Threading.Tasks;
```

## Temel Kurallar (NON-NEGOTIABLE)

- Coroutine (`IEnumerator`, `StartCoroutine`) yasak — her async iş `UniTask` ile yapılır
- `async void` yasak — sadece `async UniTask` kullanılır
- Her `async UniTask` metodu `CancellationToken` parametresi alır
- Fire-and-forget için `.Forget()` kullanılır, `async void` değil

---

## Metod İmzaları

```csharp
// GOOD
public async UniTask InitializeAsync(CancellationToken ct) { }
public async UniTask<int> LoadScoreAsync(CancellationToken ct) { }

// BAD
public async void Initialize() { }        // async void — exception yutulur
async Task Initialize() { }              // Task — Unity lifecycle entegrasyonu yok
IEnumerator Initialize() { yield return; } // coroutine yasak
```

---

## CancellationToken Yönetimi

### MonoBehaviour

```csharp
public sealed class PlayerView : MonoBehaviour
{
    private void Start()
    {
        // this.GetCancellationTokenOnDestroy() — object yok edildiğinde otomatik cancel
        LoadAsync(this.GetCancellationTokenOnDestroy()).Forget();
    }
}
```

### Plain C# Servis (IInitializable / IDisposable)

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

## Bekleme

```csharp
// Süre bekle
await UniTask.Delay(TimeSpan.FromSeconds(1f), cancellationToken: ct);
await UniTask.Delay(1000, cancellationToken: ct); // ms

// Frame bekle
await UniTask.Yield();
await UniTask.NextFrame();
await UniTask.WaitForFixedUpdate();
await UniTask.WaitForEndOfFrame(this);

// Koşul bekle
await UniTask.WaitUntil(() => _isReady, cancellationToken: ct);
await UniTask.WaitWhile(() => _isLoading, cancellationToken: ct);
```

---

## Paralel ve Sıralı Çalıştırma

```csharp
// Paralel — ikisi aynı anda çalışır, ikisi bitince devam eder
await UniTask.WhenAll(LoadAudioAsync(ct), LoadDataAsync(ct));

// İlk biten kazanır
await UniTask.WhenAny(WaitForInputAsync(ct), TimeoutAsync(ct));

// Sıralı
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

## Addressables ile

```csharp
// Raw .Task değil, .ToUniTask() kullanılır
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
        // cancel normal akış — genellikle sessizce yutulur
    }
    catch (Exception e)
    {
        DLog.Error(LogTag.General, e.Message);
    }
}
```

---

## Test Assembly'de

`[UnityTest]` Unity test runner'ın bir kısıtı — bu durumda `IEnumerator` zorunlu. Bu tek istisnadır:

```csharp
[UnityTest]
public IEnumerator MyTest()
{
    yield return SomeAsyncMethod(ct).ToCoroutine();
}
```
