# PLAN — Agent Report Fixes (7 Issues)

> **Version:** v2 — 2026-05-26
> **Status:** Active
> **Scope:** `.claude/hooks/*.sh`, `.claude/rules/*.md`, `.claude/docs/quick-start.md`, `.claude/project-features.json`, `.claude/settings.json` (template repo configuration only — no Unity C# code touched)

## Revision Note — v2 (2026-05-26)

T1 has been **substantially expanded** based on a deeper architectural finding: subagent `Write`/`Edit` calls do NOT trigger `PostToolUse` hooks in the main session — only inside the subagent's own sandbox. A path-bug fix alone leaves the verification pipeline blind whenever orchestrated agents (`/orchestrate`, `/implement`, `/fix`) perform the writes, which is the common case in this template.

To close that gap, v2 adopts the **ECC accumulator + Stop hook** pattern (mirrors the ECC project's "Record edited file paths for batch typecheck at Stop time" rule):

1. **T1** still fixes the JSON path bug in `verify-after-write.sh`, but also wires the hook into the shared `unity_track_edit` accumulator so every successful Write/Edit (main session) appends to `$UNITY_EDITS_FILE` (`.claude/state/session-edits.txt`).
2. **T1b (NEW)** introduces `stop-verify.sh` — a Stop hook that drains `$UNITY_EDITS_FILE` at session end and batch-verifies every accumulated path: `bash -n` for `.sh`, `jq .` for `.json`, and `dotnet build` for `.cs` only if a `.sln` is found. Exits 0 always (advisory). Runs AFTER `session-save.sh` (so session-save reads the accumulator first, then stop-verify truncates it).
3. **T3 (UPDATED)** now covers TWO manual `settings.json` insertions: the existing `graph-auto-update.sh` PostToolUse wiring AND the new `stop-verify.sh` Stop entry.

Reuses the existing `$UNITY_EDITS_FILE` accumulator from `_lib.sh` rather than introducing a parallel variable — `session-save.sh` already reads this file, so no schema drift. `stop-verify.sh` is placed AFTER `session-save.sh` in the Stop array so session-save reads the accumulator before stop-verify truncates it.

T2, T4, T5, T6, T7 are unchanged.

## Context

A 3-agent code review of the Claude Code Unity template repository surfaced 8 distinct issues spanning hook shell scripts, optional-feature defaults, coding-rule documentation, and onboarding guidance. One item (transform cache rule) was dropped after reviewer pass: updating only `performance.md` would contradict `check-no-hotpath-expensive-calls.sh` and `hooks-warning.md`. That task is deferred to a separate plan.

Two categories of risk drive the remaining fixes:

1. **Correctness bugs that silently break enforcement:** `verify-after-write.sh` reads the wrong JSON path (`.path // .file_path`) instead of the canonical `.tool_input.file_path`, so the compile-check never runs. Further, `PostToolUse` is invisible to the main session when a subagent does the writing — addressed by the new Stop-hook batch verifier (T1b). `graph-auto-update.sh` exists but is not wired into `settings.json`. `check-enum-byte-base.sh` has a misleading header comment claiming `Exit 0` while the script does `exit 2`.

2. **Missing or outdated guidance:** `project-features.json` defaults `testing: false`. `unity-async.md` shows `.Forget()` without the safe exception-handler variant. `unity-lifecycle.md` has no DOTween cleanup guidance. `docs/quick-start.md` has no Troubleshooting section.

One constraint shapes the plan: `.claude/settings.json` is protected by `check-config-protection.sh` — Claude cannot edit it. T3 is a MANUAL STEP covering both new hook entries. All other fixes are fully automatable.

## Goals

- [ ] T1 — Fix `verify-after-write.sh` to read `.tool_input.file_path`, and append every verified path to `$UNITY_EDITS_FILE` via `unity_track_edit`.
- [ ] T1b — Create `.claude/hooks/stop-verify.sh` — Stop hook that drains `$UNITY_EDITS_FILE` and runs syntax/structure checks per file extension.
- [ ] T2 — Fix the misleading header comment in `check-enum-byte-base.sh`.
- [ ] T3 — MANUAL STEP: add BOTH `graph-auto-update.sh` (PostToolUse) AND `stop-verify.sh` (Stop) to `settings.json`.
- [ ] T4 — Add the safe `.Forget(ex => ...)` pattern to `unity-async.md`.
- [ ] T5 — Add a DOTween Cleanup subsection to `unity-lifecycle.md`.
- [ ] T6 — Flip `testing: false` → `testing: true` in `project-features.json`.
- [ ] T7 — Add `## Troubleshooting` section to `quick-start.md`.

## Chosen Approach

**Parallel groups by file domain.** T1 (edits `verify-after-write.sh`) and T1b (creates new `stop-verify.sh`) touch different files with no compile-time type dependency — both in `parallel_group 1`. T2, T4, T5, T6, T7 are also independent — all `parallel_group 1`. T3 is sequential (manual user step), placed in Phase 2 and covers BOTH settings.json entries.

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — verify-after-write.sh path fix + accumulator wiring | ⏳ Pending | 1 |
| 1 | T1b — Create stop-verify.sh (Stop hook batch verifier) | ⏳ Pending | 1 |
| 1 | T2 — check-enum-byte-base.sh header comment fix | ⏳ Pending | 1 |
| 1 | T4 — unity-async.md `.Forget(ex => ...)` pattern | ⏳ Pending | 1 |
| 1 | T5 — unity-lifecycle.md DOTween cleanup section | ⏳ Pending | 1 |
| 1 | T6 — project-features.json `testing: true` default | ⏳ Pending | 1 |
| 1 | T7 — quick-start.md Troubleshooting section | ⏳ Pending | 1 |
| 2 | T3 — MANUAL STEP: settings.json (graph-auto-update + stop-verify) | ⏳ Pending (User) | — |

## File Map

| File | Change Type | Notes |
|------|-------------|-------|
| `.claude/hooks/verify-after-write.sh` | Edit (~6 lines) | Fix jq path; source `_lib.sh`; call `unity_track_edit "$FILE_PATH"` on non-empty path |
| `.claude/hooks/stop-verify.sh` | **NEW FILE** (~60 lines) | Stop hook. Reads `$UNITY_EDITS_FILE`, dedupes, dispatches per extension. Truncates after drain. Exit 0 always. |
| `.claude/hooks/check-enum-byte-base.sh` | Edit (1 line, comment) | Fix header: "Exit 0 — warning" → "Exit 2 — blocking" |
| `.claude/settings.json` | **MANUAL** (~14 lines, two blocks) | PostToolUse: graph-auto-update; Stop: stop-verify — Claude cannot write this file |
| `.claude/rules/unity-async.md` | Edit (additive, ~10 lines) | Expand Fire-and-Forget with `.Forget(ex => ...)` |
| `.claude/rules/unity-lifecycle.md` | Edit (additive, ~20 lines) | Insert `## DOTween Cleanup` between `## Time` and `## Transform` |
| `.claude/project-features.json` | Edit (1 line) | `"testing": false` → `"testing": true` |
| `.claude/docs/quick-start.md` | Edit (additive, ~35 lines) | Append `## Troubleshooting` with 6 subsections |

> **Why no `_lib.sh` change?** `unity_track_edit` and `UNITY_EDITS_FILE` already exist in `_lib.sh`. Reusing them keeps a single accumulator that `session-save.sh` and `stop-verify.sh` both read — no schema drift.

---

## Task T1 — Fix verify-after-write.sh JSON Path + Wire Edit Accumulator

**Files:**
- `.claude/hooks/verify-after-write.sh`

**Why expanded:** The original 1-line path fix is necessary but insufficient. `PostToolUse` hooks only fire in the session that owns the tool call — subagents spawned by `/orchestrate`, `/implement`, `/fix`, etc. trigger hooks inside their own sandbox, not in the main session. The ECC pattern closes this gap: record every successful Write/Edit path into the shared accumulator (`$UNITY_EDITS_FILE`), then drain it in a Stop hook (T1b) where the main session always gets control.

**Steps:**
1. [ ] Open `verify-after-write.sh`.
2. [ ] Add `set -euo pipefail` and source `_lib.sh` near the top so `unity_track_edit` and `$UNITY_EDITS_FILE` are available:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   HOOK_PROFILE_LEVEL="standard"
   source "${SCRIPT_DIR}/_lib.sh"
   ```
3. [ ] Locate the line: `FILE_PATH=$(echo "$INPUT" | jq -r '.path // .file_path // ""' 2>/dev/null || true)`.
4. [ ] Replace it with: `FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)`.
5. [ ] Immediately after the FILE_PATH assignment, accumulate the path:
   ```bash
   if [[ -n "$FILE_PATH" ]]; then
       unity_track_edit "$FILE_PATH"
   fi
   ```
6. [ ] Leave the existing `.cs`-only `dotnet build` block intact for immediate main-session feedback.
7. [ ] Verify: `bash -n .claude/hooks/verify-after-write.sh` exits 0.

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# PostToolUse hook — accumulates edited file paths for the Stop-time batch
# verifier, and (for main-session .cs writes) runs an immediate dotnet build.
# Exit 0 always (warning mode — never blocks pipeline).
# NOTE: PostToolUse does NOT fire in the main session for subagent writes.
# The Stop hook (stop-verify.sh) closes that gap via $UNITY_EDITS_FILE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# Record path for Stop-time batch verification (regardless of extension).
if [[ -n "$FILE_PATH" ]]; then
    unity_track_edit "$FILE_PATH"
fi

# Immediate-feedback compile check (main-session .cs edits only).
if [[ "$FILE_PATH" != *.cs ]]; then
    exit 0
fi

FEATURES=".claude/project-features.json"
PROJECT_FOLDER="."
if [[ -f "$FEATURES" ]]; then
    PROJECT_FOLDER=$(jq -r '.unity_project_folder // "."' "$FEATURES" 2>/dev/null || echo ".")
fi

SLN=$(find "$PROJECT_FOLDER" -maxdepth 2 -name "*.sln" 2>/dev/null | head -1)
if [[ -z "$SLN" ]]; then
    echo "[verify-after-write] No .sln found — skipping compile check (Stop hook will retry)" >&2
    exit 0
fi

echo "[verify-after-write] Running dotnet build after write to: $FILE_PATH" >&2
ERRORS=$(dotnet build "$SLN" -v q 2>&1 | grep -i " error " || true)
if [[ -n "$ERRORS" ]]; then
    echo "WARNING — Build errors detected after writing $FILE_PATH:" >&2
    echo "$ERRORS" >&2
fi

exit 0
```

**Acceptance Criteria:**
- `jq` call reads `.tool_input.file_path // empty` exactly.
- `_lib.sh` is sourced; `unity_track_edit` is called on any non-empty `FILE_PATH`.
- Smoke test: `echo '{"tool_input":{"file_path":"/tmp/foo.cs"}}' | bash .claude/hooks/verify-after-write.sh` → `.claude/state/session-edits.txt` contains `/tmp/foo.cs`.
- `bash -n` passes.

---

## Task T1b — Create stop-verify.sh (Stop Hook Batch Verifier)

**Files:**
- `.claude/hooks/stop-verify.sh` (**NEW FILE**)

**Why:** Subagent Write/Edit calls trigger `PostToolUse` only inside the subagent's sandbox — the main session's `verify-after-write.sh` never sees them. At Stop time the main session always has control. By draining the shared `$UNITY_EDITS_FILE` accumulator we get one batch verification pass covering every file written this session, regardless of which agent wrote it.

**Ordering note:** This hook must be registered AFTER `session-save.sh` in the `Stop` array. `session-save.sh` reads `$UNITY_EDITS_FILE` into `session.json` — `stop-verify.sh` then truncates it so the next session starts clean.

**Steps:**
1. [ ] Create `.claude/hooks/stop-verify.sh` with the body in the Code Skeleton.
2. [ ] `chmod +x .claude/hooks/stop-verify.sh`.
3. [ ] Verify: `bash -n .claude/hooks/stop-verify.sh` exits 0.
4. [ ] Smoke test (good path): append a `.sh` path to `.claude/state/session-edits.txt`, run `echo '' | bash .claude/hooks/stop-verify.sh`, confirm `verified=1 warnings=0` logged and file is truncated.
5. [ ] Smoke test (warn path): append a nonexistent `.json` path, run again, confirm `verified=0 warnings=0` (skipped — file not found) and file is truncated.
6. [ ] T3 covers wiring into `settings.json` — manual user step.

**Test Type:** NoTest

**Code Skeleton:**
```bash
#!/usr/bin/env bash
# ============================================================================
# stop-verify.sh — STOP HOOK (batch verifier)
# Drains $UNITY_EDITS_FILE at session end and runs per-extension verifiers
# on every file written this session — including writes performed by subagents
# whose PostToolUse hooks never fired in the main session (ECC pattern).
# ============================================================================
# Trigger:  Stop
# Exit:     0 always (advisory — never blocks)
# Ordering: Must be AFTER session-save.sh in the Stop array.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"

# Drain stdin (Stop hooks receive a JSON event payload we don't need here).
cat > /dev/null || true

if [[ ! -s "$UNITY_EDITS_FILE" ]]; then
    exit 0  # nothing to verify this session
fi

# Snapshot + deduplicate before truncating.
TMP_LIST="${UNITY_HOOK_STATE_DIR}/stop-verify-batch.txt"
sort -u "$UNITY_EDITS_FILE" > "$TMP_LIST" || true
: > "$UNITY_EDITS_FILE"   # truncate — next session starts clean

FEATURES=".claude/project-features.json"
PROJECT_FOLDER="."
if [[ -f "$FEATURES" ]]; then
    PROJECT_FOLDER=$(jq -r '.unity_project_folder // "."' "$FEATURES" 2>/dev/null || echo ".")
fi
SLN=$(find "$PROJECT_FOLDER" -maxdepth 2 -name "*.sln" 2>/dev/null | head -1 || true)

VERIFIED=0
WARNINGS=0

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ ! -f "$path" ]] && continue   # file deleted/moved — skip silently

    case "$path" in
        *.sh)
            if ! bash -n "$path" 2>&1; then
                echo "[stop-verify] WARNING syntax error in $path" >&2
                WARNINGS=$((WARNINGS + 1))
            fi
            VERIFIED=$((VERIFIED + 1))
            ;;
        *.json)
            if ! jq . "$path" > /dev/null 2>&1; then
                echo "[stop-verify] WARNING malformed JSON in $path" >&2
                WARNINGS=$((WARNINGS + 1))
            fi
            VERIFIED=$((VERIFIED + 1))
            ;;
        *.cs)
            VERIFIED=$((VERIFIED + 1))
            ;;
    esac
done < "$TMP_LIST"

# One batched dotnet build for all accumulated .cs files (if .sln exists).
if [[ -n "$SLN" ]] && grep -q '\.cs$' "$TMP_LIST" 2>/dev/null; then
    CS_COUNT=$(grep -c '\.cs$' "$TMP_LIST" || true)
    echo "[stop-verify] batch dotnet build for ${CS_COUNT} .cs file(s)" >&2
    ERRORS=$(dotnet build "$SLN" -v q 2>&1 | grep -i " error " || true)
    if [[ -n "$ERRORS" ]]; then
        echo "[stop-verify] WARNING build errors at Stop:" >&2
        echo "$ERRORS" >&2
        WARNINGS=$((WARNINGS + 1))
    fi
elif grep -q '\.cs$' "$TMP_LIST" 2>/dev/null; then
    echo "[stop-verify] skip .cs files — no .sln found under '$PROJECT_FOLDER'" >&2
fi

echo "[stop-verify] verified=${VERIFIED} warnings=${WARNINGS}" >&2
exit 0
```

**Acceptance Criteria:**
- `.claude/hooks/stop-verify.sh` exists and is executable (`test -x` passes).
- `bash -n` passes.
- When `$UNITY_EDITS_FILE` is empty/missing, hook exits 0 with no output.
- A `.sh` file with a syntax error produces a WARNING line on stderr; exit is still 0.
- A malformed `.json` file produces a WARNING line on stderr; exit is still 0.
- `.cs` files are batched into ONE `dotnet build` call — not one per file.
- After a successful drain, `$UNITY_EDITS_FILE` is empty (truncated).
- `session-save.sh` runs BEFORE `stop-verify.sh` in the Stop array (enforced by T3 manual step ordering).

---

## Task T2 — Fix check-enum-byte-base.sh Header Comment

**Files:**
- `.claude/hooks/check-enum-byte-base.sh`

**Steps:**
1. [ ] Open `check-enum-byte-base.sh`.
2. [ ] Locate the header comment: `# Exit 0 — warning only (does not block writes).`.
3. [ ] Replace it with: `# Exit 2 — blocking. Enums in ECS/IEvent context MUST inherit from byte (non-negotiable per rules/ecs-dots.md).`.
4. [ ] Confirm the script still does `exit 2` on violation (do NOT change the exit code — it is correct).
5. [ ] Verify: `bash -n .claude/hooks/check-enum-byte-base.sh` exits 0.

**Test Type:** NoTest

**Code Skeleton:**
```bash
# BEFORE
# Exit 0 — warning only (does not block writes).

# AFTER
# Exit 2 — blocking. Enums in ECS/IEvent context MUST inherit from byte (non-negotiable per rules/ecs-dots.md).
```

**Acceptance Criteria:**
- Header comment accurately describes `exit 2` behaviour.
- No executable code paths changed.
- `bash -n` passes.

---

## Task T3 — MANUAL STEP: Wire graph-auto-update.sh AND stop-verify.sh into settings.json

**Files:**
- `.claude/settings.json` (USER MUST EDIT — Claude cannot write this file)

**Steps:**
1. [ ] **Claude:** Show this MANUAL STEP block to the user with the exact JSON blocks.
2. [ ] **User:** Open `.claude/settings.json` in a non-Claude editor.
3. [ ] **Block 1 (PostToolUse):** Find the `"PostToolUse": [` array. Insert Block 1 below just before the `verify-after-write.sh` entry.
4. [ ] **Block 2 (Stop):** Find the `"Stop": [` array. Insert Block 2 as a new entry AFTER the existing `session-save.sh` entry (so session-save runs first and reads the accumulator, then stop-verify truncates it).
5. [ ] **User:** Validate: `jq . .claude/settings.json > /dev/null` — must exit 0.
6. [ ] **User:** Restart Claude Code.

**Test Type:** NoTest

**Code Skeleton — Block 1 (PostToolUse, before verify-after-write.sh):**
```json
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/graph-auto-update.sh",
            "timeout": 10000,
            "statusMessage": "Updating knowledge graph..."
          }
        ]
      },
```

**Code Skeleton — Block 2 (Stop, AFTER session-save.sh):**
```json
      {
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/stop-verify.sh",
            "timeout": 30000,
            "statusMessage": "Verifying session edits..."
          }
        ]
      }
```

> **Key:** Stop hooks do NOT have a `"matcher"` field — they run unconditionally at session end.
> **Ordering:** Block 2 must come AFTER `session-save.sh` in the Stop array — session-save reads `$UNITY_EDITS_FILE`, then stop-verify truncates it.
> **Why MANUAL:** `check-config-protection.sh` blocks all `Write`/`Edit` to `settings.json`. Per CLAUDE.md: *"User must add hook entries manually after any new hook is created."*

**Acceptance Criteria:**
- `jq . .claude/settings.json > /dev/null` succeeds.
- Block 1 in `PostToolUse` before `verify-after-write.sh`, matcher `Write|Edit`, timeout 10000.
- Block 2 in `Stop` AFTER `session-save.sh`, no matcher field, timeout 30000.
- After next Write/Edit: `.claude/state/graph-updates.log` shows a new line.
- After session end: stderr shows `[stop-verify] verified=N warnings=M` and `.claude/state/session-edits.txt` is empty.

---

## Task T4 — Add `.Forget(ex => ...)` Pattern to unity-async.md

**Files:**
- `.claude/rules/unity-async.md`

**Steps:**
1. [ ] Open `unity-async.md`.
2. [ ] Locate the `## Fire-and-Forget` heading.
3. [ ] Replace the entire Fire-and-Forget section with the block in the Code Skeleton.
4. [ ] Preserve a blank line before `## CancellationToken — Mandatory Pattern`.
5. [ ] Save.

**Test Type:** NoTest

**Code Skeleton:**
```markdown
## Fire-and-Forget

`.Forget()` discards the returned `UniTask` so the call site doesn't have to `await`. **Naked `.Forget()` swallows every exception** — including `NullReferenceException` from destroyed objects. Always pair it with an exception handler.

```csharp
// BAD — silently swallows all exceptions, impossible to debug
InitializeAsync(ct).Forget();

// BAD — async void cannot be awaited or cancelled
async void Initialize() { }

// GOOD — log unexpected failures, ignore expected cancellations
InitializeAsync(ct).Forget(ex =>
{
    if (ex is OperationCanceledException) return;
    Debug.LogException(ex);
});
```

If a method is genuinely throw-proof (e.g. only `await UniTask.Yield()`), a bare `.Forget()` is acceptable — leave a `// safe: throw-proof body` comment.
```

**Acceptance Criteria:**
- Section contains three examples: bad bare `.Forget()`, bad `async void`, good `.Forget(ex => ...)`.
- `OperationCanceledException` is handled separately in the good example.
- Markdown renders cleanly.

---

## Task T5 — Add DOTween Cleanup Section to unity-lifecycle.md

**Files:**
- `.claude/rules/unity-lifecycle.md`

**Steps:**
1. [ ] Open `unity-lifecycle.md`.
2. [ ] Locate the end of `## Time` section (last bullet about `Time.unscaledDeltaTime`).
3. [ ] Insert the Code Skeleton block between `## Time` and `## Transform`.
4. [ ] Single blank line on each side of the new heading.
5. [ ] Save.

**Test Type:** NoTest

**Code Skeleton:**
```markdown
## DOTween Cleanup

DOTween tweens hold a strong reference to their target. If the target `GameObject` is destroyed while a tween runs, DOTween will NRE on the next tick or silently leak. Always kill tweens explicitly.

```csharp
public sealed class FadeView : MonoBehaviour
{
    private Tween _activeTween;

    private void OnDisable()
    {
        _activeTween?.Kill();
        _activeTween = null;
    }

    private void OnDestroy()
    {
        transform.DOKill();
        gameObject.DOKill();
    }
}
```

Rules:
- `tween?.Kill()` if you cache the `Tween` reference (preferred — surgical).
- `transform.DOKill()` / `gameObject.DOKill()` as a safety net in `OnDestroy`.
- Never rely on `SetLink(gameObject)` alone — explicit `Kill()` is auditable.
- For re-issued tweens (hover animations), kill the previous before assigning a new one.
```

**Acceptance Criteria:**
- `## DOTween Cleanup` section sits between `## Time` and `## Transform`.
- Code example covers `OnDisable` (cached tween) and `OnDestroy` (blanket `DOKill()`).
- No other section reordered or rewritten.

---

## Task T6 — Default `testing: true` in project-features.json

**Files:**
- `.claude/project-features.json`

**Steps:**
1. [ ] Change `"testing": false` to `"testing": true`.
2. [ ] Validate: `jq . .claude/project-features.json > /dev/null` exits 0.
3. [ ] Save.

**Test Type:** NoTest

**Code Skeleton:**
```json
{
  "addressables": false,
  "testing": true,
  "ecs": false,
  "graph": true,
  "unity_project_folder": "."
}
```

**Acceptance Criteria:**
- `jq -r '.testing' .claude/project-features.json` returns `true`.
- JSON well-formed, no other keys changed.

---

## Task T7 — Add Troubleshooting Section to quick-start.md

**Files:**
- `.claude/docs/quick-start.md`

**Steps:**
1. [ ] Append the Code Skeleton block at the end of `quick-start.md` (one blank line before).
2. [ ] Save.

**Test Type:** NoTest

**Code Skeleton:**
```markdown

## Troubleshooting

### NSubstitute is not found / `using NSubstitute;` fails to resolve

NSubstitute is **not** distributed via the Package Manager — `/setup-project` cannot install it automatically. Manual steps:

1. Download `NSubstitute.dll` and `Castle.Core.dll` from the NSubstitute releases page (or via NuGet → extract `lib/netstandard2.0/`).
2. Place both DLLs under `Assets/Plugins/NSubstitute/` (create the folder if missing).
3. In the Unity Inspector, restrict the DLLs to **Editor** platform only to avoid build errors.
4. Reference them from your test `.asmdef` via *Assembly Definition References*.

### Claude refuses to edit `.claude/settings.json`

This is intentional. `check-config-protection.sh` (PreToolUse) blocks every `Write`/`Edit` targeting `settings.json` to prevent accidental loss of the hook pipeline. To add or modify hook entries:

1. Open `.claude/settings.json` in a **non-Claude** editor (VS Code, vim, etc.).
2. Edit the `PostToolUse` / `PreToolUse` / `Stop` array directly.
3. Validate with `jq . .claude/settings.json > /dev/null` before saving.
4. Restart Claude Code so the new hook configuration is picked up.

### I created a new hook but it doesn't run

After dropping a script into `.claude/hooks/`, you must:

1. `chmod +x .claude/hooks/<your-hook>.sh` — the harness only executes executable files.
2. Add a matching entry to `.claude/settings.json` manually (see previous item).
3. Restart Claude Code.

### `/setup-project` did not generate test folders

Check `.claude/project-features.json`: `"testing"` must be `true`. The default ships as `true` (since 2026-05-26). If you opted out, flip the flag and re-run the scaffold steps from `/setup-project`.

### The knowledge graph isn't updating after edits

Confirm: (1) `.claude/project-features.json` has `"graph": true`; (2) `.claude/settings.json` includes a PostToolUse entry for `.claude/hooks/graph-auto-update.sh` (add manually if missing); (3) `.claude/graph/graph-builder.sh` is executable. After an edit, check `.claude/state/graph-updates.log` for a new line.

### Subagent edits aren't being verified at write time

This is by design. `PostToolUse` hooks only fire in the session that owns the tool call — so `verify-after-write.sh` never sees writes performed by a subagent spawned by `/orchestrate`, `/implement`, `/fix`, etc. Instead, every successful Write/Edit is appended to `.claude/state/session-edits.txt` (the accumulator), and the `stop-verify.sh` Stop hook drains that accumulator at session end running `bash -n` / `jq .` / `dotnet build` per file extension. If you don't see a `[stop-verify] verified=N warnings=M` line at session end, confirm `stop-verify.sh` is in the `"Stop"` array of `settings.json` (see the hook-wiring item above) and is executable.
```

**Acceptance Criteria:**
- `## Troubleshooting` at end of `quick-start.md`.
- Contains 6 subsections including the new "Subagent edits aren't being verified at write time".
- No existing sections modified.
- Markdown renders cleanly.

---

## Cross-Cutting Verification

After all automatable tasks (T1, T1b, T2, T4, T5, T6, T7) complete, run from repo root:

```bash
bash -n .claude/hooks/verify-after-write.sh
bash -n .claude/hooks/stop-verify.sh
bash -n .claude/hooks/check-enum-byte-base.sh
test -x .claude/hooks/stop-verify.sh
jq . .claude/project-features.json > /dev/null
grep -n "tool_input.file_path" .claude/hooks/verify-after-write.sh
grep -n "unity_track_edit"     .claude/hooks/verify-after-write.sh
grep -n "UNITY_EDITS_FILE"     .claude/hooks/stop-verify.sh
grep -n "Exit 2 — blocking"    .claude/hooks/check-enum-byte-base.sh
grep -n "Forget(ex"            .claude/rules/unity-async.md
grep -n "DOTween Cleanup"      .claude/rules/unity-lifecycle.md
grep -n "Troubleshooting"      .claude/docs/quick-start.md
grep -n "Subagent edits"       .claude/docs/quick-start.md
```

Smoke-test the accumulator end-to-end:
```bash
rm -f .claude/state/session-edits.txt
echo '{"tool_input":{"file_path":"/tmp/dummy.sh"}}' | bash .claude/hooks/verify-after-write.sh
cat .claude/state/session-edits.txt          # should contain /tmp/dummy.sh
echo '' | bash .claude/hooks/stop-verify.sh  # should log "verified=… warnings=…" and truncate
cat .claude/state/session-edits.txt          # should be empty
```

Then present Task T3 (MANUAL STEP) with the exact JSON blocks (Block 1 PostToolUse + Block 2 Stop) and pause for user `done` reply.

## Out of Scope

- Transform cache rule — deferred (updating `performance.md` alone contradicts `check-no-hotpath-expensive-calls.sh` and `hooks-warning.md`).
- Renaming or restructuring any rule file — additive changes only.
- Introducing a separate `UNITY_VERIFY_FILES` accumulator — reuses `$UNITY_EDITS_FILE` to avoid schema drift.
- Migrating existing downstream projects' configs.
