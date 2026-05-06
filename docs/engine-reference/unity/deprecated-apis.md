# Unity 6 — Deprecated APIs to Avoid

## Forbidden (removed or breaking)

| API | Replacement |
|-----|------------|
| `Entities.ForEach(...)` | `IJobEntity` in `ISystem`, or `foreach` in `SystemBase` |
| `Resources.Load<T>()` | `Addressables.LoadAssetAsync<T>()` |
| `Input.GetKey()` / `Input.GetAxis()` | New Input System — `PlayerControls` via InputView |
| `async void` (non-lifecycle) | `async UniTask` with `CancellationToken` |
| `StartCoroutine()` | `UniTask` |
| `renderer.material` (read/write) | `renderer.sharedMaterial` (read) + `MaterialPropertyBlock` (write) |
| `FindObjectOfType<T>()` | VContainer injection |
| Static singletons | VContainer `Lifetime.Singleton` registration |

## Discouraged (still works, but avoid)

| API | Reason | Preferred |
|-----|--------|-----------|
| `UnityEngine.Random` in hot path | Allocation risk | Cache instance or use `Unity.Mathematics.Random` |
| `Debug.Log()` in production | Performance | Wrap with `[Conditional("UNITY_EDITOR")]` |
| `GameObject.tag` comparison | Allocation | `CompareTag()` |
| `SendMessage()` / `BroadcastMessage()` | Reflection, slow | `IEventBus` |
| `OnGUI()` | Immediate mode, per-frame alloc | UI Toolkit or uGUI |
| `WaitForSeconds` in coroutine | — | `UniTask.Delay()` |
