# Unity 6 — Breaking Changes & Post-Cutoff Notes

## DOTS / ECS

| Change | Risk | Action |
|--------|------|--------|
| `Entities.ForEach` deprecated | HIGH | Use `IJobEntity` + `SystemAPI.Query<>` instead |
| `WithoutBurst().Run()` pattern | MEDIUM | Still works but `IJobEntity` preferred for new code |
| `EntityCommandBufferSystem` singleton access | MEDIUM | Use `SystemAPI.GetSingleton<BeginSimulationEntityCommandBufferSystem.Singleton>()` |
| `ComponentSystemGroup` ordering | LOW | Declare `[UpdateInGroup]` explicitly — implicit ordering changed |

## Rendering / URP

| Change | Risk | Action |
|--------|------|--------|
| `Camera.main` caching | LOW | Still needed — cache in Awake |
| `UniversalRenderPipelineAsset` API | MEDIUM | Some quality settings moved; verify renderer feature API |
| `RenderTexture` pooling | LOW | Use `RenderTexture.GetTemporary` / `ReleaseTemporary` |

## Addressables

| Change | Risk | Action |
|--------|------|--------|
| `Addressables.LoadAssetAsync` | LOW | API stable; always use `.ToUniTask(ct)` |
| `AsyncOperationHandle.Task` | LOW | Prefer `.ToUniTask()` over raw `.Task` |

## UI Toolkit (Runtime)

| Change | Risk | Action |
|--------|------|--------|
| `RuntimePanelUtils` | MEDIUM | Verify screen-to-panel coordinate conversion |
| Data binding API | HIGH | Runtime data binding API changed between 2023-2024 releases; verify |

## Netcode for GameObjects

| Change | Risk | Action |
|--------|------|--------|
| `NetworkManager` singleton | MEDIUM | Use VContainer bridge; don't reference static directly |
| `NetworkBehaviour.IsOwner` | LOW | Stable |
| `NetworkList<T>` | MEDIUM | Verify serialization constraints for custom types |
