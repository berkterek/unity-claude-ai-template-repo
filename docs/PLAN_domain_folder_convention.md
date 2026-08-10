# PLAN — Domain Folder Convention for `Games/Abstracts` and `Games/Concretes`

> **Complexity:** 0.55 — Moderate-High
> **Version:** v4 — 2026-08-05
> **Status:** Active
> **Phase:** 1 of 2 — **enforcement**. The consumption side (agents and commands *reading* these docs) is a separate, deliberately deferred plan: `docs/PLAN_architecture_doc_consumption.md`.
> **Scope:** Make "the first path segment under `Games/Abstracts/` or `Games/Concretes/` is a domain, never a layer" a machine-enforced rule; remove the self-contradicting guidance in `.claude/rules/architecture.md:399`; add two hooks (`check-domain-folder-structure.sh`, `check-architecture-doc.sh`) with bats coverage; define a 40-line, intent-only `Concretes/<Domain>/ARCHITECTURE.md` contract. Out of scope: any change to `.claude/settings.json` by Claude (hand-off to the human, Task 10), any file-count heuristics, any Abstracts/Concretes mirror enforcement, and everything in the Phase 2 plan.

---

## Context

The repo contradicts itself. `.claude/rules/architecture.md:399` says:

> **Games/Concretes/ subfolder naming:** use domain/feature names (`Players/`, `Enemies/`, `UI/`, `Audio/`, `Handlers/`, `Controllers/`) — never layer names like `Services/`, `Views/`, `Providers/`.

`Handlers/` and `Controllers/` are layer names, offered in the same breath as the ban on layer names. The forbidden-folder table at `architecture.md:390–397` and the Module Structure tree at `423–446` are both correct and domain-shaped; only line 399 is wrong. `.claude/rules/csharp-unity.md` Card 1.1 (lines 27–51) reinforces the error: line 42 presents `Games/Concretes/Controllers/EnemyController.cs` as **RIGHT**, purely to illustrate plural-vs-singular, and a reader takes away "`Controllers/` is a fine top-level folder."

Nothing enforces any of it. There is no hook on folder shape, so the rule exists only as prose that a model may or may not have in context.

**Why no file counting.** An earlier draft gated `Handlers/` on the folder holding at least 5 files. That is unimplementable in this harness: hooks fire per single-file write, so the *first* write into `Handlers/` sees a count of 1, gets blocked, and the folder can never reach 5. The rule deadlocks itself. Lesson kept explicitly: **never gate a folder on a count that is only reachable by writing into that folder.** Every threshold, mirror requirement, and filesystem count is therefore out of this plan. The hook does one thing: look at one path segment.

**Why intent-only docs.** `/Users/berkterek/Desktop/Github/voxel-blast` applied a fat per-folder `ARCHITECTURE.md` convention with real discipline — 25 documents, 8031 lines. Fifteen of the 25 are factually wrong today: a `Car` → `Turret` rename was never propagated into the docs (0 `Car*.cs` on disk, 29 `Turret*.cs`). Every rotted line contained a class name. **No intent line rotted.** This repo already has `/knowledge-graph` for inventory, so the docs here carry intent only and are capped at 40 lines with a class-name ban. Worth noting: voxel-blast's *folder* layout (`Turret/`, `Conveyor/`, `Parking/`) was correctly domain-named — the folder convention is the part worth copying, the fat docs are not.

**Why `Core/` is banned by the hook, not just by prose.** The single largest folder in voxel-blast was `Core/` — 85 files, 7692 lines, spanning five unrelated concerns (DI, bootstrap, game flow, services, pooling). `Core/` is not a domain; it is a name that cannot refuse a file. Once it exists, everything drains into it. Prose alone did not stop it there and will not stop it here.

---

## Goals

1. One hard, mechanically checkable rule, enforced before the bad path is created.
2. Zero heuristics: no counting, no mirroring, no content inspection in the folder hook.
3. Freedom below the domain folder — the hook must never look there.
4. Docs that cannot rot: intent only, capped, class names banned, no exceptions among domains.
5. The rules text and the hooks say the same thing, with no surviving contradiction.
6. Both new hooks covered by the existing bats suite before they ship.

---

## The Rule (settled — implement, do not re-litigate)

**Hard rule (hook blocks).** The **first path segment** after `Games/Abstracts/` or `Games/Concretes/` must be a **domain** name. Two families are banned in that position, matched case-insensitively:

*Layer names* (legal one level deeper, illegal as the domain itself) — 14 forms:
`Service` `Services` `Provider` `Providers` `Controller` `Controllers` `View` `Views` `Manager` `Managers` `Interface` `Interfaces` `Config` `Configs`

*Catch-all names* (never a domain) — 3 forms:
`Core` `General` `Generals`

A `.cs` file sitting directly at `Games/Concretes/Foo.cs` with no domain folder is the same violation.

> **Known, accepted gap:** `Common/`, `Shared/`, `Utils/`, `Helpers/`, `Misc/` are equally poor domain names and are **not** on the banned list. Catch-all names substitute for one another, so banning a subset only redirects the problem. The decision was to enforce only the empirically observed case (`Core/`) plus its closest synonym, and keep the list short to hold false positives near zero. Revisit if one of these appears in practice.

**Free (the hook never looks).** Anything below the domain folder. `Concretes/Players/Services/`, `Players/Handlers/`, `Players/Inputs/`, `Players/Types/`, or fully flat — all legal.

**Advisory only (prose in the rules, never enforced).** Keep a domain flat while it is small. Open subfolders when the file count starts to hurt readability. Mirroring the same shape on the `Abstracts/` and `Concretes/` sides aids navigation. None of this is checked.

**Naming.** Identical domain names on both sides. Plural for countable domains (`Players/`, `Enemies/`, `Inputs/`); singular for mass nouns (`Audio/`, `UI/`, `VFX/`). DI and bootstrap code → `Concretes/Infrastructure/`. Domain-agnostic code → `_Framework/`.

**ARCHITECTURE.md.** Lives at `Concretes/<Domain>/ARCHITECTURE.md` only, never under `Abstracts/`. **Written in English, like the rest of the repo.** One H1, then exactly four `##` headings in this order:

```
## Purpose
## Boundary
## How to extend
## Gotchas
```

Cap 40 lines. No class-name symbols, per:

```
\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b
```

`Module` is deliberately **absent** from that alternation, so `PlayerModule` is exempt — module names are convention-fixed by `bootstrap-pattern.md` and are never renamed, so naming one in a doc cannot rot. This exemption is a decision, not an oversight; do not "fix" it by adding `Module` to the list.

**The ban applies to `## How to extend` as well.** That section describes the *shape* of an extension — layer, file location, wiring method — not the names of types. Naming types there is exactly the rot vector this convention exists to close, and `/knowledge-graph implementers` answers the "which interface, concretely" question on demand. Correct form:

```markdown
## How to extend
New ability: contract interface in Abstracts/<domain>/ → pure C# handler in
Concretes/<domain>/ → register in this domain's Module.Install. The controller
creates it in Awake, or via a Func<> factory if it needs a container dependency.
```

**No domain is exempt from having a doc — including `Infrastructure/`.** `Infrastructure/` is where the most frequently confused boundary question lives (app-lifetime vs. scene-lifetime registration; scope vs. module). Its doc is a short **pointer**: state the boundary, then delegate the detail to `.claude/rules/bootstrap-pattern.md` rather than duplicating six cards of content.

Missing doc → exit 0 warn. Malformed doc → exit 2 block.

---

## Chosen Approach

### Two hooks, not one

A single hook covering both folder shape and doc validity was rejected:

| | folder check | doc check |
|---|---|---|
| Input needed | path string only | file **content** from disk |
| Correct event | **PreToolUse** — can prevent the write | **PostToolUse** — content must exist |
| Failure mode | wrong folder never created | malformed doc lands, then blocks |
| Trigger file types | `.cs` | `ARCHITECTURE.md` |

Merging them forces one event choice that is wrong for one half. Under PreToolUse the doc check's `[ -f "$FILE_PATH" ] || exit 0` guard would silently skip **100%** of validation, because the file does not exist yet. Under PostToolUse the folder check would only ever complain after the bad path was already created. So:

