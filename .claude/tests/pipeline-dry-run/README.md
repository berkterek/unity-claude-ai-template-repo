# Pipeline Dry-Run Harness

Measures **gate order** and **state-file lifecycle** across a whole pipeline command, by
driving the real command file against a throwaway fake-Unity project with a scripted user
and scripted subagent results.

## The gap this covers

| Layer | Covered by | Measures |
|---|---|---|
| A guard hook's reaction to a state file | `.claude/hooks/tests/` — 36 bats suites | exit code. Deterministic. All six `guard-*.sh` covered **and** registered in `settings.json` — verified |
| A reviewer prompt's effect on a verdict | `.claude/tests/reviewer-fixtures/` | which criteria fire on planted defects |
| **A pipeline creating the state file at the right step and removing it at the end; gates firing in the documented order** | **this harness** | gate sequence, state-file lifecycle, whether the Director does the work itself |

Not covered by any of the three: `TD-COMPILE` (needs Unity + MCP), PlayMode tests,
prefab/scene work. Passing this says nothing about those.

## How to run

1. `SB="$(.claude/tests/pipeline-dry-run/make-sandbox.sh)"`
2. Spawn a subagent as the Director. Give it `$SB` as the project root and tell it to read
   the command from `$SB/.claude/commands/<cmd>.md`. Require it to:
   - **not** spawn real subagents — print `SPAWN: <agent> — <purpose>` instead
   - **actually** perform state-file operations with Bash inside the sandbox, printing each
   - **not** edit any `.cs` itself
3. Script every human reply and every subagent result in the prompt. To exercise the
   exhaustion branch, script the **same** reviewer finding three times — an unchanged
   finding set is also the case where `fix` provably cannot help.
4. Require a final block whose fields are **exactly** the right-hand column of the pass-condition
   table below — copied, not re-authored. Any condition without a field in that block is a
   condition the run did not measure.

## Pass conditions — one list, and it IS the final-block spec

**A condition with no field is not a condition.** Run 1 listed ten conditions and asked for
five fields; the two that had no field went unmeasured and were nearly read as passes. The
fix is not "remember to ask" — it is that this table has a field column, so a condition
without a way to measure it is visible in the table itself. Copy the right-hand column into
the agent prompt verbatim; do not re-author the field list, or the two lists drift apart
again — the same defect this repo's gate work spent a day removing, one layer up.

| # | Condition | Field that measures it |
|---|---|---|
| P1 | `SCOPE_GATE` shown before any spawn | `FIRST_EVENT:` — first gate or SPAWN line, whichever came first |
| P2 | `gate-cleared` created only *after* the simulated `go` | `STATE_CREATED_AFTER_GO:` yes/no |
| P3 | `SPARC_GATE` shown and `sparc-approved` created before the coder spawn | `SPARC_BEFORE_CODER:` yes/no |
| P3b | `sparc-approved` is still **present** at every *subsequent* coder-class spawn (validator fix pass, reviewer fix pass, Ralph loop) | `SPARC_AT_LATER_SPAWNS:` one `PRESENT`/`ABSENT` per later spawn, with step numbers |
| P4 | The Unity Validator step (`TD-COMPILE`) runs **before** the reviewer spawn | `VALIDATOR_BEFORE_REVIEWER:` yes/no + the two step numbers |
| P5 | 1st and 2nd `CHANGES NEEDED` → `QUALITY_GATE` (budget remains, `fix` valid) | `GATE_ORDER:` |
| P6 | 3rd `CHANGES NEEDED` → `EXHAUSTION_GATE`, **not** `QUALITY_GATE` | `THIRD_FAILURE_GATE:` |
| P7 | `EXHAUSTION_GATE` offers only `skip`/`stop` and carries a `Skipping ships:` line | `EXHAUSTION_BOX:` verbatim |
| P8 | State files removed when the run ends | `STATE_FILES_REMAINING:` |
| P8b | *Where* `sparc-approved` was deleted — Completion, not coder return | `SPARC_DELETED_AT:` step number + the step's name |
| P9 | The Director edited no `.cs` itself | `DIRECTOR_EDITED_CS:` yes/no |
| P10 | Nothing outside the sandbox was written | **no field — measured by the caller**, not the agent. Check the real repo's `.claude/state/` yourself afterwards; an agent that wrote outside its sandbox is the last witness to trust about it |

P10's exemption is the shape to copy when a condition genuinely cannot be a field: say who
measures it instead, in the table. "No field" is only acceptable when it is written down.

