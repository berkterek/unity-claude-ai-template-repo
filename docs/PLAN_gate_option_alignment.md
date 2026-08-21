# PLAN — Gate Option Alignment (scopes B + C)

> **Version:** v1 — 2026-08-21
> **Status:** Implemented 2026-08-21
> **Scope:** `.claude/commands/*.md` decision blocks, `.claude/docs/director-gates.md`
> **Complexity:** 0.4 — Medium. No new mechanism; one new gate definition plus pointer
> rewrites. The risk is textual, and scope A measured that added prompt lines have a cost.

## Context

Scope A gave every automated check gate a definition and a named caller. What it did not
touch is the **human-pause decision blocks that carry no gate name at all** — a user is
shown a menu of options that exists nowhere in `director-gates.md`, so the option set is
re-authored at each call site and drifts.

This plan was scoped as two questions. The first one is answered by measurement and the
answer is **no change needed** — that finding is the plan's most valuable output, because
it prevents 13 edits that would have made the pipelines worse.

### Scope B — dismissed, with the measurement

The premise was: *ten decision blocks offer only `skip`/`stop`, while `QUALITY_GATE`
canonically offers `fix`/`skip`/`stop` — is the missing `fix` a defect?*

It is not. Measured 2026-08-21 — there are **13** such blocks, not ten, and every one of
them is an **exhaustion branch**: it is reached only after the retry budget is already
spent.

| Site | Reached after |
|---|---|
| `implement.md:343`, `fix.md:402` | 2 validator fix passes failed |
| `implement.md:435`, `fix.md:497`, `migrate.md:332`, `orchestrate.md:525`, `scene-setup.md:269` | 3 reviewer passes failed |
| `implement.md:471`, `fix.md:536` | 3 verifier iterations failed |
| `create-prefab-scene.md:289` | 3 unity-developer passes failed |
| `create-plan.md:389`, `update-plan.md:301` | 3 planner/reviewer passes failed |
| `qa.md:113` | 2 compile/test-fix passes failed |

At that point `fix` is not a missing option — it is the option that was just tried N times
and failed. Offering it there would make the loop unbounded, contradicting
`director-gates.md` → **Retry and Pass Limits**, which scope A added specifically to bound
these loops. **Do not add `fix` to any of these blocks.**

**Three** blocks in `.claude/commands/` offer no named abort. This plan's v1 draft said
two; enumerating every option block mechanically found a third, which is why the
enumeration is an acceptance criterion in T3 and T8 rather than a spot-check:

- `qa.md:113` names `skip` but leaves abort as `*(anything else)* → abort` — an unnamed
  branch where the twelve other exhaustion blocks name `stop`.
- `orchestrate.md:714-715` offers `retry`/`skip` and **no abort at all** — the user cannot
  stop the pipeline at that point.
- `qa.md:216-218` offers `fix`/`list`/`skip` — also no abort. This one is a scope-C site
  (T4), not an exhaustion branch, but it is the same defect and T4 must fix it there.

### Scope C — five unnamed decision points

`SCOPE_GATE`, `ARCHITECTURE_GATE`, `BREAKING_GATE`, `BREAKING_REVISION_GATE`,
`QUALITY_GATE`, `COMMIT_GATE`, `SPARC_GATE` are referenced by name 75 times across the
commands. The following decision points pause for a human and are referenced **zero**
times, because they have no name:

| Decision point | Sites | Options |
|---|---|---|
| The exhaustion branch above | 13 | `skip` / `stop` |
| `/qa` findings menu | `qa.md:216-218` | `fix` / `list` / `skip` |
| `/fix-deep` reproduction evidence | `fix-deep.md:354-356` | `retry` / `manual:` / `stop` |
| `/fix-deep` REFUTED hypothesis | `fix-deep.md:398-399` | `retry` / `stop` |
| `/orchestrate` post-QA validation | `orchestrate.md:714-715` | `retry` / `skip` |

Not findings, checked and rejected: the silent-failure-hunter block
(`implement.md:527`, `fix.md:592`, `fix-deep.md:631`) already calls `QUALITY_GATE` by name;
`create-plan`/`update-plan`'s breaking-revision blocks were named in scope A.

