# SOLID & OOP Rules (NON-NEGOTIABLE)

## Cards

### Card 0: MonoBehaviour Decision Gate (first question — always)

**WHEN:** Before writing any new class, ask: "Does this need to be a MonoBehaviour?"

A class may be MonoBehaviour **only if at least one applies:**

| Justification | Example |
|---|---|
| (a) Caches scene/prefab references via Inspector (`[SerializeField]`) | Controller shell |
| (b) Receives Unity callbacks (collision, trigger, UGUI events) | Controller, View |
| (c) Cross-module Unity API boundary | Provider |
| (d) Canvas UI | View |

**"I need Update" is NOT a valid reason.** Prefab-local → Handler.Tick (Controller forwards). Global → `ITickable`.

**WRONG:**
```csharp
// MonoBehaviour with no [SerializeField] fields and no Unity callbacks
public sealed class WaveDirectorService : MonoBehaviour
{
    private void Update() { /* game logic */ }
}
```

**RIGHT:**
```csharp
// Pure C# service using ITickable — no MonoBehaviour needed
public sealed class WaveDirectorService : IWaveDirectorService, ITickable, IInitializable, IDisposable
{
    public void Tick() { /* VContainer calls every frame */ }
}
// In installer:
builder.RegisterEntryPoint<WaveDirectorService>().AsImplementedInterfaces();
```

**GOTCHA:** If a class passes none of the four conditions, it must be pure C#. Every MonoBehaviour that fails this gate is a rule violation.

---

### Card 1: MonoBehaviour — 4 Roles Only

**WHEN:** Writing a MonoBehaviour that passed Card 0.

MonoBehaviour may only take one of four roles: **View**, **Provider**, **Controller**, or **Manager**.

| Role | Suffix | Where | Does | Does NOT |
|---|---|---|---|---|
| **View** | `*View` | **Canvas/UI scripts ONLY** (HUDView, PopupView, SliderView) | Updates UI, reads input events, triggers animations | Business logic, calculation, state management |
| **Provider** | `*Provider` | Unity API abstraction (AudioProvider, PhysicsProvider) | Wraps a single Unity API group (AudioSource, Rigidbody, Transform) | Service coordination, event publishing, game logic |
| **Controller** | `*Controller` | Gameplay, character, physics coordination | Caches refs, sets up Handlers, forwards lifecycle (Update → handler.Tick). ZERO branching/calculation | Holds game logic, publishes IEventBus directly |
| **Manager** | `*Manager` | Centralized coordinator for ONE domain's collection of objects (EnemyManager, AudioManager) — used instead of pairwise IEventBus attach/detach or direct references between N same-domain instances | Register/Unregister callers via an injected interface, coordinate/query across the registered set | Coordinate more than one domain (no `GameManager`), hold unrelated cross-cutting responsibilities |

**Suffix decision test:** Is the script under a Canvas?
- Yes → `*View`
- No, and it's a single instance's coordination shell → `*Controller`
- No, and it wraps Unity API on behalf of a Service → `*Provider`
- No, and it's a single per-domain registry coordinating N sibling instances → `*Manager`

**`*Manager` constraints (NON-NEGOTIABLE):**
- **One domain per Manager.** `EnemyManager`, `AudioManager` are fine — a catch-all `GameManager`
  spanning unrelated domains is forbidden (same anti-pattern as `GameContext`/Service Locator,
  see architecture.md → "NO GameContext / Service Locator").
- **Register/Unregister over IEventBus.** Same-domain instances (e.g. 10 enemies) call
  `Register(this)`/`Unregister(this)` on the Manager via a constructor/`[Inject]`-received
  interface (`IEnemyManager`) instead of each instance individually subscribing/unsubscribing to
  `IEventBus` events. `IEventBus` remains reserved for genuinely cross-module communication
  (event-patterns.md decision tree) — a Manager is an intra-domain registry, not a replacement
  for it.
- **MonoBehaviour only if Card 0 applies**, exactly like every other role — a Manager needs its
  own `[SerializeField]` field or a Unity lifecycle callback to be a MonoBehaviour; otherwise it
  must be a pure C# Service (e.g. `EnemyDirectorService`, `ITickable`) instead. Preferring pure C#
  is still the default — `*Manager` as a MonoBehaviour is the exception, not the norm.
