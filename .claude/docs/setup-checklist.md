# Manual Setup Checklist

After running `/setup-project`, complete these steps manually (Claude cannot do them):

- [ ] **NSubstitute DLL** — Download from [NuGet](https://www.nuget.org/packages/NSubstitute): click "Download package", rename `.nupkg` to `.zip`, extract, take `NSubstitute.dll` from the `lib/` folder, place in `Assets/Plugins/NSubstitute/`
- [ ] **VContainer** — Install via Package Manager or openupm (`jp.hadashikick.vcontainer`)
- [ ] **UniTask** — Install via Package Manager or openupm (`com.cysharp.unitask`)
- [ ] **New Input System** — Install via Package Manager (`com.unity.inputsystem`); set active input handling to "Input System Package (New)" in Project Settings → Player
- [ ] **Addressables** — Install via Package Manager (`com.unity.addressables`); initialize via Window → Asset Management → Addressables → Groups
- [ ] **AppScope scene** — Create a Bootstrap scene (Build index 0), add `AppScope` component, wire `AppInstaller`
- [ ] **Build settings** — Add Bootstrap scene as index 0; add Menu and Game scenes
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

Then follow the checklist above. **Note:** `.unity` scene files must be created manually in Unity Editor — Claude cannot write scene files (`block-scene-edit.sh` blocks all `.unity` writes).
