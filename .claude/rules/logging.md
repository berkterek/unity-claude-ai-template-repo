# Logging Rules (NON-NEGOTIABLE)

> Read the **Cards** section first. The prose below is reference detail.

Runtime game code logs through `Framework.Logging.DLog`, never through `UnityEngine.Debug`. Editor code is
the exception, not a grey area — the split is by *where the file lives*, and it is mechanically checkable,
which is why it is a hook and not a suggestion.

## Cards

### Card 1: Game Code Logs Through DLog — `UnityEngine.Debug` Is for Editor Code Only

**WHEN:** Any `.cs` file under `_GameFolders/Scripts/Games/` or `_Framework/` writes a log line.

**WRONG:**
```csharp
public sealed class ScoreService : IScoreService
{
    public void AddScore(int amount)
    {
        Debug.Log($"score += {amount}");   // ships in every build, cannot be filtered, no tag
    }
}
```

**RIGHT:**
```csharp
using Framework.Logging;

public sealed class ScoreService : IScoreService
{
    public void AddScore(int amount)
    {
        DLog.Log(LogTag.Score, $"score += {amount}");
    }
}
```

**GOTCHA:** `Debug.Log` has three costs that only show up late. It is compiled into release builds, so the
string interpolation runs and allocates on a shipped device even though nobody reads the output. It carries
no tag, so a hundred log lines from six domains arrive as one undifferentiated stream in the device console.
And it cannot be turned off per domain — the only lever is deleting the line, which is why `Debug.Log` calls
get deleted during debugging and re-added a week later. `DLog` is `[Conditional]`-stripped and tag-filtered,
so none of the three applies.

---

### Card 2: Editor Code Keeps `UnityEngine.Debug`

**WHEN:** Writing a file under `Scripts/Editors/`, `_Framework/Editors/`, any `Editor/` folder, a test
assembly, or a block guarded by `#if UNITY_EDITOR`.

**WRONG:**
```csharp
// A custom inspector routing through DLog — the tag filter can silently swallow tool output
[CustomEditor(typeof(ConfigCatalog))]
public sealed class ConfigCatalogEditor : Editor
{
    public override void OnInspectorGUI() => DLog.Log(LogTag.General, "inspector drawn");
}
```

**RIGHT:**
```csharp
[CustomEditor(typeof(ConfigCatalog))]
public sealed class ConfigCatalogEditor : Editor
{
    public override void OnInspectorGUI() => Debug.Log("[ConfigCatalogEditor] inspector drawn");
}
```

**GOTCHA:** Editor code never ships, so the release-build argument that motivates `DLog` does not apply to
it — and routing tool output through `DLog`'s tag filter means an Editor tool can go silent because some
unrelated runtime code called `DLog.Disable`. The two log paths answer different questions; do not unify
them.

---

### Card 3: One `LogTag` Per Domain — And Enable It

**WHEN:** A new domain starts logging.

**WRONG:**
```csharp
DLog.Log(LogTag.General, "[Audio] clip missing");   // General is the catch-all; the tag now means nothing
```

**RIGHT:**
```csharp
// _Framework/Logging/LogTag.cs
public enum LogTag { General, EventBus, SaveLoad, Audio }

DLog.Log(LogTag.Audio, "clip missing");
```

**GOTCHA:** Adding the enum member is only half the job — a tag absent from `DLog._enabledTags` is silent
from the moment it is added. The call compiles, runs, matches nothing, and returns, with no error and no
warning; it reads as "logging is broken", not "this tag is off", and it is the single most likely way to
lose a log you were sure you wrote. `/setup-project` seeds `_enabledTags` from `Enum.GetValues(typeof(LogTag))`,
so **adding the enum member is the whole job** — a new tag is live the moment it is declared, and there is no
second place to forget. `Log`/`Warning` are `[Conditional]` on Editor/development builds, so an enabled tag
costs nothing in release; `DLog.Disable(tag)` mutes a noisy domain during a session.

A project generated before 2026-09-02 has a literal list instead and still has the trap — check the file
before trusting this. The literal list was the first attempt at this fix and it was the wrong one: it
repaired the three members that existed and left the trap armed for the fourth.

