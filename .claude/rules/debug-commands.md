---
paths:
  - "**/*DebugCommands.cs"
  - "**/PLAYTEST.md"
---
# Debug Commands & Playtest Map

> Read the **Cards** section first. The prose below is reference detail.

A debug command (cheat) is a dev-only shortcut Claude runs through MCP and a human taps in SRDebugger's panel:
skip to level 5, add gold, leave one life. `docs/PLAYTEST.md` tells Claude how to start the game, what each outcome
looks like on screen, and — in a generated table — which commands exist. Both exist so a test run does not start
with re-reading the code.

## Cards

### Card 1: A Command Sets Up a Test — It Is Never the Evidence

**WHEN:** Using a command while testing a feature, or writing a smoke-test / milestone item.

**WRONG:** "Lose panel works" — verified by running `Level.Lose` and seeing the lose panel.

**RIGHT:** `Lives.SetLives` (Lives = 1) to reach the edge, then lose the last life **by playing**, and check the
lose panel, the console and the saved state.

**GOTCHA:** A command reaches a state; only the real path proves the feature does. In the source project the
`LevelFailedEvent`'s only publisher in the whole codebase was a debug trigger, so the player could never lose — and
twelve "complete" modules hid it (`/roadmap` records this). A smoke-test item reachable only through a command is
player-unreachable and does not close a milestone.

---

### Card 2: Call the Real Service Method — Never Publish the Outcome

**WHEN:** Writing a command body.

**WRONG:**
```csharp
public void Win() => _eventBus.Publish(new LevelCompleteEvent()); // skips save, rewards, unlocks
```

**RIGHT:**
```csharp
public void Win() => _levelService.CompleteLevel(); // the service publishes, saves and rewards as in play
```

**GOTCHA:** A "Preview Level Complete" that published the event directly sat beside a "Win" that called the
service, in the same project — two different wins, one of which skipped save and rewards. `check-debug-commands.sh`
blocks `.Publish(` in a `*DebugCommands.cs`. Also blocked: `FindFirstObjectByType` / `FindObjectOfType` /
`<scope>.Container.Resolve` — services arrive by constructor injection, so a command in the wrong scene is simply
not registered (the runner says so) instead of a null-ref.

---

### Card 3: One Container per Domain, Registered Where Its Services Live

**WHEN:** Adding a command class.

**RIGHT:** `Concretes/<Domain>/<Domain>DebugCommands.cs`, `sealed`, pure C#, whole file under
`#if UNITY_EDITOR || DEVELOPMENT_BUILD`. Implements `IInitializable, IDisposable`; `Initialize()` calls
`_registry.Register(this)`, `Dispose()` calls `_registry.Unregister(this)` (`IDebugCommandRegistry` injected).
Registered by **that domain's** Module, under the same `#if`, with `.AsImplementedInterfaces()` — in the app scope
when its services are app-lifetime, in the scene scope (`SceneModules`) when they are scene-lifetime.

**GOTCHA:** Never `DebugCommandRegistryAccessor` in game code — it exists only for the Editor runner and only
`DebugCommandsModule.cs` sets it (hook-fenced). Command id = class name without `DebugCommands`, `.`, member:
`LevelDebugCommands.GoToLevel` → `Level.GoToLevel`. Renaming the class renames every id and the PLAYTEST table.

---

### Card 4: SRDebugger Shape — Properties Are Parameters, Parameterless Methods Are Commands

**WHEN:** Choosing members.

**RIGHT:**
```csharp
[Category("Level")] public int TargetLevel { get; set; }          // parameter (set from JSON "set")
[Category("Level")] public int CurrentLevel => _levels.Current;     // read-back value
/// <summary>Jumps to the target level</summary>
[Category("Level")] public void GoToLevel() => _levels.SetLevel(TargetLevel);   // command
[Browsable(false)] public void Initialize() => _registry.Register(this);
```

**GOTCHA:** Only `System.ComponentModel` attributes (`Category`, `Browsable`) — never `SROptions` or an SRDebugger
type, so the file compiles without SRDebugger. `[Browsable(false)]` hides a member everywhere (registry, PLAYTEST
table, panel): put it on `Initialize`/`Dispose` (SRDebugger's panel lists them otherwise) and on **any other
interface method** (the table generator only recognises the VContainer lifecycle interfaces and `IDisposable`).
Every other public parameterless `void` is a command — keep helpers `private`. A parameter needs a public
`get` **and** a public `set`; `{ get; private set; }` is a read-back value. A command starting async work uses `.Forget(ex => …)`; `OK` means *invoked*, not
*finished* — settle by `List` (read-back values) or by observing the scene.

---

### Card 5: A Service Method a Command Needs Is Ordinary API

**WHEN:** The command needs something the service does not expose (`SetLevel(int)`, `AddGold(int)`).

**RIGHT:** Add it to the service interface like any method — the command is a real caller. No `#if` in the
interface. It goes through the normal save and event path (setting the level saves progress like reaching it would).
It is tested if it has a branch, math or state (`rules/testing.md`); the `*DebugCommands` class itself is NoTest.

## Running a Command (Play Mode, MCP)

1. Write `Temp/debug-command.json` (under the Unity project folder): `{"command":"Level.GoToLevel","set":{"TargetLevel":"5"}}`.
2. Run the menu `Tools/Framework/Debug Commands/Run` (MCP `execute_menu_item`).
3. Read `Temp/debug-command-result.json` (`ok`, `message`, and on failure the registered `commands`) and the one
   `[DebugCommands] OK|FAIL` console line. `Tools/Framework/Debug Commands/List` returns what is registered now.

## PLAYTEST.md

Hand-written: how to start, scene flow, what each outcome shows. Generated: the table between
`<!-- debug-commands:begin -->` / `<!-- debug-commands:end -->` — `python3 -I .claude/scripts/generate-playtest-commands.py`
(`--check` to test for drift; `check-playtest-drift.sh` warns after a `*DebugCommands.cs` edit). Never edit the table
by hand. A module that changes the flow or adds an outcome updates the hand-written sections in the same task.