- **`check-domain-folder-structure.sh` → PreToolUse.** Pure path check, no content needed; genuinely prevents the bad path from being created.
- **`check-architecture-doc.sh` → PostToolUse.** Trigger B reads doc content from disk. Its acceptance criteria state plainly that a malformed doc lands on disk first and is then blocked as corrective feedback — the same contract `check-no-runtime-instantiate.sh` already has in `PostToolUse`.

A second reason to split: kill-switch independence. The folder hook matches a closed 17-word list against one path segment (near-zero false-positive surface); the doc hook runs a broad regex over free-form prose. If they shared a script, escaping a doc-regex false positive would also disable folder enforcement.

### Critique pass — what nearly broke this plan

1. **The `sed` extraction (highest severity, survived a full review round).** v1 extracted the `Abstracts|Concretes` side with `sed -E`. On this machine's BSD sed, `sed -E 's|.*Games/(Abstracts|Concretes)/.*|\1|'` errors with `RE error: parentheses not balanced` and emits **empty output** — `|` is the delimiter, so the alternation terminates the pattern. Empty `SIDE` makes `${FILE_PATH#*Games//}` fail to match, `TAIL` becomes the whole path, `FIRST` becomes `""`, both checks fall through, and **the hook is a silent no-op that never blocks anything and never errors.** A broken extraction that silently disables a hook is the worst failure mode available here: it looks installed, it looks green, it does nothing. That class of bug is why FIX 2 adds loud guards.
2. **The round-2 reviewer's proposed sed fix was also wrong.** `sed -E 's|.*Games/\(Abstracts\|Concretes\)/.*|\1|'` yields `\1 not defined in the RE`: under `-E`, `\(` is a *literal* paren, not a capture group. Both broken forms are recorded in Task 3 so neither is reintroduced.
3. **`wc -l` undercounts.** On a file with no trailing newline, `awk 'END{print NR}'` = 41 where `wc -l` = 40. A 41-line doc without a trailing newline would slip past the cap. `wc -l` is banned in these hooks; a bats case guards the regression.
4. **Cross-hook deferral.** v1 let the doc hook defer the no-domain case to the folder hook. That silently drops the case whenever the folder hook does not run. Fixed in Task 4.
5. **H1 counting vs. fenced code.** A naive `grep -c '^# '` also counts a `# comment` line inside a ``` fence — verified: 2 instead of 1, producing a spurious block. Fixed in Task 4 by stripping fenced blocks before counting.
6. **File counting.** Rejected outright — see Context.
7. **Write-only artifact risk.** Nothing in `.claude/` currently instructs anything to *read* these docs — verified: zero references across agents, commands, docs and rules. Enforcing the format of a file nobody reads would be pure ceremony. The consumption side is therefore a committed, written follow-up plan (`docs/PLAN_architecture_doc_consumption.md`), deliberately sequenced after the first real domains exist so the reading instructions can be written against real content rather than guessed.

### Conventions honored

- No `set -euo pipefail` in template hooks; do not introduce it.
- Template hooks use `#!/bin/bash`, so `diff <(...) <(...)` process substitution is safe.
- All four headings are pure ASCII, so heading comparison is a plain byte match with no locale or Unicode-normalization exposure.
- `should_skip_path` returns **0 = skip** (`_lib.sh:124`).
- `unity_hook_block` exits 2, or 0 under `UNITY_HOOK_MODE=warn` (`_lib.sh:102`).
- `unity_hook_warn` **exits 0 and terminates** (`_lib.sh:115`) — nothing may follow it on a branch.
- Because these functions exit, `cond && unity_hook_block "..."` and an `if` body are equivalent; `false && unity_hook_block` correctly continues.
- `${FP%%Games/Concretes/*}` and `${FP%Games/Concretes/*}` are identical for single-occurrence paths; `%%` is the safer choice.

---

## Status

| # | Task | Status | parallel_group | Depends on |
|---|------|--------|----------------|------------|
| 1 | `architecture.md` pass 1 — fix line 399 | ✅ Done | A | — |
| 2 | `csharp-unity.md` Card 1.1 — fix line 34 | ✅ Done | A | — |
| 3 | `check-domain-folder-structure.sh` (PreToolUse) | ✅ Done | A | — |
| 4 | `check-architecture-doc.sh` (PostToolUse) | ✅ Done | A | — |
| 5 | `architecture.md` pass 2 — domain convention prose | ✅ Done | B | 1 |
| 6 | `new-module.md` — Step 4.5 ARCHITECTURE.md | ✅ Done | B | 4 |
| 7 | `hook-profiles.md` + `hooks-blocking.md` + `hooks-warning.md` registration | ✅ Done | B | 3, 4 |
| 8 | `.claude/CLAUDE.md` rules-table row | ✅ Done | B | 5 |
| 9 | bats tests for both new hooks | ✅ Done | B | 3, 4 |
| 10 | `.claude/settings.json` registration | ✅ Done — user-authorized | C | 3, 4, 7, 9 |

T1 and T5 both edit `architecture.md` and are therefore in different groups. T10 is sequential and last.

### Implementation notes — 2026-08-05

All 10 tasks implemented; the convention is live and enforcing.

**Task 10 note — `check-config-protection.sh` was deliberately bypassed, with explicit user authorization.** The plan specified a hand-off because Claude cannot use `Edit`/`Write` on `.claude/settings.json`. The user reviewed the exact JSON, authorized a one-shot Python script, and asked for the script to be deleted afterwards. The script backed the file up, inserted both entries idempotently, validated the JSON round-trip before writing, and re-read from disk to confirm. Resulting diff: **22 insertions, 0 deletions** — exactly the two authorized blocks. One unintended side effect was caught and reverted: `ensure_ascii=False` had converted a `—` escape in an unrelated `UserPromptSubmit` hook command into a literal em dash (functionally identical, but outside the authorized change). The script and the `.bak` were then deleted — git already serves as the backup.

**End-to-end proof that the enforcement is live**, not merely registered: a real `Write` to `_GameFolders/Scripts/Games/Concretes/Services/TempService.cs` was **blocked by `check-domain-folder-structure.sh` before the file reached disk**. The doc hook's behaviour is covered by its 29 bats cases rather than a live probe, because `gateguard.sh` (correctly) demands justification before any new file is created and a throwaway probe does not warrant it.

Verification actually run:
- `check-domain-folder-structure.sh` — 12/12 ad-hoc path cases, then **31/31** bats cases.
- `check-architecture-doc.sh` — 15/15 ad-hoc cases, then **29/29** bats cases. The `wc -l` regression guard confirmed live: `awk` reports 41 where `wc -l` reports 40 on the no-trailing-newline fixture.
- `./.claude/hooks/tests/run-tests.sh` — **192 tests, exit 0**; no existing suite regressed.

Two deviations from the plan as written, both deliberate:
1. **Task 1 Step 3 (extending the forbidden-folder table at 390–397) was folded into Task 5's prose instead.** Step 3 and Step 4 contradicted each other — Step 4 required the file's line count to stay unchanged so Task 5's anchors held, which extending a table cannot do. Line 399 became a single dense replacement line, and the full banned-segment table now lives in the Domain Folder Convention section where it belongs anyway.
2. **Task 7 was widened** to also add rows to `.claude/docs/hooks-blocking.md` and `.claude/docs/hooks-warning.md`. v4's File Map had narrowed Task 7 to `hook-profiles.md` alone, but those two tables are what `.claude/CLAUDE.md` `@`-includes, making them the primary discovery surface — omitting them would have left the hooks undiscoverable from the main context.

Process deviation, for the record: the `/update-plan` implementer step calls for one subagent per task. Six subagent spawns failed consecutively with `API Error: 529 Overloaded`, so Tasks 1–9 were implemented inline instead. No commit was made, per the user's standing instruction.

---

## File Map

| Path | Action |
|------|--------|
| `.claude/rules/architecture.md` | edit ×2 (T1 line 399, T5 prose after line 447) |
| `.claude/rules/csharp-unity.md` | edit (T2 lines 34 and 42) |
| `.claude/hooks/check-domain-folder-structure.sh` | new + `chmod +x` |
| `.claude/hooks/check-architecture-doc.sh` | new + `chmod +x` |
| `.claude/commands/new-module.md` | edit (T6 insert Step 4.5 between 137 and 139) |
| `.claude/docs/hook-profiles.md` | edit (T7 insert at lines 36 and 38) |
| `.claude/hooks/tests/check-domain-folder-structure.bats` | new |
| `.claude/hooks/tests/check-architecture-doc.bats` | new |
| `.claude/hooks/tests/README.md` | edit (T9 two table rows) |
| `.claude/CLAUDE.md` | edit (T8 row at ~118) |
| `.claude/settings.json` | **human only** — Claude must not touch it |