---

### Card 4: An Error Path Never Logs and Continues Silently

**WHEN:** A catch block or a guard clause swallows a failure.

**WRONG:**
```csharp
catch (JsonException)
{
    return default;   // the fallback happens, and nothing anywhere records that it did
}
```

**RIGHT:**
```csharp
catch (JsonException ex)
{
    DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default. {ex.Message}");
    return default;
}
```

When the failure carries an exception, pass the exception object, not its `Message`:

```csharp
catch (JsonException ex)
{
    DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default.", ex);
}
```

**GOTCHA:** `DLog.Error` is the one method that is **neither `[Conditional]`-stripped nor tag-filtered** — an
error is a defect report, not a diagnostic, so it survives into release builds and cannot be silenced by
`DLog.Disable`. That asymmetry is deliberate and the comment in `DLog.cs` says so; do not "tidy" the
attributes or the tag gate back on. The bug that produced it: `EventBus` catches each subscriber's
exception and reports it through `Error(LogTag.EventBus, …, exception)`; `LogTag.EventBus` was not enabled,
and nearly all game logic runs inside subscribers — so every subscriber exception was invisible in the Editor
and compiled out of release at the same time. Two independent mechanisms had to fail together, which is why
neither was noticed alone.

Both halves are closed in the generated code now (the tag set is derived from the enum, and `Error` is
unconditional), so this reads as history rather than a live defect. It is kept because the *asymmetry* it
justifies is still there and still looks like an oversight to anyone tidying `DLog.cs` — and because it is
the reason `EventBus.Publish` carries the only `catch (Exception)` this codebase permits: the bus cannot
know what a subscriber may throw, and one subscriber's failure must not become another's.

Second half of the same rule: `exception.Message` loses the file and line. The two-argument overload calls
`Debug.LogException`, which is what makes the stack trace clickable — use it whenever you have the object.

---

## Where Each Path Applies

| Path | Log with | Why |
|---|---|---|
| `_GameFolders/Scripts/Games/**` | `DLog` | Ships to device — needs stripping and tag filtering |
| `_Framework/**` except `Editors/` | `DLog` | Same; `DLog` itself is the one exception, it wraps `Debug` |
| `_GameFolders/Scripts/Editors/**`, `_Framework/Editors/**`, any `Editor/` folder | `UnityEngine.Debug` | Never ships; must not be filterable by runtime state |
| `Scripts/Tests/**` | `UnityEngine.Debug` | Test output must always appear |
| Inside `#if UNITY_EDITOR` in a runtime file | `UnityEngine.Debug` | Editor-only branch of a shipping file |

## Enforcement

`check-dlog-usage.sh` blocks `Debug.Log` / `Debug.LogWarning` / `Debug.LogError` in runtime game paths with
exit 2. It is a `PreToolUse` content hook, so it judges the result of the pending edit, not the file on disk
— a file that already contains a violation can still be edited to remove it.

The one deliberate carve-out in the hook: `Debug.LogError` inside a **module null-guard** is allowed, because
`bootstrap-pattern.md` mandates that exact shape (`if (config == null) { Debug.LogError(...); return; }`) in
every `*Module.Install()`, and that code runs before any container — and therefore before any `DLog`
configuration — exists. Do not widen this carve-out to ordinary services.

## Common Mistakes

| Mistake | Solution |
|---------|----------|
| `Debug.Log` in a service, handler, controller or view | `DLog.Log(LogTag.<Domain>, ...)` (Card 1) |
| `DLog` inside a custom inspector or EditorWindow | `UnityEngine.Debug` — Editor code is exempt (Card 2) |
| Reusing `LogTag.General` for a real domain | Add a domain member to the enum (Card 3) |
| Adding a `LogTag` member and expecting output | It is disabled by default — enable it too (Card 3) |
| A catch or guard that returns a default with no log | Log the fallback with `DLog.Error` (Card 4) |
| Passing `exception.Message` to `DLog.Error` instead of the exception | Use the 3-arg overload — `Message` alone loses file and line (Card 4) |
