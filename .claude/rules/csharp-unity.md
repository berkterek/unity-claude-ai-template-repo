# C# Style — Unity Conventions

> Short form — every rule is here. Full examples (naming trees, collision alias, ObjectPool, field declarations,
> #region skeleton, guard clauses, interface contract docs): `rules/csharp-unity-reference.md`.

## Cards

### Card 1: Naming — Game.Concretes.<Domain> Pattern

Namespace follows the folder: `_GameFolders/Scripts/Games/Concretes/Audio/` → `Game.Concretes.Audio` (drop the
underscore prefix, `Scripts/` and `Games/`); interfaces in `Game.Abstracts.<Domain>`. **WRONG:** `Scripts.Audio`,
`GameAudio`, abbreviations like `AudioSvc`.

---

### Card 1.1: Folder Names Are Domains, Not Layers

Only the domain folder and its namespace segment are plural for countable domains (`Inputs/`, `Enemies/` →
`Game.Concretes.Inputs`); mass nouns stay singular (`Audio/`). Classes and interfaces stay singular (`Player`,
`PlayerController` — never `Players`, `Controllers.cs`). A plural **layer** name (`Controllers/`, `Services/`) is
still banned in the first position — banned list: `rules/architecture.md` → Domain Folder Convention.

**Exception — static Extension classes** are plural after the type they extend: `Vector3Extensions`,
`StringExtensions` (file name matches as usual).

---

### Card 2: Null Check — Never `?.` on UnityEngine.Object

**WRONG:** `_target?.TakeDamage(10);` / `if (_target is null)` on a MonoBehaviour, Component, ScriptableObject or any
Unity object. **RIGHT:** `if (_target == null) return;` — Unity overrides `==` for destroyed objects.

**GOTCHA:** `?.`, `??`, `is null` use C# reference equality and do NOT see destroyed Unity objects — the #1 most subtle
Unity bug. Plain C# objects may use `?.` / `??=` freely. See also `rules/event-patterns.md` → Pattern 4 note.

---

### Card 3: UniTask Only — Never `Task` or `async void`

**WRONG:** `async Task`, `async void`, `IEnumerator` coroutines. **RIGHT:** `async UniTask LoadAsync(CancellationToken ct)`;
fire-and-forget `LoadAsync(ct).Forget(ex => { if (ex is not OperationCanceledException) Debug.LogException(ex); });`.

**GOTCHA:** `async void` cannot be awaited or cancelled and its exceptions are unhandled. Every async method takes a
`CancellationToken`; a bare `.Forget()` only on a throw-proof body, with a comment. `[UnityTest]` returning
`IEnumerator` is the one allowed coroutine. Full rules incl. `CancellationTokenSource` ownership:
`rules/unity-async.md` (loads with any `.cs`).

---

### Card 4: #region Discipline — Required in _GameFolders/Scripts/

Every class under `_GameFolders/Scripts/` uses, in this order: `#region Fields` · `Constructor` · `Lifecycle`
(Awake, OnEnable, Start, OnDisable, OnDestroy) · `Public Methods` · `Private Methods`. Regions are named by role,
never by type.

**GOTCHA:** Exempt: interface files, single-member structs/enums, and helper classes with fewer than 3 methods total
(all access levels combined). At 3 or more methods, regions are required regardless of visibility.

---

### Card 5: Namespace Collision — UnityEngine Type Aliases

A domain named like a UnityEngine type makes the bare name ambiguous inside it. Add an alias to **every** `.cs` file in
that domain: `using UCamera = UnityEngine.Camera;` then use `UCamera`. Check the name **before** creating the folder —
see Namespace Collision Rule below.

---

### Card 6: Reuse Before You Hand-Roll

| Instead of hand-rolling | Use |
|---|---|
| `Queue<GameObject>` pool | `UnityEngine.Pool.ObjectPool<T>` |
| manual timer field / `WaitForSeconds` coroutine | `UniTask.Delay` |
| string-splitting JSON parser | `JsonUtility` |
| custom lerp / damping smoothing | `Mathf.SmoothDamp` |
| custom registry, service locator, static instance dictionary | VContainer |

**GOTCHA:** Hand-rolling is permitted only when the built-in **demonstrably** cannot meet a measured requirement — not
when it merely feels heavy. The reason goes in a code comment or an ADR; silence is not a justification. A reviewer
finding a hand-rolled equivalent with no stated reason returns CHANGES NEEDED.

## Naming Summary

| Construct | Style / suffix | Example |
|-----------|-------|---------|
| Class, struct, enum · method, property | PascalCase | `AudioService`, `PlaySound()`, `IsPlaying` |
| Interface | `I` + PascalCase (`I*Handler`, `I*ViewModel` for those) | `IAudioService`, `IMoveHandler` |
| Private / protected field | `_` + camelCase | `_audioService` |
| Public field (`[Serializable]` data classes only) | PascalCase | `SfxVolume` |
| Local variable, parameter | camelCase | `currentLevel` |
| Constant · `static readonly` | `SCREAMING_SNAKE_CASE` · PascalCase | `MAX_RETRY_COUNT` · `JumpHash` |
| IEvent implementation | past tense + `Event` | `LevelStartedEvent` |
| MonoBehaviour — UI/Canvas only | `View` | `HUDView` |
| MonoBehaviour — gameplay/character/physics | `Controller` | `PlayerController` |
| MonoBehaviour — Unity API abstraction | `Provider` | `AudioProvider` |
| Pure C# prefab-local logic | `Handler` | `MoveHandler` |
| Pure C# UI Toolkit screen state (only when the screen has its own state, `ui-toolkit-runtime.md` Card 11) | `ViewModel` | `ShopViewModel` |
| Static installer · installer | `Module` · `Installer` | `AudioModule`, `AppModules` · `AudioInstaller` |
| Runtime state · serializable save data | `Model` · `SaveData` | `ScoreModel` · `PlayerSaveData` |
| ScriptableObject | descriptive suffix | `AudioConfiguration` |
| Test class · test method | `Tests` · `MethodName_WhenCondition_ExpectedBehavior` | `EnemySpawnerTests` · `TakeDamage_WhenZeroHealth_RaisesEvent` |
| ECS data · tag · cleanup · managed ref · authoring | none · `Tag` · `CleanupData` · `Reference` · `Authoring` | `HealthData`, `EnemyEntityTag` |

## Namespace Convention

`<Layer>.<Domain>`, underscore prefix dropped, depth follows folders: `_Framework/Events/` → `Framework.Events`;
`Games/Abstracts/<Domain>/` → `Game.Abstracts.<Domain>`; `Games/Concretes/<Domain>/` → `Game.Concretes.<Domain>`;
`Games/Ecs/` → `Game.Ecs`; `Tests/` → `Game.Tests`; `Editors/` → `Game.Editors`. Third-party code keeps its own.

### Namespace Collision Rule (NON-NEGOTIABLE)

Known collisions (domain → alias): `Camera` → `UCamera`, `Random` → `URandom`, `Object` → `UObject`, `Input` →
`UInput`, `Physics` → `UPhysics`, `Collider` → `UCollider`, `Transform` → `UTransform`, `Time` → `UTime`, `Component` →
`UComponent`, `GridLayout` → `UGridLayout` (each `using U<Name> = UnityEngine.<Name>;`).

> **This list is NOT exhaustive — a miss here is not permission.** It lags reality by one incident each time
> (`GridLayout` was added after a module hit `CS0104`). Any single-word domain name is a candidate.

**Pre-plan check:** before creating a domain folder, verify the name against `UnityEngine` itself — `unity_reflect`
on `UnityEngine.<DomainName>` with MCP connected, else `docs/engine-reference/unity/`. On a match, add an alias task
to the plan **and** a row here.

### Type-Name Collisions (a different case)

A **class** named like a UnityEngine type collides in files outside its own namespace that have both
`using UnityEngine;` and `using Game.Concretes.<Domain>;` (`CS0104`). Known: our `AudioConfiguration` vs
`UnityEngine.AudioConfiguration` → in the consuming file `using AudioConfiguration = Game.Concretes.Audio.AudioConfiguration;`.
`ConfigCatalog` is the usual victim. The pre-plan check covers **new type names** too.

## Field Declarations

- `[SerializeField]` has two uses only: designer-configurable values, and component references on the same GO or
  its children — assigned in the Inspector, never `GetComponent` in `Awake` when the component exists at edit time.
- Public fields only in `[Serializable]` data classes and ScriptableObject configs.
- Prefer `[SerializeField] private float _moveSpeed;` + `public float MoveSpeed => _moveSpeed;` in MonoBehaviours and
  services; `[field: SerializeField]` auto-properties only in data classes / SO configs.

## Data Taxonomy

| Data type | Author | Form | Suffix | Example |
|-----------|--------|------|--------|---------|
| Config — designer-set, runtime read-only | Designer, edit-time | `ScriptableObject` (in ConfigCatalog) | `*Configuration` | `AudioConfiguration` |
| Save data — written to disk (JSON) | Runtime, persisted | `[Serializable]` plain class — no UnityEngine types | `*SaveData` | `PlayerSaveData` |
| Runtime state — session-only mutable | Runtime, not persisted | plain class (held by service/model) | `*Model` | `ScoreModel` |
| Event payload — single-frame message | Publish time | `readonly struct : IEvent` | `*Event` | `CoinsChangedEvent` |
| ECS component | System | `struct : IComponentData` | see ecs-dots.md | `HealthData` |

**Decision test:** designer writes, runtime reads → ScriptableObject; runtime writes to disk → `[Serializable]` class;
runtime writes, dies with session → Model; created once, distributed → readonly struct; nobody writes it after
compile and no designer would want to → `const` / `static readonly`.

**Config vs. code constant:** every value a designer could plausibly tune (enemy stats, item tables, spawn intervals,
level lists) is `*Configuration` data, not a `const`. `const` / `static readonly` are for values that belong to the
code (retry count, `Shader.PropertyToID`, `Animator.StringToHash`). One question: **would a designer ever want to
change this without a programmer?** Yes → ScriptableObject. Do not call the first kind "static data".

**Rules:**
- ScriptableObject is NEVER mutated at runtime (NON-NEGOTIABLE) — in the Editor the write is permanent, a build resets
  it. Copy SO → Model and mutate the Model.
- SaveData classes contain NO UnityEngine types (`Vector3`, `Color`…) — plain floats or own `[Serializable]` types.
- Every SaveData root class has an `int Version` field for forward migration.
- A class that reads or writes through `ISaveLoadService` uses one key per domain and reads `HasKey` → `Load`, else
  the config default. Before adding persistence to any class, Read `rules/save-load.md` — it auto-loads only on
  `*Save*` / `*Dal` / `*Model` / `*Settings*` / `*Progress*` files, not on the services that consume it.
- App-wide config travels via ConfigCatalog → DI only; a config SO in a MonoBehaviour `[SerializeField]` is an
  anti-pattern for app-wide config. Exception: prefab-local designer tweaks (the shell's own prefab config).

## Encapsulation (NON-NEGOTIABLE)

Everything is `private` unless a concrete caller requires otherwise: fields private by default; methods `public` only
when another class calls them today; a property getter only when another class reads it, a setter only when another
class writes it.

### Constructor Injection Rule — No `new *Service()` or `new *Provider()`

No `new *Service()` or `new *Provider()` in any class — always constructor-injected via VContainer. Exception:
`new *Handler(...)` ONLY inside a `*Controller` or `*View` (the Mono shell).

## Types, Files, Access Order, Control Flow

- `sealed` by default; one type per file, file name = primary type name; explicit access modifiers everywhere; `var`
  when the type is obvious. Exception: a UI Panel class, its UIData class and its `UITypes` partial may share a file.
- Member order: `public` → `internal` (avoid) → `protected` → `private`; within each, `static` → `readonly` → normal.
- Braces always; guard clauses over nesting; `for` over `foreach` in hot paths; no LINQ in gameplay code; no magic
  strings (`nameof()`, `Animator.StringToHash()`, `Shader.PropertyToID()`); `CompareTag("tag")`, never `tag == "tag"`.

## Interface Contract Documentation

Document a public interface method's contract where silence would surprise a caller — skip fields that state the
obvious:

| Field | When to include |
|-------|----------------|
| `Precondition:` | Input has constraints (range, non-null, must-be-registered) |
| `Postcondition:` | Guaranteed state after the call that a caller would rely on |
| `Side effect:` | Other state changes beyond the obvious return value |
| `Idempotent:` | When calling twice has a different outcome than calling once |
| `Throws:` | Which exception and under what condition |

Written in `/// <remarks>` under the `<summary>`; example in the reference file.
