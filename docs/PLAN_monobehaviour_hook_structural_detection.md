# PLAN: MonoBehaviour Hook Structural Detection

**Version:** v1 — 2026-07-20
**Complexity:** ~0.5 (Medium)
**Approach:** B (fully structural detection + rely on existing `should_skip_path` for path exclusion)

---

## Context

`check-no-monobehaviour-in-services.sh` Check 3 currently decides whether a domain/service
`.cs` file is allowed to `using UnityEngine` **by filename alone**. The whitelist
(`Provider|View|Root|Mono|Behaviour|Inspector|Editor|Drawer|Panel|Button|Controller|Installer|Scope|Loader|Dal|Client|Extensions`)
is a broad, name-based escape hatch. Two problems:

1. **Name-based, not structure-based.** A file named `Games/Concretes/Audio/CustomAudioInspector.cs`
   that lives in a *runtime* folder (not under an `Editor/` folder) passes purely because its name
   ends in `Inspector` — even though a runtime class doing Editor work in a domain folder is exactly
   the violation this hook should catch. Editor-role classes belong under an actual `Editor/` folder
   (already covered by `should_skip_path()`) or must be `#if UNITY_EDITOR`-guarded per
   `csharp-unity.md` / `unity-lifecycle.md`.
2. **No structural justification path.** A legitimate MonoBehaviour (has `[SerializeField]` or a Unity
   lifecycle callback) named e.g. `ShopManager.cs` is not on the whitelist and would be blocked,
   while an unjustified pure-C# class that leaks `using UnityEngine` slips by if it happens to match
   a whitelisted suffix.

**Prior infrastructure already landed (no conflict):** the underlying work is implemented via
commits `cb61d08` (2026-06-25) and `d73cbaf`, which added to `_lib.sh`: `should_skip_path()`
(lines 124-131, PATH-based skip for `/Editor/`, `/editor/`, `/Editors/`, `/editors/`, `/Plugins/`,
`/ThirdParty/`, `_AssetFolders/`, `PackageCache/`, `EditModeTest/`, `PlayModeTest/`, `Tests/`,
`Test/`, `Spec/`), `unity_hook_warn()` (lines 115-118), `unity_hook_block()` (lines 102-111,
pre-existing, respects `UNITY_HOOK_MODE=warn` downgrade). It also added `Installer`/`Scope` to
the Check 3 filename whitelist and the existing 4 bats tests. (Note: the plan document that
originally scoped this work is not present in the current tree — the infrastructure is verified
by the commits themselves, not by an extant plan file.) This plan builds on top of that landed
work — it is not a competing plan to merge or sequence against.

**Goal of this plan:** replace filename-guessing with structural detection. Add a shared
`unity_monobehaviour_is_justified()` helper, rewrite Check 3 to use it, narrow the filename
whitelist to only the structurally-undetectable pure-C# role categories, and reuse the same helper in
`check-mono-justification.sh` to kill the duplicated inline detection logic.

---

## Goals

