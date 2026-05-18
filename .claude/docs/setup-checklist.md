# Setup Checklist

After running `/setup-project`, most scene/wiring work is handled automatically via MCP. Only a few steps truly require manual action.

## MCP-Automated (done by /setup-project when MCP is connected)

These are NOT manual — `/setup-project` Step 5d handles them via `manage_scene`, `manage_gameobject`, `manage_components`, and `manage_build`:

- Scene creation: Bootstrap.unity, Menu.unity, Game.unity
- AppScope GameObject + component attachment in Bootstrap scene
- AppInstaller ScriptableObject creation and wiring to AppScope
- Build Settings scene order (Bootstrap at index 0)

## Truly Manual (cannot be automated)

- [ ] **NSubstitute DLL** — Download from [NuGet](https://www.nuget.org/packages/NSubstitute): click "Download package", rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from the `lib/` folder, place in `Assets/Plugins/NSubstitute/`
- [ ] **New Input System — Project Settings** — After package install: Edit → Project Settings → Player → Active Input Handling → "Input System Package (New)" (Unity restarts; this cannot be set via MCP)
- [ ] **Input Actions file** — Create `Assets/_GameFolders/Input/[ProjectName]Controls.inputactions`, enable "Generate C# Class" in Inspector
- [ ] **`check-test-scene-exists.sh` hook** — Add to `.claude/settings.json` PostToolUse section (Claude cannot edit settings.json due to config-protection hook):
  ```json
  {
    "matcher": "Write|Edit",
    "hooks": [{ "type": "command", "command": ".claude/hooks/check-test-scene-exists.sh", "timeout": 5000, "statusMessage": "Checking test scene exists..." }]
  }
  ```
- [ ] **`guard-reviewer-order.sh` hook** — Add to `.claude/settings.json` **PreToolUse** `Agent` matcher (alongside `guard-gate-cleared.sh`):
  ```json
  {
    "type": "command",
    "command": ".claude/hooks/guard-reviewer-order.sh",
    "timeout": 3000,
    "statusMessage": "Checking reviewer order (Codex first)..."
  }
  ```
  Full entry in `hooks.PreToolUse` where `"matcher": "Agent"` already exists — add as a second hook in that hooks array.
- [ ] **`track-codex-review.sh` hook** — Add to `.claude/settings.json` **PostToolUse** section as a new entry:
  ```json
  {
    "matcher": "Agent",
    "hooks": [{ "type": "command", "command": ".claude/hooks/track-codex-review.sh", "timeout": 3000, "statusMessage": "Tracking Codex review..." }]
  }
  ```

# Project-Specific Setup

When first adding this template to a new project, run `/setup-project`. It:

1. **Detects existing state** — checks folder structure and `manifest.json`, compares against `project-features.json` if it exists, reports conflicts and offers sync-only mode
2. **Asks feature questions** — Addressables (yes/no), Testing (yes/no), ECS (yes/no) — with detected signals as defaults
3. **Writes `.claude/project-features.json`** — hooks and commands read this to skip disabled features
4. **Generates** assembly definitions, base framework classes (`IEventBus`, `EventBus`, `EventBusAccessor`, `ModuleInstaller`, `AppInstaller`, `AppScope`), and test templates (if Testing=yes + NSubstitute present)
5. **Cleans settings.json** — removes hooks for disabled features
6. **Updates CLAUDE.md** — prepends `## Project Features` section listing enabled/disabled features

Then follow the checklist above. **Note:** Claude's file tools cannot write `.unity` files (`block-scene-edit.sh` blocks this), but MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`) can create and wire scenes directly through the Unity Editor — so Step 5d handles scene setup automatically when MCP is connected.
