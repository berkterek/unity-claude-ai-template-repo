## Key Architecture Rules (summary)

- **No singletons** — VContainer only. Register in AppScope (global) or scene scopes.
- **No GameContext / service locator** — each class declares only its own dependencies.
- **No coroutines** — UniTask everywhere. `async UniTask`, not `async void`.
- **No legacy Input** — New Input System only. InputView owns PlayerControls.
- **No concrete cross-module deps** — only interfaces consumed across modules.
- **No UnityEngine in services** — Provider pattern. Unity API lives in `Concretes/<Module>/`.
- **No direct EntityManager structural changes** — use `EntityCommandBuffer` in ECS systems.
- **Tests are mandatory** — NSubstitute + AAA. Only interfaces mocked. Test file per class.

### Folder Structure

```
_Framework/              ← Pure C# — no Unity dependency
  Events/                ← IEventBus, IEvent, EventBusAccessor
  Logging/
  SaveLoadSystems/

_GameFolders/
  Scripts/
    Games/
      Abstracts/         ← Interfaces, abstract classes
      Concretes/         ← Unity providers, MonoBehaviours
      Ecs/               ← Authorings, Components, Systems
    Tests/
      [ProjectName]EditModeTest/    ← Edit Mode (NUnit + NSubstitute)
      [ProjectName]PlayModeTest/    ← Play Mode (ECS World integration)
  Prefabs/
    Enemies/
    UI/
    VFX/
    Environment/
```

### Building a Game from Scratch

| Phase | Commands | What happens |
|-------|---------|--------------|
| 1 — Idea & Design | `/game-idea`, `/architect` | GDD → TDD with adversarial review |
| 2 — Planning | `/plan-workflow`, `/dry-run` | WORKFLOW.md phases, preview without execution |
| 3 — Project Setup | `/setup-project` | Folder structure, .asmdefs, base classes, URP quality tiers, audio import settings |
| 4 — Implementation | `/orchestrate`, `/continue` | Execute WORKFLOW.md phase by phase |
| 5 — Quality | `/validate`, `/review-code`, `/ralph`, `/performance-audit` | Compile + tests green, code review, fix loops, hot path audit |
| 6 — Documentation | `/learn`, `/catch-up`, `/adr`, `/smart-commit` | Extract patterns, generate CATCH_UP.md, record decisions, commit |

For incremental feature work on an existing game: `/implement <description>` (complexity scored, full pipeline).
