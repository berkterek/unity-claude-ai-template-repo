---
paths:
  - "**/*Provider.cs"
  - "**/*Dal.cs"
  - "**/*Loader.cs"
  - "**/*Client.cs"
  - "**/*Controller.cs"
  - "**/*Handler.cs"
  - "**/*Module.cs"
  - "**/*Modules.cs"
  - "**/*Scope.cs"
  - "**/_Framework/**"
  - "**/*.asmdef"
---
# Architecture Rules — Reference

> Full code and rationale behind `rules/architecture.md`. Every rule is stated there; this file only shows it.
> Loads when a Provider/Dal/Loader/Client/Controller/Handler/Module/Scope file, `_Framework/` or an `.asmdef` is
> touched. **Read it yourself before designing a new backend, a Controller–Handler pair or a new folder.**

## Card 1: No Singletons — code

**WRONG:**
```csharp
public class AudioService : MonoBehaviour
{
    public static AudioService Instance { get; private set; }
    private void Awake() => Instance = this;
}
```

**RIGHT:**
```csharp
public interface IAudioService { void PlaySound(string id); }
public sealed class AudioService : IAudioService { /* ... */ }
// AudioModule.cs
builder.Register<AudioService>(Lifetime.Singleton).AsImplementedInterfaces();
```

## Card 2: Provider Pattern — code

**WRONG:**
```csharp
public sealed class AudioService : IAudioService
{
    public void Play(string id) => AudioSource.PlayClipAtPoint(clip, Vector3.zero); // Unity API in service
}
```

**RIGHT:**
```csharp
public sealed class AudioService : IAudioService
{
    private readonly IAudioProvider _provider;
    public void Play(string id) => _provider.Play(id);
}
public sealed class BasicAudioProvider : MonoBehaviour, IAudioProvider
{
    [SerializeField] private AudioSource _source;
    public void Play(AudioClip clip) => _source.PlayOneShot(clip);
}
```

Why math types and `Debug` are not a leak: solid-oop.md Tier 3 is *"Pure C#, NO UnityEngine API — math types
allowed"*, and bootstrap-pattern.md Module null-guards call `Debug.LogError`. They need `using UnityEngine;` but
`check-no-monobehaviour-in-services.sh` allows them and blocks only the real engine/scene API.

## Card 2.1: Swappable Backend — code