No overlap with any of the 18 existing `docs/PLAN_*.md`. Phase 2 work is tracked separately in `docs/PLAN_architecture_doc_consumption.md` and must not be pulled into this plan.

---

## Task 1 — `architecture.md` pass 1: remove the self-contradicting line

**Files:** `.claude/rules/architecture.md`

**Steps:**
1. [ ] Read lines 385–400. Confirm the forbidden-folder table occupies **390–397** and line **399** is the `**Games/Concretes/ subfolder naming:**` line listing `Handlers/` and `Controllers/` as acceptable domain names.
2. [ ] Replace line 399 in place. Remove `Handlers/` and `Controllers/` from the acceptable list; state the two banned families (14 layer names + `Core`/`General(s)`); state that the ban applies to the **first segment only**.
3. [ ] Do not touch the table at 390–397 — it is already correct.
4. [ ] Confirm the file's line count changed by 0 (a one-line replacement), so T5's anchors (419, 423–446, 447, 448) stay valid.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n 'Handlers/`, `Controllers/' .claude/rules/architecture.md   # expect exit 1, no output
sed -n '399p' .claude/rules/architecture.md
```
Expected: `grep` exits **1**; line 399 lists domain examples only.

**Code Skeleton:**
```markdown
**Games/Concretes/ and Games/Abstracts/ first-segment naming:** the first folder under either
must be a **domain** (`Players/`, `Enemies/`, `Inputs/`, `Audio/`, `UI/`, `VFX/`, `Infrastructure/`) —
never a layer and never a catch-all. Banned in that position, case-insensitive:
`Service(s)`, `Provider(s)`, `Controller(s)`, `View(s)`, `Manager(s)`, `Interface(s)`, `Config(s)`,
`Core`, `General(s)`. Below the domain folder you are free: `Players/Handlers/`,
`Players/Services/` are both fine.
```

**Acceptance Criteria:**
- [ ] `Handlers/` and `Controllers/` no longer appear as acceptable first-segment names anywhere in `architecture.md`.
- [ ] All 17 banned forms are named or clearly implied by the `(s)` notation.
- [ ] Line 399 explicitly scopes the ban to the first segment.
- [ ] Total line count unchanged.

---

## Task 2 — `csharp-unity.md` Card 1.1: fix the misleading examples

**Files:** `.claude/rules/csharp-unity.md`

**Steps:**
1. [ ] Read lines 27–51 (Card 1.1). Verified layout: **31** `**WRONG:**`, **32** fence open, **33** `Games/Concretes/Input/PlayerInputHandler.cs      // domain folder singular`, **34** `Games/Concretes/Controller/PlayerController.cs   // domain folder singular`, **35** blank, **36** `public sealed class Players { }                  // class name plural`, **37** fence close. RIGHT block is **39–47**.
2. [ ] **Edit line 34, not line 33.** Line 33 is a genuine singular-vs-plural example and must stay byte-identical.
3. [ ] Replace line 34 with a layer-folder violation so the WRONG block teaches both failures: singular domain (33) and layer-as-first-segment (34).
4. [ ] Add a third WRONG line for the catch-all case: `Games/Concretes/Core/GameFlow.cs                 // BANNED: catch-all, not a domain`.
5. [ ] Fix line **42** (`Games/Concretes/Controllers/EnemyController.cs   // domain folder plural`) to a real domain folder: `Games/Concretes/Enemies/EnemyController.cs   // domain folder plural`.
6. [ ] Add a RIGHT line showing that layer names are legal *below* a domain: `Games/Concretes/Players/Services/PlayerService.cs // layer name below domain: fine`.
7. [ ] Leave line **51** (the static Extensions exception) **byte-identical**.
8. [ ] Add one sentence to the GOTCHA noting that pluralization only applies once the folder is a domain — a plural layer name is still banned.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
sed -n '33,34p;42p;51p' .claude/rules/csharp-unity.md
grep -n 'Concretes/Controllers/' .claude/rules/csharp-unity.md   # expect exit 1
```
Expected: line 33 unchanged; line 34 is the layer-folder violation; line 42 uses `Enemies/`; line 51 unchanged; grep exits **1**.

**Code Skeleton:**
```
Games/Concretes/Input/PlayerInputHandler.cs      // domain folder singular     <- line 33, KEEP
Games/Concretes/Controllers/PlayerController.cs  // layer name, not a domain   <- line 34, NEW
Games/Concretes/Core/GameFlow.cs                 // catch-all, not a domain    <- NEW
```

**Acceptance Criteria:**
- [ ] Line 33 byte-identical to before.
- [ ] Line 34 demonstrates the layer-folder violation; a third line demonstrates the catch-all violation.
- [ ] No `Concretes/Controllers/` remains in the RIGHT block.
- [ ] The "layer name below a domain is legal" case appears in RIGHT.
- [ ] Line 51 byte-identical to before.
- [ ] Card 1.1 still spans a contiguous WRONG/RIGHT/GOTCHA structure.

---

## Task 3 — `check-domain-folder-structure.sh` (PreToolUse)

**Files:** `.claude/hooks/check-domain-folder-structure.sh` (new)

**Steps:**
1. [ ] Copy the standard header from `.claude/hooks/check-no-runtime-instantiate.sh` — **lines 1–23**, not 1–20. Verified: the `_hook_log` body's closing `}` is at **21**, `trap '_hook_log $?' EXIT` at **22**, `# --- End Hook Audit Logging ---` at **23**. Copying 1–20 truncates the function mid-body and drops the trap.
2. [ ] Change the hook name string inside `_hook_log`'s `printf` to `check-domain-folder-structure`.
3. [ ] Set `HOOK_PROFILE_LEVEL="standard"`.
4. [ ] Read `FILE_PATH` from stdin JSON via `jq -r '.tool_input.file_path // empty'`; `exit 0` when empty.
5. [ ] `should_skip_path "$FILE_PATH" && exit 0` (returns **0 = skip**, `_lib.sh:124`).
6. [ ] `case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac` — non-`.cs` writes are never this hook's business. This is what lets an `ARCHITECTURE.md` write into a brand-new domain folder pass.
7. [ ] **Do NOT use `sed -E` to extract the side.** Both of these are broken on this machine and must never be reintroduced:
   - `sed -E 's|.*Games/(Abstracts|Concretes)/.*|\1|'` → `RE error: parentheses not balanced`, **empty output**. `|` is the delimiter, so the alternation ends the pattern. Empty `SIDE` ⇒ `TAIL` = whole path ⇒ `FIRST=""` ⇒ **silent no-op hook**.
   - `sed -E 's|.*Games/\(Abstracts\|Concretes\)/.*|\1|'` → `\1 not defined in the RE`. Under `-E`, `\(` is a literal paren, not a capture group.
8. [ ] Extract with pure shell (verified: `/x/.../Games/Concretes/Services/AudioService.cs` → `SIDE=Concretes`, `TAIL=Services/AudioService.cs`, `FIRST=Services`; non-greedy `#` handles a repeated `Games/Concretes/` segment correctly):
   ```bash
   case "$FILE_PATH" in
       *Games/Abstracts/*) SIDE=Abstracts ;;
       *Games/Concretes/*) SIDE=Concretes ;;
       *) exit 0 ;;
   esac
   TAIL=${FILE_PATH#*Games/$SIDE/}
   FIRST=${TAIL%%/*}
   ```
9. [ ] Add the defensive guards. Without them, any *future* extraction failure silently repeats the no-op mode instead of failing loud:
   ```bash
   [ -z "$SIDE" ] && exit 0
   [ "$TAIL" = "$FILE_PATH" ] && exit 0    # prefix strip failed — refuse to guess
   ```
