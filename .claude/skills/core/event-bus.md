---
name: event-bus
description: IEventBus kullanım paterni — proje içindeki EventBus implementasyonu, konum, namespace ve kod örnekleri
model-tier: normal
---

# EventBus — Kullanım Paterni

## Konum
`Assets/_AssetFolders/_Framework/Events/`
Assembly: `FrameworkEventBus` | Namespace: `Framework.Events`

## Yapı

```
IEvent         → tüm event struct'larının implement ettiği marker interface
IEventBus      → Subscribe / Unsubscribe / Publish API
EventBus       → sealed implementasyon, Dictionary<Type, List<object>> ile handler tutar
```

## Event Tanımlama

Event'ler `readonly struct` olarak tanımlanır, `IEvent` implement eder, isim past-tense + `Event` suffix:

```csharp
// Veri taşımayan event
public struct PlayerDiedEvent : IEvent { }

// Veri taşıyan event
public struct CoinsChangedEvent : IEvent
{
    public readonly int NewAmount;
    public CoinsChangedEvent(int amount) => NewAmount = amount;
}
```

Event dosyaları modüle özel `[Module]Events.cs` dosyasına konur — servislerin içine gömülmez.

## Subscribe / Unsubscribe

| Sınıf türü | Subscribe | Unsubscribe |
|------------|-----------|-------------|
| Plain C# (`IInitializable`, `IDisposable`) | `Initialize()` | `Dispose()` |
| MonoBehaviour (enable/disable olabilen) | `OnEnable()` | `OnDisable()` |

```csharp
// Plain C# servis
public void Initialize()  => _eventBus.Subscribe<PlayerDiedEvent>(OnPlayerDied);
public void Dispose()     => _eventBus.Unsubscribe<PlayerDiedEvent>(OnPlayerDied);

// MonoBehaviour
private void OnEnable()  => _eventBus.Subscribe<CoinsChangedEvent>(OnCoinsChanged);
private void OnDisable() => _eventBus.Unsubscribe<CoinsChangedEvent>(OnCoinsChanged);
```

## Publish

```csharp
_eventBus.Publish(new PlayerDiedEvent());
_eventBus.Publish(new CoinsChangedEvent(amount: 100));
```

## VContainer Kaydı

`IEventBus` AppScope'ta global olarak kayıtlı. Yeni modül eklerken yeniden kaydetme — sadece inject et:

```csharp
public sealed class PlayerService : IPlayerService
{
    private readonly IEventBus _eventBus;
    public PlayerService(IEventBus eventBus) => _eventBus = eventBus;
}
```

## ECS Sistemlerinde Kullanım

ECS sistemleri VContainer injection alamaz. Bunun için `EventBusAccessor` static bridge kullanılır:

```csharp
EventBusAccessor.Instance.Publish(new EnemyDiedEvent { ... });
```

## EventBus Davranışı

- Publish sırasında handler listesinin snapshot'ı alınır — iteration sırasında unsubscribe güvenlidir
- Publish içindeki handler exception'ları yakalanır, `DLog.Error` ile loglanır, diğer handler'lar etkilenmez
- Handler kalmayan event tipi otomatik olarak `_handlers` dictionary'den temizlenir
