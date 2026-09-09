# Roadmap Milestones — First Playable Discipline (NON-NEGOTIABLE)

> Read the **Cards** section first. The prose below is reference detail.

Milestones are a **design decision, not a planning decision**. They are born in the GDD
conversation, get their technical acceptance in the TDD, and `/roadmap` only **maps**
modules onto them — it never invents them. The whole rule exists because dependency order
answers "what *can* be built next", never "what *should* be built next" — and a roadmap
ordered purely by dependencies always pushes the playable end of the chain last.

## Cards

### Card 1: Milestones Are Born in the GDD — /roadmap Maps, Never Invents

**WHEN:** Writing or updating a GDD (`/game-idea`, `/refine-gdd`), and every `/roadmap` run.

**WRONG:**
```markdown
<!-- GDD with no Milestones section; weeks later /roadmap orders 21 modules purely by
     dependency. The playable end of the chain lands last, by construction. -->
| # | Module | Depends on | Priority |
| 01 | assembly-scaffold | — | P0 |
| ... 11 more infrastructure/visual modules ... |
| 15 | hud | 12 | P2 |   ← the "press Next Level" button, scheduled after wall materials
```

**RIGHT:**
```markdown
<!-- In the GDD, written in player-experience terms — no module names exist yet -->
## Milestones
### M0 — First Playable
A human opens the game, plays one level start to finish, wins or loses on screen,
and starts the next level. On target input (touch).
**Smoke test checklist:** level visible · a worm can be dragged · win state shows ·
lose state shows · "Next" and "Restart" work.
### M1 — Content Proven
Five hand-authored levels playable back to back; difficulty reads as ascending.
```

**GOTCHA:** If the GDD has no Milestones section, `/roadmap` must **stop and ask the
human to define M0** — it may not silently derive one. A milestone invented by an agent at
planning time is exactly the guess this rule removes.

**Every gate in this rule matches the heading TEXT, at any level — never the hash count.**
`## Milestones` in a new GDD and `### Milestones` nested inside the production-plan section
of a retrofitted one are both compliant (see "append, never renumber" below). Writing a
literal `## Milestones` into a gate makes the rule reject its own prescribed retrofit; that
happened once already, in five places at once.

**Ask the observable question, not the abstract one.** The question is
**"what do we need to SEE on screen?"** — never "what is the smallest playable thing".
Measured in the conversation that created this rule (9 Sep 2026): the abstract framing
returns a scope opinion, the observable framing returns an itemised list you can verify by
looking — which is the only kind of answer a smoke test can be built from. The developer
had to correct this wording once already; do not reintroduce it.

---

### Card 2: No Module Outside the Open Milestone

**WHEN:** Assigning priorities in `docs/ROADMAP.md`, and picking the next module to run.

**WRONG:** The project this rule came from, weeks 3–4: modules 11a/11b (hole visuals, wall
materials) were planned and executed while 14 (solver) and 15 (hud) sat Pending — so after
4 weeks and 12 "Complete" modules there was **one** level and no way to finish a run on
screen.

**RIGHT:** Every module in the open milestone outranks everything outside it. A polish or
decor module may not be planned, orchestrated, or started while a loop-closing module of
the open milestone is still Pending. The module table carries a `Milestone` column; what
each command does with it is listed under Deliberate Limits below and is **not** uniform —
`/plan-module` warns, `/orchestrate` displays and does not refuse. Do not summarize this as
"the commands inherit the constraint": that sentence stood here for one generation of this
rule and was true of neither command.

**GOTCHA:** "The dependency order was correct" is not a defense. Dependencies give the
*feasible* order; the milestone gives the *chosen* order. Both existed in that project and
only the first one was ever consulted.

---

### Card 3: Only a Human Closes a Milestone

**WHEN:** Declaring any milestone (and especially M0) done.

**WRONG:** Module 04b v1: 16 tasks, EditMode **358/358 green** — then a human played it
and rejected the mechanic outright. Rewritten from scratch as v2. Green tests measured
what was written, not whether it was right to write.

**RIGHT:** A milestone closes with a dated, written one-line human verdict in
`docs/ROADMAP.md` under the milestone's entry — and **`docs/ROADMAP.md` is its only home**.
A second location for the one artifact only a human may write is a drift generator: the
next reader cannot tell which copy is current, and `/roadmap` cannot know which to preserve.

```markdown
### M0 — First Playable
**Verdict:** CLOSED — 2026-09-14, played 3 runs on device, loop reads correctly. (developer)
```