- **G1** — Structural, not name-based, justification of MonoBehaviour / UnityEngine usage in domain code.
- **G2** — Single shared detection helper (`unity_monobehaviour_is_justified()`) used by both hooks.
- **G3** — Narrow the Check 3 filename whitelist to only categories that cannot be detected
  structurally (pure-C# swappable-backend + DI roles): `Handler|Loader|Dal|Client|Extensions|Installer|Scope`.
- **G4** — Close the `Inspector|Editor|Drawer` name-escape hole; rely on `should_skip_path()` (path-based)
  for legitimate Editor-folder code.
- **G5** — Keep all existing behavior (Check 1, Check 2, path guard, config/event exemptions,
  `UNITY_HOOK_MODE=warn` downgrade) intact; extend test coverage from 4 to 9 tests.

---

## Status

| # | Task | Type | parallel_group | Status |
|---|------|------|----------------|--------|
| 1 | Add `unity_monobehaviour_is_justified()` to `_lib.sh` | HOOK | Group 1 (sequential, first) | ✅ Done |
| 2 | Rewrite Check 3 in `check-no-monobehaviour-in-services.sh` | HOOK | Group 2 | ✅ Done |
| 3 | Refactor `check-mono-justification.sh` to call shared helper | HOOK | Group 2 | ✅ Done |
| 4 | Add 5 new bats tests (4→9 total) | HOOK/Test | Group 3 (after Task 2) | ✅ Done — 9/9 pass |
| 5 | Clarifying note under `solid-oop.md` Card 1 suffix table | DOCS | Group 2 | ✅ Done |
| 6 | Update `hooks-blocking.md` line 8 prose | DOCS | Group 2 | ✅ Done |
| 7 | `*Manager` naming-table gap | DECISION | ungrouped | ✅ Resolved — Option B (see Task 7) |

---

## File Map

| Path | Live state | This plan's change |
|------|-----------|--------------------|
| `.claude/hooks/_lib.sh` | `unity_hook_block()` 102-111, `unity_hook_warn()` 115-118, `should_skip_path()` 124-131, `strip_cs_noise()` 197-237 — all present | **Add** `unity_monobehaviour_is_justified()` (Task 1) |
| `.claude/hooks/check-no-monobehaviour-in-services.sh` | `source _lib.sh` line 4; `should_skip_path` guard line 41; Check 1 (Handler:MonoBehaviour) 43-56; Check 2 (Module:ScriptableObject) 58-71; Check 3 73-110 (scope guard 74, filename whitelist 81, `*Events?` 86, config families 93, `using UnityEngine` block 98) | **Rewrite Check 3** 73-110 (Task 2). Lines 1-71 unchanged |
| `.claude/hooks/check-mono-justification.sh` | `should_skip_path` guard line 48; `strip_cs_noise` line 60; inline `[SerializeField]`/callback detection 63-64; unjustified-MB warn 66-73 (`echo ... >&2`, exit 0 continues to Check 2); oversize warn 77-83 uses `unity_hook_warn` | **Refactor** 60-64 to call shared helper (Task 3). Preserve `echo ... >&2` warn-continue nuance |
| `.claude/hooks/tests/check-no-monobehaviour-in-services.bats` | 4 tests, lines 14-44, inline file-creation convention (no `fixtures/`) | **Append 5 tests** → 9 total (Task 4) |
| `.claude/rules/solid-oop.md` | Card 1 suffix table ~44-70 (Handler = pure C#, GOTCHA line 70; constructor-ref distinction line 155) | **Add clarifying note** (Task 5) |
| `.claude/docs/hooks-blocking.md` | Line 8 describes Check 3 exemptions (currently lists `*Provider/*View/*Controller/*Loader/*Dal/*Client/*Extensions/etc.`) | **Update prose** (Task 6) |

---

## Task 1 — [HOOK] Add `unity_monobehaviour_is_justified()` to `_lib.sh`

**Files:**
- `.claude/hooks/_lib.sh`

**Steps:**
1. [x] Add `unity_monobehaviour_is_justified()`. Place it **immediately after `should_skip_path()`
      (after line 131)**, grouping it with the other `unity_hook_*`/path helpers.
2. [x] Input contract: takes the **already-stripped** content on stdin (caller runs `strip_cs_noise`
      once and pipes it in), so the helper does no file I/O and can be reused cheaply. Returns 0
      (justified) if the stripped content contains `[SerializeField]` OR any Unity lifecycle callback;
      returns 1 (not justified) otherwise.
3. [x] Broaden the callback match versus `check-mono-justification.sh`'s current exact list: match
      `OnTrigger`/`OnCollision` by prefix so `OnTriggerEnter/Stay/Exit` and
      `OnCollisionEnter/Stay/Exit` all count. This is an intentional **superset** of the current inline
      list — documented in a comment so the widened match is not mistaken for a bug.

**Test Type:** NoTest (bash helper — exercised indirectly via Task 4 bats; no separate unit harness for `_lib.sh` functions).

**Code Skeleton:**
```bash
# unity_monobehaviour_is_justified — reads ALREADY-STRIPPED C# content on stdin
# (caller runs strip_cs_noise once). Returns 0 if the class has a legitimate reason
# to be a MonoBehaviour / touch UnityEngine: a [SerializeField] field OR any Unity
# lifecycle callback. Returns 1 otherwise (Card 0 candidate — should be pure C#).
# NOTE: callback match intentionally broadens check-mono-justification.sh's historical
# exact list to OnTrigger*/OnCollision* prefixes (Enter/Stay/Exit all count) — superset,
# by design.
unity_monobehaviour_is_justified() {
    local stripped; stripped=$(cat)
    if echo "$stripped" | grep -qE "\[SerializeField\]"; then
        return 0
    fi
    if echo "$stripped" | grep -qE "\b(Awake|Start|OnEnable|OnDisable|OnDestroy|Update|FixedUpdate|LateUpdate|OnTrigger[A-Za-z]*|OnCollision[A-Za-z]*)\s*\("; then
        return 0
    fi
    return 1
}
```

**Acceptance Criteria:**
- Function defined in `_lib.sh`, documented location noted.
- Justified when `[SerializeField]` present; justified when any listed callback (incl.
  `OnTriggerStay`/`OnCollisionStay`) present; not justified otherwise.
- No file I/O inside the helper; consumes stdin only.

---

## Task 2 — [HOOK] Rewrite Check 3 in `check-no-monobehaviour-in-services.sh`

**Files:**
- `.claude/hooks/check-no-monobehaviour-in-services.sh`

**Steps:**
1. [x] Lines 1-71 unchanged (audit logging, path guard line 41, Check 1, Check 2).
2. [x] Confirm `should_skip_path "$FILE_PATH" && exit 0` at **line 41** already fires before Check 3 —
      no duplicate `should_skip_path` call inside Check 3.
3. [x] Keep the Check 3 **scope guard** (line 74: `if echo "$FILE_PATH" | grep -qiE "(_Framework|Games/Abstracts|Games/Concretes)/.*\.cs$"; then`)
      unchanged. (The top-level path-exclusion guard is separately at line 41 — already confirmed
      firing before Check 3 runs, no duplicate call needed.)
4. [x] Replace the filename whitelist (line 81). NEW whitelist — structurally-undetectable pure-C#
      categories only: `Handler|Loader|Dal|Client|Extensions|Installer|Scope`.
      **DROP** `Provider|View|Root|Mono|Behaviour|Inspector|Editor|Drawer|Panel|Button|Controller`
      entirely (all now judged structurally via the helper, or already covered by `should_skip_path`).
5. [x] Keep the `*Events?.cs` exemption (line 86) unchanged.
6. [x] Keep the `(Configuration|Config|Catalog|Definition)\.(cs)$` config-family exemption (line 93)
      unchanged.
7. [x] After the exemptions and only if the file exists: run `strip_cs_noise` once, pipe into
      `unity_monobehaviour_is_justified`. If justified → `exit 0`. Otherwise, if
      `grep -n "using UnityEngine"` finds imports → `unity_hook_block` with the existing message
      style/tone (point at Card 0 / Provider pattern, move Unity code to
      `Games/Concretes/<Module>/`). `unity_hook_block` already respects `UNITY_HOOK_MODE=warn`.

**Test Type:** NoTest (bash hook — behavior covered by Task 4 bats).

**Code Skeleton (Check 3 body, replacing lines 73-110):**
```bash
# --- Check 3: UnityEngine imports in domain/service files (blocking) ---
if echo "$FILE_PATH" | grep -qiE "(_Framework|Games/Abstracts|Games/Concretes)/.*\.cs$"; then
    # Filename whitelist: ONLY structurally-undetectable pure-C# role categories.
    # *Handler (constructor-ref Unity access), *Loader/*Dal/*Client (Tier 4 swappable
    # backends, architecture.md Card 2.1), *Extensions (static extensions on Unity types),
    # *Installer/*Scope (VContainer wiring). Everything else — Provider/View/Controller/
    # Panel/Button/Inspector/Editor/Drawer — is now judged STRUCTURALLY (justified MB)
    # or excluded by should_skip_path (path-based Editor folders).
    if echo "$FILE_PATH" | grep -qiE "(Handler|Loader|Dal|Client|Extensions|Installer|Scope)\.(cs)$"; then
        exit 0
    fi

    # Event data containers may use Unity math types.
    if echo "$FILE_PATH" | grep -qiE "Events?\.(cs)$"; then
        exit 0
    fi

    # ScriptableObject config families legitimately use UnityEngine.
    if echo "$FILE_PATH" | grep -qiE "(Configuration|Config|Catalog|Definition)\.(cs)$"; then
        exit 0
    fi

    if [ -f "$FILE_PATH" ]; then
        # Structural justification: a real MonoBehaviour ([SerializeField] or lifecycle
        # callback) is allowed to touch UnityEngine even in a domain folder.
        if strip_cs_noise "$FILE_PATH" | unity_monobehaviour_is_justified; then
            exit 0
        fi
        UNITY_IMPORTS=$(grep -n "using UnityEngine" "$FILE_PATH" 2>/dev/null)
        if [ -n "$UNITY_IMPORTS" ]; then
            unity_hook_block "Domain/service file contains UnityEngine imports!
File: $FILE_PATH

Violations:
$UNITY_IMPORTS

Services and abstractions must be pure C# (solid-oop.md Card 0).
If this is genuinely a MonoBehaviour, it needs a [SerializeField] field or a Unity
lifecycle callback. Otherwise move Unity-specific code to a Provider class in
Games/Concretes/<Module>/."
        fi
    fi
fi

exit 0
```

**Acceptance Criteria:**
- Lines 1-71 byte-identical to current.
- Whitelist reduced to `Handler|Loader|Dal|Client|Extensions|Installer|Scope`.
- `Inspector|Editor|Drawer|Provider|View|Controller|Panel|Button|Root|Mono|Behaviour` no longer in
  the whitelist.
- Justified MonoBehaviour in a domain folder → exit 0; unjustified pure-C# with `using UnityEngine`
  → blocked (exit 2, or exit 0 under `UNITY_HOOK_MODE=warn`).

---

## Task 3 — [HOOK] Refactor `check-mono-justification.sh` to call the shared helper

**Files:**
- `.claude/hooks/check-mono-justification.sh`

**Steps:**
1. [x] Re-verify live state before editing: line 48 `should_skip_path` guard present; line 60
      `strip_cs_noise`; lines 63-64 inline detection; lines 66-73 warn via `echo ... >&2` (exit 0,
      **continues** to Check 2 line-count); lines 77-83 oversize warn via `unity_hook_warn`.
2. [x] Replace the inline `HAS_SERIALIZE_FIELD` / `HAS_UNITY_CALLBACKS` counts (63-64) and the
      combined `-eq 0 && -eq 0` test (66) with a single call:
      `if ! echo "$STRIPPED" | unity_monobehaviour_is_justified; then ... warn ... fi`.
3. [x] **Preserve the warn-continue nuance:** Check 1 here must use `echo "..." >&2` and NOT exit,
      because Check 2 (oversize shell, line 77) must still run afterward. Do **not** convert Check 1
      to `unity_hook_warn` (which exits 0). Confirm against the live file — it currently uses
      `echo ... >&2`; keep whatever pattern is actually live. Leave Check 2's existing
      `unity_hook_warn` call untouched.

**Test Type:** NoTest (warn-only hook; no bats file for it. Manual smoke check acceptable —
unjustified MB still warns, justified MB stays silent, oversize warning still fires).

**Code Skeleton (replacing lines 60-73):**
```bash
# Strip comments/strings once, reuse for detection.
STRIPPED=$(strip_cs_noise "$FILE_PATH")

# --- Check 1: Unjustified MonoBehaviour (Card 0) ---
if ! echo "$STRIPPED" | unity_monobehaviour_is_justified; then
    # Print WITHOUT exiting so Check 2 (line count) still runs.
    echo "Warning: MonoBehaviour with no [SerializeField] fields and no Unity callbacks.
File: $FILE_PATH

This class may not need to be a MonoBehaviour (solid-oop.md Card 0).
If you need a frame tick, use ITickable instead. If you need no Unity lifecycle, make it pure C#." >&2
fi
```

**Acceptance Criteria:**
- Inline detection removed; helper used instead.
- Check 1 still warns via stderr and does NOT exit (Check 2 runs).
- Check 2 oversize warning unchanged.
- Detection now includes the broadened `OnTrigger*/OnCollision*` prefixes (intentional superset).

---

## Task 4 — [HOOK/Test] Add 5 new bats tests (4 → 9 total)

**Files:**
- `.claude/hooks/tests/check-no-monobehaviour-in-services.bats`

**Steps:**
1. [x] Append to the EXISTING file (do not create a new one). Keep the 4 current tests (lines 14-44)
      as-is; add tests after line 44.
2. [x] Use the existing inline file-creation convention exactly (mkdir under `$TMPDIR_TEST/...`,
      `printf` the `.cs`, `run bash -c "echo '{...}' | bash $HOOK"`, assert `$status`). No
      `fixtures/` directory.
3. [x] (a) MonoBehaviour + `[SerializeField]` named `ShopManager.cs` under
      `Games/Concretes/Shop/` → exit 0 (structurally justified).
4. [x] (b) MonoBehaviour + lifecycle callback named `SpawnDirector.cs` under
      `Games/Concretes/Spawning/` → exit 0 (structurally justified).
5. [x] (c) pure-C# class named `ScoreCalculator.cs` (NOT a whitelisted suffix) under
      `Games/Concretes/Scoring/`, leaking `using UnityEngine`, no `[SerializeField]`, no callback
      → exit 2 (blocked).
6. [x] (d) `MoveHandler.cs` pure C# with a Unity ctor ref (e.g. `Rigidbody`), no `[SerializeField]`,
      under `Games/Concretes/Players/` → exit 0 (Handler name exemption survives).
7. [x] (e) **Regression guard for the dropped `Inspector` escape:** `CustomAudioInspector.cs` under
      `Games/Concretes/Audio/` (NOT under an `Editor/` folder) with `using UnityEngine` and no Card 0
      justification → exit 2. Previously passed by name; now correctly blocked.

**Test Type:** bash (bats). Run: `bats .claude/hooks/tests/check-no-monobehaviour-in-services.bats` —
expect 9 passing.

**Code Skeleton (appended after line 44):**
```bash
@test "allows justified MonoBehaviour with [SerializeField] (structural)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Shop"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Shop/ShopManager.cs"
    printf 'using UnityEngine;\npublic class ShopManager : MonoBehaviour {\n    [SerializeField] private int _slots;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "allows justified MonoBehaviour with a Unity lifecycle callback (structural)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Spawning"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Spawning/SpawnDirector.cs"
    printf 'using UnityEngine;\npublic class SpawnDirector : MonoBehaviour {\n    private void Update() {}\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks unjustified pure-C# class leaking UnityEngine (non-whitelisted name)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Scoring/ScoreCalculator.cs"
    printf 'using UnityEngine;\npublic sealed class ScoreCalculator {\n    public int Total;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Handler with Unity ctor ref (Handler name exemption survives)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Players"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Players/MoveHandler.cs"
    printf 'using UnityEngine;\npublic sealed class MoveHandler {\n    public MoveHandler(Rigidbody rb) {}\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}

@test "blocks runtime *Inspector.cs outside Editor/ folder (old name-escape removed)" {
    mkdir -p "$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio"
    local f="$TMPDIR_TEST/Assets/Scripts/Games/Concretes/Audio/CustomAudioInspector.cs"
    printf 'using UnityEngine;\npublic sealed class CustomAudioInspector {\n    public int Value;\n}\n' > "$f"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}
```

**Acceptance Criteria:**
- 9 tests total, all passing.
- Test (e) proves the `Inspector` name-escape is gone.
- New tests match the existing inline-file convention exactly.

---

## Task 5 — [DOCS] Clarifying note under `solid-oop.md` Card 1 suffix table

**Files:**
- `.claude/rules/solid-oop.md`

**Steps:**
1. [x] Under the Card 1 suffix table (~lines 44-70), add a short note: the hook now enforces
      MonoBehaviour/UnityEngine-in-domain-code **structurally** (`[SerializeField]` or a Unity
      lifecycle callback), not by suffix. The suffix is a **naming consequence** of a class's role,
      not the enforcement mechanism. Reaffirm the Handler distinction (line 155): a Handler is pure
      C# and may receive Unity component refs via its constructor — that is why `*Handler` remains a
      name-whitelisted exemption in Check 3.

**Test Type:** NoTest (markdown docs).

**Acceptance Criteria:**
- Note present, does not contradict the existing table or GOTCHA (line 70).

---

## Task 6 — [DOCS] Update `hooks-blocking.md` line 8 prose

**Files:**
- `.claude/docs/hooks-blocking.md`

**Steps:**
1. [x] Rewrite the exemption description on line 8 to match the new reality:
   - Filename exemptions now: `Handler`/`Loader`/`Dal`/`Client`/`Extensions`/`Installer`/`Scope` only.
   - Path-based exclusion via `should_skip_path()` covers Editor/third-party/test code.
   - `*Events` files and config families (`*Configuration`/`*Config`/`*Catalog`/`*Definition`) remain
     exempt.
   - MonoBehaviour/domain UnityEngine usage is now judged **structurally** (`[SerializeField]` or a
     Unity lifecycle callback) rather than by name.
   - Explicitly state: Editor-role files must live under an actual `Editor/` folder (or be
     `#if UNITY_EDITOR`-guarded) to be exempt — a name like `*Inspector.cs`/`*Editor.cs`/`*Drawer.cs`
     in a runtime domain folder is no longer exempt by name.

**Test Type:** NoTest (markdown docs).

**Acceptance Criteria:**
- Line 8 exemption list matches Task 2's whitelist exactly.
- No stale reference to `*Provider`/`*View`/`*Controller`/`*Inspector`/`*Editor`/`*Drawer` as
  filename exemptions.

---

## Task 7 — [DECISION, RESOLVED] `*Manager` naming-table gap

**Status:** ✅ Resolved — Option B chosen by user.

`*Manager` had no row in the `solid-oop.md` Card 1 suffix table. Resolved by adding it as a 4th
approved MonoBehaviour role: a centralized coordinator for ONE domain's collection of same-type
instances (e.g. `EnemyManager` for N enemies), used via a Register/Unregister pattern through an
injected interface instead of pairwise `IEventBus` attach/detach or direct references between
instances. Constraints added to `solid-oop.md` Card 1: one domain per Manager (no catch-all
`GameManager`), Register/Unregister over `IEventBus` for intra-domain coordination, Card 0 still
required for MonoBehaviour status (else pure C# Service is the default), and SRP still applies
(extract to Handler/Service if the Manager grows business logic beyond registration+coordination).

Implemented directly in `.claude/rules/solid-oop.md` Card 1 (role table, suffix decision test,
new constraints block, suffix prohibition table) — same-day follow-up after Tasks 1-6 shipped.

---

## Approach Comparison

**Approach A — Extend the filename whitelist / keep name-based decisions.**
Keep deciding by suffix; add more names as new roles appear. Rejected:
- Perpetuates the core defect — name is not structure. `CustomAudioInspector.cs` in a runtime folder
  keeps passing.
- Ever-growing whitelist; every new role suffix is a new escape hatch to audit.
- **Now also awkward given landed `should_skip_path()`:** Approach A would leave *two* path-adjacent
  whitelist mechanisms doing overlapping jobs — a filename list that partly duplicates what the
  path-based `should_skip_path()` already covers for Editor code — with subtly different semantics
  (name vs folder). That divergence is exactly the `Inspector` bug.

**Approach B — Structural detection + rely on `should_skip_path()` for paths (CHOSEN).**
- One shared `unity_monobehaviour_is_justified()` helper judges MonoBehaviour legitimacy by content.
- Filename whitelist shrinks to only categories that genuinely cannot be detected structurally
  (pure-C# swappable backends + DI wiring: `Handler|Loader|Dal|Client|Extensions|Installer|Scope`).
- Path exclusion is owned solely by the already-landed `should_skip_path()` — no second, weaker,
  name-based path mechanism. Clean separation: **paths → `should_skip_path`; structure →
  `unity_monobehaviour_is_justified`; irreducible pure-C# roles → the narrow name whitelist.**
- Removes duplicated detection logic from `check-mono-justification.sh`.

Cost: ~0.5 (Medium) — one new helper, one Check rewrite, one refactor, 5 tests, 2 doc edits, all in
files that already exist. No new hook file, no `settings.json` change (so no manual user step).

---

## Parallel Group Assignment

- **Group 1 (sequential, first):** Task 1 — the shared helper. Tasks 2 and 3 both depend on it.
- **Group 2 (parallel — disjoint files):** Task 2 (`check-no-monobehaviour-in-services.sh`),
  Task 3 (`check-mono-justification.sh`), Task 5 (`solid-oop.md`), Task 6 (`hooks-blocking.md`).
  No shared files; run concurrently after Group 1.
- **Group 3 (after Task 2):** Task 4 — bats tests assert the rewritten Check 3 behavior, so they
  must land after Task 2.
- **Ungrouped:** Task 7 — decision item, no code, does not block.

**Dependency chain:** Task 1 → {Task 2, Task 3, Task 5, Task 6} → Task 4. Task 7 independent.
