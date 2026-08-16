# Plan-Time Fact Gate — Design

> Status: approved (design), not yet implemented
> Supersedes the write-time-only enforcement in `gateguard.sh` Guard 2
> Related: `.claude/scripts/validate-plan-paths.sh`, `.claude/hooks/lib-path-rules.sh`

## Problem

Two independent mechanisms enforce the same property — *a human must see this
decision before code lands* — with **opposite assumptions about who writes the
file**:

| Mechanism | Approval granularity | Who must do the writing |
|---|---|---|
| Director Gates (`gate-cleared` + `guard-pipeline-direct-work.sh:92`) | plan level, once, up front | **subagent** — the Director is actively blocked |
| `gateguard.sh:87` (and two copies, below) | file level, at write time | **Director** — `depth -eq 0`, subagents blocked permanently |

While `gate-cleared` exists, a `.cs` write under `_GameFolders/Scripts/`:

- at depth 0 (Director) → blocked by `guard-pipeline-direct-work.sh`
- at depth > 0 (subagent) → blocked by `gateguard.sh`

**Nobody can write.** The only escape is a per-file `pipeline-override`. This is a
deadlock, not merely excessive ceremony, and it makes `/orchestrate` unusable at
the `strict` profile.

The depth restriction is not one hook's quirk — it is a **pattern copied into
three hooks**, each with the same rationale comment:

| Hook | Trigger surface | Line |
|---|---|---|
| `gateguard.sh` | every `.cs` file | 87 |
| `guard-critical-files.sh` | `AppScope.cs`, `InputService.cs`, `AppModules.cs`, `ConfigCatalog.cs`, EventBus files, `.asmdef` — **edits only**, creation exempt | 143-158 |
| `check-config-protection.sh` | `.asmdef` edits (`settings.json` / `.inputactions` are unconditionally human-only) | 88-100 |

`guard-critical-files.sh` matters as much as `gateguard.sh` here: every new module
must edit `AppModules.cs` by definition (`docs/modules/_templates/tasks.md`:
*"AppModules.cs'e bir satır eklenerek kaydolur"*). Fixing only `gateguard.sh` moves
the wall three metres, it does not remove it.

## Why write-time is the wrong layer

The five facts `gateguard.sh` demands are all answerable **before any agent
spawns** — they are properties of the plan, not of the edit. The project already
learned this lesson for path rules and wrote it down in
`validate-plan-paths.sh`:

> the folder-structure mistake that motivated it was authored in tasks.md,
> approved at SCOPE_GATE, and only then built. The write-time hook could not have
> caught it — by the time a file is written the plan is already law.

The same sentence applies verbatim to the fact demands.

## Rejected alternatives

**Downgrade `UNITY_HOOK_PROFILE` to `standard`.** Disables nine strict-level
hooks, only one of which is implicated (`enforce-skill-for-keywords.sh` and
`stop-verify.sh` are unrelated protections). Too blunt.

**Let subagents pass the retry by writing a facts receipt.** Identical to the
loophole the hook's own comment warns about (`gateguard.sh:74-77`): a subagent
that can write a retry can write a receipt. Adds an audit-trail theatre, changes
nothing.

**Cache plan approval in a new state file (`plan-facts-manifest`).** This design's
first draft. Rejected: the deadlock's root cause is two leaky state files
(`subagent-depth`, `gate-cleared`); solving it with a third one repeats the
mistake at a larger scale. Every file under `.claude/state/` is gitignored —
invisible, unreviewed, absent from git history. Decision evidence does not belong
there. A cached receipt also carries stale approval across a plan edit, which is
this project's most-experienced failure class.

## Design

No cache. The plan document **is** the manifest, re-read live on every check.

