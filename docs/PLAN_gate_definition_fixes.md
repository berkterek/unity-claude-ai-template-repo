# PLAN — Gate Definition Fixes

> **Version:** v1 — 2026-08-21
> **Status:** Active
> **Scope:** `.claude/docs/director-gates.md`, `.claude/CLAUDE.md`, `.claude/commands/{create-plan,update-plan,implement,fix,fix-deep,qa,orchestrate}.md`

## Context

Three defects break the "gates are defined once in director-gates.md, referenced by name from commands" contract:

1. **BREAKING_REVISION_GATE is referenced but never defined.** CLAUDE.md:208 lists it (`re-research`/`accept`/`stop`); create-plan.md:377-393 and update-plan.md:289-304 implement it inline; director-gates.md has NO section for it. The two inline copies already differ in **two** ways: the upstream agent (`create-plan` says "re-run Researcher", `update-plan` says "re-run Analyzer") and the explanatory sentence — `create-plan` says "Proceeding risks another round of **breaking fixes during implementation**", `update-plan` says "another round of **fix cycles**". The first divergence is legitimate (different upstream stages); the second is pure drift and must be resolved when the canonical definition is written.
2. **Same class of retry loop carries different pass limits.** Compile/test-fix: 2 in implement.md:310 and fix.md:368, but 3 in qa.md:109 and orchestrate.md:658. Reviewer-verdict: 3 in six places, but 2 in create-plan.md:524 and update-plan.md:419 — so create-plan.md contradicts itself internally.
3. **Three silent-failure-hunter blocks are unnamed QUALITY_GATEs.** implement.md:515-522, fix.md:580-587, fix-deep.md:625-632 each offer exactly `fix`/`skip`/`stop` without naming the gate, and carry a cap the canonical gate lacks: re-run hunter **once**.

> **Provenance of the line numbers in this plan.** Every cited location was measured twice — once by the planner, once by machine re-check after review. The planner's first draft was off by one to three lines in five places (create-plan/update-plan block boundaries, and `orchestrate.md:653` which is actually 651). All 33 claims in this document were verified against file contents before it was saved. Re-check before editing anyway: these numbers rot as soon as any earlier line in the file changes.

## Complexity
0.25 — Low. 9 files, all markdown prose, no runtime surface; one atomic mirror-file group; one convention decision with cross-file blast radius.

## Chosen Convention
**Reviewer-verdict loops = 3 passes. Compile/test-fix loops = 2 passes.**

Evidence: reviewer loops already say 3 in six independent places (implement.md:398, fix.md:459, fix-deep.md:573, orchestrate.md:488, migrate.md:306, scene-setup.md:242); the two that say 2 (create-plan.md:524, update-plan.md:419) sit in files whose other reviewer loop says 3. Compile loops say 2 where the loop is defined in detail (implement.md:310, fix.md:368, fix-deep.md:509 by reference); orchestrate.md:**651** — inside the verifier agent prompt — says "Attempt fixes (max 2)", contradicting orchestrate.md:658's outer "max 3". Rationale: reviewer judgement can improve across iterations; a deterministic compile error will not.

Edits: qa.md:109,112 3→2; orchestrate.md:658,660 3→2; create-plan.md:524 2→3; update-plan.md:419 2→3. Everything else: no change.

**Item 3 cap decision:** the one-re-audit cap STAYS in the command files next to the QUALITY_GATE reference, not in the gate definition. QUALITY_GATE (director-gates.md:80-100) describes only the human decision surface and says nothing about caller follow-up — same as SCOPE_GATE and BREAKING_GATE. Adding a per-caller cap parameter would introduce a configuration concept present nowhere else in that file.

## Goals
- [ ] BREAKING_REVISION_GATE has a canonical definition in director-gates.md matching the shape of the five existing human-pause gates, derived verbatim from what the two commands do.
- [ ] create-plan/update-plan reference that definition instead of duplicating it, preserving the Researcher-vs-Analyzer divergence.
- [ ] One documented pass-limit convention exists; every occurrence conforms.
- [ ] The three silent-failure blocks name QUALITY_GATE and retain the one-re-audit cap, edited atomically.

## Status
| Phase | Task | Status | parallel_group |
|---|---|---|---|
| 1 | Task 1 — Define BREAKING_REVISION_GATE | pending | — |
| 1 | Task 2 — Record pass-limit convention | pending | — |
| 2 | Task 3 — Point create-plan/update-plan at the new gate | pending | 2 |
| 2 | Task 4 — Apply compile-loop limit (2) in qa.md, orchestrate.md | pending | 2 |
| 2 | Task 5 — Apply reviewer limit (3) in create-plan, update-plan | pending | — |
| 3 | Task 6 — Name QUALITY_GATE in three silent-failure blocks (ATOMIC) | pending | — |
| 4 | Task 7 — Verification sweep | pending | — |