This is Card 2 generalized beyond Unity API — the backend isn't always `UnityEngine`, but the shape is identical:
Service (Tier 3, pure C#) depends on an interface; each mechanism is a separate implementation the Service never
references by concrete type.

**WRONG:**
```csharp
// Backend mechanism hardcoded inside the service — swapping local↔cloud save means rewriting SaveLoadService
public sealed class SaveLoadService : ISaveLoadService
{
    public void Save(PlayerSaveData data) => File.WriteAllText(Application.persistentDataPath + "/save.json", JsonUtility.ToJson(data));
}
```

**RIGHT:**
```csharp
// Game.Abstracts.SaveLoad/ISaveLoadDal.cs — Tier 4 contract, one per backend mechanism
public interface ISaveLoadDal
{
    void Write(string key, string json);
    string Read(string key);
}

// Game.Concretes.SaveLoad/LocalSaveLoadDal.cs — Tier 4, file-system backend
public sealed class LocalSaveLoadDal : ISaveLoadDal
{
    public void Write(string key, string json) => File.WriteAllText(PathFor(key), json);
    public string Read(string key) => File.Exists(PathFor(key)) ? File.ReadAllText(PathFor(key)) : null;
    private static string PathFor(string key) => Path.Combine(Application.persistentDataPath, key + ".json");
}

// Game.Concretes.SaveLoad/SaveLoadService.cs — Tier 3, pure C#, never touches File/JsonUtility directly
public sealed class SaveLoadService : ISaveLoadService
{
    private readonly ISaveLoadDal _dal;
    public SaveLoadService(ISaveLoadDal dal) => _dal = dal;
    public void Save(PlayerSaveData data) => _dal.Write("save", JsonUtility.ToJson(data));
}
```

**Two backends both active at once — WRONG (keyed factory):**
```csharp
// Factory keyed by a string/enum — SaveLoadService now branches on backend type internally
public sealed class SaveLoadService : ISaveLoadService
{
    private readonly Func<SaveTarget, ISaveLoadDal> _dalFactory;
    public void Save(SaveTarget target, string key, string json) => _dalFactory(target).Write(key, json); // OCP violation: adding a 3rd target means a 3rd factory case
}
```

**RIGHT (two Service+Backend pairs):**
```csharp
// Two independent domains — each with its own Service + Dal pair, per Card 2.1's normal shape
Game.Abstracts.SaveLoad/ILocalSaveLoadService.cs  → Game.Abstracts.SaveLoad/ILocalSaveLoadDal.cs  → LocalSaveLoadDal
Game.Abstracts.SaveLoad/ICloudSaveLoadService.cs  → Game.Abstracts.SaveLoad/ICloudSaveLoadDal.cs  → FirestoreSaveLoadDal

// Callers inject exactly the one they need — the choice already happened at the injection site
public sealed class SettingsController : MonoBehaviour
{
    [Inject] public void Construct(ILocalSaveLoadService localSave) { /* settings are always local */ }
}
public sealed class ProgressService : IProgressService
{
    public ProgressService(ICloudSaveLoadService cloudSave) { /* progress is always cloud */ } // constructor injection — Tier 3 service
}
```

A factory keyed by category (`"local"`/`"cloud"`, or an enum) just moves the `if/switch` from outside the service to
inside it — still an OCP violation, still couples the service to every backend it might route to. Two separate
interface pairs mean adding a third category (e.g. `ISessionCacheService`) is a new pair, not a new branch anywhere.

**Same data, runtime-routed (online/offline sync) — Composite Dal:**
```csharp
public sealed class SyncingSaveLoadDal : ISaveLoadDal
{
    private readonly LocalSaveLoadDal _local;
    private readonly FirestoreSaveLoadDal _cloud;
    private readonly IConnectivityProvider _connectivity;

    public void Write(string key, string json)
    {
        _local.Write(key, json);                         // always write local first — offline-safe
        if (_connectivity.IsOnline) _cloud.Write(key, json); // best-effort cloud sync
    }
}
```

`SaveLoadService` still depends on a single `ISaveLoadDal` and never learns that syncing happens — the routing logic
lives entirely inside the Dal implementation, not in a factory the Service calls into.

## Card 4: EventBus vs Action — code

```csharp
// WRONG — direct reference across modules
_scoreService.OnScoreChanged += UpdateUI; // tight coupling

// RIGHT
_eventBus.Subscribe<ScoreChangedEvent>(OnScoreChanged); // cross-module → IEventBus
// one-time callback → System.Action parameter
// internal module notification → C# event keyword
```

## Card 6: Same Prefab Hierarchy — code

**WRONG:**
```csharp
// Injecting a co-located component through VContainer — unnecessary overhead
public sealed class PlayerController : MonoBehaviour
{
    private IPlayerProvider _provider;

    [Inject]
    public void Construct(IPlayerProvider provider) => _provider = provider;
}
// PlayerModule: builder.RegisterComponent(_playerProvider).As<IPlayerProvider>();
```

**RIGHT — Pattern A: Handler needs no container dependencies (plain new):**
```csharp
public sealed class PlayerController : MonoBehaviour
{
    #region Fields

    [SerializeField] private Rigidbody        _rigidbody;
    [SerializeField] private MoveConfiguration _moveConfig;

    private IMoveHandler _moveHandler;

    #endregion

    #region Lifecycle

    private void Awake()
    {
        // Plain new — no container dependencies needed
        _moveHandler = new MoveHandler(_rigidbody, _moveConfig);
    }

    private void Update()
    {
        _moveHandler.Tick(Time.deltaTime);
    }

    #endregion
}
```

**RIGHT — Pattern B: Handler needs a container dependency (Func factory):**
```csharp
public sealed class PlayerController : MonoBehaviour
{
    #region Fields

    [SerializeField] private Rigidbody _rigidbody;

    private IMoveHandler _moveHandler;

    #endregion

    #region Lifecycle

    [Inject]
    public void Construct(Func<Rigidbody, IMoveHandler> moveFactory)
    {
        _moveHandler = moveFactory(_rigidbody);
    }

    private void Update() => _moveHandler.Tick(Time.deltaTime);

    #endregion
}
```

## Handler Factory — VContainer Func<> registration

```csharp
// In PlayerModule.Install():
builder.RegisterFactory<Rigidbody, IMoveHandler>(
    container => rigidbody =>
        new MoveHandler(rigidbody, container.Resolve<MoveConfiguration>()),
    Lifetime.Singleton  // singleton = one factory delegate; each call produces a new handler instance
);

// In PlayerController — receives the factory via [Inject]:
[Inject]
public void Construct(Func<Rigidbody, IMoveHandler> moveFactory)
{
    _moveHandler = moveFactory(_rigidbody);
}
```

## Layer Structure — full tree

```
_Framework/                               ← Never references _GameFolders or other project folders. Pure infrastructure.
  Events/FrameworkEventBus.asmdef        ← each subfolder has its OWN .asmdef
  Logging/FrameworkLogging.asmdef
  SaveLoadSystems/FrameworkSaveLoadSystems.asmdef
  Editors/FrameworkEditor.asmdef         ← Editor-only, includePlatforms: ["Editor"]

_GameFolders/        ← Depends on _Framework. All game-specific code.
  Scripts/
    Games/
      Abstracts/     ← interfaces and abstract base classes ONLY, organized by domain
        Players/     ← example domain folders (mirrors Concretes/ structure)
        Enemies/
        ...
      Concretes/     ← ALL concrete classes (pure C# or MonoBehaviour), organized by domain
        Players/     ← same domain folders as Abstracts/
        Enemies/
        ...          ← name subfolders by domain/feature, not by layer
      Ecs/           ← ECS DOTS systems, components, authorings (only if ECS enabled)
    Tests/
      [Project]EditModeTest/   ← Edit Mode tests (.asmdef includePlatforms: ["Editor"])
      [Project]PlayModeTest/   ← Play Mode tests (.asmdef all platforms)
    Editors/         ← Editor-only tools, custom inspectors
```

## Adding a Top-Level Folder — steps and why

**Both steps, or neither:**

1. Add a line to `.claude/path-allowlist.txt`: `Scripts/Simulation    # reason: engine-free deterministic sim, own asmdef with noEngineReferences`
2. Add the folder to the table in `rules/architecture.md` → Scripts/ Folder Rules, so the prose and the validator agree.

**Never valid as a reason:** "the hook did not complain", "the plan said so", "it felt cleaner". A plan that
disagrees with `rules/architecture.md` is a decision for the human at SCOPE_GATE / ARCHITECTURE_GATE (surfaced by
`validate-plan-paths.sh`).

The three-folder list is enforced fail-closed by `lib-path-rules.sh` — an unrecognized first segment under
`Scripts/`, or under `Scripts/Games/`, is a **block**, not a fall-through. That is deliberate: the earlier version
exited 0 on anything it did not recognize, and a plan recorded that silence as "verified compliant" before building
an illegal tree.

A rule with no escape hatch does not bend, it gets broken silently. There is exactly one legitimate reason to add a
fourth folder: in Unity an assembly boundary *is* a folder boundary. Assembly flags (`noEngineReferences`, platform
filters, `defineConstraints`) are per-`.asmdef`, never per-file. Code that must live in its own assembly — e.g. an
engine-free deterministic simulation that must not be able to reference `UnityEngine` — therefore must live in its
own folder. Putting it under `Concretes/<Domain>/` drops it into the game assembly and the flag becomes
unenforceable.

An allowlist entry without the matching row in `architecture.md` leaves the rule file asserting the opposite of
what the validator permits — which is the same drift, one layer down. If a plan and the rule file disagree, the
disagreement is a decision for the human at SCOPE_GATE / ARCHITECTURE_GATE — surfaced by
`.claude/scripts/validate-plan-paths.sh`, which runs at plan time precisely because the write-time hook fires too
late to prevent an approved-but-wrong tree.

## Module Structure — example tree

```
_GameFolders/Scripts/Games/Abstracts/Audio/
├── IAudioService.cs           ← service contract (interface only)
└── IAudioProvider.cs          ← provider contract (interface only)

_GameFolders/Scripts/Games/Abstracts/Players/
├── IPlayerService.cs          ← service contract
└── IMoveHandler.cs            ← handler contract (pure C# NSubstitute seam)

_GameFolders/Scripts/Games/Concretes/Audio/
├── AudioService.cs            ← sealed service (Tier 3)
├── AudioConfiguration.cs      ← ScriptableObject config
├── AudioModule.cs             ← static install method
├── AudioEvents.cs             ← IEvent structs for this module (if any)
└── BasicAudioProvider.cs      ← IAudioProvider impl — Unity API here (Tier 4)

_GameFolders/Scripts/Games/Concretes/Players/
├── PlayerController.cs        ← Mono shell, Tier 1
├── MoveHandler.cs             ← pure C# handler, Tier 2
├── PlayerService.cs           ← sealed service, Tier 3
├── PlayerConfiguration.cs     ← ScriptableObject config
├── PlayerModule.cs            ← static install method
└── PlayerEvents.cs            ← IEvent structs
```

## Domain Folder Convention — why

**Why `Core/` is hook-enforced and not merely discouraged:** in the voxel-blast project `Core/` grew to 85 files and
7692 lines spanning five unrelated concerns (DI, bootstrap, game flow, services, pooling). Prose did not stop it.
Once a catch-all exists, everything drains into it.

> **Known, accepted gap:** `Common/`, `Shared/`, `Utils/`, `Helpers/`, `Misc/` are equally poor domain names and are
> deliberately **not** enforced. Catch-all names substitute for one another, so banning a subset only redirects the
> problem; the list is kept short to hold false positives near zero. Revisit if one of these shows up in practice.

> **Advisory, never enforced:** keep a domain flat while it is small; open subfolders when the file count starts to
> hurt readability; if you do subdivide, using the same shape on the `Abstracts/` and `Concretes/` side makes
> navigation easier. There is deliberately **no file-count threshold and no mirror check** — a hook fires once per
> single-file write, so a folder gated on "must already contain N files" can never be populated at all. Do not add one.

## NO GameContext / Service Locator — code

```csharp
// BAD — hides real dependencies, breaks least-privilege
public class GameContext
{
    public PlayerModel Player { get; }
    public ScoreSystem Score { get; }
}

// GOOD — each class declares exactly what it needs
public sealed class ScoreView : MonoBehaviour
{
    [Inject]
    public void Construct(ScoreModel model) { }
}
```

## ScriptableObject Config — code

```csharp
[CreateAssetMenu(menuName = "Game/Audio Configuration")]
public sealed class AudioConfiguration : ScriptableObject
{
    [SerializeField] private float _masterVolume = 1f;
    [SerializeField] private float _sfxVolume = 1f;
    public float MasterVolume => _masterVolume;
    public float SfxVolume => _sfxVolume;
}
```

## EventBusAccessor — code

```csharp
// _Framework/Events/EventBusAccessor.cs — pure C#, no UnityEngine
public static class EventBusAccessor
{
    private static IEventBus _instance;
    public static IEventBus Instance => _instance
        ?? throw new InvalidOperationException("EventBusAccessor not initialized. Call Initialize() in AppScope.");

    public static void Initialize(IEventBus bus) => _instance = bus;
}
```

Initialized by `AppScope` in `RegisterBuildCallback` (code: `rules/bootstrap-pattern-reference.md` → "AppScope"); ECS
usage (`EventBusAccessor.Instance.Publish(...)` from a `SystemBase`): `rules/ecs-dots.md` → Card 12.