```
hooks/_lib.sh
  ├── unity_gate_cleared_valid          ← extracted from guard-gate-cleared.sh:43-70
  └── unity_plan_covers <path>          ← shared predicate, consulted by all three gates

hooks/lib-gateguard-facts.sh            ← single source of truth for fact rules
  ├── scripts/validate-plan-facts.sh    ← plan time: ALL tasks, before the gate
  └── hooks/gateguard.sh                ← write time: ONE path, recomputed live
```

This mirrors `lib-path-rules.sh` exactly: one library, two callers, no cache.

### Library contract

`hooks/lib-gateguard-facts.sh` exports:

| Function | Input | Output |
|---|---|---|
| `unity_find_task_line <path>` | script path | the declaring task line + body, empty if none |
| `unity_validate_task_facts <path> <mode>` | path + `new`\|`edit` | 0 = pass, 2 = missing/inconsistent + human-readable reason |
| `unity_gateguard_facts_summary` | — | positive receipt line |

Plan glob (`docs/**/tasks.md`) is defined once, in the library.

### Where the five demands went

| # | Demand | Destination |
|---|---|---|
| 1 | who will reference this type | plan — `Callers:` declaration |
| 2 | does an equivalent type exist | plan — automatic `grep` |
| 3 | which asmdef | plan — automatic `find` |
| 4 | DI registration / host prefab | plan — `Wiring:` declaration |
| 5 | quote the user's instruction | **ad-hoc path only** |
| + | `[FormerlySerializedAs]` plan | plan — conditional on edit tasks |

Demand 5 is dropped from the plan path deliberately. A quote written into a task
line is text the authoring agent produced itself — it proves nothing. What
actually holds it up already exists: `tasks.md` passes in front of a human at
SCOPE_GATE and lives in git. On the ad-hoc path there *is* a genuine
session-scoped instruction and a human who will read it, so the demand stays
there unchanged.

### `tasks.md` schema

Follows the existing sub-bullet convention (`- Test type:`, `- Acceptance:`); no
new syntax is invented.

```markdown
- [ ] T004 `_GameFolders/Scripts/Games/Concretes/Players/PlayerService.cs` — implementation
  - Callers: `Concretes/Players/PlayerController.cs`, T003 (EditMode test)
  - Wiring: PlayerModule.Install → Register<PlayerService>().AsImplementedInterfaces()
  - Test type: EditMode
  - Acceptance: T003 tests pass
```

**New vs edit is inferred, never declared.** Rule: path absent from disk → *new*;
present → *edit*. This is the `IS_WRITE` check `gateguard.sh` already performs.
Plan-internal exception: if the same path appears in an earlier task of the same
plan, later occurrences are *edits* (T002 creates it, T010 edits it — at plan time
neither exists on disk yet).

| Task kind | `Callers:` | `Wiring:` | `FormerlySerializedAs:` |
|---|---|---|---|
| new `.cs` | required | required | — |
| edit | — | — | conditional |
| test file (under `Tests/`) | exempt | exempt | — |

Test files are exempt because the question is structurally empty for them: no
callers, no wiring.

**Verification strength, stated honestly:**

- `Callers:` is **cross-verified** — each named target must exist on disk or be
  declared by another task in the same plan. Invented callers are caught.
- `Wiring:` is **cross-verified for `*Service`** — the plan must contain a
  `Module.cs` / `Install` task registering it. For `*Controller`, `*View`,
  `*Provider`, `*Manager` it is **presence-only**: a machine cannot know a prefab
  will exist at plan time.

Presence-only is weak and is labelled as such in the receipt, per CLAUDE.md
(*"A silent hook is NOT a compliance check"*). Its value is that the field cannot
be left blank, the answer lands in `tasks.md`, a human reads it at SCOPE_GATE, and
it stays in git. The machine is not deciding; it is forcing the decision into view.

**`FormerlySerializedAs:` trigger.** Required when the task text carries a rename
signal (`rename`, `yeniden adlandır`, `→`, `eski ad`) **and** the target file
contains `[SerializeField]`. See Residual Risks for its known gap.

### Plan-time validator

