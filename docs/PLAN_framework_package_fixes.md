# PLAN — Framework Package Fixes

**Status:** items 1-2 and 7 open, 3/5/6 already fixed upstream · **Created:** 2026-09-02
**Source:** `Framework.unitypackage` (stale) reconciled against `piggy-doku-repo/PiggyDoku/Assets/_Framework` (current)

The `_Framework/Logging/` and `_Framework/SaveLoadSystems/` files were adopted from an existing
`Framework.unitypackage` and wired into `/setup-project` Step 4 **as-is**, deliberately: getting the code
into the generator is what stops every new project from re-inventing persistence, and that was worth more
than holding the adoption until the defects below were fixed. This file is the record of what was knowingly
shipped, so the next reader does not mistake any of it for a considered design choice.

**The `.unitypackage` on the Desktop is not the newest copy of this framework.** `piggy-doku-repo` carries a
version that already fixes items 3, 5 and 6, and adds an `Error(LogTag, string, Exception)` overload the
package does not have. `/setup-project` Step 4 now ships piggy's version, not the package's. Before adopting
anything else from that `.unitypackage`, diff it against the live project first — the package is a snapshot,
the project is the source of truth.

Each remaining item names the single file it touches. Neither changes a consumer, so they can land
independently and in any order.

---

## 1. `LocalSaveLoadDal.SaveData` is not atomic — FIXED upstream

**File:** `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs` · **Rule:** `rules/save-load.md` Card 7

`File.WriteAllText` truncates the live save file and then writes. A process killed between the two leaves a
0-byte file and the previous save is gone. On mobile, the OS killing a backgrounded process is routine, not
an edge case.

```csharp
public void SaveData(string key, object value)
{
    string path = GetFilePath(key);
    string temp = path + ".tmp";

    File.WriteAllText(temp, JsonConvert.SerializeObject(value));

    if (File.Exists(path)) File.Replace(temp, path, null);
    else                   File.Move(temp, path);
}
```

Second effect: a 0-byte file makes `HasKey` return `true` while `LoadData` returns `default`. Atomic write
removes the only realistic cause of that mismatch, which is what makes the `HasKey` → `Load` read path in
Card 6 sound.

**Fixed 2026-09-02 in `/setup-project` Step 4.** `SaveData` now writes `path + ".tmp"` and swaps it in with
`File.Replace` (`File.Move` when no live file exists yet), with the mobile-kill rationale in a comment above
the method. `rules/save-load.md` Card 7 is now a description of the generated code rather than a target.

Not portable to every backend: `PlayerPrefs` has no `File.Replace` equivalent, so a `PlayerPrefsSaveLoadDal`
(item 7) approximates atomicity at best and must say so in the class.

A project generated before this date keeps the old non-atomic body.

---

## 2. `LocalSaveLoadDal.LoadData` does not catch `JsonException` — FIXED upstream

**File:** `_Framework/SaveLoadSystems/LocalSaveLoadDal.cs` · **Rule:** `rules/save-load.md` Card 8

A corrupt or version-mismatched save throws out of `DeserializeObject`, out of the service, and out of
`AppScope.Configure()` — the container never finishes building and the game does not open. The failure mode
is "the app is bricked for that user until they clear app data".

```csharp
try
{
    return JsonConvert.DeserializeObject<T>(json);
}
catch (JsonException ex)
{
    DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default. {ex.Message}");
    return default;
}
```

Catch `JsonException`, never `Exception`. An `IOException` (locked file, permissions) is a different bug and
must not be swallowed into a default-value path — that is an empty catch wearing a log statement.

No longer blocked on item 3: `DLog.Error` survives into release builds in the shipped version, so this
fallback will actually be reported on a device. Prefer the three-argument overload here and pass `ex`, not
`ex.Message` — the stack trace is what identifies which save shape broke.

**Fixed 2026-09-02 in `/setup-project` Step 4.** `LoadData` wraps `DeserializeObject` in
`try`/`catch (JsonException)`, logs through `DLog.Error(LogTag.SaveLoad, …, exception)` — the three-argument
overload, so the stack trace stays clickable — and returns `default`, which drops the caller into its
Card 6 `HasKey`/config-default branch, the same path a first-run player takes.

