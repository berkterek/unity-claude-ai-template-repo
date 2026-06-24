# PLAN — Hook False-Positive Guards + Test Infrastructure

> **Version:** v2 — 2026-06-24 (v1 revised after BREAKING review: bats filename, ecs env-override, struct regex, dropped dead helpers, bats-core install)
> **Status:** Active
> **Scope:** `.claude/hooks/` (bash hooks + `_lib.sh`), `.claude/hooks/tests/` (bats), `.github/workflows/` (CI). NOT Unity C# code.
> **Complexity:** 0.7 — Complex (touches a shared lib that all 49 hooks source; adds a CI gate; introduces a fixture corpus).

> **Pipeline adaptation note:** `/create-plan` is Unity-feature-tuned. This plan targets the template's own bash/Python/CI tooling, so the Unity `Test Type` matrix, VContainer prescan, and graph query are not applicable. The per-task **Verification** field replaces **Test Type** and means "how this task is proven correct" (bats test / clean-env manual run).

## Context

Dogfooding the template against a real Unity project (`nile_hole_incremental_repo`, 733 `.cs` files) surfaced that **four PreToolUse hooks block legitimate, shipping code** — they would reject edits to real files. Same class of bug as the already-known over-broad `check-ls-grep`. Confirmed false positives (negative-control scan, exit 2 on real files):

- `check-enum-byte-base.sh` (4 files) — context gate `grep -qE "(IEvent|IComponentData)"` matches `IEventBus`. Any file injecting `IEventBus` (≈ every file) that also contains any plain `enum` is blocked. Proven: `ChestRewardFlowController.cs` has `IEventBus _eventBus`, no real IEvent/IComponentData struct, and a plain `private enum ChestFlowState` → exit 2. Also runs even though `project-features.json` has `ecs: false`.
- `check-no-runtime-instantiate.sh` (10 files) — no path exclusion at all; blocks `new GameObject()` in `Scripts/Editor/` tooling (legitimate) and `Assets/Plugins/` third-party code.
- `check-input-system.sh` (12 files) — excludes `/Editor/` but not third-party; blocks `Assets/Plugins/UniRx/` code.
- `check-no-monobehaviour-in-services.sh` (13 files) — actually the "pure-csharp" guard (flags `using UnityEngine` in domain dirs). Its skip whitelist (Provider/View/Root/.../Controller) omits `Installer`, so every MonoBehaviour `*Installer.cs` is blocked.

The deeper problem: **none of this was caught for months** because no harness exercises hooks against realistic inputs and no CI step runs the 11 existing bats tests (49 hooks total; CI runs only an LLM review). Plus latent debt: non-POSIX regex (`\s`, `\?`, `\w`) that breaks silently under non-GNU greps (e.g. ugrep), warn output on stdout instead of stderr, and a duplicated `_hook_log` audit-rotation that errors on first use because `~/.claude/` may not exist.

This plan (1) stops the active damage via path/context guards, (2) hardens the shared lib once so the same path-skip fix isn't repeated per hook, and (3) makes a two-arm bats harness run in CI so this regresses loudly, not silently.

## Goals

