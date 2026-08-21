# PLAN — Automated Gate Inventory

> **Version:** v1 — 2026-08-21
> **Status:** Active
> **Scope:** `.claude/docs/director-gates.md`, `.claude/CLAUDE.md`, `.claude/commands/{implement,fix,fix-deep,orchestrate}.md`, `README.md`. Read-only touch: `.claude/agents/reviewer.md`, `docs/engine-reference/unity/VERSION.md`.

## Context

`.claude/docs/director-gates.md` declares two gate families at line 5-7. The five **Automated Check Gates** — `TD-ARCHITECTURE` (158), `TD-UNITY-RISK` (174), `TD-PERFORMANCE` (188), `TD-COMPILE` (204), `CD-SCOPE` (220), all under `## Automated Check Gates` (152) — are the second family, and they are the mirror-image defect of the sibling plan `docs/PLAN_gate_definition_fixes.md`: that plan fixed gates whose *definitions* were missing. These have definitions and no pipeline callers.

Measured state, re-verified for this plan:

- `grep -rn 'TD-\|CD-' .claude/commands/` returns **nothing**. No pipeline command applies any of the five, despite `director-gates.md:257-262` documenting the exact reference form (`Apply gate TD-ARCHITECTURE from .claude/docs/director-gates.md.`) and using `TD-ARCHITECTURE` as its own worked example.
- `.claude/CLAUDE.md:203-211` lists seven gates. All seven are human-pause or hook-enforced. None of the five appear.
- No hook enforces any of them. The six `guard-*.sh` hooks are `guard-critical-files.sh`, `guard-editor-runtime.sh`, `guard-gate-cleared.sh`, `guard-pipeline-direct-work.sh`, `guard-reviewer-order.sh`, `guard-sparc-approved.sh`. `guard-reviewer-order.sh` is *not* a TD-COMPILE enforcer — its header at line 8 reads "Enforces reviewer priority: Codex → unity-reviewer", nothing about compile state.

**Three corrections to the finding as originally stated.** All three change what this plan is allowed to delete:

1. **"Zero references" is true only of `.claude/commands/`.** Three live referrers exist outside it: `.claude/agents/reviewer.md:77` — *"For Unity-specific checks use `TD-ARCHITECTURE` and `TD-PERFORMANCE`. For scope checks use `CD-SCOPE`."*; `docs/engine-reference/unity/VERSION.md:25-26`, which instructs *"Apply gate `TD-UNITY-RISK`"* and *"Stamp TDD decisions with: `> Engine: Unity 6 LTS — risk assessed via TD-UNITY-RISK`"*; and **`README.md:1121-1125`, a five-row table documenting all five gates including `TD-COMPILE`**. Every one of the five names is load-bearing somewhere outside `.claude/commands/`.
2. **`TD-COMPILE` is not referrer-free.** `README.md:1124` describes it as *"Unity MCP compile + Edit Mode test pass — mandatory before reviewer"*. It remains the only gate with no *behavioural* referrer — no agent instruction, no doc that tells anyone to apply it — but deleting the definition without editing `README.md` leaves the README documenting a gate that no longer exists. That is the same defect class this plan removes, one file to the left.
3. **`TD-COMPILE`'s "mandatory before reviewer" constraint is NOT unique to the gate definition.** It is stated verbatim in both mirror files' step headers: `implement.md:283` — `## Step 2.5 — Unity Validator (MANDATORY — runs before Reviewer)` — and `fix.md:341` — `## Step 4.5 — Unity Validator (MANDATORY — runs before Reviewer)`; `fix-deep.md:509` inherits by reference (*"Validator loop: same as `/fix`"*). The sequencing survives deletion of the gate body. This invalidates the premise that `TD-COMPILE` must be kept to preserve it.

> **Provenance of the line numbers in this plan.** Every location cited below was read directly from file contents — no number is carried over from the finding that prompted the plan. Gate headings, both `## Review Criteria` blocks, both `## Output contract` count lines, `reviewer.md:77`, `VERSION.md:25-26`, `README.md:1121-1125`, and both Validator step headers were each opened and confirmed. The sibling plan shipped with five off-by-one errors caught only in review; this one states its numbers as measured and still expects the implementer to re-grep, because they rot the moment any earlier line moves. Where a count could not be pinned to a line, it is marked **[BLOCKED — needs investigation]** rather than estimated.

> **Corrections applied after review.** Four defects were found by an independent plan review and are fixed above, each recorded at the point of the fix rather than only here: a wrong rule-file home for TD-ARCHITECTURE's interface-driven bullet and a missing one for module boundaries (Task 1 step 3); a false `[BLOCKED]` on `/orchestrate`'s coder-prompt block, which exists at `orchestrate.md:326` (Task 3); a fourth mirror file, `fix-deep.md`, absent from both the tasks and Out of Scope (Tasks 3-4); and an ambiguous bare filename for `debate-critic.md`, which lives under `.claude/agents/`, not `.claude/commands/`. Two of the four were content-loss risks, not cosmetics.

> **Scope trap this plan already fell into once.** The original finding scanned only `.claude/commands/` and generalised the result to the whole repo, which is how `README.md:1121-1125` was missed by both the finding and the first draft of this plan. Every sweep step below therefore names its root explicitly, and Task 6 greps the repository root — not `.claude/` and `docs/`, which between them exclude `README.md`.

## Complexity
0.35 — Low-moderate. Six markdown files edited, two read-only. No runtime surface, no C#. One four-file mirror group for the reviewer-criteria edits (`implement.md`, `fix.md`, `orchestrate.md`, `fix-deep.md`) — review found the fourth member, which the first draft treated as a three-file group. Above the sibling plan's 0.25 because two tasks *add* behaviour to live pipelines rather than reconciling existing text, and one edit changes a hard-coded criterion count that an output contract validates against.

## Chosen Disposition

### Decision 1 — D1 gates get three different dispositions, not one

The three D1 gates fail the same test (their bodies duplicate substance held elsewhere) but differ in whether anything still tells a reader to *apply* them. That, not the duplication, decides the disposition.

