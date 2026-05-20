---
name: event-bus
description: IEventBus usage pattern — project EventBus implementation, location, namespace, and code examples
model-tier: normal
---

# EventBus — Usage Pattern

## Location
`Assets/_Framework/Events/`
Assembly: `FrameworkEventBus` | Namespace: `Framework.Events`

## Structure

```
IEvent         → marker interface implemented by all event structs
IEventBus      → Subscribe / Unsubscribe / Publish API
EventBus       → sealed implementation, stores handlers in Dictionary<Type, List<object>>
```

## Defining Events

Events are defined as `readonly struct`, implement `IEvent`, and follow the past-tense + `Event` suffix naming:

```csharp
// Event with no data
public struct PlayerDiedEvent : IEvent { }

// Event with data
public struct CoinsChangedEvent : IEvent
{
    public readonly int NewAmount;
    public CoinsChangedEvent(int amount) => NewAmount = amount;
}
```

Event files go in a module-specific `[Module]Events.cs` file — not embedded inside service classes.

## Subscribe / Unsubscribe

| Class type | Subscribe | Unsubscribe |
|------------|-----------|-------------|
| Plain C# (`IInitializable`, `IDisposable`) | `Initialize()` | `Dispose()` |
| MonoBehaviour (can be enabled/disabled) | `OnEnable()` | `OnDisable()` |

```csharp
// Plain C# service
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

## VContainer Registration

`IEventBus` is registered globally in AppScope. When adding a new module, do not re-register — just inject it:

```csharp
public sealed class PlayerService : IPlayerService
{
    private readonly IEventBus _eventBus;
    public PlayerService(IEventBus eventBus) => _eventBus = eventBus;
}
```

## Usage in ECS Systems

ECS systems cannot receive VContainer injection. Use the `EventBusAccessor` static bridge instead:

```csharp
EventBusAccessor.Instance.Publish(new EnemyDiedEvent { ... });
```

## EventBus Behavior

- A snapshot of the handler list is taken during Publish — unsubscribing during iteration is safe
- Exceptions thrown by handlers are caught, logged via `DLog.Error`, and do not affect other handlers
- Event types with no remaining handlers are automatically removed from the `_handlers` dictionary
