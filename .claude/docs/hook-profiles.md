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
| `check-write-via-bash.sh` | Blocks writing project files through Bash, so the `Edit\|Write` content hooks cannot be bypassed |
| `block-scene-edit.sh` | Blocks direct edits to `.unity`, `.prefab`, `.asset` |
| `block-projectsettings.sh` | Blocks edits to `ProjectSettings/*.asset`, `Packages/manifest.json` |
| `check-config-protection.sh` | Protects `.asmdef` (edits only — creation allowed), `settings.json`, `.inputactions`, `manifest.json` |
| `guard-critical-files.sh` | Requires investigation before editing AppScope, InputService, Installers, EventBus, AppModules, ConfigCatalog — released when the open plan covers the file (`unity_plan_covers`), otherwise deny-then-allow: first attempt blocks, retry passes |
| `check-ls-grep.sh` | **PreToolUse (all tools).** Blocks `ls \| grep/awk/sed` used for directory listing — use `tree`. Listed here because it declares **no** `HOOK_PROFILE_LEVEL`, so unlike every other quality hook it runs at *every* profile, `minimal` included. Disable: `DISABLE_HOOK_CHECK_LS_GREP=1` |

### standard (default — all minimal + quality checks)

All `minimal` hooks plus:

| Hook | Purpose |
|------|---------|
| `check-architecture-doc.sh` | **PostToolUse.** Warns when a `Concretes/<Domain>/` receiving a `.cs` write has no `ARCHITECTURE.md`; blocks a malformed one (>40 lines, wrong/missing/extra `##` headings, no H1, any class-name symbol, or placed under `Abstracts/`). Disable: `DISABLE_HOOK_CHECK_ARCHITECTURE_DOC=1` |
| `check-async-void.sh` | Warns on `async void` outside lifecycle methods |
| `check-domain-folder-structure.sh` | **PreToolUse, fail-closed, all file types.** Rule logic lives in `lib-path-rules.sh`, shared with the plan-time `.claude/scripts/validate-plan-paths.sh`. Blocks unknown first segments under `Scripts/` and `Scripts/Games/` (escape hatch: `.claude/path-allowlist.txt`), layer names (`Services/`, `Views/`, `Providers/`, …) and catch-alls (`Core/`, `Generals/`) as the first folder under `Games/Abstracts\|Concretes/`, and `.cs` files with no domain folder. Never inspects below the domain. Disable: `DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1` |
| `check-ecs-structural-changes.sh` | Warns on ECB-required structural changes in ECS systems |
| `check-mono-justification.sh` | **PostToolUse.** Warns on a Card 0-unjustified MonoBehaviour (no own `[SerializeField]`, no Unity callback) and on a MonoBehaviour shell over 150 lines. Disable: `DISABLE_HOOK_CHECK_MONO_JUSTIFICATION=1` |
| `check-test-scene-exists.sh` | **PostToolUse.** Warns when a PlayMode test references a scene absent from `_Scenes/TestScenes/`. Honours `testing: false` in `project-features.json`. Disable: `DISABLE_HOOK_CHECK_TEST_SCENE_EXISTS=1` |
| `check-no-throwaway-editor-script.sh` | **PreToolUse.** Blocks one-shot Editor `.cs` scripts (scratch `Editor/Temp/` paths, or self-declared disposable content) that do work MCP should do. Escape valve: `.claude/state/editor-script-override`. Disable: `DISABLE_HOOK_CHECK_NO_THROWAWAY_EDITOR_SCRIPT=1` |
| `check-enum-byte-base.sh` | Warns on enums without `: byte` in ECS/IEvent files |
| `check-getcomponent-in-awake.sh` | Warns on `GetComponent` in `Awake` |
| `check-input-system.sh` | Blocks legacy `Input.GetKey` / `Input.GetAxis` |
| `check-no-hotpath-expensive-calls.sh` | Warns on `GetComponent`, `Camera.main`, etc. in hot paths |
| `check-no-linq-hotpath.sh` | Warns on LINQ in Update/FixedUpdate/LateUpdate |
| `check-no-runtime-instantiate.sh` | Blocks `new GameObject()` in runtime code |
| `check-null-propagation.sh` | Warns on `?.` and `is null` on Unity objects |
| `check-no-monobehaviour-in-services.sh` | Blocks `*Handler : MonoBehaviour` / `*Module : ScriptableObject`, and real engine/scene/asset/input/time `UnityEngine` API in `_Framework/`/`Abstracts/`/`Concretes/` — math value types and `Debug` logging are allowed. Judged structurally (Card 0), not by filename. Disable: `DISABLE_HOOK_CHECK_NO_MONOBEHAVIOUR_IN_SERVICES=1` |
| `check-time-scale.sh` | Blocks `Time.timeScale =` assignment |
| `check-unitask-cancellation.sh` | Warns on `async UniTask` without `CancellationToken` |
| `check-unity-event.sh` | Blocks `UnityEvent` usage |
| `check-vcontainer-singleton.sh` | Blocks static singleton patterns |
| `block-graph-direct-read.sh` | **PreToolUse Read.** Blocks direct `Read` of `graph.json` / `scenes.json` / `prefabs.json` while `hybrid_graph: true` — use `/knowledge-graph` subcommands or the `mcp__graph_mcp__*` tools. No-op when `hybrid_graph` is false. Disable: `DISABLE_HOOK_BLOCK_GRAPH_DIRECT_READ=1` |
| `graph-auto-update.sh` | Triggers incremental knowledge graph rebuild |
| `guard-pipeline-direct-work.sh` | **PreToolUse Edit\|MultiEdit\|Write\|Bash.** Blocks direct edits to `_GameFolders/Scripts/**/*.cs` and direct `git commit` while a Director Gate is open (`gate-cleared` exists) but no subagent is running (`subagent-depth` == 0) — i.e. the main session doing the pipeline agent's job itself. Escape valve: `.claude/state/pipeline-override`. Disable: `DISABLE_HOOK_GUARD_PIPELINE_DIRECT_WORK=1` |
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
| `agent-start-log.sh` | **PreToolUse `Agent`.** Appends a spawn record to `.claude/state/subagent-log.jsonl` and increments `subagent-depth`. Pure audit — always exit 0. Disable: `DISABLE_HOOK_AGENT_START_LOG=1` |
| `agent-stop-log.sh` | **PostToolUse `Agent`.** Appends a stop record (+ `duration_approx_s`) to `.claude/state/subagent-log.jsonl` and decrements `subagent-depth`. Pure audit — always exit 0. Disable: `DISABLE_HOOK_AGENT_STOP_LOG=1` |
| `task-completed-log.sh` | **TaskCompleted.** Appends a success record to `.claude/state/task-log.jsonl`. Pure audit — always exit 0. Disable: `DISABLE_HOOK_TASK_COMPLETED_LOG=1` |