| Gate | Disposition | Evidence |
|---|---|---|
| `TD-ARCHITECTURE` | **Keep the name, replace the body with a one-line pointer** | Its five checks are in `.claude/rules/architecture.md` (Card 2 Provider pattern at 32-58; `FindObjectOfType` singleton-in-disguise gotcha at 28; `IEventBus` cross-module rule at 202) and `.claude/rules/csharp-unity.md:202` (service locator → VContainer). Reviewer criterion #2 in `implement.md:374`, #4 in `fix.md:438`, #3 in `orchestrate.md:456` already run the check on every pass. So the body is a fourth copy and goes. But `reviewer.md:77` tells an agent to *apply* this gate — delete it outright and that instruction dangles. |
| `TD-PERFORMANCE` | **Keep the name, replace the body with a one-line pointer** | Same shape. The checks are spread across three rule files, not one: `performance.md:54` (`Camera.main`), `:142-159` (`renderer.material` / `sharedMaterial` / `MaterialPropertyBlock`), `:13-33` (`GetComponent` in `Awake`); `ecs-dots.md:209-214` (ECB for structural changes); `addressables.md:60-84` (handle stored as field, released). Four hooks also enforce parts of it: `check-no-hotpath-expensive-calls.sh`, `check-no-linq-hotpath.sh`, `check-getcomponent-in-awake.sh`, `check-ecs-structural-changes.sh`. The pointer must name three files. `reviewer.md:77` names this gate too. |
| `TD-COMPILE` | **Delete the definition, and update `README.md` in the same task** | The only one of the five that nothing instructs anyone to apply. Its five steps are MCP call sequences, not rules — correct that `.claude/rules/` has no equivalent — but they are already written out operationally at `implement.md:283-315` and `fix.md:341-373`, with `### Validator Loop (max 2 fix passes)` at `implement.md:316` / `fix.md:374`. Nine files call `refresh_unity`. Per Context correction 3, the sequencing constraint is in both step headers already. Nothing behavioural is lost — but `README.md:1124` documents it, so the deletion is only lossless if that row goes with it. |

To make the deletion provably lossless rather than probably lossless, Task 2 adds **one sentence** to the existing `## Retry and Pass Limits` section (`director-gates.md:235`) stating that the validator runs before the reviewer and that a reviewer verdict on unvalidated code is void. That is where a command author already looks for loop mechanics, and it is the only rule-shaped part of `TD-COMPILE`.

**Rejected alternative:** keeping all three as pointers, for symmetry. Rejected because a named gate that nothing applies and that holds no unique content is exactly the dead text this plan exists to remove; symmetry is not a reason to keep one.

### Decision 2 — D2 gates go into the pipelines as reviewer criteria (option b), plus one pre-write pointer

**`TD-UNITY-RISK` — option (b) + a narrow (a).** The three files it requires all exist (`docs/engine-reference/unity/{deprecated-apis,breaking-changes,current-best-practices}.md`, confirmed present alongside `VERSION.md`). The only consumer is `architect.md:11`, which reads them at TDD time. `VERSION.md:25-26` instructs that the gate be applied — so the gate is *demanded* by a doc and *supplied* by nobody. `/implement`, `/fix`, `/fix-deep` and `/orchestrate` write Unity API code with no deprecated-API check.

Chosen home: a new reviewer criterion in all four commands (detection), plus one line added to each coder prompt's project-rules block (prevention). Reviewer criteria is the right shape because that is where `TD-ARCHITECTURE` and `TD-PERFORMANCE` already effectively live — this makes the third Unity-risk axis consistent with them instead of inventing a new pipeline step. Insertion points, measured:

| File | New criterion | Count line to update | Coder-prompt pointer |
|---|---|---|---|
| `implement.md` | #9, after `8. Serialization` at 380 | **383** — "every one of the **8** review criteria above" | `## Project Rules (read first)` at **262** |
| `fix.md` | #8, after `7. Unity null safety` at 441 | **444** — "every one of the **7** review criteria above" | `## Project Rules` at **323** |
| `orchestrate.md` | #11, after the BLOCKING drift item at 463 | **466** — "every one of the **10** review" | `## Project Rules` at **326** |
| `fix-deep.md` | #8, after `7. Performance` at 551 | **554** — "every one of the **7** review criteria above" | **[BLOCKED — needs investigation]** — locate its coder-prompt rules block or record the omission |

**`CD-SCOPE` — option (b), same three files.** Its checks live only in `clean-slop.md` (`### 3. Needless Abstraction` at 37; confidence rubric at 79 — *"no callers found but could be used externally"*) and `.claude/agents/debate-critic.md:36` (*"Necessity — … YAGNI, over-engineering"*). Neither is in a pipeline: `/clean-slop` is an opt-in post-hoc sweep that explicitly refuses to refactor (`clean-slop.md:131`), and `/debate` is a design exercise. `SCOPE_GATE` (`director-gates.md:14`) shows the human the task and expected files and asks for `go` — it confirms *intent*, and runs *before* any code exists, so it structurally cannot see abstractions the coder then invented.

**Do not conflate this with the existing `## Scope lock (MANDATORY)` blocks** (`implement.md:362`, `fix.md:424`, `orchestrate.md:440`). Those constrain *which files the reviewer may read* — an anti-scope-creep rule for the reviewer, not a bloat check on the coder's output. Different direction entirely.

**Wording constraint, load-bearing:** `.claude/rules/architecture.md:224` states that an interface with a single production caller is correct, because the test suite is the second caller. A criterion phrased as "no abstractions without a current caller" would directly contradict an auto-loaded rule. The criterion must be phrased against *unused* abstractions and *unrequested* files — Task 4 pins the wording and cites this line as the reason.

**Option (c) — leave defined-but-unused — is rejected for both.** It is legitimate only with a stated reason, and neither has one: both describe checks nobody performs, on files that exist, in pipelines that touch exactly the code they guard.

### Decision 3 — surviving gates get their own small table in CLAUDE.md