**The evidence environment is the milestone's own field, and this rule never dictates it.**
Device, orientation and input belong on the milestone's entry in the GDD (§13), restated by
the TDD's Milestone Acceptance and nowhere pinned as a project-wide constant. Measured
2026-09-10: a downstream project had "on an Android development build, on device, portrait,
touch" written into the TDD's acceptance section, this rule's cards and a module's
checkpoint block — so the developer's one-sentence decision that an Editor session was
enough evidence for M0 turned into a five-file edit, plus a stale ROADMAP mapping. What the
rule does require is that the environment is **written down and that its gaps are named**:
an Editor session cannot show touch-drag feel, portrait layout, or device performance, and
a milestone closed in the Editor closes with those three recorded as unmeasured. A weaker
environment is a decision; an unstated one is the defect.

**GOTCHA:** A passing test suite, a green pipeline, or a completed task list does **not**
close a milestone. An empty verdict line means the milestone is not closed, regardless of
how many of its modules say ✅ Complete.

**Exactly one milestone is OPEN, and it is derived, never chosen:** the
**lowest-numbered milestone with an empty verdict**. Every milestone after it is FUTURE,
not open — "empty verdict" alone does not make a milestone open, or M0..Mn would all be
open at project start and Card 2 would constrain nothing. Mark the open one with `← OPEN`
in `docs/ROADMAP.md`.

**Who moves the marker:** the human who writes a verdict moves it, in the same edit that
closes the milestone. That is deliberate — the marker cannot be owned by `/roadmap` alone,
because rerunning `/roadmap` is the operation that must never touch a verdict (Card 3 +
the preserve-in-place rule in `/roadmap` Step 3). If moving the cursor required a
regeneration, closing a milestone would risk erasing the verdict that closed it, and the
milestone would silently reopen. `/roadmap` may correct a marker that contradicts the
verdicts; it may not move one on its own initiative.

---

### Card 4: Every Milestone Ends in Something a Human Can Experience

**WHEN:** Defining M1, M2, … in the GDD, or restructuring milestones in a refine pass.

**WRONG:**
```markdown
### M1 — Core Systems Complete
Simulation, DI, input and import layers finished and fully tested.
```

**RIGHT:**
```markdown
### M1 — Content Proven
Five levels playable back to back; a human confirms difficulty reads as ascending.
```

**GOTCHA:** "Infrastructure done" is a status, not a milestone. If the closing sentence of
a milestone cannot name what a human *sees or does*, the milestone is mislabeled
infrastructure and must be folded into the milestone whose experience it serves.

---

### Card 5: M0 Stays Small — Stubs Are Legal Currency

**WHEN:** Mapping modules to M0 and the set starts growing.

**WRONG:** Blocking M0 on the full solver module because "levels must be validated", or
on the full HUD spec because "the UI system isn't designed yet".

**RIGHT:** M0 closes on stubs: a hand-authored level JSON instead of a solver; a two-button
panel (Restart / Next) instead of the HUD module; hardcoded win text instead of the popup
system. Guideline: if M0 maps to more than ~6 modules, shrink the scope of M0 — do not
grow the milestone.

**GOTCHA:** A stub a human can operate counts toward closing M0. A test suite — however
large — does not. The stub is later replaced by the real module in whatever milestone owns
that experience; replacing a stub is normal work, not rework.

---

## Why This Rule Exists (measured in a real project built from this template, 13 Aug – 9 Sep 2026)

Four weeks of disciplined work produced: **87,480 lines** of markdown (docs/ + .claude/),
**28,830 lines** of production C#, **18,264 lines** of test C#, 380 commits (115 of them
`docs`, 76 `feat`), 12 modules marked ✅ Complete with EditMode 459/459 green — and
**zero playable runs**: one level file, no win/lose panel, no way to advance or restart.
Nothing was built wrong; things were built in an order no milestone ever constrained.
The most expensive single artifact was 04b v1 — fully implemented, fully tested, rejected
by the first human who played it (Card 3).