### strict (all standard + audit/learning hooks)

All `standard` hooks plus:

| Hook | Purpose |
|------|---------|
| `gateguard.sh` | Blocks Edit/Write on unread C# files (Stage 1), then the fact gate (Guard 2). Guard 2 is released when the open plan covers the file — the fact demands themselves moved to plan time via `.claude/scripts/validate-plan-facts.sh`, sharing `hooks/lib-gateguard-facts.sh` with this hook. This is what makes `strict` usable inside `/orchestrate`; before it, the profile and the pipeline deadlocked each other |
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

## Written but deliberately NOT registered

These scripts exist under `.claude/hooks/` and are fully functional, but are intentionally absent
from `settings.json`. They are listed here so a future audit does not mistake them for a half-finished
job — the decision is recorded, not forgotten.

| Script | Why it is not wired |
|--------|--------------------|
| `check-new-service.sh` | Blocks `new *Service()` / `new *Provider()` anywhere and `new *Handler()` outside a `*Controller`/`*View` file (`csharp-unity.md` → Constructor Injection Rule). It reads the file from **disk**, so it can only run as PostToolUse — which would mean the offending C# is written first and blocked after. That contract is acceptable for a markdown doc (`check-architecture-doc.sh`) but not for source code: the block would leave rule-violating C# on disk with no way to prevent it. Registering it requires first rewriting it to read `tool_input.content`/`new_string` so it can run as PreToolUse. Until then the rule stays prose-enforced, with `check-vcontainer-singleton.sh` covering the singleton half. |

**Not a valid reason to leave a hook here:** "it has no tests" or "nobody registered it yet." Both are
fixable in one sitting. Only a genuine design blocker belongs in this table, stated explicitly.