- [ ] No hook blocks third-party (`/Plugins/`, `/ThirdParty/`, `_AssetFolders/`, `PackageCache/`) or `/Editor/` code.
- [ ] `check-enum-byte-base` fires only on a real `struct … : … IEvent/IComponentData` and only when `ecs` is enabled.
- [ ] `check-no-monobehaviour-in-services` exempts `*Installer.cs`.
- [ ] A single `should_skip_path()` helper in `_lib.sh` is the one source of path-exclusion truth; touched hooks call it instead of duplicating logic.
- [ ] Warn output goes to stderr; the audit-log rotation in the 4 touched hooks no longer errors on first use.
- [ ] Non-POSIX regex in the 4 touched hooks replaced with POSIX classes; remaining offenders documented.
- [ ] A checked-in fixture corpus + bats tests prove each fix with both a negative control (legit file → no block) and a positive control (real violation → block).
- [ ] CI runs `run-tests.sh` (bats-core) on every PR and fails red on a broken hook.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — `_lib.sh` shared helpers (`should_skip_path`, `unity_hook_warn`) | ✅ Done | 1 |
| 1 | T2 — Fixture corpus | ✅ Done (inline in bats per repo convention — no separate fixtures/ dir) | 1 |
| 2 | T3 — Fix the 4 false-positive hooks (helper + context/whitelist/ecs-override + inline audit-log mkdir) | ✅ Done | — |
| 2 | T4 — POSIX-ify regex in the 4 touched hooks + document remaining offenders | ✅ Done | — |
| 3 | T5 — bats tests (negative + positive control) for the 4 hooks | ✅ Done | — |
| 4 | T6 — CI: run `run-tests.sh` (bats-core) + shellcheck as a PR gate | ✅ Done | 2 |
| 4 | T7 — Document/automate bats-core install (Brewfile + README note) | ✅ Done | 2 |