`CLAUDE.md:199` introduces its table as *"Named prompts that pause the pipeline and wait for human approval before continuing."* Automated check gates by definition do not pause — so their absence from that table was **correct by its own stated scope**, not an oversight. The oversight is that no second table was ever added, leaving four gate names with zero discoverability from the auto-loaded entry point. That is the mechanism by which they died.

Fix: a four-row table under a new `### Automated Check Gates` subheading, with columns `Gate | Applied by | What it checks` — not the human-pause table's `What you decide`, which has no meaning here. `TD-COMPILE` gets no row (deleted). Kept to four rows plus one header line because `CLAUDE.md` is auto-loaded into every session and every line is paid for on every turn.

### Blast-radius note — `.claude/rules/*.md` is not touched

This plan reads `architecture.md`, `csharp-unity.md`, `performance.md`, `ecs-dots.md`, `addressables.md` and writes none of them. Those files are auto-loaded into every session, so any edit there is high blast radius and belongs in its own plan with its own review. If an implementer finds that a pointer added by Task 1 is inaccurate because a rule file lacks the check it claims, **stop and mark [BLOCKED — needs investigation]** — do not "fix" it by editing the rule file.

## Goals
- [ ] No gate name is referenced anywhere in the repo — including `README.md` — without a definition, and no gate definition carries a body that duplicates `.claude/rules/`.
- [ ] `TD-COMPILE` is gone from both the definition file and `README.md`, and its one rule-shaped constraint (validator before reviewer) is stated once, in the section that already owns loop mechanics.
- [ ] `TD-UNITY-RISK` and `CD-SCOPE` are applied by `/implement`, `/fix`, `/orchestrate` and `/fix-deep` — every pipeline that writes Unity code and carries its own reviewer-criteria block.
- [ ] Every reviewer-criteria count line matches the number of criteria beneath it.
- [ ] `CLAUDE.md` makes the surviving automated gates discoverable in four rows.
- [ ] `.claude/rules/*.md` and `.claude/hooks/*` are byte-identical before and after.

## Status
| Phase | Task | Status | parallel_group |
|---|---|---|---|
| 1 | Task 1 — Collapse TD-ARCHITECTURE and TD-PERFORMANCE to pointers | pending | — |
| 1 | Task 2 — Delete TD-COMPILE (definition + README row), preserve the sequencing rule | pending | — |
| 2 | Task 3 — Apply TD-UNITY-RISK in implement/fix/orchestrate (ATOMIC) | pending | — |
| 2 | Task 4 — Apply CD-SCOPE in implement/fix/orchestrate (ATOMIC) | pending | — |
| 3 | Task 5 — Add the automated-gate table to CLAUDE.md | pending | — |
| 4 | Task 6 — Verification sweep (repository root, not `.claude/`) | pending | — |

Tasks 1 and 2 both edit `director-gates.md` in disjoint ranges (158-203, and 204-219 plus 235-248 plus line 7), so they are sequential rather than parallel purely to avoid line-number churn — run 1 then 2. Tasks 3 and 4 both edit the same three `## Review Criteria` blocks and the same three count lines: sequential by necessity, 3 then 4, and Task 4 must re-measure every line number after Task 3 shifts them by one. Task 5 depends on 1 and 2 (it can only list gates that survived). Task 6 is last.