```
.claude/scripts/validate-plan-facts.sh docs/modules/02-xxx/
```

Parsing: a task line is a `- [ ]` line containing a backticked `.cs` path;
`[parallel_group:N]` prefixes are ignored; the body is the indented sub-bullets up
to the next task line, read as `- Key: value`; fenced code blocks are skipped so
draft C# is never mistaken for a field.

Per task:

```
path → under Tests/?              → yes: skip
     → on disk / earlier in plan? → no  → NEW:  require Callers + Wiring, then auto #2, #3
                                  → yes → EDIT: require FormerlySerializedAs if rename signalled
```

Automatic checks:

- **#2 duplicate type** — `grep -rn "class <Name>\b"` over `Assets/`,
  `_GameFolders/`; a hit that is not this task's own path is a violation.
- **#3 asmdef** — nearest `.asmdef` walking up from the path; none found is a
  violation (a file planned into a location no assembly owns).

Exit codes match `validate-plan-paths.sh`: `0` pass with receipt, `2` violations
listed with reasons, `1` usage error. **Finding no tasks is not a pass** — it
prints `NO TASKS FOUND — this is NOT a pass`, same as the path validator.

Receipt:

```
--- Plan Facts Validation ---
files scanned  : 1
tasks checked  : 12   (new: 9, edit: 3, test-exempt: 4)
cross-verified : callers 9/9, wiring 4/4 service tasks
presence-only  : wiring 5 (non-service — NOT machine-verified)
result         : OK
```

The `presence-only` line is deliberately separate: the receipt states what it did
*not* verify.

Wired as BLOCKING immediately after the existing `validate-plan-paths.sh` call in
`plan-module.md:103`, `create-plan.md:393`, `orchestrate.md:132`. The two scripts
are **not** merged — different libraries, different violation vocabularies, one is
already built and tested.

### Write-time gates

`gateguard.sh` Guard 1 (read-before-edit) is untouched: it never contributed to the
deadlock (subagents can `Read`) and independently guards against blind edits.

Guard 2 becomes:

```
unity_plan_covers(path) && facts valid ?
  ├── yes → allow, print receipt.  depth is NOT read.
  └── no  → today's deny-then-allow demand, depth-0 restriction preserved verbatim
```

`unity_plan_covers(path)` = all of:

1. `unity_gate_cleared_valid` — `gate-cleared` present **and** within TTL
2. `unity_find_task_line <path>` non-empty

`gateguard.sh` additionally requires `unity_validate_task_facts` = 0.
`guard-critical-files.sh` and `check-config-protection.sh` consult **coverage
only** — their demand is "investigate and confirm the change is intentional",
which a task declared in the plan and approved at SCOPE_GATE already satisfies;
requiring `Callers:`/`Wiring:` for a one-line `AppModules.cs` edit would be noise,
not a rule.

**`settings.json` is never released by plan coverage.** `check-config-protection.sh:99`
states this and it is the origin of this whole investigation — disabling a hook to
work around an error must stay closed.

**Prerequisite refactor:** the TTL block at `guard-gate-cleared.sh:43-70` is
extracted into `_lib.sh` as `unity_gate_cleared_valid()`, and that hook calls it.
Otherwise `2700` lives in two places and drifts. Behaviour must not change.

**Fail directions — every branch resolves toward the strict path.** Rows 1-3 and 5
apply to all three gates; row 4 applies to `gateguard.sh` only, since the other two
consult coverage without validating the facts block:

| Condition | Result |
|---|---|
| `gate-cleared` absent | ad-hoc gate |
| `gate-cleared` stale (> 2700s) | ad-hoc gate |
| path in no `tasks.md` | ad-hoc gate |
| task line present, facts block invalid (`gateguard.sh` only) | **distinct message** (below) |
| library fails to source / grep error / any unexpected error | ad-hoc gate |

