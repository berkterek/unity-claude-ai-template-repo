# Unity AI Template — Setup & Onboarding

## Quick Start

1. Copy the `.claude/` folder into your Unity project root
2. Run `/setup-project` — detects existing state, asks about optional features (Addressables / Testing / ECS), generates folder structure, .asmdef files, and base classes, then writes `.claude/project-features.json`
3. Complete the **Manual Setup Checklist** below

## Adding to an Existing Project

Copy `.claude/` into the project root. Most hooks warn only — four will **block** existing code:

| Hook | What it blocks | Migration path |
|------|---------------|----------------|
| `check-input-system.sh` | `Input.GetKey`, `Input.GetAxis` | Create `PlayerControls.inputactions`, wrap in `InputView` |
| `check-vcontainer-singleton.sh` | Static singletons | Replace with VContainer registration in scope |
| `guard-editor-runtime.sh` | Bare `using UnityEditor` in runtime | Wrap with `#if UNITY_EDITOR` |
| `check-pure-csharp.sh` | `using UnityEngine` in `_Framework/` | Move Unity calls to a Provider in `Concretes/` |

**Recommended migration order:**
1. Run `/setup-project` to scaffold the folder structure
2. Move existing scripts into the new structure without changing logic
3. Fix blocking hook violations one module at a time
4. Run `/migrate` for systematic pattern replacements (e.g. coroutine→UniTask)
5. Run `/validate` after each phase to confirm green state

## Manual Setup Checklist

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

## Building a Game from Scratch

| Phase | Commands | What happens |
|-------|---------|--------------|
| 1 — Idea & Design | `/game-idea`, `/architect` | GDD → TDD with adversarial review |
| 2 — Planning | `/plan-workflow`, `/dry-run` | WORKFLOW.md phases, preview without execution |
| 3 — Project Setup | `/setup-project` | Folder structure, .asmdefs, base classes, URP quality tiers, audio import settings |
| 4 — Implementation | `/orchestrate`, `/continue` | Execute WORKFLOW.md phase by phase |
| 5 — Quality | `/validate`, `/review-code`, `/ralph`, `/performance-audit` | Compile + tests green, code review, fix loops, hot path audit |
| 6 — Documentation | `/learn`, `/catch-up`, `/adr`, `/smart-commit` | Extract patterns, generate CATCH_UP.md, record decisions, commit |

For incremental feature work on an existing game: `/implement <description>` (complexity scored, full pipeline).

## Hook Audit Log

Every hook execution is logged. Query logs to audit what was blocked or warned:

```bash
# All hook events from the current session
cat .claude/logs/hooks-$(date +%Y-%m-%d).log

# Only blocking events (exit code 2)
grep '"exit":2' .claude/logs/hooks-*.log

# Cost tracker summary
cat .claude/logs/cost-tracker.log | tail -50
```

Logs rotate daily and are stored in `.claude/logs/`.

## Model Tiers

| Tier | Model | Alias | When to use |
|------|-------|-------|-------------|
| **light** | `claude-haiku-4-5` | `claude-light` | Quick tasks: `/dump`, `/five`, `/mermaid`, `/create-changelog`, `/context-prime` |
| **normal** | `claude-sonnet-4-6` | `claude-normal` | Balanced work: `/review-code`, `/debug-session`, `/validate`, `/generate-tests`, `/performance-audit`, `/new-module`, `/check-portability`, `/clean-slop`, `/catch-up`, `/learn` |
| **heavy** | `claude-opus-4-7` | `claude-heavy` | Deep thinking: `/architect`, `/plan-workflow`, `/game-idea`, `/grill-me`, `/refine-gdd`, `/refine-tdd` |

Setup aliases once in your shell profile — see `.claude/aliases.sh`.