`catch (Exception)` stays forbidden: an `IOException` (locked file, permissions) is a different bug and must
not be swallowed into a default-value path.

This required `using Framework.Logging;` in the DAL. The assembly reference already existed —
`FrameworkSaveLoadSystems.asmdef` references `FrameworkLogging`, added when its `noEngineReferences` was
corrected. Unlike Card 7, this fix **is** backend-independent and item 7 must carry it too.

---

## 3. `DLog.Error` is stripped from release builds — FIXED upstream

**File:** `_Framework/Logging/DLog.cs` · **Rule:** `rules/logging.md` Card 4

`Error` carries `[Conditional("UNITY_EDITOR")]` and `[Conditional("DEVELOPMENT_BUILD")]`, the same as `Log`
and `Warning`. In a release build the call is removed by the compiler, so every error path that reports
through `DLog.Error` reports nothing on a shipped device.

**Already resolved in `piggy-doku-repo`, and that version is what Step 4 now generates.** Both `Error`
overloads are unconditional and exempt from the tag filter; `Log` and `Warning` stay conditional and
filtered. Diagnostics are noise you strip, errors are the thing you keep.

The comment in `DLog.cs` records the bug that forced it: `EventBus` reports subscriber exceptions through
`Error(LogTag.EventBus, ...)`, `LogTag.EventBus` is not in `_enabledTags`, and all game logic runs inside
subscribers — so every subscriber exception was invisible in the Editor *and* compiled out of release builds
at once. That comment is load-bearing; do not tidy it away.

The same version adds `Error(LogTag, string, Exception)`, which calls `Debug.LogException` so the stack trace
survives — `exception.Message` alone loses file and line.

---

## 4. `DLog._enabledTags` defaults to `General` only — FIXED upstream

**File:** `_Framework/Logging/DLog.cs` · **Rule:** `rules/logging.md` Card 3

A newly added `LogTag` member is silent from birth: the call compiles, runs, matches nothing in
`_enabledTags`, and returns. Nothing reports this. It is the most likely way to lose a log line you are
certain you wrote — and it currently applies to `LogTag.SaveLoad`, so the framework's own save/load logs are
dropped by default.

**Fixed 2026-09-02 in `/setup-project` Step 4:** `_enabledTags` is seeded with every declared member
(`General`, `EventBus`, `SaveLoad`) and carries a comment saying why opt-out is the right default for a
logger already compiled out of release builds. `Disable(tag)` narrows it during a session.

