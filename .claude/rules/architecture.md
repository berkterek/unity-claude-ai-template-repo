# Architecture Rules

> Short form — every rule is here. Full WRONG/RIGHT code (Provider, swappable backends, Controller + Handler
> Patterns A/B, Func<> factory registration, GameContext, EventBusAccessor), the example trees and the rationale:
> `rules/architecture-reference.md`. It loads when you touch a Provider/Dal/Loader/Client/Controller/Handler/Module/
> Scope file, `_Framework/` or an `.asmdef`; **Read it yourself before designing a new backend, a Controller–Handler
> pair or a new top-level folder.**

## Cards

### Card 1: No Singletons

**WRONG:** `public static AudioService Instance` set in `Awake()`. **RIGHT:** `IAudioService` + `sealed AudioService`,
`builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();` in its module.

**GOTCHA:** `FindObjectOfType<T>()` is a singleton in disguise — equally forbidden. Always constructor injection.

---

### Card 2: Provider Pattern for Unity API

**WHEN:** A service needs Unity API (Physics, AudioSource, Transform, Screen…). **WRONG:** `AudioSource.PlayClipAtPoint`
inside `AudioService`. **RIGHT:** the service calls an injected `IAudioProvider`; `BasicAudioProvider : MonoBehaviour,
IAudioProvider` holds the `[SerializeField] AudioSource` and makes the Unity call.

**GOTCHA:** `using UnityEngine` in a service is a leak **only** for real engine/scene/asset API — `Transform`,
`GameObject`, `AudioSource`, `SceneManager`, `Physics`, `Input`, `Time`, `Resources`, etc. **Math value types**
(`Mathf`, `Vector2/3/4`, `Quaternion`, `Color`, `Rect`, `Bounds`, `Ray`, `Plane`, `Matrix4x4`) and **`Debug` logging**
are allowed in a Tier 3 service — `check-no-monobehaviour-in-services.sh` allows them. Do NOT open a Provider for
prefab-local Unity access — that is a Handler's job (Tier 2).

---

### Card 2.1: Swappable Backend — Same Shape, Suffix by Domain

