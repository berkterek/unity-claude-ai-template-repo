# Event & Callback Patterns

> Read the **Cards** section first. The prose below is reference detail.

## Mono Shell Rule (NON-NEGOTIABLE)

A Tier 1 Mono Shell (Controller/View) must NEVER publish or subscribe to IEventBus directly. Shell has no injected IEventBus. Event publishing is the Handler's or Service's responsibility — forwarded via the shell's handler reference. The shell's only job is to forward lifecycle calls to its handlers.

---

## Cards

### Card 1: UnityEvent is Forbidden

**WHEN:** Any time you need to notify another object of something.

**WRONG:**
```csharp
[SerializeField] private UnityEvent _onScored;
using UnityEngine.Events;
_onScored.Invoke();
```

**RIGHT:** Use one of the three approved patterns (Cards 2–4 below). Never declare your own `UnityEvent` field.

**GOTCHA:** `Button.onClick.AddListener(...)` in code is the only approved UnityEvent usage — it's a built-in Unity component. Wiring it in the Inspector (drag-drop) is still forbidden.

---

### Card 2: IEventBus for Cross-Module Communication

**WHEN:** Two different modules (Audio ↔ Score, Player ↔ UI) need to communicate.

**WRONG:**
```csharp
_scoreService.OnScoreChanged += _audioService.PlayCoinSound; // direct cross-module coupling
```

**RIGHT:**
```csharp
// Define: public struct CoinsChangedEvent : IEvent { public readonly int NewAmount; }
_eventBus.Publish(new CoinsChangedEvent(amount));         // publisher
_eventBus.Subscribe<CoinsChangedEvent>(OnCoinsChanged);   // subscriber in Initialize()
_eventBus.Unsubscribe<CoinsChangedEvent>(OnCoinsChanged); // in Dispose()
```

**GOTCHA:** Always unsubscribe — `check-unitask-cancellation.sh` won't catch a missing Unsubscribe, but it will cause phantom callbacks and memory leaks after the subscriber is disposed.

---

### Card 3: System.Action for One-Time Callbacks

**WHEN:** Passing a callback into a method or storing it briefly for one use.

**WRONG:**
```csharp
[SerializeField] private UnityEvent _onComplete; // serialized callback = hidden dependency
```

**RIGHT:**
```csharp
public async UniTask LoadAsync(Action onComplete, CancellationToken ct)
{
    await _loader.LoadAsync(ct);
    onComplete?.Invoke();
}
```

**GOTCHA:** Don't store `Action` callbacks long-term across scenes — they hold a reference to the subscriber and prevent GC. Use IEventBus for persistent subscriptions.

---

### Card 4: C# event for Internal Module Notifications

**WHEN:** A service notifies its own module's views/controllers (no cross-module boundary).

**WRONG:**
```csharp
public static event Action<int> OnHealthChanged; // static = memory leak, breaks VContainer lifecycle
```

**RIGHT:**
```csharp
public sealed class HealthService : IHealthService
{
    public event Action<int> OnHealthChanged;
    private void ApplyDamage(int dmg) { _hp -= dmg; OnHealthChanged?.Invoke(_hp); }
}
```

**GOTCHA:** If the event is consumed by a class in a different module, it should be an IEventBus event instead.

## UnityEvent is FORBIDDEN (NON-NEGOTIABLE)

`UnityEvent`, `UnityEvent<T>`, and `using UnityEngine.Events` are **blocked** by hook.

**Why:**
- UnityEvent is Inspector-wired — dependencies are hidden, not declared in code
- No compile-time safety: wrong method signatures fail silently at runtime
- Breaks VContainer's explicit dependency graph — hidden coupling appears
- Performance overhead: reflection-based invocation on every call
- Cannot be cancelled, filtered, or awaited with UniTask

---

## Decision Tree: Which Pattern to Use?

```
Is this a Mono Shell (Tier 1 Controller/View)?
├── YES → Shell must NOT publish — delegate to Handler or Service
└── NO — is the event crossing module boundaries?
    ├── YES → IEventBus (publish/subscribe)
    └── NO — is it a one-time callback passed into a method?
        ├── YES → System.Action / System.Func<T>
        └── NO — is it an internal module notification?
            └── YES → C# event keyword
```

---

## Pattern 1: IEventBus — Cross-Module Events

Use when two different modules need to communicate without direct dependency.

```csharp
// Define event as a readonly struct in [Module]Events.cs
public struct EnemyDiedEvent : IEvent
{
    public readonly int EnemyId;
    public EnemyDiedEvent(int id) => EnemyId = id;
}

// Publisher — in any class with IEventBus injected
_eventBus.Publish(new EnemyDiedEvent(enemy.Id));

// Subscriber — in Initialize() / Dispose()
public void Initialize() => _eventBus.Subscribe<EnemyDiedEvent>(OnEnemyDied);
public void Dispose()   => _eventBus.Unsubscribe<EnemyDiedEvent>(OnEnemyDied);

private void OnEnemyDied(EnemyDiedEvent e) { }
```