## Measurement — run 2026-08-21, before any edit

Every claim above was tested rather than asserted, because scope A shipped two changes that
passed every static check while making the reviewer measurably worse.

| Claim | Method | Result |
|---|---|---|
| 13 exhaustion blocks, each behind a spent budget | enumerate all option blocks; for each, search backwards for the budget statement | **CONFIRMED.** 15 `skip` blocks total, minus `orchestrate.md:715` (`retry`/`skip`) and `qa.md:216-218` (`fix`/`list`/`skip`) = 13. Both verifier sites state their bound at `implement.md:461` / `fix.md:526`, outside the block |
| Adding `fix` makes the loop unbounded | give an agent a block that *does* offer `fix` past exhaustion; ask what bounds the repeat | **CONFIRMED — `BOUNDED: no`.** It reached the same reasoning independently: "the 3 passes counts reviewer passes *before* the gate, not gate visits… nothing decrements a budget or forbids a fourth, fifth or tenth visit" |
| A pointer to the gate is as good as inline options (**the T2 risk**) | A/B two agents on the same failing state: inline `skip`/`stop` bullets vs. an `EXHAUSTION_GATE` pointer | **CONFIRMED for the option set.** Both arms: `OPTIONS_OFFERED: skip, stop`. Scope A's failure does not reproduce here — see the rule below |
| Two blocks lack a named abort | enumerate every option block, assert a `stop` is present | **REFUTED — there are three.** `qa.md:216-218` was missed by listing from memory |
| Gate boxes are all 58-char rules | measure every rule in `director-gates.md` | **REFUTED.** The invariant is total *line* length 58; rule widths run 35–46. And they do not all match — `SCOPE_GATE` is 57 |

### Why the pointer is safe here but was not in scope A

Scope A collapsed a five-bullet `Checks:` list into a prose pointer and the reviewer dropped
from 5/5 axes to 3/5 — it silently skipped the two it was no longer told existed. The
difference is not "pointer bad, inline good":

> **A pointer is safe when its target enumerates, and lossy when its target only gestures.**
> `EXHAUSTION_GATE` names both options explicitly, so nothing is lost. Scope A's prose
> pointer named no axes, so the count of things to check became unknowable.

Apply that test before replacing any block with a pointer, in this plan or a later one.

### An unmeasured regression the A/B surfaced