**The structure was already half there, and it had no teeth.** That is the part worth
carrying forward, because "we had no milestones" was the *wrong* diagnosis and it was
believed first. The GDD already defined Phase 1/2/3, the ROADMAP already grouped modules
under those phases, and Phase 1 already carried a written human gate ("does dragging feel
great? kill or continue"). Three things were missing instead: the gate's criterion never
required a **closable loop** (so shipping the HUD in Phase 2 was faultless by the GDD's own
text), nothing depended on the gate so it sat unanswered for four weeks at no cost, and
`/roadmap` read the **dependency graph** rather than the phases. So the phases existed in
prose and never once entered the ordering. The single mechanism that changed behaviour was
`/roadmap` stopping and asking — everything else in this rule follows from that.

## Ownership of Each Piece

| Artifact | Owner | What it must contain |
|---|---|---|
| `GDD.md → ## Milestones` | `/game-idea` conversation (updated by `/refine-gdd`) | M0..Mn in player-experience terms + M0 smoke-test checklist. No module names. |
| `TDD.md → Milestone Acceptance` | `/architect` (updated by `/refine-tdd`) | Technical acceptance for the M0 smoke test: what a stub may replace, what closes vs. what doesn't, and a **restatement** of the environment the GDD milestone declares — never a second declaration of it. |
| `ROADMAP.md → ## Milestones` + `Milestone` column | `/roadmap` | Module→milestone mapping, with each module's stub scope inline. Preserves verdict lines and row annotations in place; never regenerates them. |
| Milestone verdict line, and the `← OPEN` marker | **A human, in writing** | Date + one sentence + name, and moving `← OPEN` to the next milestone in the same edit. `/roadmap` may correct a marker that contradicts the verdicts; it may not author either. |

> **Retrofitting an existing GDD/TDD: append, never renumber.** The `/game-idea` and
> `/architect` templates place these sections at GDD §13 and TDD §14, which is correct for a
> *new* document. An existing document's numbering is load-bearing — measured 9 Sep 2026 in
> the source project: `TDD §14` was referenced **18 times** from `docs/ROADMAP.md` and the
> module plans, and `GDD §14` five times, so inserting a numbered section would have broken
> every one of those links. Retrofit instead: put the GDD's milestones **inside** the
> existing production-plan section, and append the TDD's acceptance as a new trailing
> section. Say in the document why the number diverges from the template, so nobody "fixes"
> it later.
>
> The corollary bit that project on the same day: a rule's own gate must be run **against
> its own retrofit path** once before it is trusted. `/roadmap`'s gate looked for a literal
> `## Milestones` while this very note prescribes a nested `###` — so the rule would have
> blocked a compliant retrofitted GDD. Match on the heading *text*, never the hash count.

## Cascade Rules

- `/refine-gdd` touching the Milestones section must warn: ROADMAP priorities are stale — rerun `/roadmap`.
- `/refine-gdd` adding a missing Milestones section must **append, never renumber** — see the retrofit note above. It owns that path, because `/architect` sends the developer there.
- `/refine-tdd` adding a missing Milestone Acceptance section: same rule, appended as a trailing section.
- `/roadmap` finding no Milestones section in the GDD: **stop and ask** — never proceed, never invent.
- A new module discovered mid-milestone joins the **open** milestone only if the milestone
  cannot close without it; otherwise it goes to a later milestone by default.

## Deliberate Limits

- **Enforcement is visibility and default ordering, not a hook.** What stops a determined
  agent is the `Milestone`/`Priority` column and a human saying no at SCOPE_GATE — there is
  no `guard-*` hook behind this rule. Binding it to a hook is a separate future decision.
- **Say which command actually reads the column, because they differ — and re-check this
  bullet whenever a command changes.** `/plan-module` reads it and **warns** (off-milestone
  module, or a plan whose scope exceeds the milestone's entry); the developer's `go`
  overrides. `/orchestrate` reads it too: it prints the module's milestone, the open
  milestone and the count of its still-Pending modules on the SCOPE_GATE block, and says in
  one sentence when the module is off-milestone — but it does **not** refuse. So a module
  can still be orchestrated straight past an open milestone; what stops it is a human
  reading that line, not the tooling.
  > **This bullet has now been wrong twice, in opposite directions, and both times inside
  > the sentence warning about it.** The source project's version claimed both commands
  > enforced the column — true of neither. The correction over-swung to "`/orchestrate`
  > does not consult it at all", which stayed here after `/orchestrate` gained the display
  > and the off-milestone sentence in the very same edit — so the rule then described its
  > own enforcement as *weaker* than it was, and a session repeated the stale claim to the
  > developer as fact. A rule that documents another file's behaviour is a mirror, and a
  > mirror is stale from the moment that file changes: when you touch a command's milestone
  > handling, this bullet is part of the change, not a follow-up.
- **This rule fixes ordering, not process volume.** The same measurement that produced it
  also showed 87k lines of markdown against 29k of code. That is a real third root cause and
  it is deliberately out of scope here — it belongs to `/plan-module`.
- **Milestones are forward-looking.** Modules already ✅ Complete before a milestone system
  exists are not retro-labelled; assigning them a milestone after the fact writes a date
  that never happened. Label the Pending rows only.
- **Never invent a milestone to fill a gap.** A module that no defined milestone needs waits
  with an explicit "after Mn" marker until the GDD defines the milestone that owns it.
  Opening a speculative M3 to give it a home is a Card 1 violation.