Task 1 precedes 3. Task 2 precedes 4 and 5. Tasks 3 and 5 touch the same two files, so 5 runs after 3. Task 6 is last (only atomic multi-file change).

## File Map
| File | Change Type | Notes |
|---|---|---|
| .claude/docs/director-gates.md | add | New `### BREAKING_REVISION_GATE` after COMMIT_GATE (ends ~122, before `## Automated Check Gates` at 124); new "Retry and Pass Limits" section |
| .claude/CLAUDE.md | verify only | Line 208 already lists the gate; confirm options match, edit only if divergent |
| .claude/commands/create-plan.md | edit | Replace inline block 377-393 with a reference; reviewer limit at 524 |
| .claude/commands/update-plan.md | edit | Replace inline block 289-304; reviewer limit at 419 |
| .claude/commands/qa.md | edit | Lines 109, 112 + any Stage 1 prose echoing the count |
| .claude/commands/orchestrate.md | edit | Lines 658, 660 |
| .claude/commands/implement.md | edit | 515-522 silent-failure block (mirror group) |
| .claude/commands/fix.md | edit | 580-587 byte-identical mirror |
| .claude/commands/fix-deep.md | edit | 625-632 third verbatim duplicate |
| .claude/commands/migrate.md | no change | Reviewer loop at 306 already 3; coupling risk only |
| .claude/commands/scene-setup.md | no change | Reviewer loop at 242 already 3; coupling risk only |

## Out of Scope
- **Scope B** — aligning the ten `skip`/`stop`-only blocks with a named gate: deferred by the user. Note these are NOT simply drifted copies: they are reached only *after* an internal fix loop is already spent, so the missing `fix` option may be intentional. That question is a design decision for the human, not a cleanup.
- **Scope C** — naming new gates for the qa `retry`/`skip` gate, the fix-deep evidence gates, and qa.md's `list` menu: deferred by the user. Each carries behavior QUALITY_GATE does not express (a jump target, an extra `list` action), so each needs its own canonical definition rather than a reference.

---

## Task 1 — Define BREAKING_REVISION_GATE in director-gates.md
**Files:** .claude/docs/director-gates.md (insert after COMMIT_GATE, before `## Automated Check Gates` at 124)
**Test Type:** NoTest — markdown; verified by reading the two call sites.
**Steps:**
1. [ ] Re-read director-gates.md:102-124 to copy COMMIT_GATE's exact shape (`### NAME`, `**When:**`, `**Purpose:**`, `Show the user:`, fenced box with `───` rules at fixed width, `Wait for response.`, `---`).
2. [ ] Re-read create-plan.md:377-393 and update-plan.md:289-304; extract only what they actually do. **The two copies' explanatory sentences have drifted** — `create-plan`'s is "The reviewer flagged a structural change — this means the codebase was not fully read before planning. Proceeding risks another round of breaking fixes during implementation."; `update-plan`'s is shorter ("another round of fix cycles"). **Decision: `create-plan`'s longer wording is canonical**, because it names what is actually at risk (breaking fixes landing during implementation) instead of the vaguer "fix cycles". Use it verbatim in the definition; `update-plan`'s shorter sentence disappears with its inline block. Confirmed: fires when the plan reviewer appends `REVISION_TYPE: BREAKING`; shows `⚠️  BREAKING REVISION DETECTED (v[N])`, an explanation that the codebase was not fully read and that proceeding risks cascading breaking fixes, the full CHANGES NEEDED list, and `re-research` / `accept` / `stop`.
3. [ ] Insert the new section, matching that format including box width.
4. [ ] `**When:**` — a plan reviewer returns CHANGES NEEDED with `REVISION_TYPE: BREAKING`; fires in /create-plan and /update-plan.
5. [ ] `**Purpose:**` — a breaking revision means the codebase was not fully read before planning; let the human choose to re-research rather than cascade fix cycles into implementation.
6. [ ] Keep the upstream agent generic in the definition (`re-research — re-run the research/analysis stage with expanded scope, then re-plan`) so one definition serves both callers; the caller-specific name is stated at the call site in Task 3.
7. [ ] Add the closing `Wait for response.` paragraph naming each branch.
8. [ ] Update director-gates.md:5 — the human-pause gate enumeration — to include BREAKING_REVISION_GATE.
9. [ ] Re-read CLAUDE.md:208; confirm its options and trigger wording match. If they match, no edit; record "no change".
**Acceptance Criteria:**
- The new section is indistinguishable in shape from COMMIT_GATE's.
- Every option and explanatory line traces to text present in create-plan.md or update-plan.md — nothing invented; where the two diverged, `create-plan`'s wording was used and the choice is recorded in the task notes.
- Line 5 names six human-pause gates.
- CLAUDE.md:208 consistent (verified; edited only if it was not).

