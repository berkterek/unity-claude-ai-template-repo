---
name: netcode
description: >
  Netcode for GameObjects (NGO) 2.x architecture rules and hallucination guards. Load before writing
  any code involving NetworkBehaviour, RPC, NetworkVariable, NetworkList, Spawn/Despawn,
  NetworkSceneManager or UnityTransport. This skill rests on rules verified against NGO 2.x source
  — trigger on the words NGO, multiplayer, NetworkManager, NetworkObject, ServerRpc, ClientRpc,
  IsOwner, IsServer, IsHost. The catch: this project's VContainer and UniTask usage collides with
  NGO's lifecycle order — do not write NGO code without reading this file.
user-invocable: true
---

# Netcode for GameObjects 2.x — Mimari Rehber

This project uses **VContainer** and **UniTask**. NGO brings its own lifecycle —
`OnNetworkSpawn`, `OnNetworkDespawn` and `[Rpc]` attributes must be integrated carefully with VContainer injection.

## Kritik Kurallar — Ezbere Bil

| # | Kural | Kaynak |
|---|-------|--------|
| 1 | `Spawn()` / `Despawn()` may only be called on Server/Host | `NetworkObject.cs:1884, 1921` |
| 2 | `OnNetworkSpawn()` runs **before** Unity `Start()` and **after** `Awake`/`OnEnable` | `NetworkBehaviour.cs:704` |
| 3 | A legacy `[ServerRpc]` method name must end in `ServerRpc`; `[ClientRpc]` in `ClientRpc` (ILPP enforces at compile time) | `Editor/CodeGen/` |
| 4 | The new `[Rpc(SendTo.X)]` has no naming constraint; `SendTo` has 11 values | `RpcTarget.cs:9-80` |
| 5 | `PlayerPrefab` must be registered in `NetworkPrefabsList` or `NetworkConfig.Prefabs` | `NetworkConfig.cs:40` |
| 6 | **Nested NetworkObjects are forbidden** — a NetworkObject prefab cannot live inside another NetworkObject | `NetworkObject.cs:2135-2215` |
| 7 | `NetworkVariable<T>` → `T` `unmanaged` veya `INetworkSerializable` implement etmeli. `string`, `List<>`, `class` kabul edilmez | `NetworkVariable.cs:12` |
| 8 | `NetworkList<T>` → `T: unmanaged, IEquatable<T>`. **Not** the same thing as `NetworkVariable<List<T>>` | `NetworkList.cs:14` |
| 9 | `NetworkSceneManager.LoadScene/UnloadScene` sadece Server'da | `NetworkSceneManager.cs:1496` |
| 10 | `SetRelayServerData` and `SetConnectionData` are **mutually exclusive** — never call both | `UnityTransport.cs:776-897` |

## Integration Rules Specific to This Project

### VContainer + NGO

NGO `NetworkBehaviour` classes do **not** support VContainer injection — the `[Inject]` attribute does not work.

```csharp
// WRONG — NetworkBehaviour does not take constructor injection
public class PlayerNetworkView : NetworkBehaviour
{
    [Inject] // this does not work
    public void Construct(IPlayerService service) { }
}

// RIGHT — the NetworkBehaviour gets its service reference from the scene
public class PlayerNetworkView : NetworkBehaviour
{
    [SerializeField] private PlayerProvider _provider; // same prefab

    public override void OnNetworkSpawn()
    {
        // resolve from the scene's VContainer scope
        var container = LifetimeScope.Find<GameScope>().Container;
        _playerService = container.Resolve<IPlayerService>();
    }
}
```

Alternative: use `NetworkBehaviour` as a thin adapter and delegate the real logic to a separate service.

### UniTask + NGO Lifecycle

To start async work inside `OnNetworkSpawn`:

```csharp
public override void OnNetworkSpawn()
{
    _cts = new CancellationTokenSource();
    InitializeAsync(_cts.Token).Forget(ex =>
    {
        if (ex is not OperationCanceledException) Debug.LogException(ex);
    });
}

public override void OnNetworkDespawn()
{
    _cts?.Cancel();
    _cts?.Dispose();
}
```

### NetworkVariable ile IEventBus

Bridge `NetworkVariable` changes to `IEventBus` — never build a direct cross-module reference:

```csharp
public NetworkVariable<int> Score = new(0,
    NetworkVariableReadPermission.Everyone,
    NetworkVariableWritePermission.Server);

public override void OnNetworkSpawn()
{
    Score.OnValueChanged += OnScoreChanged;
}

public override void OnNetworkDespawn()
{
    Score.OnValueChanged -= OnScoreChanged;
}

private void OnScoreChanged(int prev, int next)
{
    _eventBus.Publish(new ScoreChangedEvent(next));
}
```

## Hallucination Guard

```
❌ NetworkManager.Singleton          → singletons are forbidden here; place NetworkManager in the scene
❌ NetworkObject.NetworkObjectId      → do not confuse with GlobalObjectIdHash; different things
❌ [ClientRpc] void MyMethod()        → NGO 2.x'te yeni syntax: [Rpc(SendTo.ClientsAndHost)]
❌ NetworkVariable<string>            → string is not unmanaged; use FixedString32Bytes
❌ NetworkVariable<List<T>>           → NetworkList<T> kullan
❌ Spawn() on a Client                → Server/Host only; guard it with an IsServer check
❌ NetworkObject via new GameObject() → Instantiate from a prefab, then Spawn()
```

## Sub-doc Routing

Read the reference file that matches the topic:

| Konu | Dosya |
|------|-------|
| Lifecycle order (Awake → OnNetworkSpawn → Start) | [references/LIFECYCLE.md](references/LIFECYCLE.md) |
| IsOwner/IsServer/IsHost permission matrix | [references/OWNERSHIP.md](references/OWNERSHIP.md) |
| RPC choice, `SendTo` semantics, deprecated paths | [references/RPC.md](references/RPC.md) |
| NetworkVariable/NetworkList init ve serialization | [references/VARIABLES.md](references/VARIABLES.md) |
| Prefab registration → Spawn → Despawn flow | [references/SPAWNING.md](references/SPAWNING.md) |
| NetworkSceneManager, EnableSceneManagement | [references/SCENE.md](references/SCENE.md) |
| UnityTransport direct / Relay / DebugSimulator | [references/TRANSPORT.md](references/TRANSPORT.md) |
| 30 concrete hallucination traps | [references/PITFALLS.md](references/PITFALLS.md) |

## Versiyon

`com.unity.netcode.gameobjects` **2.x** (2.11.0, verified against Unity 6000.0+).
In 1.x, `SendTo.Authority`, `RpcInvokePermission` and the universal `[Rpc]` attribute **do not exist**.
