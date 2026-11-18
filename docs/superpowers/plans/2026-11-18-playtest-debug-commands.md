# Playtest Map & Debug Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude a playtest map (`docs/PLAYTEST.md`) and dev-only debug commands it can run through MCP, written once and also shown in SRDebugger when a project uses it.

**Architecture:** A VContainer-free `FrameworkDebugCommands` assembly in the framework package holds a registry that reflects over registered command containers. A generic Editor menu runs/lists commands from a request file. An optional SRDebugger adapter mirrors the registry into the panel. Game-side `*DebugCommands` classes self-register from their module's scope. A generator writes the command table into `PLAYTEST.md`; hooks block fake-outcome and service-locator cheats.

**Tech Stack:** C# (Unity 2022.3+ package, Newtonsoft Json), bash hooks + bats, Python 3 generator.

**Spec:** `docs/superpowers/specs/2026-11-18-playtest-debug-commands-design.md`

**End State:**
- `packages/framework/DebugCommands/` (new assembly `FrameworkDebugCommands`) and `packages/framework/DebugCommands/SRDebugger/` (assembly `FrameworkDebugCommandsSRDebugger`) exist with `ARCHITECTURE.md`; framework `package.json` is `0.3.0`.
- `Tools/Framework/Debug Commands/Run` and `/List` menu items exist in `FrameworkEditor`.
- `check-debug-commands.sh` (PreToolUse, blocking) and `check-playtest-drift.sh` (PostToolUse, warning) exist, executable, with green bats suites.
- `.claude/scripts/generate-playtest-commands.py` writes/checks the generated block of `docs/PLAYTEST.md`.
- `/setup-project` generates `DebugCommandsModule.cs`, the `AppModules` line, the asmdef reference, the `PLAYTEST.md` skeleton, the `srdebugger` feature; `run-probe.sh` exits 0.
- `rules/debug-commands.md`, rule-index row, architecture exception, singleton-hook allow, `/implement` Step 3.6 agent smoke pass and `/plan-module` guidance are in place.
- **Nothing is committed** (user instruction 2026-11-18: no commits until the user says so).

## Global Constraints

- No `git commit` in any task — the user lifts this explicitly. Changes stay in the working tree.
- Framework source is only `packages/framework/`; never copy into `Assets/`. After any framework edit: `.claude/tests/setup-compile-probe/run-probe.sh` must exit 0.
- Framework `package.json` `"unity": "2022.3"` — no API newer than 2022.3 in framework code.
- Framework stays free of VContainer and UniTask references (`package.json` dependencies unchanged except none added).
- Dev-only define condition, verbatim: `UNITY_EDITOR || DEVELOPMENT_BUILD`.
- Command id = container class name with the `DebugCommands` suffix removed, `.`, member name — e.g. `LevelDebugCommands.GoToLevel` → `Level.GoToLevel`. Registry, Editor runner and generator all use this rule.
- Request file `<unity_project_folder>/Temp/debug-command.json`; result file `<unity_project_folder>/Temp/debug-command-result.json`.
- Result log line prefix, verbatim: `[DebugCommands] OK ` / `[DebugCommands] FAIL `.
- `settings.json` is never edited by Claude; hook entries go to the manual checklist.
- PreToolUse content hooks judge the effective post-edit content and key on payload shape (`has("content")` / `has("old_string")`) — copy the approach in `.claude/hooks/guard-editor-runtime.sh`.
- New hooks/scripts are `chmod +x`.
- Dev-only command classes and the registry are `NoTest` (`rules/testing.md` dev-only tooling); hooks and the generator are tested with bats.

## Review Focus

1. **Command called in the wrong scene** (scene-scoped container not registered) → `FAIL … not registered in the current scene`, with the list of registered ids; never a null-ref. Pinned in Task 2 manual check.
2. **Unparseable parameter value** (`"TargetLevel": "abc"`, unknown property name) → `FAIL` naming the property and the value; the command is not invoked. Task 1 `TryRun` contract + Task 2 manual check.
3. **Command throws** → `FAIL` with exception type + message, logged with `Debug.LogException`; the runner never rethrows into the menu callback. Task 1 contract.
4. **Edit that removes a forbidden line from an already-bad `*DebugCommands.cs`** must pass the hook (fixability). Task 4 bats test.
5. **Generator on a `*DebugCommands.cs` whose registration it cannot find** → scope `unknown` + one warning on stderr, exit 0. Task 5 bats test.

---

### Task 1: `FrameworkDebugCommands` assembly — registry and accessor