10. [ ] Check 1 — no domain folder: if `[ "$FIRST" = "$TAIL" ]` the `.cs` file sits directly under `Games/<SIDE>/`. Block.
11. [ ] Check 2 — banned first segment: lowercase `FIRST` via `tr '[:upper:]' '[:lower:]'` and match against the **17** forms with a `case`. Emit a different message per family: layer names are legal one level deeper; catch-alls are not legal anywhere and should go to `_Framework/` or `Infrastructure/`. (Verified: the line-continuation backslash inside a `case` pattern list parses correctly, and `tr` handles spaces and UTF-8 without breaking the `case`.)
12. [ ] Never inspect anything past `FIRST`. `Players/Services/Foo.cs` must pass.
13. [ ] Emit violations through `unity_hook_block` (never bare `exit 2`), with a message naming the offending segment and showing the corrected path.
14. [ ] `chmod +x` the file. Mandatory even though `session-restore.sh:30` self-heals a missing exec bit at SessionStart — until the next SessionStart the harness fails with exit 126 and the hook silently no-ops.
15. [ ] Support `DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1` via the standard `_lib.sh` gating.

**Test Type:** NoTest (shell) — automated coverage arrives in Task 9.

**Manual verification:**
```bash
H=.claude/hooks/check-domain-folder-structure.sh
for p in \
  /x/_GameFolders/Scripts/Games/Concretes/Services/AudioService.cs \
  /x/_GameFolders/Scripts/Games/Concretes/Core/GameFlow.cs \
  /x/_GameFolders/Scripts/Games/Concretes/Foo.cs \
  /x/_GameFolders/Scripts/Games/Concretes/Players/Services/MoveService.cs \
  /x/_GameFolders/Scripts/Games/Concretes/Players/ARCHITECTURE.md ; do
  echo "{\"tool_input\":{\"file_path\":\"$p\"}}" | bash "$H" >/dev/null 2>&1
  echo "exit=$?  $p"
done
```
Expected, in order: **2** (layer name), **2** (catch-all), **2** (no domain), **0** (nested layer is free), **0** (non-`.cs`).

**Code Skeleton:**
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_PROFILE_LEVEL="standard"
source "${SCRIPT_DIR}/_lib.sh"
# --- Hook Audit Logging ---   (copy of check-no-runtime-instantiate.sh lines 6-23,
#     with the hook name string changed to check-domain-folder-structure)
# --- End Hook Audit Logging ---

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
should_skip_path "$FILE_PATH" && exit 0

case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac

