# Unity AI Template — Claude Code Configuration

This is a personal Unity development template for Claude Code. It enforces architecture, coding standards, and quality rules automatically through hooks and provides slash commands for common workflows.

## Shell Commands (NON-NEGOTIABLE)

- **Use `tree` for directory listings** — `ls | grep`, `ls -la`, `find . -type f | grep` are forbidden for this purpose
- `tree -L 2` is sufficient in most cases; use `tree -L 3` or `tree --gitignore` when deeper traversal is needed
- `check-ls-grep.sh` blocks `ls | grep` patterns with exit 2

## Interaction Style

- Do NOT validate my ideas by default. No "great question", "good idea", "interesting approach" padding.
- If I present two conflicting options, you MUST pick one and justify it. "Both are good" is not an acceptable answer.
- Challenge my assumptions before agreeing. State the weaknesses, risks, and failure cases of any idea I propose — including my own.
- Be direct, not diplomatic. If an approach won't work, say "This won't work because X" instead of "Have you considered...".
- When I'm wrong, correct me. Do not change a correct answer just because I push back.

## What You Do NOT Do

- Do not call a flawed approach "interesting" or "clever".
- Do not agree first and critique later.
- Do not soften technical problems to spare my feelings.
- Do not add filler affirmations ("Sure!", "Absolutely!", "Of course!") at the start of responses.

## Important Constraints