**Files:**
- Create: `packages/framework/DebugCommands/FrameworkDebugCommands.asmdef`
- Create: `packages/framework/DebugCommands/IDebugCommandRegistry.cs`
- Create: `packages/framework/DebugCommands/DebugCommandRegistry.cs`
- Create: `packages/framework/DebugCommands/DebugCommandInfo.cs`
- Create: `packages/framework/DebugCommands/DebugCommandRegistryAccessor.cs`
- Create: `packages/framework/DebugCommands/ARCHITECTURE.md` (format: `.claude/rules/architecture-docs.md` — Read it first)
- Modify: `packages/framework/package.json` (`version` → `0.3.0`, description mentions debug commands)
- `.meta` files: Unity generates them in the probe project; for the package, create them the same way existing ones were made (copy GUID-unique metas — `uuidgen | tr -d - | tr A-Z a-z` for the guid).

**Interfaces:**
- Produces (namespace `Framework.DebugCommands`):
  - `public interface IDebugCommandRegistry { void Register(object container); void Unregister(object container); IReadOnlyList<DebugCommandInfo> List(); bool TryRun(string commandId, IReadOnlyDictionary<string, string> set, out string message); IReadOnlyList<object> Containers { get; } event Action<object> ContainerAdded; event Action<object> ContainerRemoved; }`
  - `public readonly struct DebugCommandInfo { string Id; string Category; DebugCommandKind Kind; string ValueType; string CurrentValue; }` with `public enum DebugCommandKind { Command, Parameter, Value }` (method / settable property / read-only property).
  - `public sealed class DebugCommandRegistry : IDebugCommandRegistry`
  - `public static class DebugCommandRegistryAccessor { public static IDebugCommandRegistry Instance { get; } public static void Set(IDebugCommandRegistry registry); }`

- [ ] **Step 1: asmdef.** `name: FrameworkDebugCommands`, `rootNamespace: Framework.DebugCommands`, `references: []`, `defineConstraints: ["UNITY_EDITOR || DEVELOPMENT_BUILD"]`, `autoReferenced: true`, `noEngineReferences: false`.
- [ ] **Step 2: Verify the `||` constraint syntax before writing code.** Check `docs/engine-reference/unity/` and Unity's asmdef manual for `defineConstraints` OR support. If unsupported: replace with `["DEBUG_COMMANDS"]`, and record in Task 6 that `/setup-project` adds `DEBUG_COMMANDS` to the Standalone/Android/iOS scripting defines **and** documents that release builds must remove it. Write the outcome as one line in `ARCHITECTURE.md`.
- [ ] **Step 3: Write the types above.** Rules for `DebugCommandRegistry`:
  - `Register` ignores null and duplicates; raises `ContainerAdded`. `Unregister` raises `ContainerRemoved` only if present.
  - `List()` reflects public instance members declared on each container type: parameterless `void` methods → `Command`; properties with public get+set → `Parameter`; get-only → `Value`. `Category` from `System.ComponentModel.CategoryAttribute`, else the id prefix.
  - `TryRun`: unknown id → `false`, message lists registered ids. For each `set` entry: property must be a `Parameter` of the same container; convert with `int/float/bool/string/enum` (`CultureInfo.InvariantCulture`, `Enum.Parse(ignoreCase:true)`); any failure → `false`, method not invoked. Invocation exception → `Debug.LogException(inner)`, `false`, message `ExceptionType: message`. Success → `true`, message `Id (k=v, …)`.
  - `Accessor.Set` called twice logs a warning and overwrites (domain reload without reload-disabled).
  - All files wrapped in nothing extra — the asmdef constraint excludes them.
  - `#region` discipline per `csharp-unity` Card 4 (packages follow it too — match `EventBus.cs`).
- [ ] **Step 4: Bump `package.json` to `0.3.0`** and add a `0.3.0` entry to `packages/framework/CHANGELOG.md` (create the file — none exists yet; one entry, Keep-a-Changelog `### Added`).
- [ ] **Step 5: Run** `.claude/tests/setup-compile-probe/run-probe.sh` → expected exit 0. (Probe compiles the package via `file:`.)

### Task 2: Editor runner menu

**Files:**
- Create: `packages/framework/Editors/DebugCommandsMenu.cs`
- Modify: `packages/framework/Editors/FrameworkEditor.asmdef` (add `FrameworkDebugCommands` and `Newtonsoft.Json` references — check how `SerializedOpsApplier.cs` gets Newtonsoft and mirror it)
- Modify: `packages/framework/Editors/ARCHITECTURE.md` (one section on the runner)

