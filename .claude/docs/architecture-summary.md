## Key Architecture Rules (summary)

- **No singletons** — VContainer only. Register in AppScope (global) or scene scopes.
- **No GameContext / service locator** — each class declares only its own dependencies.
- **No coroutines** — UniTask everywhere. `async UniTask`, not `async void`.
- **No legacy Input** — New Input System only. `InputService` (pure C#, pull-based — no tick) + `InputHandler` (per-prefab). `InputView` is removed.
- **No container-driven frame ticks** — `ITickable` / `IFixedTickable` are not used. A service needing a frame update exposes `Tick(float)` and its domain's Mono shell forwards `Update`/`FixedUpdate`/`LateUpdate`.
- **No concrete cross-module deps** — only interfaces consumed across modules.
- **No UnityEngine in services** — Provider pattern (Tier 4). Unity API never crosses into Tier 3.
- **No direct EntityManager structural changes** — use `EntityCommandBuffer` in ECS systems.
- **No MonoBehaviour without Card 0 justification** — must need `[SerializeField]`, Unity callbacks, Unity API boundary, or Canvas UI. "I need Update" is not valid.
- **No `new *Service()` or `new *Provider()`** — VContainer injects these. Exception: `new *Handler(...)` inside its Controller shell only.
- **No inline `builder.Register<T>()` in GameScope** — scene-lifetime pure C# services go through `SceneModules`.
- **No ModuleInstaller SO chain** — use static `[X]Module.Install()` + `AppModules.cs`. No `.asset` installer files, no drag-drop module lists.
- **Tests are mandatory** — NSubstitute + AAA. Only interfaces mocked. Test file per class.

### 4-Tier Architecture

Every class belongs to exactly one tier:

| Tier | Name | Type | Role | Limit |
|------|------|------|------|-------|
| 1 | Mono Shell (Controller / View) | MonoBehaviour | Caches `[SerializeField]` refs, creates Handlers, forwards lifecycle (`Update → handler.Tick`). Zero branching/calculation. | ≤ ~80 lines |
| 2 | Handler | Pure C# (NOT MonoBehaviour) | Prefab-local gameplay logic. Receives Unity component refs (Rigidbody, Transform) via constructor. Lives inside one prefab — never referenced externally. Always has `I*Handler` interface. | — |
| 3 | Service + EntryPoint | Pure C# (no UnityEngine API) | Cross-module logic. Registered with VContainer. Needs frame update → expose `Tick(float)`, forwarded by the domain's Mono shell — never MonoBehaviour, never `ITickable`. EntryPoint interfaces are for lifecycle only (`IInitializable`/`IDisposable`/`IStartable`/`IAsyncStartable`). | — |
| 4 | Provider | MonoBehaviour | Unity API boundary for Services. Wraps a single Unity API group (AudioSource, Physics, etc.). One Provider per API group. | — |

**Suffix rule:** `*View` → Canvas/UI only. `*Controller` → gameplay/character shell. `*Provider` → Unity API abstraction. `*Handler` → pure C# (NEVER MonoBehaviour). `*Service` → NEVER MonoBehaviour (hook blocks it).

### Module Pattern (Code-First, Static)

```
[X]Module.Install(builder, config)   ← static class, one per domain
    ↓
AppModules.Install(builder, catalog) ← single wiring point; EventBusModule always first
    ↓
AppScope.Configure()                 ← calls AppModules; never changes
```

- `ConfigCatalog` — one ScriptableObject aggregating all domain configs; `Validate()` called before any module installs
- `SceneModules` — scene-lifetime pure C# services; called from `GameScope`; `GameScope` only uses `RegisterComponent` for scene MonoBehaviours
- New module = one static class + one line in `AppModules.Install()`. No Editor asset work.

### Building a Game from Scratch

| Phase | Commands | What happens |
|-------|---------|--------------|
| 1 — Idea & Design | `/game-idea`, `/architect` | GDD → TDD with adversarial review |
| 2 — Planning | `/roadmap`, `/plan-module`, `/dry-run` | Module roadmap + per-module spec/design/tasks, plan preview |
| 3 — Project Setup | `/setup-project` | Folder structure, .asmdefs, base classes, URP quality tiers, audio import settings |
| 4 — Implementation | `/orchestrate`, `/continue` | Execute module tasks.md task by task |
| 5 — Quality | `/validate`, `/review-code`, `/ralph`, `/performance-audit` | Compile + tests green, code review, fix loops, hot path audit |
| 6 — Documentation | `/learn`, `/catch-up`, `/adr`, `/smart-commit`, `/smart-commit-selected` | Extract patterns, generate CATCH_UP.md, record decisions, commit (selected or all) |

For incremental feature work on an existing game: `/implement <description>` (complexity scored, full pipeline).