**Rules:**
- Event structs are `readonly` — no mutable state
- Name: past tense + `Event` suffix (`LevelStartedEvent`, `CoinsChangedEvent`)
- Always unsubscribe in `Dispose()` (plain C#) or `OnDisable()` (MonoBehaviour)
- Never subscribe in `Awake()` or constructors

**Handlers (Tier 2):** A Handler that needs to publish events receives IEventBus via its constructor (injected through the owning Controller's `Func<Rigidbody, IEventBus, IMyHandler>` factory). See `rules/architecture.md → Handler factory pattern`.

---

## Pattern 2: System.Action / System.Func — Callbacks

Use for one-time or short-lived callbacks passed as parameters or stored temporarily.

```csharp
// Passing a callback into a method
public async UniTask LoadAsync(Action onComplete, CancellationToken ct)
{
    await _loader.LoadAsync(ct);
    onComplete?.Invoke();
}

// Storing a callback field (short-lived)
public sealed class TimerService : ITimerService
{
    private Action _onExpired;

    public void StartTimer(float duration, Action onExpired, CancellationToken ct)
    {
        _onExpired = onExpired;
        RunAsync(duration, ct).Forget();
    }

    private async UniTask RunAsync(float duration, CancellationToken ct)
    {
        await UniTask.Delay(TimeSpan.FromSeconds(duration), cancellationToken: ct);
        _onExpired?.Invoke();
        _onExpired = null;
    }
}

// Func for return values
public void RegisterValidator(Func<int, bool> isValid) { }
```

**Rules:**
- Null-check before invoking: `callback?.Invoke()`
- Clear the reference after single use to avoid memory leaks
- Do NOT store `Action` callbacks long-term across scenes — prefer IEventBus

---

## Pattern 3: C# event keyword — Internal Module Notifications

Use for notifications within a single module where subscribers are known at compile time.

```csharp
public sealed class HealthService : IHealthService
{
    public event Action<int> OnHealthChanged;
    public event Action      OnDied;

    public void TakeDamage(int amount)
    {
        _current = Mathf.Max(0, _current - amount);
        OnHealthChanged?.Invoke(_current);

        if (_current == 0)
            OnDied?.Invoke();
    }
}
```

**Rules:**
- Subscribers must unsubscribe in `Dispose()` or `OnDisable()`
- Do NOT use `static event` — breaks VContainer lifecycle
- If the event crosses a module boundary, use IEventBus instead

---

## Pattern 4: UGUI Button.onClick — Code-Only (APPROVED EXCEPTION)

`Button.onClick` is a built-in UnityEvent on Unity's standard UI components. It is **allowed only when subscribed in code** — never wired in the Inspector. This is the only approved UnityEvent usage in the project.

```csharp
public sealed class MainMenuView : MonoBehaviour
{
    [SerializeField] private Button _playButton;
    [SerializeField] private Button _settingsButton;

    private IMenuService _menuService;

    [Inject]
    public void Construct(IMenuService menuService) => _menuService = menuService;

    private void OnEnable()
    {
        _playButton?.onClick.AddListener(OnPlayClicked);
        _settingsButton?.onClick.AddListener(OnSettingsClicked);
    }

    private void OnDisable()
    {
        _playButton?.onClick.RemoveListener(OnPlayClicked);
        _settingsButton?.onClick.RemoveListener(OnSettingsClicked);
    }

    private void OnPlayClicked()     => _menuService.StartGame();
    private void OnSettingsClicked() => _menuService.OpenSettings();
}
```

> **Why `?.` is acceptable here:** `_playButton` is a `[SerializeField]` — it can be `null` if the designer left the field unassigned in the Inspector. This `?.` is a field-assignment null-guard, not a destroyed-object check. Using `?.` to check whether a Unity object has been **destroyed at runtime** is still forbidden (use `if (_target != null)` for that). See also: `rules/csharp-unity.md` → Card 2: Null Check.

**Rules:**
- `AddListener` in `OnEnable()`, `RemoveListener` in `OnDisable()` — mandatory pair
- The onClick list in the Inspector must remain **empty** — all wiring is done in code
- The View calls the Service — zero game logic in the View
- `Dropdown.onValueChanged`, `Toggle.onValueChanged`, `Slider.onValueChanged` follow the same pattern

```csharp
// Other approved UGUI event subscriptions — code only, never Inspector
_dropdown.onValueChanged.AddListener(OnDifficultyChanged);
_toggle.onValueChanged.AddListener(OnSoundToggled);
_slider.onValueChanged.AddListener(OnVolumeChanged);

// Matching remove in OnDisable
_dropdown.onValueChanged.RemoveListener(OnDifficultyChanged);
_toggle.onValueChanged.RemoveListener(OnSoundToggled);
_slider.onValueChanged.RemoveListener(OnVolumeChanged);
```

**What is NOT allowed:**
- `[SerializeField] UnityEvent myEvent` — declaring your own UnityEvent field
- Dragging methods onto onClick in the Inspector
- Using `UnityEvent` anywhere outside of `onClick.AddListener`

> See also: `rules/csharp-unity.md` → Card 2 (null-check: field-assignment `?.` vs destroyed-object `== null`)

---

## UI Toolkit — Editor Only

UI Toolkit (`UIDocument`, `VisualElement`) is used **only for Editor tools** in this project. Runtime UI uses UGUI (Canvas-based). In Editor scripts, UI Toolkit events can be used as normal C# events under `#if UNITY_EDITOR` guards.

---

## Forbidden Patterns

| Forbidden | Use Instead |
|-----------|------------|
| `UnityEvent myEvent` | `IEventBus` or `event Action` |
| `[SerializeField] UnityEvent` | `IEventBus` — wire via VContainer, not Inspector |
| `myEvent.AddListener(...)` | `_eventBus.Subscribe<T>(...)` or `event +=` |
| `myEvent.Invoke()` | `_eventBus.Publish(new TEvent())` or `OnSomething?.Invoke()` |
| `using UnityEngine.Events` | Remove — not needed |
| `static event Action` | Instance event registered via VContainer |