**Interfaces:**
- Consumes: `DebugCommandRegistryAccessor.Instance`, `IDebugCommandRegistry.TryRun/List` (Task 1).
- Produces: menu paths `Tools/Framework/Debug Commands/Run` and `Tools/Framework/Debug Commands/List`; request JSON `{ "command": string, "set": { string: string } }`; result JSON `{ "ok": bool, "message": string, "commands": [ { "id", "category", "kind", "valueType", "currentValue" } ] }` (`commands` filled by List, and by Run on failure).

- [ ] **Step 1: Write `DebugCommandsMenu`** (static class, `Framework.Editors`). Paths resolved from `Application.dataPath`'s parent + `Temp/`. Run: not `EditorApplication.isPlaying` → FAIL `not in Play Mode`; accessor null → FAIL `registry not set — is DebugCommandsModule installed?`; missing/unparseable request → FAIL naming the file. Every outcome writes the result file **and** logs one line with the verbatim prefix. Delete the request file after reading so a stale request never re-runs.
- [ ] **Step 2: Run the compile probe** → exit 0.
- [ ] **Step 3: Manual MCP check (deferred to Task 8)** — no game domain exists in the probe project.

### Task 3: SRDebugger adapter assembly

**Files:**
- Create: `packages/framework/DebugCommands/SRDebugger/FrameworkDebugCommandsSRDebugger.asmdef`
- Create: `packages/framework/DebugCommands/SRDebugger/SRDebuggerDebugCommandsBridge.cs`
- Modify: `packages/framework/DebugCommands/ARCHITECTURE.md` (adapter section)

**Interfaces:**
- Consumes: `IDebugCommandRegistry.Containers`, `ContainerAdded`, `ContainerRemoved` (Task 1).
- Produces: `public sealed class SRDebuggerDebugCommandsBridge : IDisposable { public SRDebuggerDebugCommandsBridge(IDebugCommandRegistry registry, SRDebugger.Services.IDebugService debugService); }` — the module registers `SRDebug.Instance` as `IDebugService` (the one touch point with the library static) — adds every existing container and subscribes; `Dispose` unsubscribes and removes all.

- [ ] **Step 1: asmdef.** `references: ["FrameworkDebugCommands", "StompyRobot.SRDebugger"]`, `defineConstraints: ["SRDEBUGGER_ENABLED", <the dev-only constraint chosen in Task 1 Step 2>]`.
- [ ] **Step 2: Bridge** calls `SRDebug.Instance.AddOptionContainer(c)` / `RemoveOptionContainer(c)`. Before writing, open SRDebugger's `IDebugService.cs` (lines ~100–110 in a project that has it, e.g. read-only in `~/Desktop/Github/voxel-blast/Assets/ThirdPartyAssets/StompyRobot/SRDebugger/Scripts/Services/IDebugService.cs`) to confirm the signatures. Also confirm there that `System.ComponentModel.CategoryAttribute` is honoured for non-`SROptions` containers; if not, note the limitation in `ARCHITECTURE.md`.
- [ ] **Step 3: Compile probe** → exit 0 (assembly is skipped there — no `SRDEBUGGER_ENABLED`; this proves it does not break projects without SRDebugger).

### Task 4: `check-debug-commands.sh` hook

**Files:**
- Create: `.claude/hooks/check-debug-commands.sh` (copy structure from `guard-editor-runtime.sh`: `_lib.sh`, effective content, `unity_hook_block`)
- Test: `.claude/hooks/tests/check-debug-commands.bats` (fixture style of `check-save-load.bats`)

**Interfaces:**
- Produces: exit 2 with a one-line reason per violation; exit 0 otherwise. Applies to files named `*DebugCommands.cs`, plus a separate accessor check on all `.cs` under `_GameFolders/`.

- [ ] **Step 1: Write failing bats tests:**
  - `blocks Publish in a DebugCommands file` — Write `LevelDebugCommands.cs` with `#if UNITY_EDITOR || DEVELOPMENT_BUILD` … `_eventBus.Publish(new LevelCompleteEvent());` … `#endif` → status 2.
  - `blocks FindFirstObjectByType` → 2. `blocks FindObjectOfType` → 2. `blocks Container.Resolve` (`gameScope.Container.Resolve<ILevelService>()`) → 2.
  - `blocks missing dev-only guard` — valid body without the `#if` → 2.
  - `allows a clean command class` — guard + `_levelService.CompleteLevel();` → 0.
  - `allows an Edit that removes the Publish line` — on-disk file contains `Publish`, Edit `old_string` = that line, `new_string` = `_levelService.CompleteLevel();` → 0.
  - `ignores Publish in a non-DebugCommands file` (`LevelService.cs`) → 0.
  - `blocks DebugCommandRegistryAccessor in game code` (`_GameFolders/Scripts/Games/Concretes/Level/LevelService.cs`) → 2.
  - `allows DebugCommandRegistryAccessor in DebugCommandsModule.cs` → 0.
  - `ignores comment-only Publish` (`// never Publish here`) → 0 (use `strip_cs_noise`).