> **Implementation notes (deviations from plan):**
> - **T2 fixtures inline, not a `fixtures/` dir** — followed the existing bats convention (`echo > $f` inside each test), which is simpler and matches all 11 prior test files. Two-arm control (negative + positive) preserved.
> - **bats tests do NOT force `PATH=/usr/bin:/bin`** — a fresh `bash $HOOK` does not inherit the interactive shell's aliased `grep` function, so the ugrep leak only affects the agent shell, not bats/CI. Forcing the PATH risked breaking `jq` resolution (homebrew installs jq at `/opt/homebrew/bin`). The POSIX regex fix (T4) is what makes detection grep-flavor independent.
> - **Two extra false positives found during real-codebase verification and fixed:** `should_skip_path` also skips `/Editors/` (trailing-s, e.g. `_Framework/Editors/`); the pure-csharp whitelist also exempts `*Scope.cs` (LifetimeScope subclasses). Both confirmed against `nile_hole_incremental_repo`.
>
> **Verification result (clean-env scan vs `nile_hole_incremental_repo`, 734 .cs files):**
>
> | hook | false positives before | blocked after | remaining are |
> |------|----|----|----|
> | check-enum-byte-base | 4 | 0 | (ecs disabled) |
> | check-no-runtime-instantiate | 10 | 2 | genuine runtime `new GameObject()` |
> | check-input-system | 12 | 3 | genuine legacy `Input.*` |
> | check-no-monobehaviour-in-services | 13 | 1 | genuine `Application.persistentDataPath` in a pure-C# DAL |
>
> **33 false positives eliminated; all 6 remaining blocks are confirmed real violations.** bats: 70/70 pass (19 new/extended).

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/hooks/_lib.sh` | Modify | Add `should_skip_path` + `unity_hook_warn`. (No `get_content`/audit helper — see Out of Scope.) |
| `.claude/hooks/check-enum-byte-base.sh` | Modify | Struct-context word-boundary regex; `UNITY_FEATURES_FILE` ecs gate; POSIX regex; `should_skip_path`; inline `_hook_log` mkdir fix |
| `.claude/hooks/check-no-runtime-instantiate.sh` | Modify | `should_skip_path` guard; inline `_hook_log` mkdir fix |
| `.claude/hooks/check-input-system.sh` | Modify | `should_skip_path` guard; inline `_hook_log` mkdir fix |
| `.claude/hooks/check-no-monobehaviour-in-services.sh` | Modify | Add `Installer` to skip whitelist; `should_skip_path`; inline `_hook_log` mkdir fix |
| `.claude/hooks/tests/fixtures/legit/*.cs` | Add | Negative-control fixtures |
| `.claude/hooks/tests/fixtures/violating/*.cs` | Add | Positive-control fixtures (incl. multi-interface struct) |
| `.claude/hooks/tests/fixtures/README.md` | Add | Per-fixture required relative path |
| `.claude/hooks/tests/check-enum-byte-base.bats` | Add | new |
| `.claude/hooks/tests/check-no-runtime-instantiate.bats` | Add | new |
| `.claude/hooks/tests/check-no-monobehaviour-in-services.bats` | Add | new |
| `.claude/hooks/tests/check-legacy-input.bats` | Modify | existing input-hook test — add third-party exclusion cases |
| `.github/workflows/hook-tests.yml` | Add | bats-core + shellcheck PR gate |
| `Brewfile` | Add | `bats-core`, `shellcheck` for local dev |
| `.github/workflows/README.md` | Modify | document the new workflow + local-test note |

---

## Task 1 — `_lib.sh` shared helpers

**Files:**
- `.claude/hooks/_lib.sh`

**Steps:**
1. [ ] Add `should_skip_path()` after `unity_hook_block` (≈ line 111). Returns 0 (skip) if `$1` matches a non-runtime path segment: `/Editor/`, `/editor/`, `/Plugins/`, `/ThirdParty/`, `_AssetFolders/`, `PackageCache/`, and test dirs `(EditModeTest|PlayModeTest|Tests|Test|Spec)/`.
2. [ ] Add `unity_hook_warn(msg)` — echoes `WARNING: $msg` to **stderr** and `exit 0`. Mirror of existing `unity_hook_block`.
3. [ ] Do NOT add `get_content()` — dropped from this plan (all 4 touched hooks read from disk via `$FILE_PATH` and early-exit on `[ ! -f ]`; the `new_string`/`content` fallback is unused here). Full input-contract unification is a separate follow-up.
4. [ ] Do NOT add a centralized audit-log helper — the `mkdir` fix is applied inline in the 4 touched hooks (T3). Centralizing `_hook_log` across all 49 hooks is a separate follow-up.
5. [ ] Do not change profile-gating (lines 33–42) or the `HOOK_PROFILE_LEVEL`-before-`source` contract.

**Verification:** Sourced by a throwaway script calling `should_skip_path` with sample paths; `shellcheck _lib.sh` clean. Covered indirectly by T5.

**Code Skeleton:**
```bash
# returns 0 (=skip) if path is non-runtime / third-party / test
should_skip_path() {
    case "$1" in
        */Editor/*|*/editor/*|*/Plugins/*|*/ThirdParty/*|*_AssetFolders/*|*PackageCache/*) return 0 ;;
        *EditModeTest/*|*PlayModeTest/*|*Tests/*|*Test/*|*Spec/*) return 0 ;;
    esac
    return 1
}

unity_hook_warn() { echo "WARNING: $1" >&2; exit 0; }
```

**Acceptance Criteria:**
- `should_skip_path "/x/Assets/Plugins/UniRx/A.cs"` returns 0; `should_skip_path "/x/Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioService.cs"` returns 1. (Verified: `Latest/`, `Greatest/` do NOT match `*Test/*` because the glob requires a literal `Test/` segment.)
- `shellcheck _lib.sh` passes with no new warnings.
- No `get_content` and no audit helper added (kept out per Steps 3–4).

---

## Task 2 — Fixture corpus

**Files:**
- `.claude/hooks/tests/fixtures/legit/` (new), `.claude/hooks/tests/fixtures/violating/` (new), `.claude/hooks/tests/fixtures/README.md` (new)

**Steps:**
1. [ ] `legit/` negative-control `.cs` files (must NOT be blocked):
   - `AudioInstaller.cs` — `using UnityEngine; public sealed class AudioInstaller : MonoBehaviour, IInstaller {}` (monobehaviour-in-services).
   - `EventBusEnum.cs` — class with `IEventBus _eventBus;` + `private enum State { A, B }`, NO `IEvent`/`IComponentData` struct (enum-byte-base word-boundary + IEventBus non-match).
   - `EditorTool.cs` — to be copied under a `/Editor/` path, uses `new GameObject("x")` (runtime-instantiate).
   - `PluginInput.cs` — to be copied under a `/Plugins/` path, uses `Input.GetKey(...)` (input-system).
2. [ ] `violating/` positive-control `.cs` files (MUST be blocked), each copied under a normal runtime path:
   - `RealEnumEvent.cs` — `public struct FooEvent : IEvent { public Dir D; } public enum Dir { Up, Down }` (no `:byte`).
   - `MultiIfaceEvent.cs` — `public struct BarEvent : IDisposable, IEvent { public Dir D; public void Dispose(){} } public enum Dir { Up, Down }` (IEvent NOT first interface — locks the regex against the false-negative the reviewer found).
   - `RuntimeSpawn.cs` — runtime MonoBehaviour with `new GameObject("Enemy")`.
   - `LegacyInput.cs` — runtime MonoBehaviour with `Input.GetKey(KeyCode.Space)`.
   - `MonoService.cs` — `using UnityEngine; public class AudioService : MonoBehaviour {}` copied under `Concretes/Audio/`.
3. [ ] `fixtures/README.md` lists, per fixture, the relative path bats must copy it to (e.g. `EditorTool.cs → Assets/Scripts/Editor/EditorTool.cs`).

**Verification:** Consumed by T5.

**Acceptance Criteria:**
- Each fixture is minimal, one trigger / one legit pattern.
- `MultiIfaceEvent.cs` exists and is in the violating set.
- README states each fixture's required relative path.

---

## Task 3 — Fix the 4 false-positive hooks

**Files:**
- `.claude/hooks/check-enum-byte-base.sh`, `check-no-runtime-instantiate.sh`, `check-input-system.sh`, `check-no-monobehaviour-in-services.sh`

**Insertion-order rule (applies to all 4):** `should_skip_path "$FILE_PATH" && exit 0` MUST be placed AFTER the hook reads stdin and sets `FILE_PATH` and passes its `.cs` / `[ -f "$FILE_PATH" ]` guards (the existing `INPUT=$(cat); FILE_PATH=…` block, ≈ line 28+). The `ecs` gate (which needs no FILE_PATH) may go right after `source _lib.sh`.

**Steps:**
1. [ ] **check-enum-byte-base.sh**:
   - (a) Context regex (≈ line 50): replace `(IEvent|IComponentData)` with a struct-declaration match that tolerates multi-interface lists and a word boundary: `struct[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[^{]*\b(IEvent|IComponentData)\b`. This rejects `IEventBus` and matches `struct Bar : IDisposable, IEvent`. Keep the existing `/Ecs/` path branch as an OR.
   - (b) ecs gate after `source _lib.sh`, redirectable for tests:
     ```bash
     UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/project-features.json}"
     [ "$(jq -r '.ecs // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0
     ```
   - (c) After FILE_PATH guards: `should_skip_path "$FILE_PATH" && exit 0`.
   - (d) Inline `_hook_log` fix: add `mkdir -p "$(dirname "$log")"` before the first `>> "$log"`.
2. [ ] **check-no-runtime-instantiate.sh**: after the existing test-file skip (≈ line 44) add `should_skip_path "$FILE_PATH" && exit 0`. Inline `_hook_log` mkdir fix.
3. [ ] **check-input-system.sh**: after the `/Editor/` skip (≈ line 49) add `should_skip_path "$FILE_PATH" && exit 0`. Inline `_hook_log` mkdir fix.
4. [ ] **check-no-monobehaviour-in-services.sh**: add `Installer` to the skip whitelist (≈ line 37 group) and add `should_skip_path "$FILE_PATH" && exit 0`. Inline `_hook_log` mkdir fix.
5. [ ] Preserve each hook's `HOOK_PROFILE_LEVEL` line and its position before `source`.

**Note on intentional coverage change:** `should_skip_path` adds `Tests/Test/Spec/` skipping to `check-no-runtime-instantiate` (which previously only skipped `EditModeTest|PlayModeTest`). Net effect: a `new GameObject()` inside the project's own test code is now allowed. This is intentional — test code legitimately constructs objects. Recorded here so it is not a silent regression.

**Verification:** bats (T5). Manual clean-env re-run against `nile_hole_incremental_repo`: previously-blocked files now pass (before/after exit-code diff).

**Code Skeleton (check-enum-byte-base.sh, abbreviated, correct order):**
```bash
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"
UNITY_FEATURES_FILE="${UNITY_FEATURES_FILE:-$(git rev-parse --show-toplevel 2>/dev/null)/.claude/project-features.json}"
[ "$(jq -r '.ecs // false' "$UNITY_FEATURES_FILE" 2>/dev/null)" = "true" ] || exit 0

INPUT=$(cat); FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
echo "$FILE_PATH" | grep -qE '\.cs$' || exit 0
[ -f "$FILE_PATH" ] || exit 0
should_skip_path "$FILE_PATH" && exit 0

grep -qE 'struct[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[^{]*\b(IEvent|IComponentData)\b' "$FILE_PATH" \
  || echo "$FILE_PATH" | grep -qE '/Ecs/' || exit 0
# … existing byte-base enum scan …
```

**Acceptance Criteria:**
- All 39 previously-blocked real files (4 + 10 + 12 + 13) return exit 0 when re-scanned in a clean env.
- Each `violating/` fixture still returns exit 2 — INCLUDING `MultiIfaceEvent.cs` (multi-interface struct).
- With `UNITY_FEATURES_FILE` pointing at a temp `{"ecs":true}`, `RealEnumEvent.cs` blocks (exit 2); with `{"ecs":false}` it returns exit 0. (This is now testable because the path is env-redirectable.)
- `AudioInstaller.cs` (legit) returns exit 0 from `check-no-monobehaviour-in-services`.

---

## Task 4 — POSIX-ify regex in touched hooks

**Files:** the 4 hooks from T3 (regex lines only).

**Steps:**
1. [ ] In the 4 touched hooks, replace non-POSIX escapes: `\s` → `[[:space:]]`, `\w` → `[[:alnum:]_]`, BRE literal-`?` matches → `grep -E` with `[?]`.
2. [ ] Repo-wide audit: record every remaining hook still using `\s`/`\w`/`\?` in a `## Known non-POSIX regex (follow-up)` section of `.github/workflows/README.md`. Full sweep of all 16 hooks is a follow-up, not this task.

**Verification:** `grep -REn '\\(s|w)' .claude/hooks/<touched>.sh` returns nothing for the 4 touched hooks. bats (T5) confirms behavior unchanged on GNU grep.

**Acceptance Criteria:**
- The 4 touched hooks contain no `\s`/`\w`/`\?` in grep patterns.
- A documented list of remaining offenders exists.
- **Honesty note:** GNU grep (CI ubuntu) supports `\s`/`\?`, so CI will NOT catch a regression here — this task is portability hardening verified by code audit, not by the CI matrix. A ugrep CI matrix is an explicit follow-up.

---

## Task 5 — bats tests (two-arm control)

**Files:**
- `.claude/hooks/tests/check-enum-byte-base.bats` (new)
- `.claude/hooks/tests/check-no-runtime-instantiate.bats` (new)
- `.claude/hooks/tests/check-no-monobehaviour-in-services.bats` (new)
- `.claude/hooks/tests/check-legacy-input.bats` (modify — add third-party exclusion cases)

**Steps:**
1. [ ] Follow the existing convention: `setup()` exports `UNITY_HOOK_STATE_DIR=$(mktemp -d)`, `cd "$BATS_TEST_DIRNAME/../../.."`, build a `mktemp -d` fixture tree, copy fixtures to their required relative paths (per `fixtures/README.md`), `run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"`, assert `$status`.
2. [ ] Per hook: ≥1 **negative control** (legit fixture → `status -eq 0`) and ≥1 **positive control** (violating fixture → `status -eq 2`). For `check-legacy-input.bats`, add: a `/Plugins/` path with `Input.GetKey` → `status -eq 0` (third-party exclusion).
3. [ ] `check-enum-byte-base.bats`: use the new `UNITY_FEATURES_FILE` override. Cases:
   - `UNITY_FEATURES_FILE=<temp {"ecs":false}>` + `RealEnumEvent.cs` → `status -eq 0` (gate skips).
   - `UNITY_FEATURES_FILE=<temp {"ecs":true}>` + `RealEnumEvent.cs` → `status -eq 2`.
   - `UNITY_FEATURES_FILE=<temp {"ecs":true}>` + `MultiIfaceEvent.cs` → `status -eq 2` (multi-interface).
   - `UNITY_FEATURES_FILE=<temp {"ecs":true}>` + `EventBusEnum.cs` → `status -eq 0` (IEventBus + plain enum must NOT block).
4. [ ] Run hooks under a controlled `PATH=/usr/bin:/bin` inside the `run` so an aliased `grep` (ugrep) cannot leak — mirrors the real fresh-bash hook env. Verified `/usr/bin/{git,jq}` exist on both macOS and ubuntu-latest, so the clean PATH does not break the hooks' own deps. Document why in a comment.

**Verification:** `bash .claude/hooks/tests/run-tests.sh` passes locally.

**Acceptance Criteria:**
- Each of the 4 hooks has ≥1 negative + ≥1 positive control; enum hook additionally covers the ecs on/off, multi-interface, and IEventBus-non-match cases.
- Tests go red if any T3 fix is reverted (verify by temporarily reverting one fix locally).
- All existing bats tests still pass.

---

## Task 6 — CI gate

**Files:** `.github/workflows/hook-tests.yml` (new), `.github/workflows/README.md` (modify)

**Steps:**
1. [ ] New workflow on `pull_request` and `push` to `main`. `ubuntu-latest`.
2. [ ] Steps: `actions/checkout@v4`; install **bats-core** via `npm install -g bats` (NOT `apt-get install bats`, which is the obsolete 0.4 fork incompatible with the repo's bats-core conventions); install `shellcheck` (`sudo apt-get install -y shellcheck`); run `bash .claude/hooks/tests/run-tests.sh`; run `shellcheck .claude/hooks/*.sh` with a documented failing-on-new-issues policy (do not blanket-`|| true`).
3. [ ] Keep separate from `claude-pr-review.yml`.
4. [ ] Update workflows README: describe the gate + local-run instructions.

**Verification:** Draft PR shows a green `hook-tests` check; a deliberate hook break on a scratch branch turns it red.

**Acceptance Criteria:**
- PRs show a `hook-tests` check.
- A reverted T3 fix turns the check red.
- bats-core (not apt 0.4) is used; shellcheck step runs with stated policy.

---

## Task 7 — bats-core install ergonomics

**Files:** `Brewfile` (new), `.github/workflows/README.md` (local-dev note added in T6)

**Steps:**
1. [ ] `Brewfile` with `brew "bats-core"` and `brew "shellcheck"` → local devs run `brew bundle`.
2. [ ] One-line "run hook tests locally" note pointing at `run-tests.sh`.

**Verification:** `brew bundle --file=Brewfile` (manual, macOS).

**Acceptance Criteria:**
- `Brewfile` installs both tools (bats-core, not the 0.4 fork).
- Local-dev instructions exist.

---

## Out of Scope (explicit follow-ups)

- `get_content()` / input-contract unification across hooks (dropped from this plan — the 4 touched hooks read from disk consistently).
- Centralizing all 49 hooks' inline `_hook_log` into a shared `unity_hook_audit_log` (only the 4 touched hooks get the inline `mkdir` fix here).
- Full POSIX sweep of all 16 `\s`/`\w` hooks (only the 4 touched hooks fixed; rest documented).
- A committed fixture **Unity project** — this plan uses small per-hook `.cs` fixtures, sufficient for hook tests.
- A ugrep CI matrix job to catch grep-flavor regressions.
- Python graph-script pytest coverage (separate plan).
- settings.json is NOT touched — all 4 fixes modify already-registered hooks; no manual registration step required.
