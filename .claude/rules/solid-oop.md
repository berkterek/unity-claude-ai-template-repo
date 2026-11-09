# SOLID & OOP Rules (NON-NEGOTIABLE)

> Short form — every rule is here. Full WRONG/RIGHT code, the worked N-enemies example (Controller / Handler /
> Event / Manager side by side), the WaveDirector EntryPoint example and the hook-enforcement note:
> `rules/solid-oop-reference.md`. It loads when you touch a Manager, Controller or Handler; **Read it yourself
> before choosing the tier or MonoBehaviour role of a new class.**

## Cards

### Card 0: MonoBehaviour Decision Gate (first question — always)

**WHEN:** Before writing any new class, ask: "Does this need to be a MonoBehaviour?"

A class may be MonoBehaviour **only if at least one applies:** (a) it caches scene/prefab references via its own
`[SerializeField]`; (b) it receives Unity callbacks (collision, trigger, UGUI events); (c) it is a cross-module Unity
API boundary (Provider); (d) it is Canvas UI (View). Otherwise it is pure C#.

**WRONG:** `public sealed class WaveDirectorService : MonoBehaviour { private void Update() { /* game logic */ } }`

**RIGHT:** a pure C# service exposing `Tick(float deltaTime)`, registered with a plain
`builder.Register<WaveDirectorService>(Lifetime.Singleton).AsImplementedInterfaces()`, and the domain's Mono shell
forwarding `private void Update() => _waveDirector.Tick(Time.deltaTime);`.

**GOTCHA:** "I need Update" is NOT a reason to be a MonoBehaviour, and NOT a reason for `ITickable` /
`IFixedTickable` — neither is used in this project. Prefab-local logic → `Handler.Tick`, forwarded by its Controller;
global logic → the domain's own shell (Controller or Manager) forwards to the service.

---

### Card 1: MonoBehaviour — 4 Roles Only

**WHEN:** Writing a MonoBehaviour that passed Card 0.

| Role | Suffix | Is | Never |
|---|---|---|---|
| View | `*View` | **Canvas/UI only** — updates UI, reads input events, triggers animations | business logic, state; gameplay objects never use `*View` |
| Provider | `*Provider` | wraps one Unity API group on behalf of a Service | coordination, event publishing, game logic |
| Controller | `*Controller` | single instance's shell: caches refs, creates Handlers, forwards lifecycle | branching, calculation, publishing `IEventBus` |
| Manager | `*Manager` | registry coordinating N instances of **one** domain | a second domain (no `GameManager`), business logic |

**GOTCHA:**
- `*Handler` and `*Service` are **never** MonoBehaviour (hook-blocked).
- Manager: same-domain instances call `Register(this)` / `Unregister(this)` (from `OnEnable` / `OnDisable`) on an
  injected `I*Manager` instead of each subscribing to `IEventBus`; `IEventBus` stays for cross-module messages. A
  Manager is Mono only if Card 0 applies to it — otherwise it is a pure C# service. Logic beyond registration and
  coordination moves to a Handler or Service.
- Per-instance events: `IEventBus` if another module listens, a C# `event` if it stays inside the prefab.

---

### Card 2: SRP (Single Responsibility Principle)

**WHEN:** Designing any class.

**WRONG:** a Controller's `Update` that computes score, writes the label and publishes a threshold event.

**RIGHT:** `private void Update() => _scoreService.Tick(Time.deltaTime);` — the service owns the logic.

**GOTCHA:** Every class is describable in one sentence without "AND", and has one reason to change. Three ANDs =
three classes.

---

### Card 3: OCP (Open/Closed Principle)

**WHEN:** Adding new behavior to an existing system.

**WRONG:** `if (type == EnemyType.Fast) { … } else if (type == EnemyType.Tank) { … }`

**RIGHT:** `public interface IEnemy { void Attack(); }` with `FastEnemy`, `TankEnemy` — new type = new class.