## Task 2 — Record the pass-limit convention in director-gates.md
**Files:** .claude/docs/director-gates.md
**Test Type:** NoTest.
**Steps:**
1. [ ] Add `## Retry and Pass Limits`, either after `### Hook-Enforced Gates` (ends ~239) or immediately before `## How to Reference Gates in Pipeline Commands` at 207 — pick what reads better, note the choice.
2. [ ] State it in two lines: reviewer-verdict loops max 3 passes; compile/test-fix loops max 2.
3. [ ] Add the one-sentence rationale (reviewer judgement improves across iterations; deterministic compile errors do not).
4. [ ] State that an exhausted loop stops and shows the human the remaining items — never silently proceeds — and cross-reference QUALITY_GATE for the reviewer case.
**Acceptance Criteria:**
- A future editor adding a retry loop learns the right number from one section without reading any command file.
- The section states the rule only — no per-command line numbers (they rot).

## Task 3 — Point create-plan/update-plan at the new definition
**Depends on:** Task 1. **parallel_group:** 2
**Files:** .claude/commands/create-plan.md:377-393, .claude/commands/update-plan.md:289-304
**Test Type:** NoTest.
**Steps:**
1. [ ] Block boundaries, measured twice (planner's original numbers were off by one — do not trust a cited number without re-checking): in create-plan.md the bullet `- **REVISION_TYPE: BREAKING** → stop immediately and show the user:` is at **377**, fence opens **378**, `Options:` at **388**, option lines **389-391**, `Wait for user input before continuing.` at **393**.
2. [ ] Replace the fenced block with the reference form documented at director-gates.md:207-213, passing plan version `v[N]` and the full CHANGES NEEDED list.
3. [ ] Immediately below the reference keep the caller-specific branch text: for create-plan.md, `re-research` re-runs the **Researcher** with expanded scope then re-plans; `accept` proceeds; `stop` aborts.
4. [ ] Repeat in update-plan.md (bullet **289**, fence opens **290**, `Options:` **299**, options **300-302**, `Wait for user input` **304**) with `re-research` naming the **Analyzer** — a legitimate divergence that must survive.
5. [ ] Leave create-plan.md:395 and update-plan.md:306 untouched — already conformant. Record "no change".
6. [ ] Grep .claude/ for the gate name and for `BREAKING REVISION DETECTED`; only these two files plus CLAUDE.md:208 and the new definition should match.
**Acceptance Criteria:**
- Neither command file duplicates the gate's option list.
- Both name their own upstream agent correctly (Researcher / Analyzer).
- Grep for `BREAKING REVISION DETECTED` returns exactly one occurrence — in director-gates.md.

## Task 4 — Apply the compile/test-fix limit (2) in qa.md and orchestrate.md
**Depends on:** Task 2. **parallel_group:** 2
**Files:** .claude/commands/qa.md:109,112; .claude/commands/orchestrate.md:658,660
**Test Type:** NoTest.
**Steps:**
1. [ ] qa.md:109 "…then re-verify. Repeat up to **3 passes**." → 2.
2. [ ] qa.md:112 "- `FAIL after 3 passes` → stop." → 2, so the failure branch matches the loop bound.
3. [ ] Re-scan qa.md Stage 1 (~105-118) for any other prose echoing the count, including the `⚠ Stage 1 — Ralph` print line, and update every occurrence — a bound stated twice with different numbers is the exact defect this plan removes.
4. [ ] orchestrate.md:658 "re-verify (max 3 passes). If still failing after 3 passes → stop and report…" → both numbers 2.
5. [ ] orchestrate.md:660 "⛔ Ralph failed after 3 passes" → 2.
6. [ ] Confirm orchestrate.md:**651** ("Attempt fixes (max 2). Re-check after each fix.") is now consistent; do not edit it. (The planner cited 653; measured, it is 651.)
7. [ ] Do NOT touch orchestrate.md:476 — "3 passes, 2026-08-18" is a historical measurement note, not a loop bound.
8. [ ] Do NOT touch orchestrate.md:488 or :513 — reviewer loop, stays 3.
**Acceptance Criteria:**
- Grepping qa.md and orchestrate.md for `3 passes` returns only orchestrate.md:476 and the reviewer-loop lines at 488/513.
- No compile/test loop in either file states a bound other than 2.

## Task 5 — Apply the reviewer limit (3) in create-plan.md and update-plan.md
**Depends on:** Task 2, and Task 3 (same files — run after, to avoid line-number churn).
**Files:** .claude/commands/create-plan.md:524, .claude/commands/update-plan.md:419
**Test Type:** NoTest.
**Steps:**
1. [ ] create-plan.md:524 "…re-run the reviewer (max 2 fix passes). After 2 failed passes → show remaining issues to the user." → both numbers 3.
2. [ ] update-plan.md:419 "…re-run the reviewer (max 2 fix passes)." → 3, and add the missing "After 3 failed passes → show remaining issues to the user." clause so it matches create-plan.md — the absent stop-and-show branch is a real gap, not just a number mismatch.
3. [ ] Re-confirm before editing that both are reviewer loops, not validator loops (both say "re-run the reviewer" and sit after the implementation-verification reviewer prompt). If either turns out to wrap a compile/test check, stop and mark **[BLOCKED — needs investigation]** instead of editing.
4. [ ] Leave create-plan.md:395 and update-plan.md:306 untouched — already 3.
**Acceptance Criteria:**
- Neither plan-pipeline file contains two reviewer loops with different pass limits.
- Both stop and show the human remaining issues when the loop is exhausted.

## Task 6 — Name QUALITY_GATE in the three silent-failure blocks (ATOMIC — do not split)
**Files (single change):** .claude/commands/implement.md:515-522, .claude/commands/fix.md:580-587, .claude/commands/fix-deep.md:625-632
**Test Type:** NoTest.
> Applied as ONE unit. The three blocks are byte-identical today. Applying to one or two produces exactly the drift this plan eliminates. If any of the three cannot be edited, revert the others.
**Steps:**
1. [ ] Diff the three blocks first (implement.md:513-524, fix.md:578-589, fix-deep.md:623-634). Confirmed shared content: a fence with `Silent failure issues found. Options:` and `fix   — spawn unity-coder to address findings, then re-audit once` / `skip  — accept and proceed to commit` / `stop  — abort`, then three bullets (`fix` → spawn unity-coder with all findings, re-run hunter once, proceed to committer regardless; `skip` → committer; `stop` → abort). If diverged, stop and mark **[BLOCKED — needs investigation]**.
2. [ ] In each file replace the fenced ad-hoc block with a QUALITY_GATE reference in the form at director-gates.md:207-213, passing the hunter's findings as the CHANGES NEEDED list.
3. [ ] Directly beneath, retain the three outcome bullets INCLUDING the cap, worded unmistakably: `fix` spawns unity-coder with all findings, re-runs the hunter **exactly once** (no further re-audit), proceeds to the committer regardless of the second result; `skip` → committer; `stop` → abort.
4. [ ] Add a short parenthetical at each site noting the cap is caller-specific and intentionally not part of the QUALITY_GATE definition, so a future reader does not delete it as redundant.
5. [ ] Keep the three blocks byte-identical to each other after the edit.
6. [ ] Record a decision on converting fix-deep.md's copy into a `same as /fix` reference (it already uses that pattern at 509 and 573). Recommended: convert — a third verbatim copy is pure drift surface; fix.md becomes the single authority and the mirror set shrinks to two.
7. [ ] Do NOT alter QUALITY_GATE at director-gates.md:80-100 — no per-caller cap parameter is being introduced.
**Acceptance Criteria:**
- All three sites name QUALITY_GATE; none re-lists `fix`/`skip`/`stop` inline.
- The one-re-audit cap is stated at every site that still has a block, or inherited via an explicit `same as /fix` reference.
- director-gates.md:80-100 unchanged.
- A diff of the three sites shows byte-identical blocks, or one block plus explicit references to it.

## Task 7 — Verification sweep
**Files:** read-only across .claude/
**Test Type:** NoTest — verified by grep and read.
**Steps:**
1. [ ] Grep .claude/ for each gate name; confirm every referenced human-pause gate now has a definition: SCOPE_GATE, ARCHITECTURE_GATE, BREAKING_GATE, BREAKING_REVISION_GATE, QUALITY_GATE, COMMIT_GATE, SPARC_GATE.
2. [ ] Grep .claude/commands/ for `passes`; read every hit against the convention — 3 for reviewer loops, 2 for compile/test loops, sole exception the historical note at orchestrate.md:476.
3. [ ] Grep .claude/commands/ for `Options:` inside fenced blocks; the three silent-failure sites must no longer appear. Remaining hits are expected — scope B and C, explicitly deferred.
4. [ ] Confirm migrate.md:304-331 and scene-setup.md:240-268 were not modified and still say 3 passes.
5. [ ] Re-read CLAUDE.md:197-211 and confirm the Director Gates table is consistent with director-gates.md after all edits.
**Acceptance Criteria:**
- No gate is referenced anywhere in .claude/ without a definition in director-gates.md.
- Every retry loop in .claude/commands/ conforms to the recorded convention.
- No file outside the File Map was modified.
