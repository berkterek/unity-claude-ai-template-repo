# Setup Checklist

After running `/setup-project`, most scene/wiring work is handled automatically via MCP. Only a few steps truly require manual action.

## MCP-Automated (done by /setup-project when MCP is connected)

These are NOT manual — `/setup-project` Step 5d handles them via `manage_scene`, `manage_gameobject`, `manage_components`, and `manage_build`:

- Scene creation: Bootstrap.unity, Menu.unity, Game.unity
- AppScope GameObject + component attachment in Bootstrap scene
- ConfigCatalog ScriptableObject creation and wiring to AppScope
- Build Settings scene order (Bootstrap at index 0)

## Truly Manual (cannot be automated)

- [ ] **NSubstitute DLL** — Download from [NuGet](https://www.nuget.org/packages/NSubstitute): click "Download package", rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from the `lib/` folder, place in `Assets/Plugins/NSubstitute/`
- [ ] **New Input System — Project Settings** — After package install: Edit → Project Settings → Player → Active Input Handling → "Input System Package (New)" (Unity restarts; this cannot be set via MCP)
- [ ] **Input Actions file** — Create `Assets/_GameFolders/Input/[ProjectName]Controls.inputactions`, enable "Generate C# Class" in Inspector
- [ ] **`check-write-via-bash.sh` hook** — Add to the existing `"matcher": "Bash"` block under `hooks.PreToolUse` in `.claude/settings.json` (Claude cannot edit settings.json — the config-protection hook blocks it):
  ```json
  {
    "type": "command",
    "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-write-via-bash.sh",
    "timeout": 3000,
    "statusMessage": "Checking for hook-bypassing file writes..."
  }
  ```
  Until this entry exists the hook sits on disk and never runs, so `cat > Foo.cs` still skips every `Edit|Write` content hook.

> `check-test-scene-exists.sh`, `guard-reviewer-order.sh` and `track-codex-review.sh` used to be listed here. They are registered in the tracked `.claude/settings.json` and are inherited by any project derived from this template — nothing to do. `check-save-load.sh` and `check-dlog-usage.sh` were added on 2026-09-02 and are registered the same way, so they are inherited too. Verify with `bats .claude/hooks/tests/check-save-load.bats .claude/hooks/tests/check-dlog-usage.bats` (35 tests).

# Testing Infrastructure

When `testing: true` in `project-features.json`, `/setup-project` generates the following. If testing was enabled after initial setup, re-run `/setup-project` to generate missing pieces.

## What Gets Generated

| Artifact | Path | Notes |
|----------|------|-------|
| Edit Mode test assembly | `Scripts/Tests/[Project]EditModeTest/[Project]EditModeTest.asmdef` | NSubstitute refs included if DLL present |
| Play Mode test assembly | `Scripts/Tests/[Project]PlayModeTest/[Project]PlayModeTest.asmdef` | All platforms, NSubstitute refs included if DLL present |
| Edit Mode sample test | `Scripts/Tests/[Project]EditModeTest/SampleEditModeTests.cs` | AAA pattern, IEventBus mock example |
| Play Mode sample test | `Scripts/Tests/[Project]PlayModeTest/SamplePlayModeTests.cs` | UnityTest + yield return pattern |

## NSubstitute Dependency

NSubstitute cannot be installed via Package Manager — it requires a manual DLL drop:

1. Download from [nuget.org/packages/NSubstitute](https://www.nuget.org/packages/NSubstitute) → "Download package"
2. Rename `.nupkg` → `.zip`, extract, copy `NSubstitute.dll` from `lib/netstandard2.0/`
3. Place at `Assets/Plugins/NSubstitute/NSubstitute.dll`
4. Re-run `/setup-project` — it will regenerate `.asmdef` files with `precompiledReferences` and `overrideReferences: true`

Without NSubstitute.dll, test asmdefs are generated without mock support. `Substitute.For<T>()` will not compile.

## Test Type Decision

Every class goes through `test-type-router` before a test is written. Some classes are always `NoTest` — no test file is generated for them:

| Class type | Decision |
|-----------|----------|
| `LifetimeScope` subclass | NoTest — DI wiring tested via integration |
| `ScriptableObject` | NoTest — data container, no logic |
| `IComponentData` struct | NoTest — data only |
| `Baker<T>` | NoTest — bake-time only |
| Pure C# service | EditMode |
| MonoBehaviour (no lifecycle deps) | EditMode or PlayMode-Programmatic |
| MonoBehaviour (lifecycle matters) | PlayMode-Programmatic or PlayMode-Scene |
| ECS System | PlayMode-ECS (isolated World) |

## PlayMode Scene Tests

PlayMode-Scene tests require a real Unity scene. Each test scene lives in `Assets/_Scenes/TestScenes/` and must:
- Contain exactly one `TestBootstrap` prefab
- Be added to Build Settings
- Have a matching `[Feature]TestScope.cs` + `[Feature]TestInstaller.cs`

The `check-test-scene-exists.sh` hook warns when a PlayMode test references a scene that doesn't exist yet. See the manual hook entry in the checklist above.

---

# Project-Specific Setup

When first adding this template to a new project, run `/setup-project`. It:

1. **Detects existing state** — checks folder structure and `manifest.json`, compares against `project-features.json` if it exists, reports conflicts and offers sync-only mode
2. **Asks feature questions** — Addressables (yes/no), Testing (yes/no), ECS (yes/no) — with detected signals as defaults
3. **Writes `.claude/project-features.json`** — hooks and commands read this to skip disabled features
4. **Generates** assembly definitions, base framework classes (`IEventBus`, `EventBus`, `EventBusAccessor`, `ConfigCatalog`, `AppModules`, `AppScope`), and test templates (if Testing=yes + NSubstitute present)
5. **Cleans settings.json** — removes hooks for disabled features
6. **Updates CLAUDE.md** — prepends `## Project Features` section listing enabled/disabled features

Then follow the checklist above. **Note:** Claude's file tools cannot write `.unity` files (`block-scene-edit.sh` blocks this), but MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`) can create and wire scenes directly through the Unity Editor — so Step 5d handles scene setup automatically when MCP is connected.