## File Map
| File | Change Type | Notes |
|---|---|---|
| .claude/docs/director-gates.md | edit | Bodies of `### TD-ARCHITECTURE` (158) and `### TD-PERFORMANCE` (188) replaced with pointers; `### TD-COMPILE` (204-219) deleted; one sentence added to `## Retry and Pass Limits` (235); the family list at line 6 loses `TD-COMPILE` |
| README.md | edit | Row for `TD-COMPILE` in the gate table at **1121-1125** removed. Missed by the original finding and by this plan's first draft because both scanned `.claude/` and `docs/`, which exclude the repo root |
| .claude/CLAUDE.md | edit | New `### Automated Check Gates` table below the existing gate table (203-211). Four rows, no more |
| .claude/commands/implement.md | edit | Criteria #9 and #10 after 380; count at 383 (8 → 10); pointer in `## Project Rules (read first)` at 262 |
| .claude/commands/fix.md | edit | Criteria #8 and #9 after 441; count at 444 (7 → 9); pointer in `## Project Rules` at 323 |
| .claude/commands/orchestrate.md | edit | Criteria #11 and #12 after 463; count at 466 (10 → 12); pointer in `## Project Rules` at **326** |
| .claude/commands/fix-deep.md | edit | Fourth mirror, found in review: criteria #8 and #9 after 551; count at 554 (7 → 9); coder-prompt pointer location BLOCKED |
| .claude/agents/reviewer.md | verify only | Line 77 tells the agent to apply TD-ARCHITECTURE / TD-PERFORMANCE / CD-SCOPE. All three survive, so no edit expected — confirm, do not assume |
| docs/engine-reference/unity/VERSION.md | verify only | Lines 25-26 name TD-UNITY-RISK, which survives. No edit expected |
| .claude/rules/*.md | no change | High blast radius — auto-loaded every session. Read-only inputs to Task 1's pointers |
| .claude/hooks/guard-*.sh | no change | None enforces these gates; `guard-reviewer-order.sh` is about Codex priority, not compile state |
| .claude/commands/fix-deep.md (validator loop) | no change | It inherits the validator loop by reference at 509 — nothing to add *there*. Its reviewer-criteria block is a separate matter and is edited above |

## Out of Scope
- **Scope B** — aligning the ten `skip`/`stop`-only blocks with a named gate: deferred by the user to a later plan. As the sibling plan established, these are reached only after an internal fix loop is already spent, so the missing `fix` option may be deliberate; that is a design call for the human.
- **Scope C** — naming new gates for the four unnamed distinct decision points (the qa `retry`/`skip` gate, the two fix-deep evidence gates, and qa.md's `list` menu): deferred by the user. Each expresses behaviour QUALITY_GATE does not — a jump target, an extra `list` action — so each needs its own canonical definition rather than a reference.
- Adding a hook to enforce any automated gate. All five are reviewer-judgement checks, not file-content predicates; a `PreToolUse` hook cannot evaluate "is this abstraction unused".
- `/fix-codex`, `/qa`, `/migrate`, `/scene-setup`, `/create-prefab-scene` — they also have reviewer-criteria blocks, but extending the two new criteria to every pipeline is a second, wider change. This plan covers the four pipelines that write Unity API code from scratch (`/implement`, `/fix`, `/fix-deep`, `/orchestrate`). `/fix-deep` was added after review found its criteria block; the same argument may later pull in the five above, and that is the right trigger for a follow-up rather than a reason to widen now.

---

## Task 1 — Collapse TD-ARCHITECTURE and TD-PERFORMANCE to pointers
**Files:** .claude/docs/director-gates.md:158-172, :188-202
**Test Type:** NoTest — markdown prose; verified by reading the rule files each pointer names.
**Steps:**
1. [ ] Re-confirm the headings before editing: `### TD-ARCHITECTURE` at **158**, `### TD-UNITY-RISK` at **174**, `### TD-PERFORMANCE` at **188**, `### TD-COMPILE` at **204**, `### CD-SCOPE` at **220**. If any has moved, re-derive all ranges.
2. [ ] For `TD-ARCHITECTURE`: keep the `### ` heading, the `**Trigger:**` line, and the `**Verdict:**` line. Replace the five-bullet `Checks:` list with one line pointing at `.claude/rules/architecture.md` and `.claude/rules/csharp-unity.md`, and stating that both are auto-loaded so the reviewer already has them.
3. [ ] Before writing that pointer, open the rule files and confirm each of the five deleted checks is genuinely covered. Measured homes, re-verified after review caught two wrong ones:
   - DI / no-singleton → `architecture.md:28` (`FindObjectOfType` is a singleton in disguise), `csharp-unity.md:202`
   - interface-driven → `architecture.md:348` ("Services depend on interfaces, never concrete types") and `architecture.md:812` (`### Interface-First Registration`); also `solid-oop.md:604`. **Not** `csharp-unity.md:367-369` — that section is the `new *Service()` constructor-injection rule, which is the DI check above, not this one. The first draft cited it here and was wrong.
   - `IEventBus` cross-module → `architecture.md:202`
   - Provider pattern → `architecture.md:32-58` (Card 2)
   - module boundaries → `architecture.md:532-533`, the Module Portability Checklist rows (`using` dependencies limited to `_Framework` + own types; cross-module dependencies "None — only interfaces consumed"). The first draft named no home at all for this bullet.
   If any check has **no** home in the rules, do not delete that bullet — keep it and note the asymmetry.
4. [ ] For `TD-PERFORMANCE`: same treatment, but the pointer must name **three** files — `performance.md`, `ecs-dots.md`, `addressables.md` — because the checks are split across them. Do not write "see performance.md"; two of the five checks are not there.
5. [ ] Confirm each before deleting: `Camera.main` → `performance.md:54`; `renderer.material` / `sharedMaterial` / `MaterialPropertyBlock` → `:142-159`; `GetComponent` caching → `:13-33`; ECB for structural changes → `ecs-dots.md:209-214`; Addressables handle release → `addressables.md:60-84`.
6. [ ] Add to the pointer that four hooks enforce parts of this mechanically (`check-no-hotpath-expensive-calls.sh`, `check-no-linq-hotpath.sh`, `check-getcomponent-in-awake.sh`, `check-ecs-structural-changes.sh`), so a reader knows the gate is not the only line of defence.
7. [ ] Do NOT edit any file under `.claude/rules/`. If a pointer would be inaccurate, mark **[BLOCKED — needs investigation]** and stop.
8. [ ] Leave `reviewer.md:77` alone — both names survive, so the instruction stays valid. Re-read it to confirm.
**Acceptance Criteria:**
- Neither gate body restates a rule that exists in `.claude/rules/`.
- Both gates keep their `### ` heading, trigger, and verdict format, so `reviewer.md:77` and the reference example at `director-gates.md:257-262` still resolve.
- Every deleted bullet traces to a specific rule-file line recorded in the task notes; anything untraceable was kept.
- `git diff --stat .claude/rules/` is empty.

## Task 2 — Delete TD-COMPILE (definition + README row) and preserve its one rule-shaped constraint
**Files:** .claude/docs/director-gates.md:204-219 (delete), :235-248 (one sentence added), :6 (family list); README.md:1124 (row removed)
**Test Type:** NoTest — verified by a repository-root grep for the gate name.
**Steps:**
1. [ ] Before deleting, run `grep -rn 'TD-COMPILE' .` from the **repository root** — not `.claude/`, not `docs/`; both exclude `README.md`, which is exactly how this referrer was missed twice. Expected hits: the definition at `director-gates.md:204`, the family list at `:6`, and `README.md:1124`. **Any hit outside those three → stop; the disposition was premised on no behavioural referrer and must be revisited.**
2. [ ] Re-read `implement.md:283` and `fix.md:341` and confirm both headers still read `(MANDATORY — runs before Reviewer)`. This is the evidence that deletion is lossless; if either header has changed, do not delete.
3. [ ] Re-read `fix-deep.md:509` and confirm it still says the validator loop is "same as `/fix` — max 2 fix passes". Third data point.
4. [ ] Delete `### TD-COMPILE` and its body, including the trailing `---` separator, leaving `### TD-PERFORMANCE` and `### CD-SCOPE` correctly separated.
5. [ ] Remove the `TD-COMPILE` row from `README.md`'s gate table (currently at **1124**, in the five-row block spanning **1121-1125**). Confirm the table's surrounding prose does not also state a count of gates; if it does, update it in the same edit.
6. [ ] Add exactly one sentence to `## Retry and Pass Limits` (heading at **235**), after the two-bullet bounds and before the exhaustion paragraph: the compile/test validator runs before the reviewer in every pipeline that has both, and a reviewer verdict on code that has not compiled is void. Do not restate the five MCP steps — they are operational, and `.claude/rules/` correctly has no equivalent.
7. [ ] Update the automated-gate enumeration at `director-gates.md:6` to list four gates, not five.
8. [ ] Do NOT add the validator's MCP call sequence anywhere. It exists in two mirror files and nine `refresh_unity` call sites; a third canonical copy is the drift this plan removes.
**Acceptance Criteria:**
- `grep -rn 'TD-COMPILE' .` from the repository root returns nothing.
- The "validator before reviewer" constraint is stated in exactly three places: both Validator step headers (unchanged) and one new sentence in `## Retry and Pass Limits`.
- `director-gates.md:6` names four automated gates; `README.md`'s table has four rows.
- No MCP tool call was copied into `director-gates.md`.

## Task 3 — Apply TD-UNITY-RISK in implement.md, fix.md, orchestrate.md (ATOMIC — do not split)
**Files (single change):** .claude/commands/implement.md, .claude/commands/fix.md, .claude/commands/orchestrate.md, .claude/commands/fix-deep.md
**Test Type:** NoTest — verified by grep and by reading each criteria block against its count line.
> **Four files, not three.** `/implement` and `/fix` are near-mirror files, and review found that `fix-deep.md` carries its own `## Review Criteria` block (**544**, seven items) with its own count line (**554**) — a fourth mirror the first draft neither included nor excluded. A deprecated-API check added to some pipelines and not others means the *deep* bug-hunt pipeline is the one without it, which is backwards. Applied as ONE unit across all four; if any cannot be edited, revert the others.
**Steps:**
1. [ ] Re-measure all eight line numbers first. As measured: `implement.md` `## Review Criteria` at **372**, items 1-8 at **373-380**, count line **383**; `fix.md` header **434**, items 1-7 at **435-441**, count line **444**; `orchestrate.md` header **453**, items 1-10 at **454-463**, count line **466**; `fix-deep.md` header **544**, items 1-7 at **545-551**, count line **554**. Any drift → re-derive, do not edit on a stale number.
2. [ ] Confirm the three target files exist under `docs/engine-reference/unity/`: `deprecated-apis.md`, `breaking-changes.md`, `current-best-practices.md`. All four files including `VERSION.md` were confirmed present when this plan was written.
3. [ ] Append one criterion to each block, worded identically in all three: Unity engine risk — no API listed in `deprecated-apis.md` is used; the change does not fall in an area listed in `breaking-changes.md`; where `current-best-practices.md` names a better alternative, it was used or the deviation is justified. Reference gate `TD-UNITY-RISK` by name rather than restating its three reads.
4. [ ] Update each count line in the same edit: `implement.md:383` 8 → 9, `fix.md:444` 7 → 8, `orchestrate.md:466` 10 → 11, `fix-deep.md:554` 7 → 8. **A count line that disagrees with the list beneath it invalidates the output contract** — each of those lines reads "every one of the N review criteria above", and the contract requires one emitted line per item.
5. [ ] Add the prevention-side pointer to each coder prompt: `implement.md` `## Project Rules (read first)` at **262**, `fix.md` `## Project Rules` at **323** — one line instructing the coder to check `docs/engine-reference/unity/deprecated-apis.md` before using an unfamiliar Unity API.
6. [ ] `orchestrate.md`'s coder-prompt block is `## Project Rules` at **326** — the first draft marked this BLOCKED after failing to find it, and review measured it. Add the same pointer line there. For `fix-deep.md` the equivalent block is **[BLOCKED — needs investigation]**: locate it, or omit the pointer for that file and record the omission explicitly. Do not invent a new header.
7. [ ] Re-read `VERSION.md:25-26` and confirm its instruction to "Apply gate `TD-UNITY-RISK`" is now satisfied by at least one pipeline. Note in the task record that `architect.md:11` remains the TDD-time consumer — this task adds implementation-time coverage, it does not replace it.
8. [ ] Do NOT add a new pipeline step. The criterion rides the existing reviewer spawn; a new step would need its own pass limit, its own failure branch, and a place in three pipeline diagrams.
**Acceptance Criteria:**
- All four files name `TD-UNITY-RISK` in their reviewer criteria.
- Every count line equals the number of criteria beneath it, verified by counting.
- `grep -rln 'deprecated-apis' .claude/commands/` returns `architect.md`, `implement.md`, `fix.md`, `orchestrate.md`, and `fix-deep.md` unless step 6 was resolved as an omission.
- The three engine-reference files were confirmed to exist before being cited.

## Task 4 — Apply CD-SCOPE in implement.md, fix.md, orchestrate.md (ATOMIC — do not split)
**Depends on:** Task 3 (same four blocks, same four count lines). Re-measure everything: Task 3 shifted each list by one line and each count line by one.
**Files (single change):** .claude/commands/implement.md, .claude/commands/fix.md, .claude/commands/orchestrate.md, .claude/commands/fix-deep.md
**Test Type:** NoTest.
**Steps:**
1. [ ] Re-measure the four `## Review Criteria` blocks and the four count lines after Task 3. Do not reuse Task 3's numbers.
2. [ ] **Pin the wording before editing anything.** `.claude/rules/architecture.md:224` states an interface with a single production caller is correct because the test suite is the second caller. A criterion reading "no abstractions with no current callers" — the phrasing in the deleted `CD-SCOPE` body — contradicts that auto-loaded rule and would produce false CHANGES NEEDED verdicts on correct code. Phrase it instead against abstractions with **no caller at all** and files **not implied by the task**.
3. [ ] Append one criterion to each of the four blocks, identically worded: scope discipline — no file was changed that the task did not require; no unrelated code was refactored; no abstraction was introduced that nothing calls. Reference gate `CD-SCOPE` by name.
4. [ ] Update each count line again, in the same edit.
5. [ ] Do NOT touch the existing `## Scope lock (MANDATORY)` blocks (`implement.md:362`, `fix.md:424`, `orchestrate.md:440`). Those bound what the reviewer may *read*; this criterion bounds what the coder may *write*. Confusing them would delete a real protection.
6. [ ] Do NOT weaken `orchestrate.md`'s existing item 10, the BLOCKING architecture-drift criterion at **463**. It overlaps CD-SCOPE on "no new folders not in the TDD" but is strictly stronger (BLOCKING, requires a paired ADR). Both stay; note the overlap in the task record so a future reader does not delete one as redundant.
7. [ ] Update the `CD-SCOPE` definition in `director-gates.md` (heading at **220**, or wherever it sits after Tasks 1-2) only if its own bullet still contains the "no current callers" phrasing that contradicts `architecture.md:224`. If so, that is a genuine defect in the definition — fix the definition, and say so.
8. [ ] Confirm `reviewer.md:77`'s "For scope checks use `CD-SCOPE`" now resolves to a gate with at least one pipeline caller.
**Acceptance Criteria:**
- All four files name `CD-SCOPE`; none restates its four bullets inline.
- No criterion anywhere contradicts `.claude/rules/architecture.md:224`.
- Every count line still equals the number of criteria beneath it after two rounds of appending.
- `orchestrate.md`'s item on architecture drift is unchanged and still marked BLOCKING.
- `git diff --stat .claude/rules/` is empty.

## Task 5 — Add the automated-gate table to CLAUDE.md
**Depends on:** Tasks 1 and 2 (the table can only list gates that survived).
**Files:** .claude/CLAUDE.md, below the existing gate table at 203-211
**Test Type:** NoTest — verified by cross-reading against `director-gates.md`.
**Steps:**
1. [ ] Re-read `CLAUDE.md:197-211`. Confirm the framing sentence at **199** still reads "Named prompts that pause the pipeline and wait for human approval before continuing" and that the table still holds seven rows ending with `SPARC_GATE` at **211**.
2. [ ] Add a `### Automated Check Gates` subheading below that table with columns `Gate | Applied by | What it checks`. Do not reuse the `What you decide` column — nothing is decided by a human here.
3. [ ] Four rows only: `TD-ARCHITECTURE`, `TD-UNITY-RISK`, `TD-PERFORMANCE`, `CD-SCOPE`. No `TD-COMPILE`.
4. [ ] Populate `Applied by` from what is true *after* Tasks 3 and 4 — `/implement`, `/fix`, `/orchestrate` reviewer criteria for all four, plus `reviewer.md` for three of them and `architect.md` + `VERSION.md` for `TD-UNITY-RISK`. Do not list a caller that does not exist yet.
5. [ ] Add one sentence above the table explaining why these were absent: the table above it covers gates that pause for a human, and these do not — they ride the reviewer spawn. This is the sentence that stops a future editor from deleting the new table as off-topic.
6. [ ] Keep the whole addition to a heading, one sentence, and five lines of table. `CLAUDE.md` is auto-loaded into every session; this is a per-turn cost.
7. [ ] Do NOT add rows to the existing human-pause table. Its seven rows and its stated scope are correct.
**Acceptance Criteria:**
- Four rows, matching exactly the four gates remaining in `director-gates.md`.
- The human-pause table at 203-211 is byte-identical.
- A reader who has only `CLAUDE.md` loaded can name every automated gate and which command applies it.
- Net addition is under ten lines.

## Task 6 — Verification sweep (repository root, not `.claude/`)
**Files:** read-only across the whole repository
**Test Type:** NoTest — verified by grep and read.
**Steps:**
1. [ ] `grep -rn 'TD-\|CD-SCOPE' .` from the **repository root**. Scanning `.claude/` and `docs/` instead is the exact mistake that hid `README.md:1121-1125` from both the original finding and this plan's first draft. Expect: four gate definitions, the reference example at `director-gates.md:257-262`, the family list at line 6, `reviewer.md:77`, `VERSION.md:25-26`, `README.md`'s four-row table, and the new criteria in the three commands. No `TD-COMPILE` anywhere. No name without a definition; no definition without a caller.
2. [ ] For each of the three commands, count the items under `## Review Criteria` and read the count line. All three must match. This is the single most likely defect in the whole plan — two atomic tasks appended to the same lists and edited the same counts.
3. [ ] `git diff --stat .claude/rules/` — must be empty. If not, revert those files and re-read Task 1 step 7.
4. [ ] `git diff --stat .claude/hooks/` — must be empty. No hook was to be added or changed.
5. [ ] Diff `implement.md`'s and `fix.md`'s new criteria against each other. The two new criteria must be worded identically; that is what makes the mirror pair a pair.
6. [ ] Confirm `implement.md:283` and `fix.md:341` Validator headers are untouched and still say `(MANDATORY — runs before Reviewer)` — Task 2's losslessness depends on them.
7. [ ] Re-read `director-gates.md` end to end and confirm the two remaining pointer-form gates read as pointers, not as summaries that grew back.
8. [ ] Confirm no file outside the File Map was modified — `git status --short` against the File Map list.
**Acceptance Criteria:**
- No gate name anywhere in the repository lacks a definition, and no automated gate definition lacks a caller.
- Every reviewer-criteria count line is correct.
- `.claude/rules/` and `.claude/hooks/` are unmodified.
- The two new criteria are byte-identical between `implement.md` and `fix.md`.
- Everything unconfirmable is recorded as **[BLOCKED — needs investigation]**, not guessed.

---

## Task 7 — Name TD-ARCHITECTURE and TD-PERFORMANCE in the criteria that already run them (found by Task 6)
**Files:** .claude/commands/{implement,fix,fix-deep,orchestrate}.md — the existing `Architecture —` and `Performance —` criteria
**Test Type:** NoTest.

> Found by Task 6's sweep. After Tasks 1-5, `grep -rl TD-ARCHITECTURE .claude/commands/` returned **zero** — the two D1 gates were kept as pointers on the strength of "reviewer criteria already run them", but no criterion *named* either gate. Task 5's new CLAUDE.md table then claimed both are "applied by" four commands: true in substance, unverifiable by grep, and in direct tension with this plan's own Goal that no definition lacks a caller. Naming them is what makes the claim checkable.

**Steps:**
1. [ ] In each of the four files, rename the existing criterion `N. Architecture — VContainer DI, …` to `N. Architecture (gate \`TD-ARCHITECTURE\`) — …`, leaving the check text unchanged.
2. [ ] Same for `N. Performance — no allocations …` → `N. Performance (gate \`TD-PERFORMANCE\`) — …`.
3. [ ] Do **not** add or remove any criterion — the item count must not change, so no count line may move. Verify after: implement 10, fix 9, fix-deep 9, orchestrate 12, each matching its own count line.
4. [ ] The item numbers differ per file (implement 2/4, fix 4/5, fix-deep 4/7, orchestrate 3/5) — that is expected; the criteria lists are different lengths. Only the wording after the number must match across files.

**Acceptance Criteria:**
- `grep -rl` for each of the four gate names returns all four command files.
- No count line changed, and every count still equals its item total.
- No check text was altered — only the gate name was inserted.

## Implementation note — Tasks 3 and 4 were applied as one edit per file
The plan sequenced Task 3 then Task 4 with a re-measure between them, because Task 3 shifts every line Task 4 needs. Both criteria were instead appended in a single edit per file, taking each count straight from N to N+2. This removes the re-measure step the plan itself flagged as "the single most likely defect in the whole plan"; the two criteria remain separate, individually numbered items, so nothing about the outcome differs.

## Line-number rot, observed twice during implementation
`TD-COMPILE`'s heading moved from 204 to **196** once Task 1 shortened the two gate bodies above it, and the four count lines moved by two once the criteria were appended. Both were re-measured before editing rather than trusted. This is the third plan in a row where a cited line number was stale by the time it was used — treat every number in a plan document as a starting point for a grep, never as an address.

---

## Task 8 — Restore TD-COMPILE as a named pointer (reverses Task 2's deletion)
**Files:** `.claude/docs/director-gates.md` (definition + family list at 6), `.claude/commands/implement.md` (Step 2.5 header), `.claude/commands/fix.md` (Step 4.5 header), `README.md` (gate table row), `.claude/CLAUDE.md` (automated-gate table row)
**Test Type:** NoTest.

> **Why Task 2 was wrong, stated plainly.** Both of its premises held: the gate body was a third copy of the two Validator steps, and no command named the gate. The conclusion did not follow. The remedy for "nothing names it" is to name it — which is exactly what Task 7 did for `TD-ARCHITECTURE` and `TD-PERFORMANCE` in the same pass. Deleting instead left the automated-gate list with four entries and no compile gate, which reads as though compile validation is ungated. The option "name it at the Validator step" was never evaluated, because the insight that produced Task 7 arrived after Task 2 had already been applied, and the earlier decision was not revisited in its light.
>
> Nothing detected this. The 417-test hook suite passed, all 12 factual claims in the changed files verified, and the gate inventory was internally symmetric — the deletion was *consistent*, merely wrong. It surfaced only when the human asked why the README row had gone. Recorded here because it is the clearest instance in this plan of a class of defect that measurement cannot reach: a decision that is coherent with its own evidence but has an unexamined better alternative.

**Steps:**
1. [ ] Re-add `### TD-COMPILE` to `director-gates.md` in the same **pointer** form Task 1 gave the other two — trigger, verdict, and one line pointing at `implement.md` Step 2.5 / `fix.md` Step 4.5 for the MCP sequence. Do **not** restore the five MCP steps; the third-copy problem Task 2 correctly identified must stay solved.
2. [ ] Add the deletion-and-restoration note to the definition, so a future reader does not re-delete it on the same reasoning.
3. [ ] Restore `TD-COMPILE` to the automated-gate family list at `director-gates.md:6` — five names again.
4. [ ] Name the gate at its call sites: `## Step 2.5 — Unity Validator (gate \`TD-COMPILE\`) (MANDATORY — runs before Reviewer)` in `implement.md`, and the Step 4.5 equivalent in `fix.md`. `fix-deep.md` inherits by reference at 509 and needs no edit — state that in the definition rather than editing it.
5. [ ] Restore the `README.md` gate-table row, below `TD-PERFORMANCE`.
6. [ ] Add a `TD-COMPILE` row to the `CLAUDE.md` automated-gate table, and correct that section's lead sentence: it said "all four", and there are five.
7. [ ] Leave the "Order between the two" sentence in `## Retry and Pass Limits` in place. It is now redundant with the restored gate but not wrong, and it is the only statement of the ordering rule that sits where loop mechanics are documented.

**Acceptance Criteria:**
- Five automated gates, each with a definition, each named by at least one caller: `TD-COMPILE` by `implement.md` and `fix.md`; the other four by all four pipelines.
- `director-gates.md` contains no `mcp__unityMCP` call — the pointer did not become a copy again.
- `README.md` and the `CLAUDE.md` table both list five, and the lead sentence says five.
- The restored definition explains why it was deleted once, so the reasoning is not repeated.

## Process note — what the measurements did and did not catch
Across this plan and its sibling, defects split cleanly by kind:

| Kind | Count | Caught by |
|---|---|---|
| Wrong factual claim (line numbers, "zero referrers", "auto-loaded") | 3 | grep / a reviewer / a self-test |
| Wrong verification tooling (a sweep that counted only numbered list items; a diff that compared item numbers) | 2 | re-reading the sweep's own output |
| Wrong decision with a sound evidence chain (Task 2) | 1 | **the human, by asking** |

Facts and tools are testable and were tested. A decision that is internally consistent produces no failing test, so the only control on it is showing it to a person before it is applied. Task 2 was even flagged in advance as the most aggressive step in the plan and was still applied without being taken to a gate — flagging is not a control.

---

## Task 9 — Revert Task 1's pointer collapse; the bullets were load-bearing (measured, not argued)
**Files:** `.claude/docs/director-gates.md` (`TD-ARCHITECTURE`, `TD-PERFORMANCE` bodies), `.claude/CLAUDE.md` (the `TD-ARCHITECTURE` row's description)
**Test Type:** Behavioural — a planted-defect fixture reviewed by a live agent. This is the first test in this plan that measures agent behaviour rather than text consistency.

> **Task 1 was wrong, and only a behavioural test could show it.** It replaced each gate's five-bullet `Checks:` list with a prose pointer into `.claude/rules/`, on the correct observation that the bullets duplicated substance held elsewhere. Every static check passed afterwards: 417/417 hooks, 16/16 line citations, a symmetric gate inventory. None of that touched the question that mattered — what a reviewer *does* with the text.
>
> **A/B measured 2026-08-21** on a fixture carrying five planted defects (`FindObjectOfType`, LINQ in `Update`, `renderer.material` write, `Resources.Load`, a zero-caller interface). Two reviewers, same fixture, same gate, differing only in the `TD-ARCHITECTURE` body:
>
> | | five bullets | prose pointer |
> |---|---|---|
> | Axes given a verdict | **5/5** | **3/5** |
> | Axes silently skipped | none | IEventBus, module boundaries |
> | Primary defect caught | yes | yes |
>
> Both arms caught the defect, so the pointer was not *blunter* — it was *narrower*. The list was never a duplicate of the rules; it was the **coverage contract**, and nothing else in the prompt told the reviewer how many axes existed. Removing it let two axes vanish with no error and no missing output line.
>
> A second wrong claim rode along with Task 1 and is also reverted: the pointer's justification asserted that rule files are not available to a reviewer because nothing under `.claude/rules/` is `@`-included. The first half is true; the conclusion is false. All three test agents independently reported the rule files present in their own system prompt as project instructions, which is also visible in this session's. `CLAUDE.md`'s `## Rules (auto-loaded)` heading was correct all along; calling it misleading was the error.

**Steps:**
1. [ ] Restore both `Checks:` bullet lists, one bullet per axis, each carrying the `rules/` citation that Task 1's research produced — the citations were the one durable gain of that task and are kept.
2. [ ] Record the A/B measurement inside the `TD-ARCHITECTURE` body, so the next reader sees why the list may not be collapsed, and state that axis names do not rot when a rule's content changes.
3. [ ] Delete the "not `@`-included / a subagent does not inherit" note entirely. Do not soften it — it is false.
4. [ ] Correct `CLAUDE.md`'s `TD-ARCHITECTURE` row, which described the pointer form ("the rules themselves, not a copy").
5. [ ] Do not touch `CLAUDE.md:128` `## Rules (auto-loaded)` — measured correct.
6. [ ] Re-run the fixture after the revert and confirm no regression.

**Acceptance Criteria:**
- Both gates list five bullets; each cites a rule location; neither restates rule content.
- No claim anywhere that rule files are unavailable to a subagent.
- `CLAUDE.md`'s row describes what the gate now is.
- Hook suite still 417/417.

## Task 10 — Two prompt defects the fixture exposed, and their measured fix
**Files:** `.claude/commands/{implement,fix,fix-deep,orchestrate}.md` — criterion `CD-SCOPE`, and each `## Output contract`
**Test Type:** Behavioural — same fixture, before/after.

> **Defect A — the `CD-SCOPE` criterion missed its own target.** First run: it flagged an unused field and an uncalled private method but not the planted zero-caller interface, which was instead noticed under the *Events* criterion by accident. Cause, on re-reading the line: the sentence ended with its exception, and that exception carried the line's only bold — `**not** a violation` — while the actual target, "no abstraction was introduced that nothing calls", sat unbolded in the middle of three clauses. The exception was the salient half.
>
> **Defect B — the output contract manufactured findings.** Four of ten criteria returned `GAP` with evidence sentences that denied any violation — criterion 7 read "no `?.`/`is null` misuse found in this file" and was still marked `GAP`. "Emit one line per item" makes filling every line mandatory; nothing said that finding a fault on every line is not. This defect pre-dated the plan on eight criteria, and this plan made it worse by adding two more lines to fill.

**Steps:**
1. [ ] Rewrite the `CD-SCOPE` criterion to lead with the count and make the numeric distinction explicit: **zero** callers is a violation, **exactly one** production caller is not, and the exception may not be generalised into "never flag an abstraction".
2. [ ] Add to all four output contracts: a `GAP` needs a violation with a `file:line`; a `GAP` whose own evidence denies a violation is invalid; filling every line is mandatory, finding a fault on every line is not. Include the measurement so the rule is not later trimmed as verbose.
3. [ ] Apply to all four files identically — they are one mirror group.

**Measured result (same fixture, same answer key, criteria fixed in advance of the run):**

| | before | after |
|---|---|---|
| False `GAP` (evidence contradicts verdict) | 4 / 10 | **0 / 10** |
| Planted defects caught | 4 / 5 | **5 / 5** |
| Zero-caller interface caught under `CD-SCOPE` | no — surfaced under *Events* | **yes** |
| Output lines emitted | 10 / 10 | 10 / 10 |

Criterion 7 is the clearest single illustration: `GAP` — "no `?.`/`is null` misuse found" became `CONFIRMED` — "line 29's `closest == null` correctly uses Unity's overridden `==`". Same file, same criterion, a verdict that now matches its own evidence and cites the line that justifies it.

**Not fixed, deliberately:** no criterion in these lists covers `#region` discipline, so the fixture's misplaced field declaration goes unreported. Adding an eleventh criterion is a new decision, and this plan just measured that adding lines to fill has a cost. It belongs in its own change.

## What this plan learned about verifying prompt work
Eleven static checks — hook suite, line citations, count-line integrity, gate inventory, table well-formedness — passed while two of this plan's changes were actively wrong. Both were found by running an agent against a fixture with known defects. Text consistency and agent behaviour are different properties, and only the second is what a prompt file is for. The fixture is the reusable artifact here: `.claude/hooks/tests/` holds 36 suites and none of them measures what a prompt makes an agent do.