- **SRP still applies.** If a Manager grows business logic/calculation beyond
  registration+coordination, extract that into a Handler or Service — the Manager stays a thin
  registry.

**Worked example — N enemies in a scene (Controller / Handler / Event / Manager, side by side):**

```csharp
// 1. EnemyController — Mono. Card 0: [SerializeField] refs + lifecycle callbacks. Role: Controller (forward only).
public sealed class EnemyController : MonoBehaviour
{
    [SerializeField] private Rigidbody _rigidbody;
    [SerializeField] private Animator  _animator;

    private IHealthHandler _healthHandler;
    private IEnemyManager  _enemyManager;

    [Inject]
    public void Construct(Func<Animator, IEventBus, IHealthHandler> factory, IEnemyManager enemyManager)
    {
        _healthHandler = factory(_animator, _eventBus);
        _enemyManager  = enemyManager;
    }

    private void OnEnable()  => _enemyManager.Register(this);   // Manager registry, not IEventBus
    private void OnDisable() => _enemyManager.Unregister(this);

    private void Update() => _healthHandler.Tick(Time.deltaTime); // forward only, zero branching
}

// 2. HealthHandler — pure C#. *Handler suffix: Unity refs via constructor, never MonoBehaviour.
public sealed class HealthHandler : IHealthHandler
{
    private readonly IEventBus _eventBus;
    private readonly int _enemyId;

    public void TakeDamage(int amount)
    {
        _hp -= amount;
        if (_hp <= 0)
            _eventBus.Publish(new EnemyDiedEvent(_enemyId)); // crosses to UI/Score/Audio → IEventBus
    }
}

// 3. EnemyManager — Mono only because it has a lifecycle-driven registry; one domain, Register/Unregister only.
public interface IEnemyManager
{
    void Register(IEnemyController enemy);
    void Unregister(IEnemyController enemy);
    int ActiveCount { get; }
}

public sealed class EnemyManager : MonoBehaviour, IEnemyManager
{
    private readonly List<IEnemyController> _enemies = new();

    public void Register(IEnemyController enemy)   => _enemies.Add(enemy);
    public void Unregister(IEnemyController enemy)  => _enemies.Remove(enemy);
    public int ActiveCount => _enemies.Count;

    // Only when ALL enemies are gone does this cross into another module — via IEventBus, not a direct call.
    private void OnEnemyCountChanged()
    {
        if (_enemies.Count == 0) _eventBus.Publish(new WaveClearedEvent());
    }
}
```