- [ ] **Step 2: Run** `bats .claude/hooks/tests/check-debug-commands.bats` → all FAIL (hook missing).
- [ ] **Step 3: Implement the hook**; `chmod +x`.
- [ ] **Step 4: Run bats** → all PASS. Run the whole suite `bats .claude/hooks/tests/` → no new failures.

### Task 5: Playtest generator + drift hook

**Files:**
- Create: `.claude/scripts/generate-playtest-commands.py`
- Create: `.claude/hooks/check-playtest-drift.sh` (PostToolUse, `unity_hook_warn`, exit 0 always)
- Test: `.claude/hooks/tests/check-playtest-drift.bats` (also exercises the generator through fixtures in `mktemp -d`)

**Interfaces:**
- Produces: `generate-playtest-commands.py [--root <unity_project_folder>] [--doc docs/PLAYTEST.md] [--check]`. Default: rewrites only between `<!-- debug-commands:begin -->` and `<!-- debug-commands:end -->`. `--check`: exit 1 if the block would change, 0 if current. Missing markers → exit 2 with a message. Table header verbatim: `| Command | Scope | Parameters | Description |`.
- Parsing (regex, stdlib only, `python3 -I`): classes in `*DebugCommands.cs`; members as in Task 1's kinds; description = first `/// <summary>` line; Parameters column = the container's `Parameter` properties used as `Name:type`; Scope = `App` if `Register<X>` is found in a module file whose `Install` is called from `AppModules.cs`, `Scene` if from `SceneModules.cs`, else `unknown` + stderr warning.

- [ ] **Step 1: Failing bats tests:** generator writes one row `| Level.GoToLevel | Scene | TargetLevel:int | Jumps to the target level |` for a fixture `LevelDebugCommands.cs` + `LevelModule.cs` + `SceneModules.cs`; `--check` exits 1 before generation and 0 after; unresolved registration → row with `unknown`, stderr contains `unknown scope`, exit 0; missing markers → exit 2; drift hook on an edited `*DebugCommands.cs` with a stale doc prints the regenerate command and exits 0; drift hook ignores other files.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** both; `chmod +x`. **Step 4: Run** → PASS; full bats suite no new failures.

### Task 6: `/setup-project` wiring

**Files:**
- Modify: `.claude/commands/setup-project.md` — Step 1 (srdebugger question), Step 1c (`"srdebugger": bool` in features JSON), Step 0 existing-project path (offer opt-in), Step 2b (pin `#framework/v0.3.0`), Step 3 (`[ProjectName]Games.asmdef` references `FrameworkDebugCommands`), Step 4 (new `DebugCommandsModule.cs` block + `AppModules` line), new `docs/PLAYTEST.md` skeleton block, Manual checklist (two hook entries + "create tag `framework/v0.3.0`"). If SRDebugger detected and chosen: add `SRDEBUGGER_ENABLED` scripting define (via MCP `manage_editor`/ProjectSettings route the command already uses for defines — check; if none exists, put it in the manual checklist, `block-projectsettings.sh` forbids hand edits).
- Modify: `.claude/project-features.json` schema docs wherever the feature list is described (`.claude/CLAUDE.md` Optional Features line + Project Features table row `srdebugger`).

**Interfaces:**
- Consumes: `DebugCommandRegistry`, `DebugCommandRegistryAccessor.Set`, `SRDebuggerDebugCommandsBridge` (Tasks 1, 3).
- Produces: generated `Concretes/Infrastructure/DebugCommandsModule.cs`:
  ```csharp
  #if UNITY_EDITOR || DEVELOPMENT_BUILD
  public static class DebugCommandsModule
  {
      public static void Install(IContainerBuilder builder)
      // registers DebugCommandRegistry .AsImplementedInterfaces();
      // #if SRDEBUGGER_ENABLED: builder.Register<SRDebuggerDebugCommandsBridge>(Lifetime.Singleton).AsSelf().As<IDisposable>();
      // builder.RegisterBuildCallback(c => {
      //     DebugCommandRegistryAccessor.Set(c.Resolve<IDebugCommandRegistry>());
      //     #if SRDEBUGGER_ENABLED  c.Resolve<SRDebuggerDebugCommandsBridge>();  #endif   // force creation; container disposes it
      // });
  }
  #endif
  ```
  and in `AppModules.Install`, directly after `SaveLoadModule.Install(builder);`:
  ```csharp
  #if UNITY_EDITOR || DEVELOPMENT_BUILD
              DebugCommandsModule.Install(builder); // before any module whose *DebugCommands registers in Initialize()
  #endif
  ```