**Why P3b and P8b exist — a condition can be present, measurable, and still blind.** This
harness's stated trigger is "a pipeline's step order or its state-file handling changed", and
the SPARC-gate lifetime defect (`6f62324`) is exactly that — yet P3 and P8 as originally
written **passed on the broken behaviour**. P3 only looked before the *first* coder, and the
deletion happened after it; P8 only looked at the end, and the end was empty either way. The
run that did catch it caught it in prose, not in a field. That is one layer above this file's
own "a condition with no field is not a condition" rule: a condition with a field can still
measure the wrong moment. When a defect is about *when* something happens, at least one field
must carry a step number, not a yes/no.

## Recorded runs

### 2026-08-21 — `/implement`, reviewer fails 3× with an identical finding

`GATE_ORDER: SCOPE_GATE, SPARC_GATE, QUALITY_GATE, QUALITY_GATE, EXHAUSTION_GATE`

| Condition | Result |
|---|---|
| P1, P2 | **PASS** — `gate-cleared` created after the SCOPE_GATE `go` |
| P3 | **PASS** — `sparc-approved` created after the SPARC_GATE `go`. ⚠️ **This row also records the deletion happening once the coder completed, "matching the gate's own Deleted row" — that behaviour was later found to be the defect fixed by `6f62324`, and the gate row itself was wrong. Read this as a PASS on P3 as then written, not as evidence about the SPARC lifetime; P3b and P8b were added because nothing here could see it.** |
| P5 | **PASS** — two `QUALITY_GATE`s while the budget held |
| P6 | **PASS** — the third failure produced `EXHAUSTION_GATE` |
| P8 | **PASS** — state dir empty at the end; `gate-cleared` removed on abort |
| P9 | **PASS** — `DIRECTOR_EDITED_CS: no` |
| P10 | **PASS** — verified independently in the real repo: no `gate-cleared`, `sparc-approved` or `pipeline-override` |
| P4, P7 | **NOT MEASURED** — see below |

**Design flaw in this run, recorded so it is not repeated:** P4 and P7 were written as pass
conditions but the final block never asked for them. The validator is not a gate, so it
cannot appear in `GATE_ORDER`; and the gate's body was in the transcript but not in any field
that came back. A condition you do not ask for in the final block is a condition you did not
measure — listing it and then reading the result as a pass is exactly the "green because
nothing looked at it" failure the whole gate audit exists to prevent. Add
`VALIDATOR_BEFORE_REVIEWER: yes/no` and `EXHAUSTION_BOX: <verbatim>` next time.

### 2026-08-21, run 2 — same scenario, complete field list

Re-run for one reason: close P4 and P7, which run 1 could not score. Every field in the
table's right-hand column was requested, and every one came back.

| Condition | Result |
|---|---|
| P1 | **PASS** — `FIRST_EVENT: SCOPE_GATE`, before any SPAWN line |
| P2 | **PASS** — `STATE_CREATED_AFTER_GO: yes` |
| P3 | **PASS** — `SPARC_BEFORE_CODER: yes` |
| **P4** | **PASS — newly measured.** Validator at step 16, first reviewer spawn at step 17 |
| P5 | **PASS** — `QUALITY_GATE` twice while the budget held |
| P6 | **PASS** — `THIRD_FAILURE_GATE: EXHAUSTION_GATE` |
| **P7** | **PASS — newly measured.** Box offers only `skip`/`stop`; both rules 58 chars; `Skipping ships:` carried a substantive consequence, not a restatement of the finding: "the Unity call cannot be mocked, so the NSubstitute seam the tests rely on is broken, and swapping the rotation backend later requires rewriting TurretService itself" |
| P8 | **PASS** — state dir empty at the end |
| P9 | **PASS** — `DIRECTOR_EDITED_CS: no`, working tree clean |
| P10 | **PASS** — verified in the real repo by the caller, per the table |

Two runs, independently produced, gave the identical `GATE_ORDER`. That is worth more than
either run alone: a sequence of five gates reproducing exactly is not a plausible coincidence,
which is the standard the Limits section below asks for.

**One cosmetic item, deliberately not fixed:** the box's first line renders as "the reviewer
loop still failing after 3 reviewer passes" — a lowercase noun phrase opening a sentence,
because `$WHAT_WAS_RETRIED` sits at the start of the template line. Callers supply it
lowercase, which reads correctly mid-sentence and slightly oddly at line start. Left alone:
it changes no decision, and editing the template across 13 call sites to fix letter case is
not worth the churn. Recorded so the next reader knows it was seen, not missed.