**WHEN:** A Service's job is "call some external mechanism to do X" (load a scene, persist data, call a remote API)
and more than one mechanism plausibly does it. Service (Tier 3, pure C#) depends on a backend interface; each
mechanism is a separate implementation the Service never references by concrete type.

| Domain | Backend interface suffix | Example |
|---|---|---|
| Scene loading | `*Loader` | `ISceneLoader` → `NormalSceneLoader`, `AddressableSceneLoader` |
| Data persistence | `*Dal` (Data Access Layer) | `ISaveLoadDal` → `LocalSaveLoadDal`, `CloudSaveLoadDal` |
| Unity API wrapping | `*Provider` | `IAudioProvider` → `BasicAudioProvider` |
| Remote/external service call | `*Client` | `IAnalyticsClient` → `FirebaseAnalyticsClient` |

**GOTCHA:**
- Test of correctness: adding a backend never changes the Service's class name or public API. Check this table
  before inventing a suffix; add a row only when none of the four meanings fit.
- **Two backends active at once for different data** (settings → local, progress → cloud): two Service+Backend
  pairs (`ILocalSaveLoadService`, `ICloudSaveLoadService`), callers inject the one they need — **never** a factory
  keyed by string/enum, which is the same `switch` moved inside the service (OCP violation).
- **Same data, routed at runtime** (online/offline sync): a Composite Dal (`SyncingSaveLoadDal : ISaveLoadDal`)
  holds both backends; the Service still sees one `ISaveLoadDal`.

---

### Card 3: Module → Static Install Method → AppModules → AppScope

`[X]Module.Install()` → one line in `AppModules.Install()` → `AppScope`; `AppScope.cs` never changes, no installer
assets. Full card: `rules/bootstrap-pattern.md` → Cards 1–2.

---

### Card 4: EventBus Crosses Modules; Action Stays Local

Cross-module → `IEventBus` (never `_scoreService.OnScoreChanged += …` across modules); one-time callback →
`System.Action` parameter; internal module notification → C# `event`. **`UnityEvent` is forbidden entirely.** Full
decision tree: `rules/event-patterns.md`.

---

### Card 5: One-Caller Rule — Postpone MODULE Ceremony, Never Postpone the Interface

**RIGHT:** with one caller, register the handler or helper directly in the parent module's `Install()` — no new
module file. **A separate module is justified only when:** at least 2 independent production callers exist, OR the
service has its own lifecycle (async setup, pooling, Dispose), OR a provider must hide Unity API behind a pure C#
boundary.

**GOTCHA:** Postpones **module + installer ceremony**, never the interface. Every injectable layer (Handler,
Service, Provider) always gets an interface — the test suite is the second caller. `IMoveHandler` with only
`PlayerController` as caller is correct, not over-engineering.

---

### Card 6: Same Prefab Hierarchy — SerializeField + Handler, Not VContainer

**WRONG:** injecting a co-located component through VContainer (`[Inject] Construct(IPlayerProvider)` +
`RegisterComponent(_playerProvider)`). **RIGHT:** `[SerializeField]` references; the Controller creates its Handler —
**Pattern A** `_moveHandler = new MoveHandler(_rigidbody, _moveConfig);` in `Awake` when the Handler needs only
prefab-local refs; **Pattern B** `[Inject] Construct(Func<Rigidbody, IMoveHandler> moveFactory)` when it also needs a
container dependency (IEventBus, a ConfigCatalog config). `Update` forwards `_moveHandler.Tick(Time.deltaTime)`.

| Relationship | Wire with |
|---|---|
| Same GameObject, child or grandchild in the same prefab | `[SerializeField]` drag-drop |
| Handler (prefab-local logic, pure C#) | `new` in Awake OR `Func<>` factory inject |
| Different prefab / different module | VContainer injection (interface) |
| Cross-scene / global service | VContainer injection (AppScope) |

**GOTCHA:** VContainer is for **cross-module boundaries**. Handlers are pure C# and never registered with VContainer
directly — the Controller creates them. Do not force a factory on every Handler.

---

### Card 7: GameScope vs Module Boundary

`GameScope` only `RegisterComponent`s scene objects; anything that does not reference a scene object belongs in a
module's `Install()` — app-lifetime via `AppModules`, scene-lifetime via `SceneModules`. Full card:
`rules/bootstrap-pattern.md` → Card 4.

---

## Dependency Direction

`Tier 1 (Mono Shell: Controller/View) → Tier 2 (Handler) → Tier 3 (Service + EntryPoint) → IEventBus → Tier 4 (Provider)`
— assembly definitions enforce it at compile time. Tier definitions: `rules/solid-oop.md` → 4-Tier Architecture.

## Layer Structure

`_Framework/` — pure infrastructure, **never references `_GameFolders`** or any other project folder; each subfolder
has its own `.asmdef`. `_GameFolders/Scripts/` — all game code, may reference `_Framework`:
`Games/Abstracts/<Domain>/` (interfaces and abstract base classes only), `Games/Concretes/<Domain>/` (all concrete
classes), `Games/Ecs/` (only if ECS enabled), `Tests/[Project]EditModeTest|PlayModeTest/`, `Editors/`.

### Scripts/ Folder Rules (NON-NEGOTIABLE)

The **only** valid top-level folders under `Scripts/` are: `Games/`, `Tests/`, `Editors/`.

| Forbidden folder | Correct location |
|-----------------|-----------------|
| `Scripts/Config/` | ScriptableObject configs → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/GameUnity/` | MonoBehaviour views/providers → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/Game/` | Services → `Scripts/Games/Concretes/<Domain>/` |
| `Scripts/Abstracts/` | Must be inside `Games/` → `Scripts/Games/Abstracts/` |
| `Scripts/Concretes/` | Must be inside `Games/` → `Scripts/Games/Concretes/` |
| `Scripts/Services/` | Services → `Scripts/Games/Concretes/<Domain>/` |

### Adding a Top-Level Folder (the declared exception)

`lib-path-rules.sh` blocks any other first segment. The one legitimate reason for a fourth folder is code that needs
its **own `.asmdef`**; it takes a `.claude/path-allowlist.txt` line **and** a row in the table above. **Read
`rules/architecture-reference.md` → "Adding a Top-Level Folder" before proposing one.**

### _Framework Assembly Definition Rules (NON-NEGOTIABLE)

- Every subfolder under `_Framework/` has its **own** `.asmdef`; **never** one root `.asmdef` covering all
  subfolders, **never** delete a subfolder `.asmdef` to replace it with a root one.
- A `_Framework` assembly references only other `_Framework` assemblies — never `_GameFolders`.
- Names: `Events/` → `Framework.Events` (or `[Project].Framework.Events`), `Logging/` → `Framework.Logging`,
  `SaveLoadSystems/` → `Framework.SaveLoadSystems`, `Editors/` → `Framework.Editor` (`includePlatforms: ["Editor"]`).

## Module Structure (NON-NEGOTIABLE)

A feature module spans `Abstracts/<Domain>/` (interfaces only: `I[X]Service`, `I[X]Provider`, `I[X]Handler`) and
`Concretes/<Domain>/` (everything else: sealed service, `*Configuration` SO, `[X]Module` static installer,
`[X]Events.cs`, Provider, Controller, Handler).

**`[Module]Events.cs` lives inside `Concretes/<Domain>/` — never a top-level `Scripts/Games/Events/` or
`Scripts/Events/` folder.** Interfaces live in `Abstracts/` so other modules depend on contracts.

### Domain Folder Convention (NON-NEGOTIABLE)

The **first** folder under `Games/Abstracts/` or `Games/Concretes/` is a **domain**, never a layer and never a
catch-all; `Abstracts/<Domain>/` and `Concretes/<Domain>/` use identical domain names. Banned in that position,
case-insensitive, singular and plural — `check-domain-folder-structure.sh` (exit 2):

| Banned first segment | Why | Correct location |
|---|---|---|
| `Service(s)/`, `Provider(s)/`, `Controller(s)/`, `View(s)/`, `Manager(s)/`, `Config(s)/` | layer name | `Concretes/<Domain>/` |
| `Interface(s)/` | layer name; `Abstracts/` already means "interfaces" | `Abstracts/<Domain>/` |
| `Core/`, `General(s)/` | catch-all — a name that cannot refuse a file | a real domain, or `_Framework/` / `Concretes/Infrastructure/` |

- A `.cs` directly at `Games/Concretes/Foo.cs` with no domain folder is the same violation.
- **Below the domain folder you are free** (`Players/Services/`, `Players/Handlers/`, or flat). No file-count
  threshold and no mirror check — do not add one.
- Naming: plural for countable domains (`Players/`, `Enemies/`, `Inputs/`), singular for mass nouns (`Audio/`,
  `UI/`, `VFX/`). DI and bootstrap wiring → `Concretes/Infrastructure/`; domain-agnostic infrastructure → `_Framework/`.

### ARCHITECTURE.md — one per Concretes domain

Every `Concretes/<Domain>/` — and every `_Framework/` subfolder or allowlisted folder that owns an `.asmdef` —
carries one `ARCHITECTURE.md`. **Before writing or editing one, Read `.claude/rules/architecture-docs.md`** (format,
scope, why). Missing → warning, malformed → block (`check-architecture-doc.sh`).

### Module Portability Checklist

Before exporting a module: `using` only `_Framework` + own types · no cross-module dependencies except interfaces ·
no `UnityEngine` API in the service (moved to a provider) · no static service calls · config null guard in
`Install()` · events in `[Module]Events.cs` · every Handler has `I[X]Handler` in `Abstracts/<Domain>/`.

## VContainer for Dependency Injection

VContainer is the **only** wiring mechanism. No singletons, no static access, no `FindObjectOfType`, no service locator.

- **Code-first static modules (NON-NEGOTIABLE)** and interface-first registration: `rules/bootstrap-pattern.md`
  Cards 1–3. EntryPoint lifecycle interfaces: `rules/solid-oop.md` → EntryPoint.
- **NO GameContext / ServiceLocator / Dependencies class (NON-NEGOTIABLE)** bundling several dependencies into one
  injectable object — each class declares only its own dependencies.
- **Handler factory:** when a Handler needs a container dependency, the module registers
  `builder.RegisterFactory<Rigidbody, IMoveHandler>(container => rigidbody => new MoveHandler(rigidbody, container.Resolve<MoveConfiguration>()), Lifetime.Singleton)`
  (one delegate; each call makes a new handler) and the Controller injects the `Func<>`. No container dependency →
  plain `new` in `Awake`. Handlers themselves are never registered; the Controller creates them.

### Scene Scope Hierarchy

`AppScope` (Bootstrap scene, build index 0, `DontDestroyOnLoad`, persistent root; all global services) → children
`MenuScope` / `GameScope` (scene-local dependencies). A scope sees its parent's services, never a sibling's.

### GameScope — Scene Component Registration Only

`rules/bootstrap-pattern.md` → Card 4. **If the wiring does not directly reference a scene object, it belongs in a
module's `Install()`** — services, factories, and conditional setup (difficulty, feature flags) included.

## IEvent System for Communication

`IEventBus` is the **only** cross-system communication channel — no C# static events, no UnityEvents, no direct
cross-module calls. Event struct shape, naming and the decision tree: `rules/event-patterns.md` (loads on any `.cs`).
This table is the authority for subscription:

| Class type | Subscribe | Unsubscribe |
|-----------|-----------|-------------|
| Plain C# (`IInitializable`, `IDisposable`) | `Initialize()` | `Dispose()` |
| MonoBehaviour — registered via `RegisterComponent` | `Initialize()` | `Dispose()` |
| MonoBehaviour — can be enabled/disabled | `OnEnable()` | `OnDisable()` |
| MonoBehaviour — runtime instantiated (Instantiate, not VContainer-registered) | `OnEnable()` | `OnDisable()` |

Never unsubscribe in `OnDestroy()` for VContainer-managed types. Instantiated MonoBehaviours have no
`Initialize()`/`Dispose()` — use `OnEnable()`/`OnDisable()`, never only `OnDestroy()`.

## Input, Config, EventBusAccessor

- **Input:** pull-based pure C# `InputService` (no tick, not `ITickable`) + per-prefab `InputHandler`; services never
  touch Unity Input. Full pattern: `rules/unity-input.md`.
- **Config:** all configuration is ScriptableObject data (`[SerializeField] private` field + read-only property);
  runtime mutable state lives in service/model classes.
- **`EventBusAccessor` (APPROVED EXCEPTION)** — the only approved static accessor: lives in `_Framework/Events/`, pure
  C#, initialized by `AppScope` in `RegisterBuildCallback`, used **only** by ECS systems
  (`EventBusAccessor.Instance.Publish(...)`; `rules/ecs-dots.md` → Card 12). MonoBehaviours and services always get
  `IEventBus` by injection. No new static accessor without an explicit design decision;
  `check-vcontainer-singleton.sh` blocks all other static singleton patterns.