The last row is load-bearing. Under `set -euo pipefail` an internal library error
exits the hook with status 1, which is **not blocking** — a silent fail-open.
Therefore `unity_plan_covers` runs in a subshell and **any** non-zero exit is
interpreted as "not covered". No uncertainty ever produces a pass.

The invalid-facts message is separate so the Director takes the right action: the
ad-hoc message says "present the facts and retry", but retrying cannot help here —
the problem is in `tasks.md`. It reads: *the plan covers this path but its facts
block is invalid — fix the plan and re-run `validate-plan-facts.sh`*, followed by
the library's reason.

`guard-pipeline-direct-work.sh` is not modified. The Director still cannot write
directly during a pipeline and `pipeline-override` remains the valve. The deadlock
breaks because **the subagent side opens** — that is the side that was wrong.

## Testing

`bats`, one file per hook, `UNITY_HOOK_STATE_DIR` is `mktemp -d` per test, so
suites are hermetic.

**Existing tests must stay green unmodified.** `gateguard.bats`'s *"fact-gate NEVER
clears on retry inside a subagent"* runs with a temp state dir containing no
`gate-cleared`, so `unity_plan_covers` returns false and the ad-hoc gate behaves
exactly as today. If that test needs editing, the ad-hoc path was changed by
accident — that is the regression signal.

TDD order, each step starting red:

| # | File | Pins |
|---|---|---|
| 1 | `guard-gate-cleared.bats` (existing) | behaviour unchanged after the TTL extraction |
| 2 | `lib-gateguard-facts.bats` (new) | parser: task line, `[parallel_group:N]`, sub-bullets, fence skipping |
| 3 | `lib-gateguard-facts.bats` | `unity_plan_covers` — one test per row of the fail-direction table |
| 4 | `validate-plan-facts.bats` (new) | exit codes 0/1/2; `NO TASKS FOUND is NOT a pass`; `presence-only` receipt line |
| 5 | `validate-plan-facts.bats` | `Callers:` cross-verification (invented caller = violation); `Wiring:` service cross-check |
| 6 | `gateguard.bats` | passes at depth 2 under plan coverage; unchanged behaviour without coverage |
| 7 | `guard-critical-files.bats` | `AppModules.cs` edit passes under coverage, blocks without |
| 8 | `check-config-protection.bats` | `.asmdef` passes under coverage; **`settings.json` blocks unconditionally** |

Tests 3 and 8 are the critical pair. Test 3 makes fail-open impossible, including
the deliberately-malformed-`tasks.md` case. Test 8 pins the origin of this
investigation: working around an error by disabling a hook stays closed.

## Backward compatibility

None required. `docs/modules/` contains only `_templates`, and the repo has no
project `.cs` outside `.claude/graph/test/fixtures/`. The new schema is the only
schema from birth. Module 02 is the first plan and the first code — the intended
pilot.

## Residual risks

Stated, not silently accepted:

| Risk | Status |
|---|---|
| `subagent-depth` leaks | Not fixed. The harness exposes no reliable signal. Blast radius shrinks to ad-hoc work only; pipelines no longer read it. |
| Subagent running > 15 min + `guard-pipeline-direct-work.sh` staleness downgrade blocks its edit | Pre-existing, accepted in that hook's own comment; valve is `pipeline-override`. |
| A rename nobody wrote into the task text escapes the `FormerlySerializedAs` heuristic | Open. Plan time has no diff to read. Closing it needs a write-time field-name diff — out of scope here. |
| `Wiring:` unverified for non-service types | Open by design. Presence-only, labelled as such in the receipt. |
| A task line added purely to pass the gate | Possible, but `tasks.md` is git-tracked and human-reviewed at SCOPE_GATE — unlike a gitignored receipt file. |

## Out of scope

- Fixing the `subagent-depth` counter itself
- Write-time serialized-field diffing
- Merging `validate-plan-paths.sh` and `validate-plan-facts.sh`
- Any change to `settings.json` (blocked by `check-config-protection.sh`; also not needed by this design)