| Structure | Mono or pure C#? | Why |
|---|---|---|
| `EnemyController` (per instance) | Mono | Card 0: own `[SerializeField]` + lifecycle callbacks; role = Controller |
| `HealthHandler` / `MoveHandler` (per instance's internal logic) | Pure C# | `*Handler` — Unity ref via constructor, MonoBehaviour blocked by the hook |
| "Died" / "Damaged" event | `IEventBus` if another module listens (UI/Score/Audio); C# `event` if it stays inside the same prefab | event-patterns.md decision tree |
| Shared registry across N enemies | `*Manager` — Mono only if it has its own lifecycle callback (e.g. `OnEnable`/`OnDisable` on itself); otherwise a pure C# Service | New Card 1 role — one domain, Register/Unregister |

**GOTCHA (worked example):** `EnemyManager`'s own `MonoBehaviour`-ness came from nothing here except being
placed in the scene — if it has no lifecycle callback and no `[SerializeField]` of its own, prefer a pure
C# `EnemyDirectorService` (`ITickable`, `RegisterEntryPoint`) instead. A `*Manager` MonoBehaviour is the
exception, not the default, exactly like every other role in Card 0.

**Suffix prohibition table:**

| Suffix | Allowed as MonoBehaviour? | Notes |
|---|---|---|
| `*View` | YES — Canvas/UI ONLY | Gameplay/physics objects must NOT use `*View` |
| `*Controller` | YES | Gameplay or character coordination shell |
| `*Provider` | YES | Unity API boundary |
| `*Manager` | YES — with constraints above | One domain only; prefer pure C# Service unless Card 0 applies |
| `*Handler` | **NO** | Handler must be pure C# — never MonoBehaviour |
| `*Service` | **NO** | `check-no-monobehaviour-in-services.sh` blocks it |

**GOTCHA:** `*Handler` is NOT a MonoBehaviour role. A class named `MoveHandler : MonoBehaviour` is a rule violation.

> **Note — enforcement is structural, not name-based.** `check-no-monobehaviour-in-services.sh`
> decides whether MonoBehaviour/`UnityEngine` usage in domain code (`Games/Abstracts/`,
> `Games/Concretes/`, `_Framework/`) is legitimate by **code structure**, not filename: a class
> is judged justified when it satisfies Card 0 — it has an **own** `[SerializeField]` field
> and/or a Unity lifecycle callback (`Awake`, `OnEnable`, `Update`, `OnTriggerEnter`, etc.) —
> regardless of whether its name ends in `View`/`Controller`/`Provider`/anything else. The
> suffix in the table above is a **naming-convention consequence** of the role a class already
> has (Card 0 + Card 1 together decide the role; the suffix documents it) — it is not itself
> the mechanism the hook checks.
>
> This is also why `*Handler` stays exempt **by name** in the hook's filename whitelist rather
> than by the Card 0 structural test: a Handler (Tier 2) is pure C# and legitimately receives a
> Unity component reference (`Rigidbody`, `Transform`) **as a constructor parameter** — see
> Handler Rules below. A constructor parameter is not an **own** `[SerializeField]` field, so a
> Handler never passes the Card 0 structural test and would otherwise be flagged. The filename
> exemption exists specifically to cover this structurally-undetectable, intentional exception —
> it does not mean Handler is a fourth MonoBehaviour role; a Handler is never a MonoBehaviour.
>
> **`using UnityEngine` in a pure-C# file is not automatically a leak.** The hook does not block
> on the import itself — it blocks on the actual API surface. A file whose only `UnityEngine`
> usage is **math value types** (`Mathf`, `Vector2/3/4`, `Quaternion`, `Color`, `Rect`, `Bounds`,
> `Ray`, `Plane`, `Matrix4x4`) or **`Debug` logging** is allowed (this Tier 3 "math types allowed"
> rule; Module null-guards call `Debug.LogError`). It is blocked only when the file references
> real engine/scene/asset/input/time API — `SceneManager`, `Transform`, `GameObject`,
> `AudioSource`, `Physics`, `Input`, `Time`, `Resources`, etc. — which must move to a Provider
> (`*Provider`) or a swappable backend (`*Loader`/`*Dal`/`*Client`). Matching runs against
> comment/string-stripped source, so an API name inside a comment or string literal is ignored.

---

### Card 2: SRP (Single Responsibility Principle)

**WHEN:** Designing any class.

**WRONG:**
```csharp
// MonoBehaviour computing, displaying, and publishing all at once — SRP violation
private void Update()
{
    _score += Time.deltaTime * _multiplier; // business logic — does not belong here
    _label.text = _score.ToString();        // show service output, not calculation
    if (_score > 100) _eventBus.Publish(new ScoreThresholdEvent()); // service's job
}
```

**RIGHT:**
```csharp
// Controller shell only forwards — service handles the logic
private void Update()
{
    _scoreService.Tick(Time.deltaTime);
}
```

**GOTCHA:** Every class must be describable in one sentence — and that sentence must not contain AND. "PlayerService calculates movement AND updates score AND publishes events" = 3 classes.

---

### Card 3: OCP (Open/Closed Principle)

**WHEN:** Adding new behavior to an existing system.

**WRONG:**
```csharp
// Every new enemy type changes this switch (OCP violation)
public void ProcessEnemy(EnemyType type)
{
    if (type == EnemyType.Fast) { /* ... */ }
    else if (type == EnemyType.Tank) { /* ... */ }
}
```

**RIGHT:**
```csharp
// New enemy = new class; existing code is unchanged
public interface IEnemy { void Attack(); }

public sealed class FastEnemy : IEnemy { public void Attack() { /* fast attack */ } }
public sealed class TankEnemy : IEnemy { public void Attack() { /* heavy attack */ } }
```

**GOTCHA:** An `if/else if` chain on type is almost always an OCP violation. Use polymorphism.

---

### Card 4: DIP (Dependency Inversion Principle)

**WHEN:** Declaring constructor parameters.

**WRONG:**
```csharp
// Concrete dependency — DIP violation
public sealed class PlayerService
{
    private readonly AudioService _audio; // concrete

    public PlayerService(AudioService audio) => _audio = audio;
}
```

**RIGHT:**
```csharp
// Interface dependency
public sealed class PlayerService
{
    private readonly IAudioService _audio;

    public PlayerService(IAudioService audio) => _audio = audio;
}
```

**GOTCHA:** Constructor takes only interfaces. Exception: Handler constructors intentionally receive Unity component refs (Rigidbody, Transform) by design — this is not a DIP violation.

---

## 4-Tier Architecture

Every class belongs to exactly one tier. Assign the tier before writing a single line.

```
┌─ Tier 1: Mono Shell (Controller / View) ──────────────────────────────┐
│  MonoBehaviour. Caches refs ([SerializeField]), sets up Handlers,     │
│  forwards lifecycle (Update → handler.Tick(dt)). ZERO branching/calc. │
│  Does NOT take interfaces (nobody mocks the shell). Target ≤ ~80 ln.  │
├─ Tier 2: Handler (prefab-local logic) ────────────────────────────────┤
│  Pure C# class (NOT MonoBehaviour). Receives Unity refs (Rigidbody,   │
│  Transform) via constructor — may touch Unity API intentionally.       │
│  Lives and dies with the prefab; FORBIDDEN to be referenced from       │
│  outside the prefab. Always has an interface (IMoveHandler) →          │
│  NSubstitute seam.                                                     │
├─ Tier 3: Service + EntryPoint (cross-module logic) ───────────────────┤
│  Pure C#, NO UnityEngine API (math types allowed). Registered with    │
│  VContainer. Needs Update → use ITickable/IStartable                  │
│  (RegisterEntryPoint) — NOT a reason to be MonoBehaviour.             │
│  Interface-first.                                                      │
├─ Tier 4: Provider (cross-module Unity API boundary) ───────────────────┤
│  Remains as-is: wraps Unity API that the Service needs.               │
│  Do NOT open a Provider for prefab-local Unity access —               │
│  that is Handler's job.                                                │
│  Scene loading follows this tier exactly: ISceneService (Tier 3,      │
│  pure C#, EntryPoint) depends on ISceneLoader (Tier 4 Provider         │
│  interface). SceneManager-backed and Addressables-backed loading are   │
│  two interchangeable ISceneLoader implementations — swap without       │
│  touching SceneService. Suffix: `*SceneLoader` (e.g.                   │
│  NormalSceneLoader, AddressableSceneLoader).                          │
└───────────────────────────────────────────────────────────────────────┘
```

**Tier assignment decision:**

| Question | Tier |
|---|---|
| Does it live on a Canvas? | Tier 1 — View |
| Does it cache scene refs + forward lifecycle only? | Tier 1 — Controller |
| Does it contain gameplay logic that touches Unity refs, lives inside one prefab? | Tier 2 — Handler |
| Is it pure C# logic shared across modules? | Tier 3 — Service |
| Does it need a frame tick but should stay pure C#? | Tier 3 — EntryPoint (`ITickable`) |
| Does it wrap Unity API on behalf of a Service (cross-module)? | Tier 4 — Provider |
| Does it perform the actual scene load call (SceneManager / Addressables)? | Tier 4 — `ISceneLoader` implementation (`*SceneLoader`) |

---

## Handler Rules

Handlers are **pure C# classes** — never MonoBehaviour. They hold prefab-local gameplay logic and may intentionally access Unity API through refs received in their constructor.

```csharp
// Game.Abstracts.Players/IMoveHandler.cs
namespace Game.Abstracts.Players
{
    public interface IMoveHandler
    {
        void SetInput(Vector2 input);
        void Tick(float deltaTime);
    }
}

// Game.Concretes.Players/MoveHandler.cs — pure C#, NOT MonoBehaviour, sealed
namespace Game.Concretes.Players
{
    public sealed class MoveHandler : IMoveHandler
    {
        #region Fields

        private readonly Rigidbody         _rigidbody;
        private readonly MoveConfiguration _config;
        private Vector2 _input;

        #endregion

        #region Constructor

        public MoveHandler(Rigidbody rigidbody, MoveConfiguration config)
        {
            _rigidbody = rigidbody;
            _config    = config;
        }

        #endregion

        #region Public Methods

        public void SetInput(Vector2 input) => _input = input;

        public void Tick(float deltaTime)
        {
            var velocity = new Vector3(_input.x, 0f, _input.y) * _config.MoveSpeed;
            _rigidbody.velocity = velocity;
        }

        #endregion
    }
}
```

**Handler rules:**

- Handlers **do not see each other** — coordination happens in the Controller shell
- A Handler may not be referenced from outside its prefab; when a second consumer appears, promote it to a Service
- Interface always lives in `Game.Abstracts.<Domain>/` — NSubstitute seam for tests
- Two wiring patterns:

| Handler's needs | Setup | Location |
|---|---|---|
| Only prefab components (no container deps) | `new MoveHandler(_rigidbody, ...)` | `Controller.Awake` — dependency-free instantiation in Awake is allowed |
| + Container dependency (IEventBus, config) | VContainer factory: inject `Func<Rigidbody, IMoveHandler>` | Factory registered in the module's installer |

Factory is **not mandatory** — use plain `new` when there are no container dependencies. Forcing a factory onto every Handler brings back installer ceremony.

---

## Controller Shell

The Controller shell is a thin MonoBehaviour that caches refs, creates Handlers, and forwards Unity lifecycle — nothing else.

```csharp
namespace Game.Concretes.Players
{
    public sealed class PlayerController : MonoBehaviour
    {
        #region Fields

        [SerializeField] private Rigidbody _rigidbody;

        private IMoveHandler _moveHandler;
        private IJumpHandler _jumpHandler;

        #endregion

        #region Lifecycle

        // Factory injected when container dep is needed
        [Inject]
        public void Construct(Func<Rigidbody, IMoveHandler> moveFactory)
        {
            _moveHandler = moveFactory(_rigidbody);
        }

        // Plain new when no container deps — Awake is the right place
        private void Awake() => _jumpHandler = new JumpHandler(_rigidbody);

        // ONLY forwarding — no logic, no branching, no state
        private void Update() => _moveHandler.Tick(Time.deltaTime);

        #endregion
    }
}
```

**Shell violation examples (WRONG):**

```csharp
// WRONG 1 — branching/calculation in Update
private void Update()
{
    if (_isGrounded) _moveHandler.Tick(Time.deltaTime); // branching in shell
    _score += Time.deltaTime;                           // state field on shell
}

// WRONG 2 — state fields on shell (score, cooldown, timers)
private float _attackCooldown; // belongs in Handler or Service
private int   _score;          // belongs in ScoreModel (Service/Model)

// WRONG 3 — shell publishing IEventBus directly
private void Update()
{
    if (_health <= 0)
        _eventBus.Publish(new PlayerDiedEvent()); // Handler or Service publishes, not shell
}
```

**Shell limits:**
- No `if`/branching in Update/FixedUpdate/LateUpdate — forward unconditionally
- No state fields (score, cooldown, health values) — those belong in Handler or Service
- No IEventBus publish — Handler or Service is the publisher
- Target: ≤ ~80 lines. Hook warns at 150 lines.

---

## EntryPoint — ITickable for Pure C# Update

When a pure C# service needs a frame update, use `ITickable`. **"I need Update" is never a reason to make something a MonoBehaviour.**

```csharp
namespace Game.Concretes.Waves
{
    public sealed class WaveDirectorService : IWaveDirectorService, ITickable, IInitializable, IDisposable
    {
        #region Fields

        private readonly IEventBus _eventBus;
        private CancellationTokenSource _cts;

        #endregion

        #region Constructor

        public WaveDirectorService(IEventBus eventBus)
        {
            _eventBus = eventBus;
        }

        #endregion

        #region Lifecycle

        public void Initialize()
        {
            _cts = new CancellationTokenSource();
        }

        // VContainer calls every frame — no MonoBehaviour needed
        public void Tick()
        {
            /* wave progression logic */
        }

        public void Dispose()
        {
            _cts?.Cancel();
            _cts?.Dispose();
        }

        #endregion
    }
}

// In the module installer:
builder.RegisterEntryPoint<WaveDirectorService>().AsImplementedInterfaces();
```

**ITickable / IStartable / IFixedTickable:**

| Interface | Called by VContainer | Replaces |
|---|---|---|
| `ITickable` | Every frame (Update equivalent) | `MonoBehaviour.Update` |
| `IFixedTickable` | Every fixed frame (FixedUpdate) | `MonoBehaviour.FixedUpdate` |
| `IStartable` | Once on scope start | `MonoBehaviour.Start` |
| `IAsyncStartable` | Once on scope start (async) | Async `MonoBehaviour.Start` |

Use `RegisterEntryPoint<T>()` in the installer — this wires the lifecycle interfaces automatically.

---

## Interface Scope

**Who gets an interface:**

| Class | Interface? | Why |
|---|---|---|
| Handler | YES — always (`I*Handler`) | NSubstitute seam for tests; the test is a caller |
| Service | YES — always (`I*Service`) | Cross-module; VContainer interface-first |
| Provider | YES — always (`I*Provider`) | Testability, swappability |
| Controller shell | NO | Nobody mocks the shell |
| View | NO | Nobody mocks the shell |
| ScriptableObject config | NO | Data container, no logic |
| Event struct | NO | Plain value type |
| Model/data class | NO | Test uses the model directly |

**One-caller rule revised:** Do not create a separate **module + installer ceremony** for a single caller. But every injectable layer (Handler, Service, Provider) always has an interface — the test is a caller.

---

## SRP — Single Responsibility in Depth

**Core rule:** Every class must be describable in one sentence — and that sentence must not contain AND.

```
✓ "AudioService plays sounds."
✓ "ScoreModel tracks the score."
✗ "PlayerService calculates movement AND updates score AND publishes events."
         → 3 responsibilities = 3 different classes
```

**Responsibility test — ask before writing:**

| Question | Bad sign |
|---|---|
| Can I describe this class in one sentence? | If not → SRP violation |
| Does the sentence contain AND? | If yes → split |
| Why does this class change? | More than one reason → split |

---

## OCP — Polymorphism Over Conditionals

New behavior added to a system must not require changing existing code. Every `if/else if` chain on type is a potential OCP violation — use polymorphism instead.

---

## DIP — Constructor Interface Rule

Constructor takes only interfaces. Services depend on interfaces, never on concrete types.

```csharp
// BAD — concrete dependency
public sealed class PlayerService
{
    private readonly AudioService _audio; // concrete — DIP violation
    public PlayerService(AudioService audio) => _audio = audio;
}

// GOOD — interface dependency
public sealed class PlayerService
{
    private readonly IAudioService _audio;
    public PlayerService(IAudioService audio) => _audio = audio;
}
```

---

## Forbidden Patterns

| Forbidden | Why | Correct approach |
|---|---|---|
| MonoBehaviour with no `[SerializeField]` and no Unity callbacks | Card 0 violation — no justification to be Mono | Pure C# (Service, Handler, or EntryPoint) |
| `*Handler : MonoBehaviour` | Handler must be pure C# — hook blocks it | Pure C# sealed class implementing `I*Handler` |
| Handler referenced from outside its prefab | Breaks prefab-local boundary | Promote Handler to Service |
| Business logic in `Update()` of a Controller | Shell forwards only | Move logic to Handler.Tick or Service |
| State fields (score, cooldown) on Controller shell | SRP + shell purity violation | Hold in Handler or Service |
| Controller shell publishing `IEventBus` directly | Handler or Service is the publisher | Move publish to Handler or Service |
| `new Service()` or `new Provider()` in any class | DIP violation | VContainer injection |
| `new Handler()` outside Controller/View | Handler wired only by its shell | Move instantiation to Controller.Awake or factory |
| Constructor with concrete type parameter | DIP violation | Interface parameter |
| `if/else if` chain on type | OCP violation | Polymorphism |
| AND in class responsibility description | SRP violation | Split into two classes |
| `async void` (non-lifecycle) | Swallows exceptions | Return `UniTask` + `.Forget(ex => ...)` |
| Injection-dependent initialization in `Awake()`/`Start()` | Breaks VContainer lifecycle order | Use `Initialize()` (VContainer calls it) |

---

## Limits Summary

| Layer | Line target | Hook warning |
|---|---|---|
| Controller / View (Mono shell) | ≤ ~80 lines | At 150 lines |
| Handler | No hard limit — split when AND creeps in | Reviewer criterion |
| Service | No hard limit | Reviewer criterion (AND test) |
