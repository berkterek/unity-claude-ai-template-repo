---
name: netcode
description: >
  Netcode for GameObjects (NGO) 2.x mimari kuralları ve hallucination guard'ları. NetworkBehaviour,
  RPC, NetworkVariable, NetworkList, Spawn/Despawn, NetworkSceneManager veya UnityTransport hakkında
  herhangi bir kod yazılmadan önce yükle. Bu skill NGO 2.x kaynak kodundan doğrulanmış kurallara
  dayanır — NGO, multiplayer, NetworkManager, NetworkObject, ServerRpc, ClientRpc, IsOwner, IsServer,
  IsHost sözcükleri geçtiğinde tetikle. Eğlenceli kısım: bu projedeki VContainer ve UniTask
  kullanımı NGO lifecycle sırasıyla çakışır — bu dosyayı okumadan NGO kodu yazma.
user-invocable: true
---

# Netcode for GameObjects 2.x — Mimari Rehber

Bu proje **VContainer** ve **UniTask** kullanıyor. NGO kendi lifecycle'ını getiriyor —
`OnNetworkSpawn`, `OnNetworkDespawn` ve `[Rpc]` attribute'ları VContainer injection ile dikkatli entegre edilmeli.

## Kritik Kurallar — Ezbere Bil

| # | Kural | Kaynak |
|---|-------|--------|
| 1 | `Spawn()` / `Despawn()` sadece Server/Host'ta çağrılır | `NetworkObject.cs:1884, 1921` |
| 2 | `OnNetworkSpawn()` Unity `Start()`'tan **önce**, `Awake`/`OnEnable`'dan **sonra** çalışır | `NetworkBehaviour.cs:704` |
| 3 | Legacy `[ServerRpc]` metod adı `ServerRpc` ile bitmeli; `[ClientRpc]` → `ClientRpc` ile (ILPP compile-time zorlar) | `Editor/CodeGen/` |
| 4 | Yeni `[Rpc(SendTo.X)]` isim kısıtlaması yok; `SendTo` 11 değere sahip | `RpcTarget.cs:9-80` |
| 5 | `PlayerPrefab` mutlaka `NetworkPrefabsList` veya `NetworkConfig.Prefabs`'ta kayıtlı olmalı | `NetworkConfig.cs:40` |
| 6 | **İç içe NetworkObject yasak** — bir NetworkObject prefabı başka bir NetworkObject içinde olamaz | `NetworkObject.cs:2135-2215` |
| 7 | `NetworkVariable<T>` → `T` `unmanaged` veya `INetworkSerializable` implement etmeli. `string`, `List<>`, `class` kabul edilmez | `NetworkVariable.cs:12` |
| 8 | `NetworkList<T>` → `T: unmanaged, IEquatable<T>`. `NetworkVariable<List<T>>` ile aynı şey **değil** | `NetworkList.cs:14` |
| 9 | `NetworkSceneManager.LoadScene/UnloadScene` sadece Server'da | `NetworkSceneManager.cs:1496` |
| 10 | `SetRelayServerData` ve `SetConnectionData` **birbirini dışlar** — ikisini birden çağırma | `UnityTransport.cs:776-897` |

## Bu Projeye Özgü Entegrasyon Kuralları

### VContainer + NGO

NGO `NetworkBehaviour` sınıfları VContainer injection **desteklemez** — `[Inject]` attribute çalışmaz.

```csharp
// YANLIŞ — NetworkBehaviour constructor injection almaz
public class PlayerNetworkView : NetworkBehaviour
{
    [Inject] // Bu çalışmaz
    public void Construct(IPlayerService service) { }
}

// DOĞRU — NetworkBehaviour servis referansını sahneden alır
public class PlayerNetworkView : NetworkBehaviour
{
    [SerializeField] private PlayerProvider _provider; // aynı prefab içi

    public override void OnNetworkSpawn()
    {
        // Sahnedeki VContainer scope'tan çöz
        var container = LifetimeScope.Find<GameScope>().Container;
        _playerService = container.Resolve<IPlayerService>();
    }
}
```

Alternatif: `NetworkBehaviour`'ı thin adapter olarak kullan, asıl mantığı ayrı bir servise delege et.

### UniTask + NGO Lifecycle

`OnNetworkSpawn` içinde async işlem başlatmak için:

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

`NetworkVariable` değişimini `IEventBus`'a köprüle — doğrudan cross-module referans kurma:

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
❌ NetworkManager.Singleton          → proje singleton yasak; NetworkManager sahneye yerleştirilmeli
❌ NetworkObject.NetworkObjectId      → GlobalObjectIdHash ile karıştırma; farklı şeyler
❌ [ClientRpc] void MyMethod()        → NGO 2.x'te yeni syntax: [Rpc(SendTo.ClientsAndHost)]
❌ NetworkVariable<string>            → string unmanaged değil; FixedString32Bytes kullan
❌ NetworkVariable<List<T>>           → NetworkList<T> kullan
❌ Spawn() Client'ta                  → sadece Server/Host; IsServer kontrolü ile koru
❌ new GameObject() ile NetworkObject → prefabdan Instantiate et, ardından Spawn()
```

## Sub-doc Routing

Konuya göre ilgili referans dosyasını oku:

| Konu | Dosya |
|------|-------|
| Lifecycle sırası (Awake → OnNetworkSpawn → Start) | [references/LIFECYCLE.md](references/LIFECYCLE.md) |
| IsOwner/IsServer/IsHost permission matrix | [references/OWNERSHIP.md](references/OWNERSHIP.md) |
| RPC seçimi, `SendTo` semantiği, deprecated yollar | [references/RPC.md](references/RPC.md) |
| NetworkVariable/NetworkList init ve serialization | [references/VARIABLES.md](references/VARIABLES.md) |
| Prefab kayıt → Spawn → Despawn akışı | [references/SPAWNING.md](references/SPAWNING.md) |
| NetworkSceneManager, EnableSceneManagement | [references/SCENE.md](references/SCENE.md) |
| UnityTransport direct / Relay / DebugSimulator | [references/TRANSPORT.md](references/TRANSPORT.md) |
| 30 somut hallucination tuzağı | [references/PITFALLS.md](references/PITFALLS.md) |

## Versiyon

`com.unity.netcode.gameobjects` **2.x** (2.11.0, Unity 6000.0+ ile doğrulandı).
1.x'te `SendTo.Authority`, `RpcInvokePermission`, evrensel `[Rpc]` attribute **mevcut değildir**.