- `PLAYTEST.md` skeleton sections, verbatim headings: `## How to start`, `## Scene flow`, `## Outcomes — what is visible`, `## Debug commands` (with the two markers and an empty table), `## Rules` (setup-not-evidence, one paragraph linking `rules/debug-commands.md`).

- [ ] **Step 1: Edit the command file.**
- [ ] **Step 2: Run** `python3 .claude/scripts/validate-generated-asmdefs.py` → exit 0.
- [ ] **Step 3: Run** `.claude/tests/setup-compile-probe/run-probe.sh` → exit 0 (now compiles `DebugCommandsModule` against the package).

### Task 7: Rule, docs and pipeline text

**Files:**
- Create: `.claude/rules/debug-commands.md` — `paths: ["**/*DebugCommands.cs", "**/PLAYTEST.md"]`, `## Cards` first: Card 1 setup-not-evidence (cite the `LevelFailedEvent` incident, `/roadmap` line 74), Card 2 real-method-not-event (cite hole_sphere "Preview Level Complete"), Card 3 scope placement (app vs scene module, self-register in `Initialize`/`Dispose`), Card 4 SRDebugger shape (property = parameter, parameterless method = command, `System.ComponentModel` attributes only), Card 5 debug-only service API allowed, no `#if` in interfaces, normal save/event path, method tested if it has branch/math/state.
- Modify: `.claude/docs/rule-index.md` — row `write or plan a cheat / debug command, or test the game through MCP` → `.claude/rules/debug-commands.md`.
- Modify: `.claude/docs/rules-overview.md` — one line for the new rule.
- Modify: `.claude/rules/architecture.md` — the `EventBusAccessor (APPROVED EXCEPTION)` bullet gains `DebugCommandRegistryAccessor` (dev-only, set by `DebugCommandsModule`, read only by the framework Editor runner; hook-fenced).
- Modify: `.claude/hooks/check-vcontainer-singleton.sh:51` — add `DebugCommandRegistryAccessor` to the filename allow regex; add a bats case to its existing suite (`allows DebugCommandRegistryAccessor`).
- Modify: `.claude/commands/implement.md` Step 3.6 — before the manual prompt, "Agent smoke pass (MCP connected only)": read `docs/PLAYTEST.md`, enter Play, use `List` then `Run` for setup, reach the outcome via the real path, check the visible outcome and `read_console` errors, report observed vs expected; then show the existing manual prompt unchanged.
- Modify: `.claude/commands/plan-module.md` near line 242 — a module that adds a reachable state (level, currency, lives, unlock) gets a `<Domain>DebugCommands` task (`Test type: NoTest`, dev-only) and a `PLAYTEST.md` hand-section update.
- Modify: `.claude/docs/hooks-blocking.md` / `hooks-warning.md` — one row each for the two hooks.

- [ ] **Step 1: Write the edits.**
- [ ] **Step 2: Run** `bats .claude/hooks/tests/check-vcontainer-singleton.bats` (or the suite holding that hook's tests) → PASS.
- [ ] **Step 3: Run** `.claude/tests/rule-awareness-probe/run-probe.sh --help` and follow its README for adding the new rule's probe prompt if the README requires one per path-scoped rule; otherwise note "not required" in the hand-off.

### Task 8: End-to-end verification (manual, needs a game)

The template has no game domain, so the full loop cannot be proven here.

- [ ] **Step 1:** In the compile-probe project (`run-probe.sh --keep`), add a throwaway `Concretes/Probe/ProbeDebugCommands.cs` (a `TargetValue:int` property, `Echo()` method that logs it, registered via a probe module in `AppModules`). Open it in the Editor with MCP connected, enter Play, write the request file, `execute_menu_item("Tools/Framework/Debug Commands/Run")`, read the result → expected `[DebugCommands] OK Probe.Echo (TargetValue=5)`. Also check: wrong id → FAIL listing `Probe.*`; `TargetValue: "abc"` → FAIL; not in Play → FAIL. Delete the probe project afterwards.
- [ ] **Step 2:** Report to the user which checks ran and which did not (SRDebugger panel needs a project that owns SRDebugger — hole_sphere/voxel-blast; trying it there requires the user's separate approval).