**GOTCHA:** An `if/else if` (or `switch`) chain on type is almost always an OCP violation. Use polymorphism.

---

### Card 4: DIP (Dependency Inversion Principle)

**WHEN:** Declaring constructor parameters.

**WRONG:** `public PlayerService(AudioService audio)` — concrete dependency.

**RIGHT:** `public PlayerService(IAudioService audio)`.

**GOTCHA:** Constructors take only interfaces. Exception: Handler constructors receive Unity component refs
(`Rigidbody`, `Transform`) by design. `new *Service()` / `new *Provider()` anywhere is a DIP violation — VContainer
injects them.

---

## 4-Tier Architecture

Assign the tier before writing a line.

| Tier | Is | Rules |
|---|---|---|
| 1 Mono Shell (Controller / View) | MonoBehaviour | caches refs, sets up Handlers, forwards lifecycle; zero branching; no interface by default |
| 2 Handler | pure C#, prefab-local logic | Unity refs via constructor; lives and dies with its prefab; always has an `I*Handler` |
| 3 Service + EntryPoint | pure C#, cross-module | **no UnityEngine API** — math types (`Mathf`, `Vector*`, `Quaternion`, `Color`, `Rect`, `Bounds`…) and `Debug` logging allowed; frame update = `Tick(float)` forwarded by a Mono shell |
| 4 Provider | wraps Unity API a Service needs | cross-module only — prefab-local Unity access is a Handler's job; scene loading = `ISceneLoader` (`*SceneLoader`) |

## Handler Rules

- Pure C# `sealed` class implementing `I*Handler` (interface in `Game.Abstracts.<Domain>/`) — never MonoBehaviour.
- Handlers do not see each other; the Controller coordinates them.
- Never referenced from outside its prefab — a second consumer means promote it to a Service.
- Created only by its shell: plain `new` in `Awake` when it needs no container dependency; an injected
  `Func<…, I*Handler>` factory (registered in the module) when it does. Do not force a factory on every Handler.

## Controller Shell

- Forwards unconditionally — no `if`/branching in `Update` / `FixedUpdate` / `LateUpdate`.
- No state fields (score, cooldown, health) — those live in a Handler or Service.
- Never publishes `IEventBus` — the Handler or Service does.
- Target ≤ ~80 lines; the hook warns at 150. Handlers and Services have no hard limit — split when "AND" appears.

## EntryPoint — Lifecycle Yes, Frame Ticks No

| Interface | Status |
|---|---|
| `IInitializable` / `IDisposable` | used — acquire and release |
| `IStartable` / `IAsyncStartable` | used — one-shot (async) startup, e.g. `SceneService` |
| `ITickable` / `IFixedTickable` | **not used** — the domain's Mono shell owns `Update` / `FixedUpdate` |

`RegisterEntryPoint<T>()` only for a lifecycle interface; a tick-only service is a plain `Register<T>`. Why: VContainer's
tick position relative to `MonoBehaviour.Update` is not a published contract, so a container tick feeding a
MonoBehaviour is right only by accident. A genuine owner-less per-frame stream uses R3 (`Observable.EveryUpdate()`),
never `ITickable` or a `while (true) await UniTask.Delay` loop.

## Interface Scope

| Class | Interface? |
|---|---|
| Handler, Service, Provider, ViewModel | **always** — the test is a caller |
| Controller / Manager | only when a Manager, registry or another prefab holds it (`IEnemyController`); may name Unity types |
| View | no — UI Toolkit screens implement `IScreen` / `IPopup<T>` through the base class, never a per-screen `I*View` |
| ScriptableObject config, event struct, model / data class | no |

Postpone module + installer ceremony for a single caller; never postpone the interface.

## Forbidden Patterns (not covered above)

- Injection-dependent initialization in `Awake()` / `Start()` — use `Initialize()` (VContainer calls it).
- `async void` outside Unity lifecycle methods — return `UniTask` and `.Forget(ex => …)`.