# NO sed -E HERE. See Steps 7-8: both sed forms are broken and turn this
# hook into a silent no-op.
case "$FILE_PATH" in
    *Games/Abstracts/*) SIDE=Abstracts ;;
    *Games/Concretes/*) SIDE=Concretes ;;
    *) exit 0 ;;
esac
[ -z "$SIDE" ] && exit 0

TAIL=${FILE_PATH#*Games/$SIDE/}
[ "$TAIL" = "$FILE_PATH" ] && exit 0
FIRST=${TAIL%%/*}

if [ "$FIRST" = "$TAIL" ]; then
    unity_hook_block "No domain folder: '$FILE_PATH'
.cs files may not sit directly under Games/$SIDE/.
Put it in a domain folder: Games/$SIDE/<Domain>/$FIRST"
fi

case "$(printf '%s' "$FIRST" | tr '[:upper:]' '[:lower:]')" in
    service|services|provider|providers|controller|controllers|view|views|\
manager|managers|interface|interfaces|config|configs)
        unity_hook_block "Layer name as first segment: 'Games/$SIDE/$FIRST/'
The first folder under Games/$SIDE/ must be a DOMAIN (Players/, Enemies/, Audio/, UI/, Infrastructure/).
Layer names are free BELOW the domain: Games/$SIDE/<Domain>/$FIRST/ is fine."
        ;;
    core|general|generals)
        unity_hook_block "Catch-all folder: 'Games/$SIDE/$FIRST/'
'$FIRST' is not a domain — it is a name that cannot refuse a file, and everything
drains into it. (voxel-blast's Core/ reached 85 files across five concerns.)
Pick a real domain, or use _Framework/ for domain-agnostic code and
Concretes/Infrastructure/ for DI and bootstrap wiring."
        ;;
esac
exit 0
```

**Acceptance Criteria:**
- [ ] Registered as **PreToolUse** in the hand-off (Task 10); the check is pure-path, so it prevents the bad path from being created rather than reporting it afterward.
- [x] No `sed` in executable code: `grep -c '^[^#]*sed ' ` returns 0. (An earlier draft of this criterion said plain `grep -c sed` must return 0, which contradicted Step 7 — that step deliberately records both broken `sed` forms in comments so neither is reintroduced. The comment mentions are intended; only executable `sed` is banned.)
- [ ] `[ -z "$SIDE" ] && exit 0` and the `[ "$TAIL" = "$FILE_PATH" ]` guard are both present, so an extraction failure exits explicitly rather than falling through into a silent no-op.
- [ ] All 17 banned forms matched case-insensitively, with distinct messages for the layer and catch-all families.
- [ ] `Players/Services/Foo.cs` exits 0 — nothing past `FIRST` is inspected.
- [ ] `.cs` directly under `Games/<SIDE>/` exits 2.
- [ ] Non-`.cs` paths and paths outside `Games/` exit 0.
- [ ] Uses `unity_hook_block`, not bare `exit 2`; header copied from lines **1–23** including the `trap`.
- [ ] Executable bit set.

---

## Task 4 — `check-architecture-doc.sh` (PostToolUse)

**Files:** `.claude/hooks/check-architecture-doc.sh` (new)

**Steps:**
1. [ ] Copy the header from `check-no-runtime-instantiate.sh` **lines 1–23** (same reasoning as Task 3, Step 1); rename the hook string to `check-architecture-doc`. `HOOK_PROFILE_LEVEL="standard"`.
2. [ ] Parse `FILE_PATH`; `exit 0` if empty; `should_skip_path "$FILE_PATH" && exit 0`.
3. [ ] Define the heading array once, shared by both triggers. All four are pure ASCII, so comparison is a plain byte match with no locale exposure:
   ```bash
   REQUIRED_H2=("## Purpose" "## Boundary" "## How to extend" "## Gotchas")
   ```
4. [ ] **Trigger A — a `.cs` write into a domain folder whose doc is missing.** Only for `*.cs` under `Games/Concretes/`. Derive `TAIL` / `DOMAIN` with the same `case` + parameter-expansion technique as Task 3 (again: no `sed`).
5. [ ] **No domain is exempt — including `Infrastructure/`.** An earlier draft exempted it on the aesthetic grounds that it is "not a real domain". That was backwards: `Infrastructure/` hosts the most frequently confused boundary in the project (app-lifetime vs. scene-lifetime registration, scope vs. module). Its doc is a short pointer to `bootstrap-pattern.md`. Exceptions also get forgotten, questioned and multiplied; having none is worth more than the one doc saved.
6. [ ] Trigger A, no-domain case: use `unity_hook_warn`, **not** `exit 0`. Deferring to the PreToolUse folder hook silently drops the case whenever that hook does not run — under `UNITY_HOOK_MODE=warn`, under the `minimal` profile, or with `DISABLE_HOOK_CHECK_DOMAIN_FOLDER_STRUCTURE=1`. Each hook must be independently correct and must not assume a sibling ran. Because `unity_hook_warn` **exits 0 and terminates** (`_lib.sh:115`), it must be the **last statement on that branch**.
7. [ ] Trigger A: if `Concretes/<DOMAIN>/ARCHITECTURE.md` does not exist → `unity_hook_warn` naming the expected path and the four required headings. Warn only; never blocks the code write.
8. [ ] **Trigger B — the write is itself an `ARCHITECTURE.md`.**
9. [ ] Trigger B, placement check 1: path under `Games/Abstracts/` → `unity_hook_block` ("ARCHITECTURE.md belongs in Concretes/<Domain>/, never Abstracts/").
10. [ ] Trigger B, placement check 2: after the `Abstracts/` check, derive `TAIL` and `DOMAIN` and block when `[ "$DOMAIN" = "$TAIL" ]` — the doc sits directly at `Games/Concretes/ARCHITECTURE.md` with no domain folder. Otherwise unguarded: Task 3's hook exits early on non-`.cs`, so a stray top-level doc would pass everything.
11. [ ] Trigger B: `[ -f "$FILE_PATH" ] || exit 0`. This guard is exactly why the hook is PostToolUse — under PreToolUse it would skip 100% of validation.
12. [ ] Trigger B, line cap: count with `awk 'END{print NR}' "$FILE_PATH"`. **`wc -l` is banned** — on a file with no trailing newline it reports 40 where `awk` reports 41, so a 41-line doc would slip past the cap. Block above 40.
13. [ ] Trigger B, H1 count — **strip fenced code blocks before counting.** A naive `grep -c '^# '` also counts a `# comment` line inside a ``` fence: verified 2 instead of 1, producing a spurious block on a perfectly legal doc. Use:
    ```bash
    H1=$(strip_fences "$FILE_PATH" | grep -c '^# ')
    [ "$H1" -eq 1 ] || unity_hook_block "Exactly one H1 title required (found $H1)."
    ```
    (Verified: `grep -c '^# '` does **not** count `## ` lines, so the `^# ` anchor is correct; the fence strip is the only additional guard needed.)
14. [ ] Trigger B, H2 exact-order comparison — use this concrete mechanism (template hooks are `#!/bin/bash`, so process substitution is safe). It catches missing, extra, reordered, and misspelled headings in one check:
    ```bash
    if ! diff <(strip_fences "$FILE_PATH" | grep '^## ') \
              <(printf '%s\n' "${REQUIRED_H2[@]}") >/dev/null; then
        unity_hook_block "..."
    fi
    ```
15. [ ] Trigger B, class-name ban — applies to the **whole file, `## How to extend` included**:
    ```bash
    grep -nE '\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b' "$FILE_PATH"
    ```
    Any hit → `unity_hook_block` quoting the offending lines and explaining the voxel-blast rot (`Car` → `Turret`, 15/25 docs wrong, every rotted line held a class name). The message must tell the author what to write instead: describe the **shape** of the extension (layer, file location, wiring method), and use `/knowledge-graph implementers` for concrete names. **`Module` is intentionally NOT in the alternation** — module names are convention-fixed and never renamed, so `PlayerModule.Install` passes by design. Add a code comment saying so; a later reader will otherwise "fix" it.
16. [ ] `chmod +x` (see Task 3, Step 14).
17. [ ] Support `DISABLE_HOOK_CHECK_ARCHITECTURE_DOC=1`.

**Test Type:** NoTest (shell) — automated coverage in Task 9.

**Manual verification:**
```bash
H=.claude/hooks/check-architecture-doc.sh
D=$(mktemp -d)/Games/Concretes/Players && mkdir -p "$D"
printf '# Players\n## Purpose\nx\n## Boundary\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$D/ARCHITECTURE.md"
echo "{\"tool_input\":{\"file_path\":\"$D/ARCHITECTURE.md\"}}" | bash "$H"; echo "well-formed exit=$?"   # 0

printf '# Players\n## Boundary\nx\n## Purpose\nx\n## How to extend\nx\n## Gotchas\nx\n' > "$D/ARCHITECTURE.md"
echo "{\"tool_input\":{\"file_path\":\"$D/ARCHITECTURE.md\"}}" | bash "$H"; echo "reordered exit=$?"     # 2

S=$(dirname "$D") && printf '# Stray\n' > "$S/ARCHITECTURE.md"
echo "{\"tool_input\":{\"file_path\":\"$S/ARCHITECTURE.md\"}}" | bash "$H"; echo "no-domain exit=$?"     # 2
```

**Code Skeleton:**
```bash
REQUIRED_H2=("## Purpose" "## Boundary" "## How to extend" "## Gotchas")
# Strip fenced code blocks before counting headings — a `# comment` inside a
# fence would otherwise be counted as a second H1.
strip_fences() { awk '/^```/{f=!f;next} !f' "$1"; }

case "$FILE_PATH" in
  */ARCHITECTURE.md)
      case "$FILE_PATH" in
          *Games/Abstracts/*)
              unity_hook_block "ARCHITECTURE.md belongs in Games/Concretes/<Domain>/, never Abstracts/." ;;
      esac
      case "$FILE_PATH" in *Games/Concretes/*) ;; *) exit 0 ;; esac
      TAIL=${FILE_PATH#*Games/Concretes/}
      [ "$TAIL" = "$FILE_PATH" ] && exit 0
      DOMAIN=${TAIL%%/*}
      [ "$DOMAIN" = "$TAIL" ] && unity_hook_block \
          "ARCHITECTURE.md must live at Games/Concretes/<Domain>/ARCHITECTURE.md, not directly under Concretes/."
      [ -f "$FILE_PATH" ] || exit 0

      LINES=$(awk 'END{print NR}' "$FILE_PATH")   # wc -l is BANNED here
      [ "$LINES" -gt 40 ] && unity_hook_block "ARCHITECTURE.md is $LINES lines; cap is 40. Intent only."

      H1=$(strip_fences "$FILE_PATH" | grep -c '^# ')
      [ "$H1" -eq 1 ] || unity_hook_block "Exactly one H1 title required (found $H1)."

      if ! diff <(strip_fences "$FILE_PATH" | grep '^## ') \
                <(printf '%s\n' "${REQUIRED_H2[@]}") >/dev/null; then
          unity_hook_block "Headings must be exactly these four, in this order:
$(printf '%s\n' "${REQUIRED_H2[@]}")
Found:
$(strip_fences "$FILE_PATH" | grep '^## ')"
      fi

      # 'Module' is deliberately absent from the alternation: module names are
      # convention-fixed and never renamed, so PlayerModule.Install is allowed.
      HITS=$(grep -nE '\b[A-Z][A-Za-z0-9]*(Service|Manager|Controller|Handler|Provider|View|Event|Config|Configuration|Scope|Installer)\b' "$FILE_PATH")
      [ -n "$HITS" ] && unity_hook_block "Class names rot — voxel-blast lost 15 of 25 docs to one rename.
$HITS
Describe the SHAPE instead: which layer, which folder, how it is wired.
Concrete names: /knowledge-graph implementers <interface>"
      exit 0 ;;
esac

# Trigger A — no domain is exempt, Infrastructure included.
case "$FILE_PATH" in *.cs) ;; *) exit 0 ;; esac
case "$FILE_PATH" in *Games/Concretes/*) ;; *) exit 0 ;; esac
TAIL=${FILE_PATH#*Games/Concretes/}
[ "$TAIL" = "$FILE_PATH" ] && exit 0
DOMAIN=${TAIL%%/*}
# unity_hook_warn exits 0 and terminates -> must be last on the branch.
[ "$DOMAIN" = "$TAIL" ] && unity_hook_warn "No domain folder for '$FILE_PATH'. Move it under Games/Concretes/<Domain>/."
DOC="${FILE_PATH%%Games/Concretes/*}Games/Concretes/$DOMAIN/ARCHITECTURE.md"
[ -f "$DOC" ] || unity_hook_warn "Missing $DOC. English, <= 40 lines, no class names. Required headings:
$(printf '%s\n' "${REQUIRED_H2[@]}")"
exit 0
```

**Acceptance Criteria:**
- [ ] Registered as **PostToolUse**. Its contract is stated plainly: a malformed `ARCHITECTURE.md` **lands on disk first** and is then blocked as corrective feedback. This is accepted deliberately — under PreToolUse the `[ -f ]` guard would skip all validation. Same contract as `check-no-runtime-instantiate.sh` in `PostToolUse`.
- [ ] Uses `awk 'END{print NR}'`; no `wc -l` anywhere in the file.
- [ ] H1 and H2 checks both run on fence-stripped content; a doc with a `# comment` inside a ``` fence exits 0.
- [ ] The H2 check is the `diff <(...) <(...)` form against the four ASCII headings and rejects missing, extra, reordered, and misspelled headings.
- [ ] `PlayerModule` passes the class-name regex; `PlayerService` blocks, including inside `## How to extend`. A comment in the script records that the `Module` omission is deliberate. The block message tells the author to describe shape, not names.
- [ ] `Games/Concretes/ARCHITECTURE.md` with no domain folder exits 2.
- [ ] `Games/Abstracts/<X>/ARCHITECTURE.md` exits 2.
- [ ] Trigger A's no-domain branch calls `unity_hook_warn` — no cross-hook deferral. The hook is correct even when `check-domain-folder-structure.sh` is disabled or in `warn` mode.
- [ ] **No `Infrastructure/` special case appears anywhere in the script.**
- [ ] Every `unity_hook_warn` is the last statement on its branch.
- [ ] Header copied from lines 1–23; executable bit set.

---

## Task 5 — `architecture.md` pass 2: the domain convention prose

**Files:** `.claude/rules/architecture.md`
**Depends on:** Task 1

**Steps:**
1. [ ] Confirm anchors after T1: `## Module Structure (NON-NEGOTIABLE)` at **419**, tree fence **423–446**, line **447 blank**, line **448** the bold `[Module]Events.cs` sentence.
2. [ ] Insert the new prose **after line 447** (blank line), before 448. Do not disturb the tree.
3. [ ] Write the hard rule: first segment under `Games/Abstracts/` or `Games/Concretes/` must be a domain; the 14 layer forms plus `Core`/`General(s)`; a `.cs` directly under either is the same violation. Include the one-paragraph `Core/` rationale (voxel-blast: 85 files, five concerns) so the ban reads as evidence, not taste. Record the accepted gap (`Common/`, `Shared/`, `Utils/`, `Helpers/`, `Misc/` are not enforced) so a future reader knows it was a decision.
4. [ ] Write the freedom clause: below the domain folder anything goes — `Players/Services/`, `Players/Handlers/`, `Players/Inputs/`, `Players/Types/`, or fully flat.
5. [ ] Write the **advisory** paragraph, labelled as advisory and explicitly *not enforced*: keep a domain flat while small; open subfolders when file count hurts readability; mirroring the shape on both sides aids navigation. State that there is **no file-count threshold and no mirror requirement** — include the deadlock reason in one clause so nobody re-adds a threshold.
6. [ ] Write the naming rules: identical names on both sides; plural countable / singular mass noun; DI and bootstrap → `Concretes/Infrastructure/`; domain-agnostic → `_Framework/`.
7. [ ] Write the `ARCHITECTURE.md` contract: `Concretes/<Domain>/` only; **English**; H1 + the four ordered `##` headings verbatim (`## Purpose`, `## Boundary`, `## How to extend`, `## Gotchas`); 40-line cap; no class names anywhere including `## How to extend`, with the shape-not-names guidance and a worked example; `Module` exempt **by design**; **every domain needs one, `Infrastructure/` included** — and its doc is a pointer to `bootstrap-pattern.md`; missing → warn, malformed → block.
8. [ ] Add a two-sentence "Why intent only" note citing voxel-blast (25 docs, 8031 lines, 15/25 wrong after the unpropagated `Car` → `Turret` rename; 0 `Car*.cs` vs 29 `Turret*.cs`; every rotted line held a class name, no intent line rotted) and pointing at `/knowledge-graph` for inventory.
9. [ ] Name both enforcing hooks so a reader knows the prose is machine-checked. Add a forward pointer: *the reading side of this convention is tracked in `docs/PLAN_architecture_doc_consumption.md`.*

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n '## Boundary' .claude/rules/architecture.md   # expect a hit after line 447
sed -n '419p;447p' .claude/rules/architecture.md       # header + blank line intact
```

**Code Skeleton:**
```markdown
### Domain Folder Convention (NON-NEGOTIABLE)

**Hard rule.** The first folder under `Games/Abstracts/` or `Games/Concretes/` is a **domain** …
**Free below the domain.** `Players/Services/`, `Players/Handlers/`, or flat — all legal …
**Advisory (not enforced).** Keep a domain flat while small … no file-count threshold exists,
and none may be added: a hook fires per single file write, so a count gate can never be satisfied.
**Naming.** … **ARCHITECTURE.md.** English, 4 headings, <= 40 lines, no class names …
**Why intent only.** …
Enforced by `check-domain-folder-structure.sh` (PreToolUse) and `check-architecture-doc.sh` (PostToolUse).
```

**Acceptance Criteria:**
- [ ] Inserted after line 447; the Module Structure tree (423–446) and line 448 are byte-identical.
- [ ] Hard rule, `Core/` rationale, accepted gap, freedom clause, advisory (explicitly non-enforced), naming, and doc contract all present.
- [ ] The four English headings appear verbatim.
- [ ] The shape-not-names guidance for `## How to extend` includes a worked example.
- [ ] `Infrastructure/` is stated as needing a pointer doc, not as exempt.
- [ ] No contradiction with the revised line 399 or with the table at 390–397.
- [ ] Both hook filenames named, plus the Phase 2 forward pointer.

---

## Task 6 — `new-module.md`: generate the doc as Step 4.5

**Files:** `.claude/commands/new-module.md`
**Depends on:** Task 4

**Steps:**
1. [ ] Confirm Step 4 ends at **137** and Step 5 begins at **139**; insert the new step between them.
2. [ ] Add `### Step 4.5 — Write Concretes/[X]/ARCHITECTURE.md`.
3. [ ] Embed a fill-in template: H1 `# [X]`, then the four English headings in order, one or two intent sentences under each.
4. [ ] State the constraints inline: English, 40-line cap, no class names anywhere — **including `## How to extend`** — and show the shape-not-names form, since that is the section a generator will otherwise fill with type names and get blocked on.
5. [ ] Note that `[X]Module` is allowed (convention-fixed), and that `/knowledge-graph implementers` is where concrete names come from.
6. [ ] **No exemption for `Infrastructure`.** When the module is `Infrastructure`, write a pointer doc: state the boundary in `## Boundary`, then delegate detail to `.claude/rules/bootstrap-pattern.md` in `## How to extend` rather than restating six cards.
7. [ ] Note that `check-architecture-doc.sh` validates the result on write and that a malformed doc will be blocked after landing, so it must be fixed before proceeding to Step 5.
8. [ ] Add a Portability Checklist line in Step 5: `- [ ] ARCHITECTURE.md present at Concretes/<Domain>/, English, <= 40 lines, no class names`.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
grep -n 'Step 4.5' .claude/commands/new-module.md
sed -n '135,155p' .claude/commands/new-module.md
```

**Code Skeleton:**
```markdown
### Step 4.5 — Write Concretes/[X]/ARCHITECTURE.md

English, max 40 lines, intent only, no class names (`[X]Module` is the one exception).
For `Infrastructure`, write a pointer doc that delegates to `.claude/rules/bootstrap-pattern.md`.

    # [X]

    ## Purpose
    <one sentence; no "AND">

    ## Boundary
    <what this domain never does, and which domain owns that instead>

    ## How to extend
    <shape, not names: contract interface in Abstracts/[X]/ -> pure C# handler in
    Concretes/[X]/ -> register in [X]Module.Install. Concrete type names come from
    /knowledge-graph implementers, not from this file.>

    ## Gotchas
    <the mistake people actually make here>
```

**Acceptance Criteria:**
- [ ] Step 4.5 sits between Step 4 and Step 5; both are otherwise untouched.
- [ ] Template reproduces the four English headings verbatim and in order.
- [ ] 40-line cap, class-name ban (incl. `## How to extend`), `Module` exemption, and the `Infrastructure` pointer-doc form are all stated.
- [ ] No `Infrastructure` skip instruction anywhere in the step.
- [ ] The Portability Checklist gains exactly one new line.
- [ ] A doc produced verbatim from the template passes `check-architecture-doc.sh`.

---

## Task 7 — register both hooks in `hook-profiles.md`

**Files:** `.claude/docs/hook-profiles.md`
**Depends on:** Tasks 3, 4

**Steps:**
1. [ ] Verified layout: line **34** = `| Hook | Purpose |`, **35** = separator, **36** = `check-async-void.sh`, **37** = `check-ecs-structural-changes.sh`, **38** = `check-enum-byte-base.sh`, … The `standard` table is alphabetical.
2. [ ] Insert `check-architecture-doc.sh` at **line 36**, before `check-async-void.sh` (a < s).
3. [ ] Insert `check-domain-folder-structure.sh` at **line 38** — after `check-async-void.sh` (now at 37) and before `check-ecs-structural-changes.sh`, since `d` < `e`.
4. [ ] Purpose column, one line each: "Validates `Concretes/<Domain>/ARCHITECTURE.md` shape (4 headings, 40 lines, no class names)" and "Blocks layer names (`Services/`, `Views/`, …) and catch-alls (`Core/`) as the first folder under `Games/Abstracts|Concretes/`".
5. [ ] Record the event choice next to each entry (PreToolUse / PostToolUse) so nobody re-registers them on the other event.
6. [ ] Document both `DISABLE_HOOK_*` env var names wherever the other per-hook disables are listed.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
sed -n '34,42p' .claude/docs/hook-profiles.md
grep -n 'check-architecture-doc\|check-domain-folder-structure' .claude/docs/hook-profiles.md
```
Expected: both rows present, alphabetical order unbroken.

**Acceptance Criteria:**
- [ ] `check-architecture-doc.sh` at line 36, `check-domain-folder-structure.sh` at line 38.
- [ ] Alphabetical ordering of the `standard` table unbroken.
- [ ] `check-async-void.sh` and `check-ecs-structural-changes.sh` still present, just shifted.
- [ ] Both `DISABLE_HOOK_*` names documented.
- [ ] PreToolUse / PostToolUse recorded per hook.

---

## Task 8 — `.claude/CLAUDE.md` rules-table row

**Files:** `.claude/CLAUDE.md`
**Depends on:** Task 5

**Steps:**
1. [ ] Locate the rules table's `architecture.md` row at **~line 118**.
2. [ ] Append to its "Covers" cell: `domain folder convention (first segment = domain, never a layer or catch-all); Concretes/<Domain>/ARCHITECTURE.md intent contract`.
3. [ ] Keep the existing cell contents and the table's markdown intact; do not add a new row.
4. [ ] Do **not** add hook entries here — the hooks tables are `@`-included, so Task 7's edits surface automatically.

**Test Type:** NoTest (markdown)

**Manual verification:**
```bash
sed -n '116,120p' .claude/CLAUDE.md
```

**Acceptance Criteria:**
- [ ] The `architecture.md` row mentions the domain folder convention and the ARCHITECTURE.md contract.
- [ ] No other row modified; table renders correctly.

---

## Task 9 — bats tests for both new hooks

**Files:** `.claude/hooks/tests/check-domain-folder-structure.bats` (new), `.claude/hooks/tests/check-architecture-doc.bats` (new), `.claude/hooks/tests/README.md` (edit)
**Depends on:** Tasks 3, 4

`.claude/hooks/tests/` is a live bats suite with `run-tests.sh` and ~20 per-hook `.bats` files. Two new hooks must not ship with zero tests.

**Steps:**
1. [ ] Read `.claude/hooks/tests/README.md` and `check-unity-event.bats` first, and follow their conventions exactly: `#!/usr/bin/env bats`, `setup()` exporting `UNITY_HOOK_STATE_DIR="$(mktemp -d)"`, setting `HOOK`, creating `TMPDIR_TEST`, and `cd "$BATS_TEST_DIRNAME/../../.."`; `teardown()` removing both temp dirs; each case invoking `run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"` and asserting `$status`.
2. [ ] Construct paths under `TMPDIR_TEST` containing a literal `Games/Concretes/` segment. Verified: `should_skip_path` excludes `Editor|Plugins|ThirdParty|_AssetFolders|PackageCache|*Tests/*|*Test/*|*Spec/*` and has **no temp-dir exclusion**, so `$TMPDIR_TEST/proj/_GameFolders/Scripts/Games/Concretes/...` is not vacuously skipped. Avoid any `Test`/`Spec`/`Editor` path component.
3. [ ] **Folder hook cases** — layer name as first segment, several of the 14 forms plus mixed case (`Services`, `Service`, `Views`, `Manager`, `Interfaces`, `CONFIGS`, `ProViDers`) → 2; catch-all first segment (`Core`, `core`, `Generals`, `General`) → 2; `.cs` with no domain folder (`Games/Concretes/Foo.cs`) → 2; legal nested `Games/Concretes/Players/Services/MoveService.cs` → 0; legal nested catch-all-shaped name below a domain is **not** tested as legal — `Players/Core/` is out of scope for this hook by design, note that in a comment; `ARCHITECTURE.md` ignored as non-`.cs` → 0; path entirely outside `Games/` → 0; a path with no `Games/Abstracts|Concretes` segment → 0; both `Abstracts/` and `Concretes/` sides covered.
4. [ ] **Doc hook cases** — Trigger A warns (exit 0, warning on stderr) when the domain doc is missing; **`Infrastructure/` also warns** (no exemption — this is the regression guard for the removed special case); Trigger B blocks a **41-line file with no trailing newline** (the `wc -l` regression guard: build it with `printf` and no final `\n`) → 2; missing H1 → 2; **a doc with a `# comment` inside a ``` fence → 0** (the fence-strip regression guard); reordered headings → 2; extra fifth heading → 2; a doc containing `PlayerService` → 2; a doc containing `IMoveHandler` inside `## How to extend` → 2 (the ban covers that section); a doc whose only capitalized tokens are `PlayerModule.Install` → 0; `ARCHITECTURE.md` under `Abstracts/` → 2; stray `Games/Concretes/ARCHITECTURE.md` → 2; a well-formed 4-heading English doc → 0.
5. [ ] Add the two profile/mode cases the suite standardizes on: `UNITY_HOOK_PROFILE=minimal` skips both hooks (exit 0), and `UNITY_HOOK_MODE=warn` downgrades a blocking case to exit 0.
6. [ ] All fixture headings are ASCII (`## Purpose`, `## Boundary`, `## How to extend`, `## Gotchas`), so no encoding setup is needed.
7. [ ] Add both files to the test table in `.claude/hooks/tests/README.md`.
8. [ ] Run `./.claude/hooks/tests/run-tests.sh` and confirm the whole suite is green, not just the two new files.

**Test Type:** bats (this task *is* the test task)

**Manual verification:**
```bash
bats .claude/hooks/tests/check-domain-folder-structure.bats
bats .claude/hooks/tests/check-architecture-doc.bats
./.claude/hooks/tests/run-tests.sh; echo "exit=$?"   # expect 0
```

**Code Skeleton:**
```bash
#!/usr/bin/env bats

setup() {
    export UNITY_HOOK_STATE_DIR="$(mktemp -d)"
    HOOK=".claude/hooks/check-domain-folder-structure.sh"
    TMPDIR_TEST="$(mktemp -d)"
    ROOT="$TMPDIR_TEST/proj/_GameFolders/Scripts/Games"
    cd "$BATS_TEST_DIRNAME/../../.." || exit 1
}
teardown() { rm -rf "$UNITY_HOOK_STATE_DIR" "$TMPDIR_TEST"; }

@test "blocks Services/ as first segment under Concretes" {
    local f="$ROOT/Concretes/Services/AudioService.cs"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "blocks Core/ as first segment (catch-all)" {
    local f="$ROOT/Concretes/Core/GameFlow.cs"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 2 ]
}

@test "allows Players/Services/ (layer below domain is free)" {
    local f="$ROOT/Concretes/Players/Services/MoveService.cs"
    run bash -c "echo '{\"tool_input\":{\"file_path\":\"$f\"}}' | bash $HOOK"
    [ "$status" -eq 0 ]
}
```

**Acceptance Criteria:**
- [ ] Both `.bats` files exist and follow the suite's `setup`/`teardown`/`run bash -c` conventions.
- [ ] Every case listed in Steps 3 and 4 is present as a distinct `@test`.
- [ ] The 41-line no-trailing-newline case fails against a `wc -l` implementation and passes against `awk 'END{print NR}'` — verified by temporarily swapping the counter.
- [ ] The fenced-`# comment` case fails against a naive `grep -c '^# '` and passes against the fence-stripped version.
- [ ] The `Infrastructure/` warn case fails against any implementation that still carries the removed exemption.
- [ ] The `IMoveHandler`-in-`## How to extend` case blocks, proving the ban is section-independent.
- [ ] The `PlayerModule.Install` doc exits 0, proving `Module`'s deliberate absence from the alternation.
- [ ] Test paths avoid `should_skip_path` components; at least one case would fail if the hook were a no-op, so the suite catches the silent-no-op regression class.
- [ ] `run-tests.sh` exits 0 across the whole suite.
- [ ] `README.md` test table lists both new files.

---

## Task 10 — `.claude/settings.json` registration hand-off (human, sequential, last)

**Files:** `.claude/settings.json` — **human edits only**
**Depends on:** Tasks 3, 4, 7, 9

Claude **MUST NOT** edit `.claude/settings.json`; `check-config-protection.sh` blocks it. This task produces the exact instructions for the human. Until it is done, Tasks 1–9 leave the repo documenting enforcement that does not fire.

**Steps:**
1. [ ] Confirm Tasks 3, 4 and 9 are complete and `run-tests.sh` is green before asking for the edit.
2. [ ] Print the two JSON entries for the human to paste, naming the destination array for each:
   - `check-domain-folder-structure.sh` → **`PreToolUse`** (currently 20 entries, all preventive `Edit|Write` blockers — this fits the pattern exactly), matcher `Edit|Write`.
   - `check-architecture-doc.sh` → **`PostToolUse`** (currently 19 entries; `PostToolUse` already holds exit-2 hooks such as `check-no-runtime-instantiate.sh`, where exit 2 is corrective feedback that cannot prevent the write — the same contract applies here), matcher `Edit|Write`.
3. [ ] Remind the human to `chmod +x` both hooks if not already set. `session-restore.sh:30` self-heals a missing exec bit at SessionStart, but until then the harness fails with exit 126 and the hook silently no-ops.
4. [ ] After the human edits, verify with a real write: the fresh-domain walkthrough below must show no deadlock.

**Test Type:** NoTest (configuration)

**Manual verification:**
```bash
jq '.hooks.PreToolUse  | length' .claude/settings.json   # expect 21
jq '.hooks.PostToolUse | length' .claude/settings.json   # expect 20
jq -r '.. | .command? // empty' .claude/settings.json \
  | grep -c 'check-domain-folder-structure\|check-architecture-doc'   # expect 2
test -x .claude/hooks/check-domain-folder-structure.sh \
  && test -x .claude/hooks/check-architecture-doc.sh; echo "exec=$?"
```

**Code Skeleton — paste into the named arrays:**
```jsonc
// -> hooks.PreToolUse
{ "matcher": "Edit|Write", "hooks": [ { "type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-domain-folder-structure.sh",
  "timeout": 5000, "statusMessage": "Checking domain folder structure..." } ] }

// -> hooks.PostToolUse
{ "matcher": "Edit|Write", "hooks": [ { "type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/check-architecture-doc.sh",
  "timeout": 5000, "statusMessage": "Checking ARCHITECTURE.md..." } ] }
```

**Fresh-domain walkthrough (no deadlock — verify end to end):**
1. Write `Games/Concretes/Players/PlayerService.cs` → folder hook: `FIRST=Players`, passes. Doc hook Trigger A: doc missing → **warn only**, exit 0. File lands.
2. Write `Games/Concretes/Players/ARCHITECTURE.md` → folder hook skips (non-`.cs`). Doc hook Trigger B validates it. File lands.
3. Write `Games/Concretes/Players/Services/MoveService.cs` → folder hook: `FIRST=Players`, passes. Doc hook Trigger A: doc now exists, exit 0.

No step requires a file that a prior step was prevented from creating.

**Acceptance Criteria:**
- [ ] `PreToolUse` count 20 → 21; `PostToolUse` count 19 → 20.
- [ ] `check-domain-folder-structure.sh` registered on **PreToolUse** only; `check-architecture-doc.sh` on **PostToolUse** only.
- [ ] Claude made no edit to `.claude/settings.json`; the change is attributable to the human.
- [ ] Both hooks executable.
- [ ] The three-step fresh-domain walkthrough completes with no block.

---

## Revision History

**v4 — 2026-08-05** (`/grill-me` stress-test; 7 decisions applied, plan split into two phases)

- **D1** — banned first-segment list extended with the catch-all family `Core`, `General`, `Generals` (17 forms total), with a distinct hook message pointing at `_Framework/` and `Infrastructure/`. Evidence: voxel-blast's `Core/` reached 85 files / 7692 lines across five concerns. Accepted gap recorded in the rule text: `Common/`, `Shared/`, `Utils/`, `Helpers/`, `Misc/` remain unenforced, to keep the list short and false positives near zero.
- **D3** — `ARCHITECTURE.md` is written entirely in **English**, headings included: `## Purpose`, `## Boundary`, `## How to extend`, `## Gotchas`. Repo becomes single-language, the template is portable, and the previous Turkish headings' Unicode-normalization exposure (`ı` under NFC/NFD) is eliminated — heading comparison is now a plain ASCII byte match with no locale caveat.
- **D4** — the class-name ban applies to `## How to extend` too. Rejected exempting that section: it would reinstate the rot vector in the most concretely written part of the doc. Instead the section describes the **shape** of an extension (layer, folder, wiring method) and defers concrete names to `/knowledge-graph implementers`. `/new-module`'s template now demonstrates this form, since a generator left to itself will write type names there and get blocked.
- **D6** — the `Infrastructure/` doc exemption is **removed**. Its only justification was aesthetic ("not a real domain"); functionally it hosts the project's most frequently confused boundary. Its doc is a short pointer that delegates detail to `bootstrap-pattern.md`. A bats case guards against the exemption returning.
- **D7** — the plan is now **Phase 1 of 2**. All consumption-side work (agent Step 0 reading instructions, research-command Step 0 layering, `/build-knowledge-graph` orphan-doc reconciliation) moved to `docs/PLAN_architecture_doc_consumption.md`, written now and held at `Blocked` status. Reason: that work configures ~15 files to read documents that do not exist yet (0 domains today), and the instructions will be more accurate written against real content. Countered the obvious risk — deferred work never happens — by writing the plan immediately rather than leaving it as an intention.
- **Critique pass** — added the write-only-artifact risk (verified: zero references to `ARCHITECTURE.md` anywhere in `.claude/`) and the reasoning that resolved it.

**v3 — 2026-08-05** (third review round)

- **FIX 10** — the H1 check `grep -c '^# '` also counted a `# comment` inside a ``` fence (verified: 2 instead of 1), spuriously blocking a legal doc. H1 and H2 checks now run on fence-stripped content via `awk '/^```/{f=!f;next} !f'`; bats regression case added.
- **FIX 11** — `hook-profiles.md` second insertion point corrected from "~39" to **38**.
- **REJECTED** — the round-3 reviewer proposed adding `Module` to the class-name alternation because `PlayerModule.Install` passes uncaught. That is intended: module names are convention-fixed by `bootstrap-pattern.md` and never renamed, and `/new-module`'s own template references `[X]Module`, so adding it would make the generated template block itself. A code comment now records the exemption.

**v2 — 2026-08-05** (second review round, INCREMENTAL; rule unchanged from v1)

- **FIX 1 (blocking)** — dropped `sed -E` entirely for the `Abstracts|Concretes` extraction. v1's form errored (`parentheses not balanced`) and emitted empty output, turning the hook into a silent no-op; the reviewer's proposed `\(...\|...\)` replacement also fails (`\1 not defined in the RE`). Replaced with a verified `case` + parameter-expansion form, with both broken variants recorded so neither is reintroduced.
- **FIX 2** — added `[ -z "$SIDE" ] && exit 0` and a failed-prefix-strip guard so future extraction failures fail loud.
- **FIX 3** — retargeted the Card 1.1 edit from line 33 to **line 34**.
- **FIX 4** — header copy range corrected from lines 1–20 to **1–23**; 1–20 truncated `_hook_log` mid-body and dropped the `EXIT` trap.
- **FIX 5** — added a block for a stray `Games/Concretes/ARCHITECTURE.md` with no domain folder.
- **FIX 6** — replaced the unspecified "exact-order H2 comparison" with a concrete `diff <(grep '^## ') <(printf ...)` mechanism.
- **FIX 7** — replaced Trigger A's cross-hook deferral with `unity_hook_warn`.
- **FIX 8** — corrected the `hook-profiles.md` insertion anchors.
- **FIX 9** — added bats coverage for both hooks; renumbered the settings.json hand-off to Task 10.

**v1 — 2026-08-05** — initial plan. Superseded before saving: its `Handlers/` >= 5 file-count gate was unimplementable (the folder can never reach 5, since the first write into it is blocked at count 1). All counting and mirror logic removed in response.