### Observation that was **not** a defect

The Director reported that `implement.md`'s inline
`mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo … > …` one-liner was
denied by a permission classifier, and it wrote the identical content to the identical path
via `Write` instead — correctly, without routing around the intent.

Tested afterwards: the byte-identical one-liner runs fine from the main session, exit 0,
correct JSON. So the friction is specific to a restricted subagent environment, **not** a
defect in the command. Three command files were left unchanged on the strength of that
measurement. One observation in an artificial environment is not grounds to edit a working
instruction — check whether it reproduces outside the sandbox first.

## Limits

- **Not deterministic.** One `PASS` does not rule out a meaningful failure rate: at a true
  rate of 30%, a single run still passes 70% of the time. Re-run before treating a change
  as a regression, and prefer conditions that are behavioural (a sequence, a lifecycle) over
  binary ones — those are harder to satisfy by chance.
- **A dry run, not a real run.** Every subagent result and every human reply is scripted by
  the prompt. It proves the Director sequences correctly *given* those results; it does not
  prove a real reviewer would return them, and it never compiles anything.
- **`hooks/` and `settings.json` are not copied into the sandbox**, so no content hook fires
  on the sandbox's own paths. Hook behaviour belongs to the bats suites; do not read this
  harness as covering it.
- **Costs one long agent invocation** (~3 min). Run it when a pipeline's step order or
  state-file handling changes — not on every commit.

### 2026-09-13 — `/implement`, first run measuring P3b/P8b

`GATE_ORDER: SCOPE_GATE, SPARC_GATE, QUALITY_GATE, QUALITY_GATE, EXHAUSTION_GATE, COMMIT_GATE`

Run immediately after `6f62324`'s SPARC fix and the `director-gates.md` correction, to measure
the two fields that were added because nothing here could see that defect.

| Condition | Result |
|---|---|
| P1, P2 | **PASS** — `FIRST_EVENT: SCOPE_GATE` (step 7), before the first spawn (step 8) |
| P3 | **PASS** — `sparc-approved` created step 9, coder spawned step 10 |
| **P3b** | **PASS** — PRESENT at step 14 and step 17, the two later coder-class spawns |
| P4 | **PASS** — validator step 11, reviewer step 12 |
| P5, P6 | **PASS** — two `QUALITY_GATE`s, third failure produced `EXHAUSTION_GATE` (step 19) |
| P7 | **PASS** — `skip`/`stop` only; `Skipping ships:` named the actual unclosed DIP boundary |
| **P8b** | **PASS** — deleted at step 26, Completion, with `gate-cleared` |
| P8, P9 | **PASS** — state dir empty; `DIRECTOR_EDITED_CS: no` |
| P10 | **PASS** — verified by the caller in the real repo, before and after |

**The deadlock did not reproduce, and this is the first run that could have seen it.** The
2026-08-21 runs recorded the deletion-on-coder-return as a pass because P3 and P8 did not look
at those moments.

**Defect this run found, in `director-gates.md`:** the COMMIT_GATE block hardcoded
`Reviewer: APPROVED` as a literal while every other field was a variable. `/implement` reaches
COMMIT_GATE from an `EXHAUSTION_GATE` `skip`, which by definition ships a state the reviewer
did not approve — so the one gate whose purpose is informed consent stated the opposite of what
happened, and the human has no other source for it. Both verdict lines are variables now. Found
only because the run took the exhaustion branch; a run scripted to pass review never reaches it.

**Harness gaps this run closed:** `skills/` and `agents/` are now copied into the sandbox. They
were absent in both the 2026-08-21 and 2026-09-13 runs, and in both the Director *substituted*
for the missing inputs rather than stopping — Step 0.5, Step 0c and every `Read .claude/agents/X.md`
line. A substituted input is not a measurement.

**One unscripted pause remains:** Step 0.5 MCP Preflight State 2 (disconnected) is a human pause
with no scripted reply, and the harness has no MCP. Script it next run. Per the 2026-09-13
worm-repo finding, an unscripted pause is an invitation to fabricate consent — this Director
reported it instead of inventing an answer, which is the behaviour to preserve.

**Not a template defect, recorded to prevent a re-report:** the run's `unity-verifier` result was
scripted as `VERIFY PASSED`, which matches neither literal in Step 3.5's contract (`VERIFIED` /
`VERIFY FAILED`). That was an error in the run's own prompt, not in the command.