- `settings.json` cannot be edited by Claude — `check-config-protection.sh` blocks it. User must add hook entries manually after any new hook is created. New hook scripts must be `chmod +x`'d (the harness invokes them by path, so a missing exec bit makes the hook fail with exit 126 and silently become a no-op); `session-restore.sh` also self-heals any `.claude/hooks/*.sh` missing its exec bit at SessionStart as a safety net.
- Hook exit 0 = warning only (pipeline continues). Exit 2 = blocking. A hook that only warns has minimal enforcement value.
- **Never route around a blocking hook.** Every content hook is registered on `Edit|Write` and does not see a Bash command, so `cat > file.cs`, `tee`, `sed -i`, or `cp` into a project file skips all 20+ of them at once. `check-write-via-bash.sh` blocks that channel with exit 2 (`/tmp` scratch paths exempt). If `Write`/`Edit` was blocked, the block is the answer: fix the underlying issue, or surface the conflict at the gate and let the human decide. Silencing a check yourself is a critical violation even when the resulting file content is correct — the check existed to move a decision to a human, and switching tools cancels that, not the rule.
- **A green hook suite is NOT evidence about a prompt — the test layers measure different things.** `.claude/hooks/tests/` (48 bats files, 533 tests) measures a hook's exit code and is deterministic. It cannot measure what an instruction makes an agent *do*, because a prompt has no exit code. Measured 2026-08-21: two edits to the reviewer criteria passed all 417 tests, every cited line number and a symmetric gate inventory **while making the reviewer measurably worse** — caught only by running an agent against a fixture. So: editing a reviewer prompt or a criteria list → run `.claude/tests/reviewer-fixtures/`; editing a pipeline's step order or its state-file handling → run `.claude/tests/pipeline-dry-run/`. Both are generators, not committed fixtures (their inputs are deliberately rule-violating C# and deliberately artificial gate state; committing either would defeat a content hook or strand a `gate-cleared`). Both cost an agent invocation, neither is CI-able, and neither is deterministic — one `PASS` does not rule out a real failure rate, so prefer conditions that are behavioural over binary and re-run before calling a change a regression. A cheap deterministic check does exist for one narrow thing the bats suite cannot see: `.claude/scripts/validate-generated-asmdefs.py` parses the `.asmdef` and `.cs` blocks `/setup-project` emits and asserts the assembly graph still matches the code inside it — a cross-assembly `using` with no matching reference, or `UnityEngine` under `noEngineReferences: true`. It exists because exactly those three errors shipped on 2026-09-02, in asmdefs written while their folders were still empty. Run it after editing any Step 3 / Step 4 block; it is covered by `validate-generated-asmdefs.bats`. It is a text analysis and says so in its own output — **a clean run is not a compile**, and the real compile probe is still unbuilt (`docs/PLAN_setup_compile_probe.md`). A **fourth** layer, `.claude/tests/blender-fbx-probe/`, is different in kind: it drives real Blender and a real `Unity -batchmode` with no model in the loop, so it *is* deterministic — run it after editing the FBX export contract in `.claude/scripts/blender-mcp-bridge.py`. It measures what no content hook can, because a `.fbx` is binary. Its first run disproved a claim in the skill it tests. A **fifth** layer, `.claude/tests/setup-compile-probe/`, is deterministic for the same reason: it extracts the Step 3 / Step 4 blocks from `/setup-project` and runs a real `Unity -batchmode` over them, so it answers whether the project the template generates actually compiles. Run it after editing any of those blocks. Like the Blender probe it paid for itself on its first run — with the asmdef validator already green it failed on `CS0246: VContainer`, a missing package reference in `FrameworkEvents` that predates the save/load work; the validator was then taught package references so the class is caught cheaply. Still covered by none of the five: PlayMode, prefab/scene authoring, and `TD-COMPILE` against real project code rather than generated code — those need the Unity Editor plus MCP.
- **A silent hook is NOT a compliance check.** Never write "verified compliant" into a spec, AC, or report because a hook exited 0 — it may not have inspected that path at all. Only an explicit `checked: <rule>` receipt counts as evidence.
- **A `PreToolUse` content-check hook must validate the EDIT's result, never the on-disk file, or a blocked file becomes permanently unfixable.** `PreToolUse` fires *before* `Edit`/`Write` touches disk — `$FILE_PATH` at that point is always the file's state **before** the pending change. A hook that does `grep "$FILE_PATH"` or `strip_cs_noise "$FILE_PATH"` is therefore judging the OLD content on every single invocation, including the one edit whose entire purpose is removing the violating line — so once a file has any blocking line on disk, it can never again pass through `Edit`/`Write`, by anyone, for any reason; the fix is not a fix because the check never sees it. Found 2026-08-24 in `check-no-monobehaviour-in-services.sh` (an `InputService.cs` with a real `UnityEngine.InputSystem` leak could not be edited to *remove* that leak) and confirmed in five more `PreToolUse` content hooks with the identical shape: `check-input-system.sh`, `check-unity-event.sh`, `check-time-scale.sh`, `check-enum-byte-base.sh`, `check-new-service.sh` — all six fixed the same way, by computing an `EFFECTIVE_FILE` (a temp file holding `tool_input.content` for `Write`, or the on-disk content with `old_string→new_string` applied for `Edit`) and checking that instead of `$FILE_PATH`. **2026-09-02, the same bug one layer down: five of those six fixed hooks still never inspected a brand-new file.** Computing `EFFECTIVE_FILE` is only half the fix — it does nothing if an `if [ ! -f "$FILE_PATH" ]; then exit 0; fi` guard still sits *above* it. At `PreToolUse` a newly created file is by definition not on disk, so that guard returned 0 before the `Write` branch could ever read `tool_input.content`: the branch was unreachable dead code in `check-new-service.sh`, `check-input-system.sh`, `check-time-scale.sh`, `check-unity-event.sh` and `check-enum-byte-base.sh`. Each enforced its rule only on edits to files that already existed — and new code arrives as new files. `check-no-monobehaviour-in-services.sh`, the sixth hook from that round, never had the guard and did block new-file writes, which is what proved the intent. Fixed by deleting the early guard and moving `[ -f "$FILE_PATH" ] || exit 0` into the `Edit` and default branches, where a missing file really is a no-op. The lesson generalizes: after adding the `Write` branch, assert that it is **reachable** — a file existence check anywhere above it silently disables it. Found only because bats coverage was written for the nine previously untested hooks; the suite had been green for months with this hole in it. `PostToolUse` hooks (e.g. `check-async-void.sh`, `check-no-linq-hotpath.sh`) are unaffected — they run *after* the write lands, so disk is already current. When writing a new `PreToolUse` content hook, or auditing an existing one: if it does path-based filtering (extension, skip-list, filename regex) that's fine on `$FILE_PATH`; the moment it reads file *content* to decide pass/block, it must read the effective post-edit content, not disk.
- **Path rules are validated at PLAN time, not only at write time.** `.claude/hooks/lib-path-rules.sh` is the single source of truth; it is called by `check-domain-folder-structure.sh` (write time) and by `.claude/scripts/validate-plan-paths.sh` (plan time, run by `/create-plan` and `/plan-module` at their SAVE step — after the plan is written, since neither script can read a plan that is not yet on disk — and by `/orchestrate` at Step 0b, before SCOPE_GATE, where the plan is already on disk). A folder-structure mistake is authored in `tasks.md` long before any file is written — the plan-time run is the one that prevents it. Legit exceptions are declared in `.claude/path-allowlist.txt` **and** `rules/architecture.md` → "Adding a Top-Level Folder", never invented silently. **2026-08-29:** `lib-path-rules.sh`'s `unity_path_allowlist_file()` located `path-allowlist.txt` via a bare `git rev-parse --show-toplevel`, which depends on the caller's cwd — a subagent's tool-execution context is not guaranteed to run from the repo root, so an empty result silently fell back to `.`, and a real, reviewed allowlist entry stopped matching inside a subagent even though it was correctly declared. Fixed by preferring `$CLAUDE_PROJECT_DIR` first (see the `subagent-depth` root-cause finding above — same bug class, same fix shape).
- **The gateguard's fact demands are also validated at PLAN time.** Same shape, same reason: `.claude/hooks/lib-gateguard-facts.sh` is the single source of truth; it is called by `gateguard.sh` (write time) and by `.claude/scripts/validate-plan-facts.sh` (plan time, run BLOCKING — by `/create-plan` and `/plan-module` at their SAVE step, **after** the plan is written, and by `/orchestrate` at Step 0b, before SCOPE_GATE). **"Before the gate" is not an option for a command that authors its own plan:** run against a folder that does not exist yet, this script prints `not found` and exits **0** — a silent green, never a block. `/plan-module` demanded exactly that until it was corrected; the gate had no teeth at all. A task that cannot name its callers or its wiring is a planning defect, so it is caught while the plan is editable rather than mid-pipeline where it deadlocks a subagent. There is **no cache and no receipt file** — the plan document *is* the manifest and every check is recomputed live. `NO TASKS FOUND` is not a pass; the script says so in its own output. Task declaration format: `docs/modules/_templates/tasks.md`. **Pass it a module plan folder (`docs/modules/NN-name/`) or a single `tasks.md`, never a broad root** — its directory walk collects `tasks.md` only and skips `_templates/` (the template's `[Domain]` placeholders own no folder and no `.asmdef`, so scanning the form would block on paths nobody intends to write; naming that file explicitly still scans it). The sibling `validate-plan-paths.sh` walks **every** `*.md`, not just `tasks.md`, so the same argument reaches much further there — see README → Plan-Time Validation.
- **Plan coverage releases the deny-then-allow gates.** When `gate-cleared` is open and the target file is named by a task in the plan, `unity_plan_covers` (in `_lib.sh`) lets `gateguard.sh`, `guard-critical-files.sh` and `check-config-protection.sh` (`.asmdef` branch only) pass without the Director-only retry. This is what makes `/orchestrate` and the `strict` profile compatible — before it, `guard-pipeline-direct-work.sh` blocked the Director while the gates blocked the subagent, so with a gate open *nobody* could write a `.cs`. `settings.json`, `manifest.json` and `.inputactions` are never released by coverage. Design record: `docs/superpowers/specs/2026-08-16-plan-time-fact-gate-design.md`.
- **Hook profiles:** `UNITY_HOOK_PROFILE=minimal|standard|strict` (default: `standard`). `minimal` runs only the 6 critical safety hooks (plus `check-ls-grep.sh`, which declares no level and therefore runs at every profile); `standard` runs all standard-level hooks; `strict` adds heavy enforcement hooks. `DISABLE_UNITY_HOOKS=1` disables all hooks. `UNITY_HOOK_MODE=warn` downgrades blocking to warnings. Full profile docs: `.claude/docs/hook-profiles.md`.
- `skills/genre/` and `skills/gameplay/` were removed. Use `/skill-creator` to generate project-specific genre/gameplay skills when needed.
- `.claude/agents/*.md` files define agent roles and provide prompt overlays for built-in FleetView agent types. The `subagent_type` value is always the agent's filename without `.md` (e.g. `unity-coder`, `lean-planner`). See `.claude/docs/agents-index.md` for the full mapping table.
- Command `/create-test-scene` was renamed to `/create-test`. Agent `unity-test-scene-builder` was renamed to `unity-test-builder`.
- **A session's MCP tool list is frozen at session start — and a missing bridge is never a reason to reach for its transport.** A server added mid-session with `claude mcp add` runs correctly and still contributes no `mcp__<server>__*` tools to that session; nothing reports this, the tools are just absent. That is why `.mcp.json` is **committed** (it was gitignored, which is exactly why each clone re-hit this) — every session in this repo opens with `graph_mcp` and `blender` already registered. When a bridge genuinely is missing, restart the session; do **not** substitute Bash. Talking to Blender's socket on `localhost:9876` directly and calling `bpy.ops.export_scene.fbx` skips `blender_export_fbx`'s pre-flight (missing UV layer, wrong unit scale, non-uniform scale) in one move — those three fail silently in Unity and **no content hook can see them, because a `.fbx` is binary**. Same shape as the `check-write-via-bash.sh` rule: switching tools to get past a gate cancels the gate. Full note: README → "MCP servers are frozen at session start".
- Claude's file tools (`Write`/`Edit`) cannot write `.unity` scene files — `block-scene-edit.sh` blocks this. **However, MCP tools (`manage_scene`, `manage_gameobject`, `manage_components`, `manage_build`) can create and wire scenes through the Unity Editor directly.** Always prefer MCP over listing manual Editor steps when MCP is connected.
- `.claude/graph/graph.json` is generated — never edit by hand. Use `/build-knowledge-graph` to refresh. **Partition architecture (since v1.3.0):** `scenes[]` and `prefabs[]` are stored in sibling files `scenes.json` and `prefabs.json` (same dir). `graph.json` holds `{"$partition": "scenes.json"}` refs. All three files are generated and committed together. **Schema is v1.7.0** (`.AsImplementedInterfaces()` expansion); v1.6.0 added event declaration records + structural installer detection, v1.5.0 added scope-parent resolution fields, v1.4.0 added `extraction_version`.
- **`extraction_version` vs `schema_version` — they answer different questions, do not conflate them.** `schema_version` tracks the document's *shape*; `extraction_version` tracks *what the values mean*. A change that makes the same input file produce a different record (e.g. which type lands in `registrations[].type`) bumps `EXTRACTION_VERSION` in `graph-builder.py` and **not** `schema_version`. Both move together only when a change does both at once — v1.5.0's scope-parent work added fields *and* changed what a record says, so it bumped `EXTRACTION_VERSION` 2→3 and `schema_version` 1.4.0→1.5.0; v1.6.0 and v1.7.0 did the same again (→4/1.6.0, →5/1.7.0). Assume one, not both — and when both move, say why in the version comment. The builder reads the stored value back on `--incremental` runs and promotes one run to `--full` on a mismatch, absent, or corrupt value — self-clearing, non-fatal, reason on stderr. This exists because `generator` and `schema_version` are write-only and staleness was judged purely on a 24h clock, so old wrong records survived indefinitely while the graph reported itself fresh.
- **`GRAPH_DISK_MISMATCH` is a warning, never a build failure.** Every build reconciles the `.cs` files on disk against the files the graph represents and names any that are missing. Non-fatal by design: a false alarm that blocks every build is worse than the silent omission it replaces. If you see it, run `python3 .claude/graph/graph-builder.py --full` — and if you are diagnosing *why*, capture `cache/file-hashes.json` **before** rebuilding, because `--full` overwrites it (that is how the original root cause was lost).
- **`events[].file` is the declaration site, and an event with no declaration record says so.** Until extraction v4 `events[]` was pivoted purely from `Publish`/`Subscribe` call sites, so `file` named whichever class referenced the event *first* — never the `IEvent` struct's own file — and `line`/`namespace` were dropped. It now comes from the extractor's declaration records. An event known only from a reference carries `declaration_unresolved: true` with an **empty** `file`; never render that as a path, and never backfill it from the referencing class. An event with empty `publishers` **and** `subscribers` is declared-and-unused — that case used to be absent from `events[]` entirely, and `EVENT_DANGLING` (R2) does not cover it, so this is the only place it surfaces.
- **Installer detection is structural: an `Install*` method taking an `IContainerBuilder`.** Not a name suffix. The old test (`endswith("Installer")`, or `endswith("Module")` + static) silently missed `AppModules` and `SceneModules` — plural — which `rules/bootstrap-pattern.md` *mandates*, so the project's own required convention was invisible to the graph in every project built from this template. Do **not** "fix" a future miss by adding a suffix to a list (`GameModules`, `AppInstallers`, …); that is the same hand-maintained-blacklist failure as the `csharp-unity.md` Card 5 collision table. Aggregators legitimately appear with an empty `registrations[]` — they register nothing, they order the modules that do.
- **A scope's `parent: null` means "not resolved", NEVER "no parent" — and must never be rendered as `(root)`.** A `LifetimeScope`'s parent arrives by two routes: `ParentReference.Create<T>()` in `Awake()` (read by `csharp_extractor.py`, works with Unity closed) and the serialized `parentReference.TypeName` on the prefab (read by the MCP extractor, needs the Editor). Both end in `GetRuntimeParent()` → `Find(parentReference.Type)`, so neither is more real — but **code wins on conflict**, because `Create<T>()` overwrites the whole struct at runtime, making a differing serialized value dead config. `parent_source` says which route answered; an unresolved parent carries `parent_unresolved_reason` = `mcp-extraction-absent` (Inspector route never read — re-run with the Editor open before concluding anything) or `no-parent-declared` (both read, neither named one — ambiguous by design: fits a real root scope **and** a parent assigned indirectly, so check the scope's `Awake()` before reporting a missing parent as a defect). Two corollaries: (1) the Inspector "Parent" control is a **type-name dropdown**, not an object picker, so it works across scenes — a claim that it cannot is wrong; (2) do **not** "fix" a null by filling the prefab field when `Awake()` assigns the parent in code — the dropdown value is discarded at runtime and the graph becomes accidentally right, which is worse than known-wrong.
- **Registration records name the concrete type, with the interface in `as`.** `RegisterInstance<IFoo>(new Foo())` → `type: "Foo"`, `as: "IFoo"`; `/knowledge-graph registrations` resolves through either name. **`.AsImplementedInterfaces()` is now findable by interface name (extraction v5).** It still stores that literal string in `as` — a **placeholder**, never an interface name — but the builder expands it into `as_resolved` from the concrete type's own *and inherited* `implements`, and `registrations IFoo` matches that. `as` is deliberately not rewritten: an explicit `.As<IFoo>()` is a statement of intent, a wildcard that happens to cover `IFoo` is a side effect — say which one you found. **Always read `as_resolution` before calling the list complete:** `partial` comes with `as_resolution_reason` (`type-unresolved` — no concrete type to look up; `class-not-in-graph` — third-party/generated or a real extraction miss; `base-not-in-graph` — interfaces on an unseen ancestor are missing). And expect `IDisposable`/`IInitializable` to match nearly every service: that is correct, since the idiom registers them, so never filter VContainer lifecycle interfaces out of that answer. `ITickable` is the one exception, for a project reason rather than a graph one — this template does not use container-driven ticks (`solid-oop.md` → EntryPoint), so `registrations ITickable` returning nothing is the right answer, not a missed extraction.
- **`registrations[].lifetime` is always `""` — do not report it as the registered lifetime.** `csharp_extractor.py` hardcodes the empty string in every registration branch and never reads the `Lifetime` argument, so `Register<T>(Lifetime.Singleton)` records `""` exactly like `RegisterComponent` does. The three named enum values are reserved for when extraction populates it. Do not infer `Transient` from an empty value, and do not "fix" a report by guessing the lifetime from the call name.
- Rule files under `.claude/rules/` start with a `## Cards` section (WHEN/WRONG/RIGHT/GOTCHA format). Read the cards first — the prose below each cards section is full reference detail.

## Knowledge Graph

@.claude/docs/knowledge-graph.md

## Required Stack

| Package | Source | Purpose |
|---------|--------|---------|
| **VContainer** | openupm / Package Manager | Dependency injection — replaces all singletons |
| **UniTask** | openupm / Package Manager | Async/await — replaces all coroutines |
| **New Input System** | Package Manager (com.unity.inputsystem) | Input — legacy Input API is blocked |
| **Newtonsoft Json** | Package Manager (com.unity.nuget.newtonsoft-json) | Save/load serialization — `LocalSaveLoadDal` will not compile without it |

## Optional Features

Selected during `/setup-project`. Choices are saved to `.claude/project-features.json`. Disabled features have their hooks removed from `settings.json` and their rules skipped per the `## Project Features` header in this file (written by setup).

| Package | Source | Feature flag | When disabled |
|---------|--------|--------------|---------------|
| **Addressables** | Package Manager (com.unity.addressables) | `addressables` | Addressables rules and skills skipped |
| **NSubstitute** | Manual DLL install | `testing` | Test folders, asmdefs, test hooks skipped |
| **Unity ECS DOTS** | Package Manager (optional) | `ecs` | ECS folder, asmdef, ECS hooks skipped |
| **Unity Knowledge Graph** | Built-in (`.claude/graph/`) | `graph` | Skip extractors and hooks. All graph-aware commands (planning, implementation, fix/debug, investigation, migration, and audit/review pipelines) fall back to direct file-scan. |
| **Unity project subfolder** | — | `unity_project_folder` | Set to `"."` (default) when `Assets/` is at repo root. Set to e.g. `"MyGame"` when the Unity project lives in a subfolder. `graph-builder.py` reads this and prefixes all `Assets/` paths accordingly. Set once in `project-features.json` — never hardcode paths in scripts. |

## Optional Plugins

Optional Claude Code plugins. Each pipeline command checks for these at Step 0/0.5 Plugin Preflight.

| Plugin | Commands | Threshold |
|--------|----------|-----------|
| `superpowers:test-driven-development` | `/implement` | always |
| `superpowers:brainstorming` | `/implement` (score ≥ 0.7), `/scene-setup` (score ≥ 0.7), `/architect` | conditional |
| `superpowers:systematic-debugging` | `/fix` (score ≥ 0.4), `/fix-deep` (score ≥ 0.4), `/debug-session` | conditional |
| `superpowers:verification-before-completion` | `/architect`, `/orchestrate`, `/qa`, `/validate`, `/migrate` (score ≥ 0.7) | conditional |
| `code-simplifier` | `/implement` | always |
| `claude-md-management:revise-claude-md` | `/implement`, `/fix` | always |

## Quick Start

@.claude/docs/quick-start.md

## Model Tiers

Three layers: session model (launch alias), subagent model (agent `.md` frontmatter — Lead=Opus / Worker=Sonnet / Scanner=Haiku by role level), and skill `model-tier`. Every agent spawned inside a command must carry an explicit `model` (never inherit the session model).

Agent frontmatter uses the aliases `opus` / `sonnet` / `haiku`, **never a pinned model ID** — Layer 2 tracks whatever Layer 1 resolves to, so a model bump needs no agent edits. Do not write `model: claude-opus-5` into an agent file.

**There is no automatic model fallback.** The API's `fallbacks` parameter fires only on safety refusals — overloads (529) and rate limits (429) are returned as-is. When the current-generation model is unavailable, switching is a manual call: prefer `/model claude-opus-4-7` (or `claude-sonnet-4-6`) inside the running session over restarting, since that keeps context and gate state. `claude-fable-5` is deliberately not a tier — full rationale, the fallback table, and the symptom→fix table below:

@.claude/docs/model-tiers.md

## Session Start

When starting a new conversation on this project, read these files first:
- `.claude/CLAUDE.md` (this file — already loaded)
- `.claude/rules/architecture.md` — module structure, VContainer, IEventBus patterns; same prefab hierarchy (root/child/grandchild) uses SerializeField not VContainer; domain folder convention (first folder under `Games/Abstracts|Concretes/` is a domain, never a layer or catch-all) and the `Concretes/<Domain>/ARCHITECTURE.md` intent contract
- `.claude/rules/solid-oop.md` — SOLID & OOP rules (MonoBehaviour role boundaries, SRP, OCP, DIP)
- `docs/CATCH_UP.md` if it exists — human-readable codebase guide
- If `.claude/graph/graph.json` exists and `graph` feature is enabled: run `/knowledge-graph summary` — **this is the primary source of truth** for classes, interfaces, events, installers, scopes, prefabs, methods, and call edges. Do NOT manually scan source folders if the graph is available and fresh (< 24h).

**Graph query cheatsheet (use before touching any existing system):**
- "What interfaces exist?" → `/knowledge-graph implementers IAudioService`
- "Who publishes/subscribes to an event?" → `/knowledge-graph publishers LevelStartedEvent`
- "What does an installer register?" → `/knowledge-graph registrations AudioService`
- "VContainer scope hierarchy?" → `/knowledge-graph scope-tree` (read `parent_source`; an `(unresolved: …)` parent is not a root scope)
- "Any architecture violations?" → `/knowledge-graph violations`
- "What components does a prefab have?" → `/knowledge-graph prefab Player`
- "Who calls this method?" → `/knowledge-graph callers AudioService.PlaySound`
- "What breaks if I change this class?" → `/knowledge-graph impact AudioService --hops 3`
- "How does X reach Y?" → `/knowledge-graph path AudioService.PlaySound HUDView.UpdateHUD`
- "Which classes are over-coupled?" → `/knowledge-graph god-nodes`

Before modifying any injectable class: apply Card 0 (solid-oop.md) — if no `[SerializeField]` and no Unity callbacks needed, make it pure C#.

If the user asks to continue work on a specific module, also read its source files before making any changes.

Before modifying or implementing any existing system, check `skills-index.md` for a relevant skill first — do not read source files directly if a skill covers the system.

## Rules (auto-loaded)

Detailed coding standards in `.claude/rules/`:

| File | Covers |
|------|--------|
| `architecture.md` | VContainer DI, module structure, IEventBus, EventBusAccessor, Provider pattern, InputService, AppScope; one-caller overfitting rule; GameScope vs [Domain]Module wiring boundary; same-prefab scripts wire via `[SerializeField]` not VContainer; **Scripts/ folder rules + declared exceptions** (`.claude/path-allowlist.txt`); **domain folder convention** (first segment under `Games/Abstracts\|Concretes/` is a domain — never a layer or catch-all; free below it); **`Concretes/<Domain>/ARCHITECTURE.md` intent contract** (English, 4 headings, ≤40 lines, no class names) |
| `csharp-unity.md` | Naming, namespaces, #region, null checks, UniTask, encapsulation; interface contract documentation (precondition/postcondition/side-effect); namespace collision rule (`Game.Concretes.<Domain>` vs UnityEngine type aliases); reuse-first (built-in over hand-rolled) |
| `performance.md` | Zero-alloc hot paths, caching, pooling, draw calls, UI canvas; **material folder structure** (`Arts/Materials/<Domain>/`); **shader file structure** (`.shader`/`.shadergraph` → `_GameFolders/Arts/Shaders/`); shader authoring → `unity-shader-dev` agent (HLSL or ShaderGraph complexity router); particle VFX → `unity-particle-designer` agent |
| `serialization.md` | FormerlySerializedAs, Unity null checks, SerializeReference |
| `save-load.md` | `ISaveLoadService`/`ISaveLoadDal` chain (never `PlayerPrefs`/`File` in game code), `*SaveData` = `[Serializable]` class + `int Version` (never a struct — the DAL's `object` parameter boxes it), `*SaveData` vs `*Model` split, `SaveKeyHelper` key contract, one key per domain, `HasKey`→`Load`→config default read path, atomic write, corrupt-save fallback (`catch (JsonException)`, never `Exception`), synchronous-I/O deviation record |
| `logging.md` | Runtime game code logs through `DLog`, never `UnityEngine.Debug`; Editor/test code keeps `Debug`; one `LogTag` per domain **and it must be enabled** — a new tag is silent by default for `Log`/`Warning`, while `Error` is deliberately neither stripped nor filtered; an error path never falls back without logging, and a caught exception is passed as an object, not as `.Message` |
| `unity-lifecycle.md` | Editor guards, platform defines, lifecycle order, threading, Time, `.meta` files |
| `unity-async.md` | UniTask, no coroutines, CancellationToken, DontDestroyOnLoad |
| `unity-input.md` | New Input System, InputService (pure C#, **pull-based — no tick**) + InputHandler (per-prefab), action map switching, `FixedUpdate` latch rule. InputView removed. |
| `unity-prefabs.md` | Prefab rules, new GameObject() forbidden, Destroy() rules, BaseCanvas pattern, Prefab Variants (Base+Variant decision table), **prefab DRY — same-parent duplicate siblings must be extracted (Card 5, + layout prerequisite, verified by `.claude/scripts/check-duplicate-siblings.py`)**, folder structure, logic/visual separation |
| `testing.md` | Test type decision tree (EditMode / PlayMode-Programmatic / PlayMode-Scene / ECS / NoTest), NSubstitute, AAA pattern, assembly setup |
| `ecs-dots.md` | Authoring/Baker, component naming, ISystem+IJobEntity, ECB, Hybrid linking; ECS→VContainer push-inject bridge (no singleton `Instance` from ECS) |
| `addressables.md` | No Resources.Load, async loading, handle lifecycle, address constants |
| `event-patterns.md` | UnityEvent forbidden, IEventBus vs Action vs C# event decision tree |
| `scene-hierarchy.md` | Standard 6-container scene hierarchy (`[Setup]`→`[VFX]`), classification table, prefab/container rules, enforcement |
| `bootstrap-pattern.md` | Code-first static Module pattern: [X]Module static class → AppModules.cs → AppScope. ConfigCatalog, SceneModules, new module addition flow. |
| `solid-oop.md` | MonoBehaviour role boundaries (View/Provider/Controller/Manager only, ~100 lines max); **suffix rule: `*View` is Canvas/UI only, `*Controller` is gameplay/character, `*Provider` abstracts Unity API, `*Manager` is a single-domain coordinator (Register/Unregister instead of IEventBus)**; enforcement is structural, not name-based (Card 0: `[SerializeField]` / Unity lifecycle callback); SRP one-sentence test (must not contain AND); OCP polymorphism rule; DIP constructor-interface rule; 4-tier: Mono Shell (≤80 ln) / Handler (pure C#) / Service+EntryPoint / Provider |
| `web-tool-data-contract.md` | **Web authoring tools only** — export schema single-source, enum int map, version field, unit/scale contract, parity fixture lock, importer error-on-missing, tool-side import validation (version + required-field checks before hydrating) |
| `web-tool-architecture.md` | **Web authoring tools only** — zero-build `file://` constraint, single model source of truth, pure-core/DOM-shell split, ~400 line limit, event delegation, idempotent render, runner-less tests, stable row identity (never array index) |
| `web-tool-design-system.md` | **Web authoring tools only** — design tokens, fixed spacing scale, control-type decision table, viewport primacy, unit display, destructive actions undoable-or-confirmed, keyboard access with visible focus, visible unsaved/invalid/empty state, bounded undo history, localStorage draft persistence across reloads |

## Hooks (auto-enforced on every Write/Edit)

@.claude/docs/hooks-blocking.md

### Warning (exit 0 — logs to stderr, does not block)

@.claude/docs/hooks-warning.md

### Subagent Lifecycle Hooks (agent spawn / agent stop / TaskCompleted)

Three hooks produce persistent JSONL audit files in `.claude/state/` — they fire automatically when multi-agent pipelines run (`/implement`, `/fix`, `/orchestrate`):

| Hook | Event (as actually registered in `settings.json`) | Output |
|------|--------------------------------------------------|--------|
| `agent-start-log.sh` | `PreToolUse` matcher `Agent` | `.claude/state/subagent-log.jsonl` — spawn record; increments `subagent-depth` |
| `agent-stop-log.sh` | `PostToolUse` matcher `Agent` | `.claude/state/subagent-log.jsonl` — stop record + `duration_approx_s`; decrements `subagent-depth` |

> **Trimmed at SessionStart, not by the writers.** Neither hook caps `subagent-log.jsonl` itself — `agent-stop-log.sh` searches it backwards for the matching `SubagentStart` line to compute `duration_approx_s`, and trimming mid-session could drop that line out from under an in-flight agent (silently yielding `-1`). Instead `session-restore.sh` trims it (and `task-log.jsonl`) to the newest 500 lines once, at SessionStart, when nothing is in flight.

> **`subagent-depth` can still leak — treat it as a hint, never as fact.** The pair only balances when every increment gets a matching Stop; an agent that errors, is interrupted, or is still running when the session ends leaves the count permanently high (measured once, pre-fix: 340 Start vs 319 Stop records, counter at 12 with no agent running). **2026-08-27 finding:** the dominant cause of that gap, measured across two projects, was not interruption at all — it was the Agent tool's own internal retry-on-transient-error path. A retried call fires a second `PreToolUse/Agent` (same `session_id`+`description`, seconds-to-minutes later) but the logical call still resolves to exactly one `PostToolUse` Stop, so every retry leaked +1. `agent-start-log.sh` now detects this (an unmatched same-`session_id`+`description` Start already pending means the new one is a retry) and skips the increment, logging `is_retry:true` instead. **2026-09-02 finding, and it leaks the OTHER way:** an agent resumed via `SendMessage` fires no `PreToolUse/Agent` at all, so the increment never happens and depth reads **lower** than reality while a subagent really is running. Measured mechanically: `settings.json` registers `agent-start-log.sh` on matcher `Agent`, and the string `SendMessage` appears nowhere in it. Both consumer directions are wrong in this case, and they are wrong in opposite ways — `guard-pipeline-direct-work.sh` reads 0 as "the Director is doing this" and **blocks the running subagent's own write** (loud, and the block message now names this cause), while the deny-then-allow gates *pass* on 0 and **release that subagent through the gate** (silent, and therefore worse). Do not "fix" this by registering the logging hooks on `Agent|SendMessage`: `to` is also a plain session name, so a message to another local or cloud session would increment depth and hand the Director the exact bypass. A correct fix needs a way to tell an in-process subagent resume from a cross-session message, which the current log cannot answer — it records `description` and `agent_type`, never the agent's name. Tracked in `docs/PLAN_subagent_depth_resume.md`. The remaining leak causes — genuine interruption, terminal error, session end mid-agent — are unfixable at this layer by design; `session-restore.sh` resets the counter at SessionStart. Each consumer resolves a doubtful count toward **enforcing its own rule**, so the two staleness directions are deliberately opposite: `guard-pipeline-direct-work.sh` allows on depth > 0 and therefore downgrades a stale count to 0; the deny-then-allow gates (`gateguard.sh`, `guard-critical-files.sh`, `check-config-protection.sh`) *pass* on 0 and therefore never downgrade — a timeout there would release a long-running subagent through the gate. If a leaked count locks the Director out, **clear both files or neither** — the counter has a companion queue, `subagent-depth-pending.jsonl`, holding decrements that have not matured yet (`_lib.sh` `unity_subagent_schedule_decrement`, applied lazily on the next read). Zeroing only the counter leaves matured decrements in the queue, which then drive it *negative* on the next read. `session-restore.sh` clears both together; do the same by hand:
> `printf 0 > "$CLAUDE_PROJECT_DIR"/.claude/state/subagent-depth && rm -f "$CLAUDE_PROJECT_DIR"/.claude/state/subagent-depth-pending.jsonl`
> The same pairing applies when correcting the count **upward** for a resumed subagent: a hand-written `1` is silently reset to `0` by the next hook read if any matured decrement is still queued — measured, not theorised. Correcting a counter that is demonstrably wrong is legitimate and is **not** the same as writing `pipeline-override`, which asserts that the user approved skipping the pipeline; if the pipeline is in fact doing the work, that assertion is false and must not be recorded. But the hand edit leaves no audit trail at all, where `pipeline-override` at least leaves a reason on disk — so say in the response what you changed and why, and put the counter back when the agent finishes, or the guard stays disabled for the rest of the session.
> Measured 2026-09-02 in a real project: the counter was hand-reset twice and both were the wrong fix — the actual cause was retry-dedupe skipping the increment (see the retry-window note above), and the reset only masked it while desynchronising the queue.

> **2026-08-29 finding: a subagent can read a permanently-different `subagent-depth` than the main session, with no leak involved.** `.claude/hooks/_lib.sh`'s `_resolve_state_dir()` picked the state directory via `git rev-parse --show-toplevel`, which depends on the caller's `cwd` — but a spawned subagent's own tool-execution context is not guaranteed to run from the repo root. When it doesn't, `git rev-parse` there resolves to a different git root (or fails) and the function silently falls back to `/tmp/unity-claude-hooks`, an always-fresh, always-zero directory the main session never writes to. Every `guard-pipeline-direct-work.sh` check inside that subagent's process then reads depth `0` no matter what the main session already incremented — real coder/tester subagents got blocked as "no subagent running" during `/orchestrate`, and an unrelated `mkdir`-lock fix for a genuine (but separate) race in the increment/decrement did not resolve it. Fixed by having `_resolve_state_dir()` prefer `$CLAUDE_PROJECT_DIR` — which every hook invocation receives correctly, since `settings.json` registers hooks as `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<script>.sh` — and fall back to `git rev-parse` only when that variable is unset or its `.claude/state` doesn't exist. This fixes every `_lib.sh` consumer, not just the depth counter.
>
> **2026-08-29 finding, discovered after the fix above: subagents were STILL getting blocked, for a second and unrelated reason — the Stop signal fires before the subagent is actually done.** In at least one harness the Agent tool dispatches asynchronously: `PostToolUse:Agent` fires on dispatch *acknowledgement*, not on real completion. Measured directly on three real subagent calls: `duration_approx_s` (the Start→Stop interval `agent-stop-log.sh` observes) was 1-3 seconds, while the same calls' own `usage.duration_ms` was 45,000-54,000ms — the depth counter was decremented back toward 0 roughly 50 seconds before the subagent actually finished, including through the exact moment it called `Write`. No reliable "subagent truly finished" event exists at the hook layer here (native Stop is already unreliable — see above; `TaskCompleted` tracks todo-list items, not `Agent` dispatches, and doesn't correlate 1:1 with them). Fixed by deferring the decrement instead of applying it immediately: `agent-stop-log.sh` schedules it via `unity_subagent_schedule_decrement()` (anchored on the matched Start timestamp + `UNITY_SUBAGENT_STOP_GRACE_SECONDS`, default 180s), and `unity_subagent_depth()` applies any matured pending decrement lazily on the next read. This is a heuristic, not an exact signal — it fails in the safe direction for `guard-pipeline-direct-work.sh` specifically (late decrement only over-permits a bounded window after real completion, never under-permits mid-run) — and it does not change the on-disk shape of `subagent-depth` itself, only when it gets decremented.
| `task-completed-log.sh` | `TaskCompleted` | `.claude/state/task-log.jsonl` — success record |

> **Why not the native `SubagentStart` / `SubagentStop` events:** both scripts state it in their header — those events do not fire consistently in Claude Code, so spawn and stop are observed by matching the `Agent` tool on `PreToolUse` / `PostToolUse` instead. This is a deliberate workaround, not an oversight. Note the JSONL records still carry `"event": "SubagentStart"` / `"SubagentStop"` as their **field value** — that is the record label, not the hook event. Searching `settings.json` for those event names will find nothing.

`session-save.sh` embeds these counts on every Stop: `session.json → subagent_summary.{spawned, stopped, tasks_completed}`. **Not all-time** — `session-restore.sh` trims `subagent-log.jsonl` and `task-log.jsonl` to the newest 500 lines at every SessionStart (same `tail -n 500` pattern as `hook-logger.sh`/`instinct-capture.sh`), so the counts reset to "since the last SessionStart trim" once a log has ever exceeded that threshold.
Payload note: the stop record carries **no `exit_code`**; TaskCompleted carries **no `status`** field — all three hooks are pure audit trail (exit 0 always).

> **None of the three touches gate state, and `agent-stop-log.sh` in particular must not.** It used to delete `gate-cleared` when the `committer` agent stopped, assuming committer is always the last pipeline step. `/orchestrate` commits after **every** phase and then continues, so that deletion tore the gate down mid-pipeline and forced the Director to re-open it once per phase. Gate teardown belongs to whoever opened the gate — the pipeline's own final step — with the 45-minute TTL and `session-restore.sh` as the safety nets. Do not re-add a `rm` here, and do not paper over it with an "orchestrate is active" marker file: that just moves the same conflict one layer down.
Full field reference and jq queries: `.claude/docs/hooks-warning.md → ## Subagent Audit Trail`.

## Commands (slash commands)

@.claude/docs/commands.md

## Agents (`.claude/agents/`)

@.claude/docs/agents-index.md

## Key Architecture Rules (summary)

@.claude/docs/architecture-summary.md

## Context Management & Review Modes

@.claude/docs/context-management.md

## Director Gates

Named prompts that pause the pipeline and wait for human approval before continuing. Full definitions in `.claude/docs/director-gates.md`.

@.claude/docs/director-gates.md

| Gate | Commands | When it fires | What you decide |
|------|----------|--------------|-----------------|
| `SCOPE_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/create-prefab-scene` | After complexity scoring, before any agent spawns | Confirm scope matches intent — type `go` or redirect |
| `ARCHITECTURE_GATE` | `/implement`, `/scene-setup`, `/new-module` | When new module folder detected (+0.3 signal), or always in `/new-module` | Approve proposed module structure (interface/service/installer/scope) |
| `BREAKING_GATE` | `/fix` (>3 files), `/fix-deep` (>3 files), `/migrate` (>5 files) | After affected files identified | Confirm wide-blast-radius change is intentional |
| `BREAKING_REVISION_GATE` | `/create-plan`, `/update-plan` | When reviewer classifies a plan revision as BREAKING (structural change, contradicts prior decision) | Choose: `re-research` / `accept` / `stop` — prevents cascading fix cycles |
| `QUALITY_GATE` | All pipeline commands | After reviewer returns CHANGES NEEDED, while the fix budget still has passes left | Choose: `fix` / `skip` / `stop`, plus display-only `list` |
| `EXHAUSTION_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/orchestrate`, `/qa`, `/create-prefab-scene`, `/create-plan`, `/update-plan` (13 sites) | A bounded retry loop spent its budget and the work still fails | Ship the known-bad state or abandon the run: `skip` / `stop`. **`fix` is deliberately absent** — the loop already spent it |
| `EVIDENCE_GATE` | `/fix-deep` | Automated reproduction produced no debug logs | Supply the evidence yourself: `retry` / `manual: <text>` / `stop` |
| `HYPOTHESIS_GATE` | `/fix-deep` | Evidence refuted the hypothesis (bound: 2 revision cycles) | Spend another investigation cycle or stop: `retry` / `stop` |
| `COMMIT_GATE` | `/implement`, `/fix`, `/fix-deep`, `/migrate`, `/scene-setup`, `/create-prefab-scene` | After all verification, immediately before committer | Final sign-off on staged files — type `go` or `stop` |
| `SPARC_GATE` | `/implement`, `/orchestrate`, `/fix` (≥ 0.4) | Before coder spawn, after SCOPE_GATE | Approve Specification + Architecture (how it will be built) |

> **`sparc-approved` is bounded by a TTL, not by per-turn deletion (fixed 2026-09-02).** `session-save.sh` used to delete it at every turn-end, so a phase spanning several turns re-opened SPARC_GATE on every one of them — measured in a real project. It is now excluded from that list, exactly like `gate-cleared`, and bounded the same way instead: the same 45-minute `UNITY_GATE_TTL` (`guard-sparc-approved.sh` calls `unity_gate_cleared_valid "sparc-approved"`), plus a SessionStart clear in `session-restore.sh`. All three parts are required — removing the deletion alone would have made an approval immortal, since the file previously had no expiry of any kind and was not cleared at SessionStart either.

### Automated Check Gates

These decide nothing and pause nothing — four ride the reviewer spawn as named criteria and `TD-COMPILE` rides the validator step, which is why none is in the table above rather than overlooked. Listing them here is what keeps them findable: all five were defined, referenced by no pipeline, and effectively dead until they were wired in.

| Gate | Applied by | What it checks |
|------|-----------|----------------|
| `TD-ARCHITECTURE` | `/implement`, `/fix`, `/fix-deep`, `/orchestrate` reviewer criteria; `reviewer.md` | VContainer DI, interfaces over concrete types, IEventBus across modules, Provider boundary, module boundaries — five named axes, each citing the rule it enforces |
| `TD-UNITY-RISK` | the same four, plus `/architect` at TDD time | Deprecated / breaking Unity 6 APIs, per `docs/engine-reference/unity/` |
| `TD-PERFORMANCE` | the same four; `unity-reviewer.md` | Zero-alloc hot paths, `sharedMaterial`, ECS ECB, Addressables handle release |
| `TD-COMPILE` | `/implement` Step 2.5, `/fix` Step 4.5, `/fix-deep` by reference | Unity MCP compile + Edit Mode tests pass before the reviewer runs at all |
| `CD-SCOPE` | the same four; `reviewer.md` | Unrequested files, unrelated refactors, abstractions nothing calls |

## NON-NEGOTIABLE: /orchestrate Rules

@.claude/docs/orchestrate-rules.md

---

## NON-NEGOTIABLE: Director Gate Rules

NEVER spawn a `tester`, `coder`, `unity-coder`, `unity-fixer`, `committer`, `unity-migrator`, `migrator`, or `unity-setup` agent without first:

1. Showing the required Director Gate (SCOPE_GATE or ARCHITECTURE_GATE) to the user
2. Receiving explicit `go` from the user
3. Writing `$(git rev-parse --show-toplevel)/.claude/state/gate-cleared` via Bash

Skipping a gate is a critical violation — the `guard-gate-cleared.sh` hook will block the agent spawn with exit 2. After the pipeline completes, delete `$(git rev-parse --show-toplevel)/.claude/state/gate-cleared`.

**Residual-risk note:** Gate approval expires after 45 minutes (2700s TTL). If a pipeline is abandoned mid-flight (QUALITY_GATE "stop", error, user interruption), the gate file remains valid until the TTL expires or the next SessionStart. A cautious Director can force-clear it immediately: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"`.

**Gate-cleared ≠ pipeline-executed — enforced mechanically, not just by instruction.** Showing a gate and receiving `go` only proves the gate was displayed; it does not prove the Test Writer/Coder/Reviewer/Committer pipeline was actually spawned afterward. Doing the work directly (Edit/Write/Bash) instead of spawning the pipeline agent is a violation of this rule even if the gate itself was shown correctly. This is enforced by `guard-pipeline-direct-work.sh`: while `.claude/state/gate-cleared` exists and no subagent is currently running (`.claude/state/subagent-depth` == 0, or a count left untouched for 15 min — the counter can still leak on an interrupted/errored/still-running agent, so staleness is resolved toward enforcing), direct `Edit`/`MultiEdit`/`Write` to `_GameFolders/Scripts/**/*.cs` and direct `git commit` are blocked with exit 2. (2026-08-27: `agent-start-log.sh` now dedupes the Agent tool's internal retry-on-error path — a retried call previously fired a second `PreToolUse/Agent` with no matching `PostToolUse` Stop, which was the dominant leak cause; retries are detected by an unmatched same-`session_id`+`description` Start already pending and no longer increment the counter.) If the user has explicitly approved skipping the pipeline for a specific task, the escape valve is writing a one-line reason to `.claude/state/pipeline-override` before retrying — never write it speculatively or to route around a legitimate block.

---

## Project Features

Configured by `/setup-project`. Source of truth: `.claude/project-features.json`.

| Feature | Status | Effect when disabled |
|---------|--------|----------------------|
| `addressables` | **DISABLED** | Skip `rules/addressables.md`, Addressables hooks, and address-constant checks |
| `testing` | **ENABLED** | Enforce `rules/testing.md`, NSubstitute rules, test-folder/asmdef requirements, and test hooks |
| `ecs` | **DISABLED** | Skip `rules/ecs-dots.md`, ECS structural-change hook (`check-ecs-structural-changes.sh`), and enum-byte-base hook (`check-enum-byte-base.sh`) |
| `graph` | **ENABLED** | `graph.json` is the primary source of truth. Graph-aware commands run a Step 0 graph preload — planning (`/create-plan`, `/update-plan`, `/plan-module`, `/new-module`), implementation (`/implement`, `/orchestrate`), fix/debug (`/fix`, `/fix-deep`, `/fix-codex`, `/debug-session`), investigation (`/search`, `/catch-up`, `/context-prime`, `/architect`), migration (`/migrate`), audit/review (`/qa`, `/validate`, `/review-code`, `/performance-audit`, `/check-portability`) — query graph first and fall back to file-scan only if graph is stale (> 24h), empty, or disabled. |
| `hybrid_graph` | **DISABLED** | Route call-graph queries (`callers`, `impact`, `path`, `god-nodes`) via `graph-mcp-server.py` MCP tools (backed by `graph_bfs_core.py`) with Bash-emitted stderr warning and lazy pip probe on fallback. When disabled: all queries use `graph-traversal.py`/`jq` (current behaviour), zero stderr output, no pip probe. |

> When a feature is DISABLED, Claude must not enforce its rules or suggest its patterns.

---

## Setup Checklist & Project-Specific Setup

@.claude/docs/setup-checklist.md

## Skills Library (`.claude/skills/`)

`skills-index.md` is the live index of all skills. It is updated automatically:
- `/discover --write` adds/updates rows in the `## Discovered Packages` table after writing package skills
- `/learn` adds/updates rows in the `## Learned Skills` table after saving approved patterns

Skills under `third-party/`, `plugins/`, `learned/`, and `platform/` are auto-loaded into every session via `@`-references in `auto-loaded-skills.md`. The `auto-load-skills.sh` PostToolUse hook keeps that file in sync — whenever a skill file is written, the reference is added automatically.

**Agent-side skill loading:** All code-writing, review, and exploration agents (`unity-coder`, `coder`, `tester`, `reviewer`, `unity-fixer`, `debugger`, `unity-scout`, and 20+ others) include a **Step 0** that reads `auto-loaded-skills.md` and then loads every relevant skill before starting work. This ensures subagents — which do not receive the parent session's `@`-includes — still have access to project-specific conventions. `unity-git-master` reads `.claude/skills/core/unity-git.md` at Step 0 for the same reason. `committer` carries the same Step 0, but it runs **both** ways: the nine commit-capable pipelines commit inline (session model, `@`-includes already loaded), while `/create-plan`, `/update-plan`, and `audio-clip-agent` spawn it as a real subagent on `sonnet`. Its Step 0 is load-bearing on the spawned paths and redundant on the inline ones. See `.claude/agents/committer.md` for the split.

**Skill enforcement (NON-NEGOTIABLE):** `enforce-skill-for-keywords.sh` (UserPromptSubmit hook) detects third-party package keywords in every prompt. Enforcement is skipped when the skill is already available — either auto-loaded via `auto-loaded-skills.md` (already in context) or previously invoked via the `Skill` tool this session. Otherwise it injects a blocking context message — you MUST invoke the skill before writing code, giving advice, or calling MCP tools. `track-skill-invocations.sh` (PostToolUse/Skill hook) records each Skill tool invocation. To add a new keyword mapping, edit the `KEYWORD_MAP` array in `.claude/hooks/enforce-skill-for-keywords.sh`.

@.claude/docs/skills-index.md

## Engine Version Reference

Engine-specific documentation lives in `docs/engine-reference/unity/`. Reference these files when answering questions about specific Unity 6 APIs, lifecycle changes, or package compatibility.

@.claude/docs/auto-loaded-skills.md
