# Playtest Map & Debug Commands — Design

> Status: approved by the user 2026-11-18 (design), not yet implemented
> Scope: template infrastructure (framework package, `.claude/` rules/hooks/commands). Migrating any existing
> project's cheats (hole_sphere, voxel-blast) is **out of scope** and needs separate approval per repo.

## Intent

When the user says "go test X via MCP", Claude today re-reads source code every time to work out how to start the
game, which scene to open, and how to reach a state (level 5, win, lose, rich wallet). That exploration is repeated
cost and frequently wrong. The project should carry:

1. **A playtest map** — how to start the game, the scene flow, and what is observable on screen for each outcome.
2. **Ready-made debug commands** (win, lose, skip level, add currency …) that Claude can call through MCP **and**
   that appear in SRDebugger's in-game panel when the project uses SRDebugger — written once.

## Evidence (current state)

- Template: no cheat infrastructure. Only `rules/testing.md:24` mentions cheats (NoTest, dev-only).
- `/implement` Step 3.6 Play Mode smoke test is fully manual; Claude cannot drive the game.
- `nile_hole_sphere_repo` (read-only inspection, 2026-11-18):
  - The same cheat list is written twice: `_AssetFolders/StompyRobot/SROptions/SROptions.Economy.cs` and
    `_GameFolders/Scripts/Editors/CheatTool/CheatToolWindow.cs` (+1K/10K/100K gold, Max/Buy/Reset upgrades).
  - Every cheat locates services with `FindFirstObjectByType<AppScope|GameScope>().Container.Resolve<T>()` —
    a service locator, and a null-ref when the wrong scene is open.
  - Two different "win" cheats: `SROptions.Win()` calls `ILevelService.CompleteLevel()` (real path);
    `CheatToolWindow` "Preview Level Complete" publishes `LevelCompleteEvent` directly, skipping save and rewards.
  - Cheats live inside the vendor folder because `partial class SROptions` must stay in Assembly-CSharp.
- `voxel-blast`: same `partial SROptions` + `ResolveContainer()?.Resolve<T>()` pattern.
- `/roadmap` (line 74) already records the failure this design must not reintroduce: `LevelFailedEvent`'s only
  publisher was a debug trigger, so the player could never lose and 12 "complete" modules hid it.

## Goals

- One source per cheat: a `*DebugCommands` class per domain, visible to Claude (MCP) and to SRDebugger.
- Cheat classes are constructor-injected, scope-correct, and never look up the container themselves.
- Claude can list the commands currently available, set a parameter, run one, and read the result — via MCP only.
- `docs/PLAYTEST.md` tells Claude how to play and what to observe; its command table is generated, never hand-kept.
- Release builds contain none of it.

## Non-goals

- A bot that plays the game by simulating input.
- An in-game debug UI of our own (SRDebugger is the in-game panel when wanted).
- Migrating existing `SROptions` partials in other repos.

## Anti-goals (failure even if it works)

- **A cheat used as evidence.** Cheats are *setup* (go to level 5, leave 1 life). "Does the lose panel appear" is
  verified through the real game path. A milestone smoke-test item reachable only via a cheat stays
  player-unreachable (`/roadmap` rule unchanged).
