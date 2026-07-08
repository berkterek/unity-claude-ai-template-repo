# Hook Profiles

Hook execution is gated by the `UNITY_HOOK_PROFILE` environment variable. Set it
in `.claude/settings.json` under `env`. The default is `standard`.

```json
{ "env": { "UNITY_HOOK_PROFILE": "standard" } }
```

## Levels

| Profile | When to use | Tradeoff |
|---------|-------------|----------|
| `minimal` | Brand-new project, exploring, or running an external tool that triggers many false positives. | Only corruption-preventing hooks fire. Code quality is unenforced. |
| `standard` | Default. Day-to-day work. | All quality checks fire; gateguard and instinct capture skipped. |
| `strict`  | Pipelines (`/implement`, `/orchestrate`, `/fix`) where every safeguard matters. | All hooks fire, including those that may add 1–3 s per Write/Edit. |

## Which hooks run at each level

### minimal (safety/corruption preventers only)

| Hook | Purpose |
|------|---------|
| `block-git-push.sh` | Prevents Claude from running `git push` |
| `block-scene-edit.sh` | Blocks direct edits to `.unity`, `.prefab`, `.asset` |
| `block-projectsettings.sh` | Blocks edits to `ProjectSettings/*.asset`, `Packages/manifest.json` |
| `check-config-protection.sh` | Protects `.asmdef`, `settings.json`, `.inputactions`, `manifest.json` |
| `guard-critical-files.sh` | Requires investigation before editing AppScope, InputService, Installers, EventBus, AppModules, ConfigCatalog (deny-then-allow: first attempt blocks, retry passes) |

### standard (default — all minimal + quality checks)

All `minimal` hooks plus:

| Hook | Purpose |
|------|---------|
| `check-async-void.sh` | Warns on `async void` outside lifecycle methods |
| `check-ecs-structural-changes.sh` | Warns on ECB-required structural changes in ECS systems |
| `check-enum-byte-base.sh` | Warns on enums without `: byte` in ECS/IEvent files |
| `check-getcomponent-in-awake.sh` | Warns on `GetComponent` in `Awake` |
| `check-input-system.sh` | Blocks legacy `Input.GetKey` / `Input.GetAxis` |
| `check-no-hotpath-expensive-calls.sh` | Warns on `GetComponent`, `Camera.main`, etc. in hot paths |
| `check-no-linq-hotpath.sh` | Warns on LINQ in Update/FixedUpdate/LateUpdate |
| `check-no-runtime-instantiate.sh` | Blocks `new GameObject()` in runtime code |
| `check-null-propagation.sh` | Warns on `?.` and `is null` on Unity objects |
| `check-pure-csharp.sh` | Blocks `using UnityEngine` in `_Framework/`/`Abstracts/`/`Concretes/` |
| `check-test-scene-exists.sh` | Checks test scene exists for PlayMode-Scene tests |
| `check-time-scale.sh` | Blocks `Time.timeScale =` assignment |
| `check-unitask-cancellation.sh` | Warns on `async UniTask` without `CancellationToken` |
| `check-unity-event.sh` | Blocks `UnityEvent` usage |
| `check-vcontainer-singleton.sh` | Blocks static singleton patterns |
| `graph-auto-update.sh` | Triggers incremental knowledge graph rebuild |
| `guard-editor-runtime.sh` | Blocks `UnityEditor` namespace in runtime code without `#if UNITY_EDITOR` |
| `guard-gate-cleared.sh` | Blocks agent spawns without Director Gate approval |
| `guard-reviewer-order.sh` | Enforces Codex review before unity-reviewer |
| `guard-sparc-approved.sh` | Enforces SPARC gate before coder spawn |
| `warn-serialization.sh` | Warns on renamed `[SerializeField]` without `[FormerlySerializedAs]` |
| `auto-load-skills.sh` | Auto-loads skills into new session |
| `session-save.sh` | Saves session state on Stop; expires gate files |
| `session-restore.sh` | Restores session state on SessionStart |
| `notify.sh` | OS-level notification when Claude finishes |
| `pre-compact.sh` | Snapshots state before `/compact` |
| `verify-after-write.sh` | Runs `dotnet build` after C# edits |
| `track-read.sh` | Records Read calls for gateguard |
| `track-skill-invocations.sh` | Records Skill invocations for enforcement |

### strict (all standard + audit/learning hooks)

All `standard` hooks plus:

| Hook | Purpose |
|------|---------|
| `gateguard.sh` | Blocks Edit/Write on unread C# files |
| `enforce-skill-for-keywords.sh` | Blocks action until skill loaded for detected keywords |
| `cost-tracker.sh` | Logs every tool call for cost auditing |
| `hook-logger.sh` | Detailed hook audit log |
| `instinct-capture.sh` | Captures tool-use observations for distillation |
| `instinct-distill.sh` | Distills observations into confidence-scored instincts |
| `stop-verify.sh` | Batch verifier at session end |
| `track-codex-review.sh` | Records Codex review completion marker |
| `install-git-hooks.sh` | Installs git hooks for pre-commit checks |

## Per-hook override

Disable a single hook regardless of profile:

```bash
DISABLE_HOOK_CHECK_PURE_CSHARP=1 claude
```

The env var name is the hook filename uppercased with hyphens → underscores, prefixed with `DISABLE_HOOK_`.

## Downgrade blocking → warning

Run all blocking hooks in warn-only mode (exit 0 instead of exit 2):

```bash
UNITY_HOOK_MODE=warn claude
```

## Disable all hooks

```bash
DISABLE_UNITY_HOOKS=1 claude
```