The two arms offered the same options but not the same *help*. The inline arm named the rule
each finding violated and stated what `skip` costs ("ships a per-frame allocation and a
broken DIP seam that also blocks NSubstitute mocking"). The pointer arm emitted the bare box
and nothing else.

For a gate whose entire purpose is a human decision, that is a regression in a dimension this
plan was not measuring. It is one A/B pair, so treat it as a lead, not a finding — but it is
cheap to design against: T1 must make a consequence line part of the box rather than leaving
it to the caller's initiative. Re-run the A/B after T1 to check the line actually appears.

## Goals

- [ ] Record the scope-B dismissal where it cannot be re-litigated by the next reader
- [ ] Define `EXHAUSTION_GATE` once; replace 13 restated option sets with pointers
- [ ] Give all three abort-less blocks a named abort (`qa.md` ×2, `orchestrate.md`)
- [ ] Name the four remaining decision points, or record why one stays unnamed

## Non-goals

- Adding `fix` to any exhaustion branch (measured wrong — see above)
- Changing any retry budget (scope A set them; this plan only names what happens after)
- A new hook. These are human-pause gates; nothing mechanical can enforce a menu

## Status

| Phase | Task | Status | parallel_group |
|-------|------|--------|----------------|
| 1 | T1 — define `EXHAUSTION_GATE` | ✅ Done | — |
| 2 | T2 — point the 13 sites at it | ✅ Done | — |
| 2 | T3 — name the abort in all 3 abort-less blocks | ✅ Done | — |
| 3 | T4 — name `/qa` findings menu | ✅ Done | 1 |
| 3 | T5 — name the two `/fix-deep` points | ✅ Done | 1 |
| 3 | T6 — `/orchestrate` post-QA point | ✅ Done | 1 |
| 4 | T7 — sync README + CLAUDE.md | ✅ Done | — |
| 4 | T8 — verify | ✅ Done | — |

T2 must follow T1 (a pointer to an undefined gate is the exact defect scope A fixed).
T3 edits `qa.md:113` and `orchestrate.md:714`; T2 edits `qa.md:113` too — **same file,
same line: T3 runs after T2, not in parallel.**

## File Map

| File | Change | Notes |
|------|--------|-------|
| `.claude/docs/director-gates.md` | Modify | +1 human-pause gate, +1 or more C gates, table row(s) |
| `.claude/commands/implement.md` | Modify | 3 exhaustion sites |
| `.claude/commands/fix.md` | Modify | 3 exhaustion sites |
| `.claude/commands/fix-deep.md` | Modify | 2 C sites |
| `.claude/commands/orchestrate.md` | Modify | 1 exhaustion + 1 C site + missing abort |
| `.claude/commands/qa.md` | Modify | 1 exhaustion + unnamed abort + findings menu |
| `.claude/commands/{migrate,scene-setup,create-prefab-scene,create-plan,update-plan}.md` | Modify | 1 exhaustion site each |
| `README.md`, `.claude/CLAUDE.md` | Modify | gate tables |

---

## Task 1 — Define `EXHAUSTION_GATE`

**Files:** `.claude/docs/director-gates.md`

**Steps:**
1. [ ] Add `### EXHAUSTION_GATE` under `## Human-Pause Gates`, after `QUALITY_GATE` —
   it is the branch QUALITY_GATE falls through to, so it reads in order.
2. [ ] Box geometry — **measured, because v1 of this plan got it wrong.** The invariant is
   *total line length 58*: `NAME` + one space + dashes filling to 58, and a closing rule of
   58 dashes. It is **not** a fixed rule width (those range 35–46 by name length), and the
   boxes do **not** all match: `SCOPE_GATE` is 57 on both its lines, a pre-existing off-by-one.
   Match `COMMIT_GATE` (58). Do **not** "fix" `SCOPE_GATE` here — out of scope, record only.
3. [ ] Options are exactly `skip` / `stop`. State in prose *why* `fix` is absent, citing
   `## Retry and Pass Limits` — otherwise the next reader re-adds it.
4. [ ] The box must interpolate what was exhausted; a fixed string cannot serve 13 callers
   with four different budgets. Use a placeholder: `after [N] [pass type] passes`.
5. [ ] Add the row to the `## Human-Pause Gates` summary table if one exists in this file.
6. [ ] **Require a consequence line in the box** — what `skip` actually ships. The A/B above
   showed the pointer arm emitting the bare template while the inline arm volunteered the
   cost of skipping. A gate that pauses for a human decision and then withholds the basis
   for it is worse than the restatement it replaced.
7. [ ] Record what the unbounded-loop test surfaced beyond the plan's own argument: an
   **unchanged finding set across rounds** means the fixer cannot resolve those findings, so
   another `fix` cannot help by construction. That is the strongest form of the argument for
   this gate's option set, and it belongs in the definition.

**Test Type:** NoTest (markdown)

**Skeleton:**
```
### EXHAUSTION_GATE

**When:** A bounded retry loop has spent its budget and the work is still failing.
**Purpose:** The budget is gone; only a human can decide whether to ship the known-bad
state or abandon the run.

EXHAUSTION_GATE ──────────────────────────────────────────
[what was being retried] still failing after [N] [pass type] passes:
[list every remaining issue]

Options:
  skip   — proceed anyway (your responsibility)
  stop   — abort
──────────────────────────────────────────────────────────

> **`fix` is deliberately absent.** This gate is only reachable once the fix loop has
> already run its full budget — see `## Retry and Pass Limits`. Offering `fix` here makes
> the loop unbounded, which is the defect those limits exist to prevent. A user who wants
> another attempt picks `stop` and re-runs the command.
```

**Acceptance Criteria:**
- Total line length is 58 for both the opening and closing rule, verified against `COMMIT_GATE`
- The "`fix` is deliberately absent" note is present and cites Retry and Pass Limits
- Both option words match all 13 call sites verbatim (`skip`, `stop`)
- The box carries a consequence line stating what `skip` ships
- **Re-run the inline-vs-pointer A/B after this task.** Pass = both arms offer `skip`/`stop`
  *and* both state the cost of skipping. The first half already passed; the second is the
  one this task adds, so it is the one that can regress

---

## Task 2 — Point the 13 exhaustion sites at the gate

**Files:** the 10 command files listed in the Context table

**Steps:**
1. [ ] At each of the 13 sites, replace the two restated option bullets with a reference:
   `show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`)`, keeping the site-specific
   part — what was exhausted and after how many passes.
2. [ ] Do **not** delete the pass count at the call site. The gate box needs it as input;
   only the option *list* is centralized.
3. [ ] Re-check every line number in this plan before editing. Scope A hit stale line
   numbers three times: they rot the moment any earlier line in the file moves.

**Test Type:** NoTest

**Acceptance Criteria:**
- `grep -c 'EXHAUSTION_GATE' .claude/commands/*.md` sums to 13
- No command file restates the `skip`/`stop` option pair for an exhaustion branch
- Each site still states what was exhausted and after how many passes

---

## Task 3 — Give every abort-less block a named abort

**Files:** `.claude/commands/qa.md`, `.claude/commands/orchestrate.md`

**Steps:**
1. [ ] `qa.md:113` — replace `*(anything else)* → abort` with a named `stop`. An unnamed
   catch-all abort means the transcript never records that the user chose to abort.
2. [ ] `orchestrate.md:714-715` — add `stop → abort`. Currently `retry`/`skip` are the only
   options, so a user who wants out has no listed way to take it.
3. [ ] `qa.md:216-218` — add `stop → abort`. (T4 owns the naming of this block; the abort
   belongs here so all three land in one reviewable change.)
4. [ ] **Do not spot-check these three.** Enumerate every option block in
   `.claude/commands/` and assert each offers a named abort. The v1 draft of this plan
   missed `qa.md:216-218` precisely by listing sites from memory instead of enumerating.
5. [ ] Runs **after** T2 — T2 touches `qa.md:113` as well.

**Test Type:** NoTest

**Acceptance Criteria:**
- Every human-pause decision block in `.claude/commands/` offers a named abort
- Verified by enumerating option-bullet blocks, not by spot-checking these two files

---

## Task 4 — Name the `/qa` findings menu

**Files:** `.claude/docs/director-gates.md`, `.claude/commands/qa.md`

**Steps:**
1. [ ] Decide first whether this is `QUALITY_GATE` with a third option or its own gate.
   Evidence for reuse: `fix`/`skip` match and the trigger is identical (a reviewer-style
   pass returned findings). Against: `list` is not in QUALITY_GATE, and there is no `stop`.
2. [ ] Recommended: extend `QUALITY_GATE` with an optional `list` rather than minting a
   near-duplicate gate — two gates differing by one display-only option is the drift this
   plan exists to remove. Add `stop` to `qa.md` while there.
3. [ ] If extended, say in `QUALITY_GATE` that `list` is display-only and re-shows the gate
   — it is not a terminal choice, and a caller that treats it as one will exit early.

**Test Type:** NoTest

**Acceptance Criteria:**
- `qa.md:216-218` references a gate by name
- `list` is documented as non-terminal wherever it lands
- `qa.md` findings menu offers a named abort

---

## Task 5 — Name the two `/fix-deep` decision points

**Files:** `.claude/docs/director-gates.md`, `.claude/commands/fix-deep.md`

**Steps:**
1. [ ] `fix-deep.md:354-356` (`retry` / `manual: <description>` / `stop`) — the user is
   asked to produce evidence the agent cannot obtain itself. Propose `EVIDENCE_GATE`.
2. [ ] `fix-deep.md:398-399` (`retry` / `stop` on a REFUTED hypothesis, max 2 cycles) — a
   different decision: whether to spend another investigation cycle. Propose
   `HYPOTHESIS_GATE`, and state the 2-cycle bound in the definition so the two numbers
   cannot drift apart at the call site.
3. [ ] Both are `/fix-deep`-only. **State that in each definition.** Scope A found five
   gates that were defined with no caller at all; a single-caller gate is fine, a gate
   whose caller count is unstated is how that happens.
4. [ ] `manual: <description>` takes free-form input, unlike every other option in the
   file, which is a fixed word. Document the parse expectation.

**Test Type:** NoTest

**Acceptance Criteria:**
- Both sites reference a gate by name; both gates name `/fix-deep` as their only caller
- `HYPOTHESIS_GATE`'s definition and `fix-deep.md`'s call site state the same cycle bound
- `manual:` prefix syntax documented

---

## Task 6 — `/orchestrate` post-QA validation point

**Files:** `.claude/commands/orchestrate.md`, possibly `.claude/docs/director-gates.md`

**Steps:**
1. [ ] After T3 adds `stop`, the option set is `retry`/`skip`/`stop` — structurally
   identical to `QUALITY_GATE`'s `fix`/`skip`/`stop`, with `retry` meaning "re-run the
   whole QA stage" rather than "spawn a coder".
2. [ ] Judge whether that difference warrants a name. Recommended: **reference
   `QUALITY_GATE` and state the substitution** (`retry` replaces `fix` because the failing
   thing is a validation stage, not a file). One line beats a fourth near-duplicate gate.
3. [ ] If the substitution is too confusing to state in one line, mint the gate instead
   and record why here — this decision, either way, is the task's real output.

**Test Type:** NoTest

**Acceptance Criteria:**
- The site references a gate by name, whichever route was chosen
- The `retry`-for-`fix` substitution is stated wherever the reference lands
- If a new gate was minted, the reason is written into this plan file

---

## Task 7 — Sync `README.md` and `.claude/CLAUDE.md`

**Files:** `README.md`, `.claude/CLAUDE.md`

**Steps:**
1. [ ] Add every gate defined by T1/T4/T5/T6 to the gate table in **both** files. Scope A
   found the same stale claim in five places, including files `@`-included into every
   session — a gate table that lags the definitions is exactly that failure.
2. [ ] Check `.claude/docs/hooks-blocking.md` and `docs/modules/_templates/` too: both
   carried stale gate claims in scope A.
3. [ ] `CLAUDE.md`'s Director Gates table lists *what you decide* per gate — fill that
   column with a real decision, not a restatement of the gate name.

**Test Type:** NoTest

**Acceptance Criteria:**
- Every gate in `director-gates.md` appears in both tables; no table lists a gate that
  is not defined
- No file claims a gate fires somewhere it does not

---

## Task 8 — Verify

**Steps:**
1. [ ] **Symmetry, both directions:** every gate name in `director-gates.md` has ≥1 caller
   in `.claude/commands/`, and every `*_GATE` referenced in a command is defined. Both
   directions — scope A's residue gates were defined-but-uncalled, and a typo'd reference
   is called-but-undefined. One-directional checking finds neither reliably.
2. [ ] Every option-bullet block in `.claude/commands/` either references a gate by name
   or is recorded in this plan as deliberately unnamed.
3. [ ] Every such block offers a named abort.
4. [ ] Box rules in `director-gates.md` are all 58 chars.
5. [ ] `.claude/hooks/tests/` full run stays green (417/417). Nothing here touches a hook,
   so a change in that number means an unintended edit — the value is as a tripwire.
6. [ ] **A green static pass is not evidence the prompts got better.** Scope A shipped two
   changes that passed 417/417, every line-number check and a symmetric gate inventory
   while making the reviewer measurably worse. Both were caught only by running an agent.
   If any task here ends up editing reviewer criteria or an output contract, run
   `.claude/tests/reviewer-fixtures/` before and after and record both numbers.
7. [ ] Nothing in this plan is expected to touch reviewer criteria. If a task does, that
   is a scope change worth surfacing, not a detail.

**Acceptance Criteria:**
- Gate symmetry holds in both directions
- Zero unnamed human-pause decision blocks, or each exception recorded here with a reason
- Hook suite unchanged at 417/417

---

## Implementation record — 2026-08-21

Three gates defined (`EXHAUSTION_GATE`, `EVIDENCE_GATE`, `HYPOTHESIS_GATE`), `QUALITY_GATE`
extended with a display-only `list`, 13 exhaustion sites and 4 other decision points pointed
at a named gate, 3 abort-less blocks given a named abort, both gate tables synced.

Two things surfaced during T8 that were not in the plan:

- **`SPARC_GATE` looked called-but-undefined and was not.** It is defined as a `####` heading
  under `## How to Reference Gates in Pipeline Commands`, in table form. The symmetry check
  scanned `^### ` only. The defect was in the check, not the repo — so the fix was the check,
  plus a note in `director-gates.md` telling the next auditor to match `####` too. This is the
  same shape as scope A's TD-COMPILE deletion: two true premises ("7 references", "not under
  `### `") and a false conclusion. Looking before editing is what separated the two outcomes.
- **The header bullet list did not mention `SPARC_GATE` at all**, so the file's own summary of
  what it contains was incomplete. Fixed.

`SCOPE_GATE`'s 57-char box was left alone, as planned — recorded, not fixed.

## Behavioural test results — 2026-08-21, after implementation

Five agent runs against the edited prompts. Pass conditions were written before each run.

| # | What it measured | Pass condition | Result |
|---|---|---|---|
| 1 | `EXHAUSTION_GATE` pointer vs. the inline bullets it replaced | both arms offer `skip`/`stop` | **PASS** — identical option sets |
| 2 | the mandatory `Skipping ships:` line (re-run of 1 after T1) | options offered **and** the cost of skipping stated | **PASS** — `CONSEQUENCE_STATED: yes`, a distinct runtime cost per finding |
| 3 | `list` is non-terminal — **highest blast radius: a new option on a gate called from 15 sites** | prints detail, re-shows the gate, advances nothing | **PASS** — `GATE_RESHOWN: yes`, `PIPELINE_ADVANCED: no`. It also dropped the `list` line from the re-show, which is the gate's own "omit when already shown in full" rule applied unprompted |
| 4 | `retry`-for-`fix` substitution in `/orchestrate` | offers `retry`/`skip`/`stop`, never `fix`, and says retry re-runs the stage | **PASS** — "re-runs the whole QA validation stage from Step 1, rather than spawning a coder" |
| 5 | `HYPOTHESIS_GATE` → `EXHAUSTION_GATE` chain after 2 spent cycles | shows EXHAUSTION_GATE with `N`=2 / `PASS_TYPE`=revision, offers no third cycle | **PASS** — `RETRY_OFFERED: no` |
| 6 | `EVIDENCE_GATE`'s `manual:` prefix — the only free-form option in the file | empty `manual:` re-shows the gate; non-empty is carried verbatim without demanding quoting | **PASS** — `DEMANDED_QUOTING: no`, evidence text carried unmodified |

### A gap the tests found that this plan did not

Filling `Skipping ships:` at the hypothesis fall-through, run 5 observed on its own that "any
debug logging added during the two investigation cycles remains in the code unless removed" —
the `stop` branch said to remove it and the fall-through said nothing. The `skip` destination
was undefined there too: at hypothesis exhaustion the root cause is unknown, so what `skip`
even means was never stated.

Both are now spelled out at that call site: `skip` proceeds to the fix against an explicitly
**unproven** hypothesis and must be labelled as such, and debug logs are removed on both
paths. Worth noting how this surfaced — not from reviewing the diff, but from making an agent
fill in a field the gate now requires. A mandatory field is a question, and questions find
things assertions do not.

## What this plan deliberately does not do

`fix` is not added to any exhaustion branch. That was the question scope B opened with, and
the answer is measured, not argued: all 13 sites sit past a spent retry budget, so `fix`
there is an unbounded loop. If a future reader wants to revisit it, the thing to change is
the **budget** in `## Retry and Pass Limits` — not the option list at the call site.
