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
_Framework/                              ← Never references _GameFolders or other project folders
  Events/FrameworkEventBus.asmdef       ← each subfolder has its OWN .asmdef (never a single root-level one)
  Logging/FrameworkLogging.asmdef
  SaveLoadSystems/FrameworkSaveLoadSystems.asmdef
  Editors/FrameworkEditor.asmdef

_GameFolders/
  Scripts/
    Games/
      Abstracts/         ← interfaces and abstract base classes ONLY, organized by domain
        Players/
        Enemies/
        ...
      Concretes/         ← ALL concrete classes (pure C# or MonoBehaviour), organized by domain
        Players/
        Enemies/
        Audio/
        ...
      Ecs/               ← Authorings, Components, Systems (if ECS enabled)
    Tests/
      [ProjectName]EditModeTest/    ← Edit Mode (NUnit + NSubstitute)
      [ProjectName]PlayModeTest/    ← Play Mode (ECS World integration)
    Editors/             ← Editor-only tools, custom inspectors
  Prefabs/
    Bootstrap/           ← AppScope.prefab, GameScope.prefab
    CoreObjects/         ← EventSystem.prefab, MainCamera.prefab
    Enemies/
    UI/
      Canvases/          ← BaseCanvas.prefab + Prefab Variants (CanvasHUD, CanvasPopup…)
    VFX/
    Environment/
Arts/
  Materials/             ← all .mat files — NEVER inside Prefabs/
    Items/
    Environment/
    Characters/
    VFX/
  Textures/              ← textures by domain
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