**Corrected the same day.** The first fix seeded a literal list and recorded the leftover trap ("a member
added later is still silent") as by-design, on the grounds that reflecting over the enum would enable a tag
the author never meant to ship as live. That reasoning does not hold: `Log`/`Warning` are `[Conditional]` and
stripped from release at the call site, so nothing ships either way, and declaring a tag you do not want
enabled is not a real case — muting a noisy one is, which `Disable(tag)` already does. The literal list fixed
three members and left the trap armed for the fourth.

The seed is now `new((LogTag[])Enum.GetValues(typeof(LogTag)))`. There is no second place to edit, so the
class of mistake is gone rather than one instance of it. Raised by a project that had already made this
change locally.

A project generated before this date keeps the old one-member seed; widening it there is a two-line edit.

---

## 5. `SaveLoadManager` should be `SaveLoadService` — FIXED upstream

**File:** `_Framework/SaveLoadSystems/SaveLoadManager.cs` · **Rule:** `rules/solid-oop.md` Card 1

`*Manager` is reserved for a MonoBehaviour role — a single per-domain registry coordinating N sibling
instances via Register/Unregister. This class is a pure C# Tier 3 service implementing `ISaveLoadService`,
which the same card names `*Service`. The suffix is wrong in the one place a new developer is most likely to
copy it from.

Rename touches the class, its file, and the one registration line in `SaveLoadModule.Install`. No consumer
references the concrete type — they all inject `ISaveLoadService`.

---

## 6. `FramworkLogging.asmdef` typo in the source package — not present upstream

**File:** `_Framework/Logging/` asmdef · **Severity:** cosmetic, but it is an assembly name

The `.unitypackage` ships `FramworkLogging.asmdef` (missing the `e`). `/setup-project` Step 3 already
generates the correctly spelled `FrameworkLogging.asmdef`, so projects created by the template are
unaffected — but any project that imported the package directly carries the typo as its assembly name, and
renaming an assembly later means touching every `.asmdef` that references it.

`piggy-doku-repo` also has the correct spelling. The typo exists only in the `.unitypackage` snapshot.

No action needed in this repo. Recorded so the divergence between the package and the generator is not
mistaken for a generator bug — and as one more reason to diff that package against a live project before
trusting it.

---

## 7. `PlayerPrefsSaveLoadDal` does not exist yet

**File:** new — `_Framework/SaveLoadSystems/PlayerPrefsSaveLoadDal.cs` · **Rule:** `rules/save-load.md` Card 1

`LocalSaveLoadDal` is the only `ISaveLoadDal` that ships. That is fine as a default and wrong as the only
option: on **WebGL** a write to `Application.persistentDataPath` lands in the browser's IndexedDB and is not
flushed until an explicit `FS.syncfs`, so a save can silently disappear when the tab closes. A project
targeting WebGL has no working persistence today without writing its own backend — which is exactly the
duplication the `*Dal` split exists to prevent.

```csharp
public sealed class PlayerPrefsSaveLoadDal : ISaveLoadDal
{
    public void SaveData(string key, object value) => PlayerPrefs.SetString(key, JsonConvert.SerializeObject(value));
    public T LoadData<T>(string key) => HasKey(key) ? JsonConvert.DeserializeObject<T>(PlayerPrefs.GetString(key)) : default;
    public bool HasKey(string key) => PlayerPrefs.HasKey(key);
    public void DeleteData(string key) => PlayerPrefs.DeleteKey(key);
}
```

Three things must be written down with it, or it will be picked for the wrong reason:

1. **Card 7 cannot be satisfied here.** `PlayerPrefs` has no temp-file-then-replace equivalent. `SetString`
   plus a later `Save()` is the closest approximation and it is not atomic. Say so in the class, do not
   pretend the guarantee carries over.
2. **Size ceiling is platform-dependent** — a registry value on Windows, a plist entry on macOS/iOS. This
   backend is for a handful of small scalars, not for progress blobs.
3. **`PlayerPrefs.Save()` must be called**, or writes are flushed only at a graceful quit — which is the one
   exit path mobile does not guarantee.

Registration stays a one-line change in `SaveLoadModule.Install`; no service and no consumer moves. If
adding it requires touching `SaveLoadService`, the DIP boundary is in the wrong place.

`check-save-load.sh` already permits this: its `PlayerPrefs` block is scoped to
`_GameFolders/Scripts/Games/`, so `_Framework/SaveLoadSystems/` is deliberately free to implement one.
Verified 2026-09-02 — a `PlayerPrefs` DAL under `_Framework/` exits 0, the same call in a game service
exits 2.

**Card 8 applies here too — measured, and currently missed.** `terek_worm_escape_jam_repo` already has a
`PlayerPrefsSaveLoadDal`, and its `LoadData` calls `JsonConvert.DeserializeObject<T>` with no `try`/`catch`
(checked 2026-09-02). Card 7's atomic write genuinely does not port to `PlayerPrefs` — the rule says so
itself — but Card 8 is backend-independent: a corrupt stored string throws `JsonException` out of the DAL,
through `Configure()`, and the game does not open. Whichever backend is written here must carry
`catch (JsonException)` → `DLog.Error(LogTag.SaveLoad, ...)` → `return default`, so the caller falls into
its Card 6 default branch exactly as a first-run player does. `catch (Exception)` is separately forbidden.

That repo's file is a usable starting point for the shape, not for the error handling.