- **A cheat that fakes an outcome.** A cheat calls a real service method; it never publishes the outcome event
  itself. (`CheatToolWindow`'s "Preview Level Complete" is the counter-example.)
- A hand-written command list that drifts from code.
- A new general-purpose static accessor leaking into game code.

## Approaches considered

| | Approach | Trade-off | Verdict |
|---|---|---|---|
| A | `*DebugCommands` classes (SRDebugger shape) + framework registry + one generic Editor runner + generated table | Needs one dev-only static accessor for the Editor runner | **Chosen** |
| B | Hand-written list + one `[MenuItem]` per cheat | No parameters (`go to level N` = N menu items), each item does its own container lookup, list drifts | Rejected |
| C | In-game debug panel clicked through MCP | MCP cannot click UI reliably | Rejected |
| A′ | Runner as an MCP-for-Unity custom tool instead of a menu item | Couples the framework to one MCP package; new tools need a session restart (tool list frozen at start) | Rejected for v1 |

The user picked A, and asked that it merge with SRDebugger when a project uses it.

## Design

### 1. Command classes (game side)

- One class per domain: `Concretes/<Domain>/<Domain>DebugCommands.cs` (e.g. `LevelDebugCommands`,
  `EconomyDebugCommands`). Pure C#, `sealed`, whole file under `#if UNITY_EDITOR || DEVELOPMENT_BUILD`.
- **SRDebugger option-container shape:** a public property = a parameter (`public int TargetLevel { get; set; }`),
  a public parameterless method = a command (`public void GoToLevel()`), public read-only property = a displayed
  value. Grouping with `System.ComponentModel.[Category]` / `[DisplayName]` only (BCL — no SRDebugger reference).
  `///` summary on each member is the description that ends up in the table.
- Constructor takes only service interfaces. Implements `IInitializable` / `IDisposable`: registers itself with
  `IDebugCommandRegistry` in `Initialize()`, unregisters in `Dispose()`.
- Registered in the module of the scope whose services it uses: app-lifetime services → its module via
  `AppModules`; scene-lifetime → via `SceneModules`. The registration line sits under the same `#if`.
  So a scene-scoped command exists exactly while its scene is loaded.
- Body calls real service methods only. **No `IEventBus.Publish`** in a `*DebugCommands` file (hook-enforced, §6).
- Category: dev-only tooling → `NoTest` (`rules/testing.md`, unchanged).

### 2. Framework: `Framework.DebugCommands` assembly (new, in `packages/framework/DebugCommands/`)

- `IDebugCommandRegistry` — `Register(object container)`, `Unregister(object container)`, the current container
  list, and a C# `event` raised on change.
- `DebugCommandRegistry` — plain implementation. Reflection over the registered containers lives here
  (list members, set property from a string, invoke method), so the Editor runner and any other front-end share it.
- `DebugCommandRegistryAccessor` — static, the **second approved exception** after `EventBusAccessor`: set once by
  the game's debug module in `RegisterBuildCallback`, read **only** by the Editor runner. Game code always injects
  `IDebugCommandRegistry`. Needs a row in `rules/architecture.md` and an allow in `check-vcontainer-singleton.sh`.
- Own `.asmdef`, no `_GameFolders` reference, `ARCHITECTURE.md` per `rules/architecture-docs.md`.
- The framework does not depend on VContainer today (`package.json`): the registry stays VContainer-free; the
  `IInitializable` plumbing lives in the game-side command classes.

### 3. Framework: Editor runner (`packages/framework/Editors/`)

- Menu `Tools/Framework/Debug Commands/Run` reads a request file, runs it through the accessor, writes a result
  file and logs one line (`[DebugCommands] OK Level.GoToLevel (TargetLevel=5)` or `FAIL … reason`).
- Menu `Tools/Framework/Debug Commands/List` writes the currently registered commands (with category, parameters,
  current values) to the result file — Claude's "what can I call right now in this scene".
- Request/result files: `<unity_project_folder>/Temp/debug-command.json` and `debug-command-result.json`
  (`Temp/` is Unity-ignored, per-machine). Request shape: `{ "command": "Level.GoToLevel", "set": { "TargetLevel": 5 } }`.
- Not in Play Mode, command not registered (wrong scene), unparseable value → `FAIL` with the reason, never throw.
- Claude's loop: write request → `execute_menu_item` → read result file / `read_console`.

### 4. SRDebugger adapter (optional)

- `/setup-project` gains a feature `srdebugger` (detected by the presence of the `StompyRobot.SRDebugger` asmdef;
  user confirms). When on, it adds the scripting define `SRDEBUGGER_ENABLED`.
- Adapter assembly (`packages/framework/DebugCommands/SRDebugger/`), `defineConstraints: ["SRDEBUGGER_ENABLED"]`,
  references `StompyRobot.SRDebugger`. Subscribes to the registry's change event and mirrors it with
  `SRDebug.Instance.AddOptionContainer` / `RemoveOptionContainer`. Without the define the assembly is skipped, so
  projects without SRDebugger compile unchanged.
- Result: the same `EconomyDebugCommands` appears in the device panel and to Claude. No `partial SROptions`, so
  cheats leave the vendor folder.

### 5. `docs/PLAYTEST.md`

Two parts in one file:

- **Hand-written** (owned by modules, updated when flow changes): how to start (scene to open, Play, what appears
  first), the scene flow, and per outcome *what is visible* (win panel name, lose panel name, HUD values) — the
  things Claude checks with screenshots / hierarchy queries.
- **Generated** between `<!-- debug-commands:begin -->` / `<!-- debug-commands:end -->`: table of
  `Command | Scope (App/Scene name) | Parameters | Description`, produced by
  `.claude/scripts/generate-playtest-commands.py` from the `*DebugCommands.cs` sources (static parse — works
  without Unity open). Scope comes from which module registers the class.
- `/setup-project` writes the skeleton. The template ships an example `LevelDebugCommands` in the docs only, not
  as code (the template has no game domains).

### 6. Enforcement

- `check-debug-commands.sh` (PreToolUse, `Edit|Write`, judges effective post-edit content per
  `docs/incidents/pretooluse-effective-content.md`), on `*DebugCommands.cs`:
  - `.Publish(` → **exit 2** (fake outcome).
  - `FindFirstObjectByType` / `FindObjectOfType` / `.Container.Resolve` → **exit 2** (service locator).
  - missing `#if UNITY_EDITOR || DEVELOPMENT_BUILD` wrapper → **exit 2**.
- `check-playtest-drift.sh` (PostToolUse) — after a `*DebugCommands.cs` change, re-run the generator in check mode;
  out of date → exit 0 warning with the regenerate command.
- Both are `chmod +x`; the **user** adds their `settings.json` entries (Claude cannot edit it).
- Hook tests under the existing hook test harness.

### 7. Rule & pipeline wiring

- New path-scoped rule `rules/debug-commands.md` (`paths: **/*DebugCommands.cs, docs/PLAYTEST.md`) with Cards:
  setup-not-evidence, real-method-not-event, scope placement, SRDebugger shape. Row in `docs/rule-index.md`.
- `/implement` Step 3.6: before the manual prompt, Claude runs an **agent smoke pass** via MCP using `PLAYTEST.md`
  (enter Play, reach the state with commands, observe through the real path, read console) and reports what it saw.
  The manual `ok`/`fail` step stays — it is not replaced.
- `/plan-module`: when a module adds a reachable state worth jumping to (level, currency, lives, unlock), its task
  list includes a `<Domain>DebugCommands` task (`Test type: NoTest`, dev-only) and a `PLAYTEST.md` hand-section update.

## Decisions settled after the builder check (Claude's calls — user may override)

- **Game-side wiring:** the framework ships no VContainer code. `/setup-project` generates
  `Concretes/Infrastructure/DebugCommandsModule.cs` (under the dev-only `#if`): registers
  `DebugCommandRegistry` as `IDebugCommandRegistry` and, inside `Install()`, calls
  `builder.RegisterBuildCallback(c => DebugCommandRegistryAccessor.Set(c.Resolve<IDebugCommandRegistry>()))`.
  One `#if`-wrapped line in `AppModules`, right after `EventBusModule`. `AppScope.cs` stays unchanged.
- **Async commands:** command methods stay `void` and parameterless (SRDebugger buttons are sync). A command that
  starts async work runs it with `.Forget(ex => …)` (csharp-unity Card 3). `OK` means *invoked without throwing*,
  not *effect finished*. Claude settles by re-running `List` (read-only properties expose state such as
  `CurrentLevel`) or by observing scene/hierarchy/console — the agent smoke pass in `/implement` says so.
- **Accessor fencing:** `check-debug-commands.sh` also blocks any reference to `DebugCommandRegistryAccessor`
  outside `packages/framework/Editors/` and the generated `DebugCommandsModule.cs`.
- **Release builds:** the `Framework.DebugCommands` assemblies carry the dev-only define constraint too, so
  nothing ships. Verifying `||` in `defineConstraints` on 2022.3 is therefore a required first task, not
  optional; fallback is a project define `DEBUG_COMMANDS` that `/setup-project` adds to Editor + Development
  build settings.
- **Rollout:** framework minor bump (0.2.0 → 0.3.0) + changelog entry + `/setup-project` Step 2b pinned tag
  update. `srdebugger` detection also runs on the "already configured" path so existing projects can opt in.
- **Generator scope column:** resolve by finding `Register<XDebugCommands>` in the module files reached from
  `AppModules` vs `SceneModules`; unresolved → `unknown` in the table plus one generator warning, never a failure.

## Decision by the user (2026-11-18)

- **Debug-only service API is allowed.** A `*DebugCommands` class counts as a real caller under the encapsulation
  rule. A method it needs (`ILevelService.SetLevel(int)`, `IWalletService.AddGold(...)`) is added to the interface
  normally — **no `#if` inside interfaces or services** (it splits the API per build and breaks mocks). The method
  goes through the same save/event path as gameplay (as hole_sphere's `AddGold` does) and documents
  `Side effect:` per csharp-unity's interface-contract table. It ships in release, uncalled. If it has a branch,
  math or state, it is tested like any service method (risk-based TDD) — only the `*DebugCommands` class is NoTest.

## Constraints

- Framework is a package; `packages/framework/` is its only source; bump version, run
  `tests/setup-compile-probe/run-probe.sh` after editing.
- Framework targets Unity 2022.3 — reflection and `defineConstraints` used must work there.
- No `unity command eval` / Bash route into the Editor; MCP only.
- `.claude/settings.json` is user-edited.

## Left to the builder

- Exact reflection rules (which property types are settable from a string: int/float/bool/string/enum is enough).
- Request/result JSON field names beyond the shape above.
- Generator parsing strategy (regex vs tree-sitter — the graph tooling already depends on tree-sitter).
- Task ordering and plan split.

## Open items to verify during planning

- `defineConstraints` with `||` (`UNITY_EDITOR || DEVELOPMENT_BUILD`) on 2022.3 — else two asmdef approach or `#if`.
- Unity MCP `execute_menu_item` availability and naming in the current MCP-for-Unity version.
- SRDebugger `AddOptionContainer` honours `System.ComponentModel.Category` for non-`SROptions` containers
  (seen in voxel-blast's copy: `InternalOptionsRegistry` buffers containers; attribute handling unverified).
