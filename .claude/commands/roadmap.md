---
name: roadmap
description: Reads the GDD, the TDD and the existing modules, then creates or updates the module table in docs/ROADMAP.md. Sets dependency order, priority and status for every module. Serves as input for /plan-module.
---

# /roadmap — Module Roadmap Generator

Reads the GDD, the TDD and the current contents of `docs/modules/`, then writes `docs/ROADMAP.md`.

## Usage

```
/roadmap
```

## Process

### Step 1 — Read

Read these files in order:
1. `.claude/rules/roadmap-milestones.md` — **the milestone rule; binding for every step below**
2. `docs/GDD.md` — the full game design document (if present)
3. `docs/TDD.md` — the technical architecture (if present)
4. `docs/ROADMAP.md` — the current roadmap (if present; it may not exist yet)
5. Scan every module under `docs/modules/`:
   - Read the Status line inside each `docs/modules/<n>-<name>/tasks.md`
   - Build the list of existing modules

**Status arbiter (at rest):** a module's status is derived from the **checkboxes** in its
own `tasks.md`. The `> Status:` header of that file and the Status cell in the ROADMAP row
are both *mirrors* — correct them from the checkboxes, never the reverse. Measured in a
downstream project: a `tasks.md` header still read `⏳ Pending` while all 41 of its
checkboxes were ticked, and because `/roadmap` reads the header, the stale header carried a
wrong status into the table for weeks. During a live `/orchestrate` run the ledger is
authoritative instead — see `/continue` for that boundary; `/roadmap` runs at rest and uses
the checkboxes.

**Milestone gate (NON-NEGOTIABLE):** if `docs/GDD.md` defines no milestones, **STOP** and
ask the human to define M0 — First Playable (in player-experience terms, with a smoke-test
checklist) before anything else. Match on the heading **text at any level** — `## Milestones`
in a new GDD, `### Milestones` nested inside the production-plan section in a retrofitted
one (see the rule's "append, never renumber" note). Never gate on the hash count: a literal
`## Milestones` check rejects the retrofit this very rule prescribes. `/roadmap` maps
modules onto milestones; it never invents them (rule Card 1). Silently deriving a milestone
is a violation.

### Step 2 — Gap Analysis

Compare the game systems in the GDD against the modules that exist under `docs/modules/`:
- Which systems have a plan? (module folder exists)
- Which systems have none? (present in the GDD, no module folder)
- Dependency order: which module must come before which?

### Step 2.5 — Milestone Assignment (MANDATORY)

Map every module onto the GDD's milestones **before** assigning any priority:

1. For each milestone (starting at M0 — First Playable), list the **minimum** module set
   that closes it. Stubs are legal currency (rule Card 5): a hand-authored level instead of
   a solver, a two-button panel instead of the full HUD. If M0 maps to more than ~6
   modules, shrink M0's scope — never grow the milestone.
   **Write each module's stub scope inline, never a bare number:** `15 (minimal — two
   panels, two buttons)`, not `15`. A milestone rarely takes a *whole* module — it takes a
   slice, and the remainder belongs to a later milestone. This parenthetical is the scope
   ceiling `/plan-module` reads; without it the planner sees a bare module number next to a
   one-sentence milestone entry, holds the module's full TDD section in context, and the
   full spec wins. Add a one-line rationale for any module whose presence is non-obvious
   (`why 20 is in M0: without a move limit the player cannot lose, so the "lose panel"
   checklist item is unreachable`) — the reasoning is what stops the mapping being
   re-derived wrong later.
   **Then check each smoke-test item has a real, non-debug trigger path.** Name the in-game
   action that fires it. An item reachable only through a debug menu or a QA button is
   *player-unreachable* and the milestone cannot close on it. This check is why the rule
   exists: in the source project, writing the item "lose panel shows" forced the discovery
   that `LevelFailedEvent`'s only publisher in the entire codebase was a debug trigger and
   the move-budget field had zero references — the player could not lose. Twelve modules
   marked ✅ Complete had never surfaced it.
2. Priority follows the milestone, not the dependency graph: every module of the **open**
   milestone outranks everything outside it (rule Card 2). A polish/visual/decor module may
   not be scheduled ahead of a loop-closing module of the open milestone. Dependencies give
   the *feasible* order; the milestone gives the *chosen* order.
3. Every milestone must end in something a human can experience (rule Card 4). If a
   milestone's closing sentence names no human-visible outcome, it is mislabeled
   infrastructure — fold it into the milestone whose experience it serves.
4. Verify the `Depends on` edges of the open milestone's modules before trusting the order.
   A recorded dependency is a claim, not a fact: in the source project a module carried a
   false dependency on the solver, which held it at P3 for weeks and made the lose panel
   unreachable. A recording error blocked a mechanic.

### Step 3 — Write ROADMAP.md

Create `docs/ROADMAP.md` if it does not exist. **If it exists, edit it in place — never
regenerate it.**

**Preserve on every update, without exception:**
- every `**Verdict:**` line, verbatim — a verdict is the one artifact only a human may
  write, and an empty verdict means the milestone is not closed. Overwriting a CLOSED
  verdict silently *reopens* a finished milestone and destroys a play-test judgment that
  exists nowhere else.
- the `← OPEN` marker's position — a human moves it (rule Card 3). Correct it only if it
  contradicts the verdicts, and say so in the summary.
- every hand-written annotation inside a row or a milestone entry: measurements, freeze
  notes, rationale lines, falsifiers, dates and attributions.

This is the whole reason the file is edited rather than rewritten. In the source project the
ROADMAP rows had become a decision-record substrate — a single module's row ran to roughly a
page of measurements and reviewer findings — and the practice that saved it was never written
into any command: *"the tables were not rewritten from scratch; the measurement notes and
decision rationale inside them were preserved."* It is written down here now.

Regenerate only the derived parts: the module list, dependency edges, the `Milestone` and
`Priority` columns, and Status cells.

Shape of the file:

```markdown
# ROADMAP

> Last updated: [date]
> Source: GDD + TDD gap analysis

## Milestones — this sets the order, not the dependency graph

> Rule: `.claude/rules/roadmap-milestones.md`. A milestone closes ONLY with a dated,
> written human verdict on its line — green tests do not close it, and neither does a
> count of ✅ Complete modules (rule Card 3). Exactly one milestone is `← OPEN`: the
> lowest-numbered one with an empty verdict. The rest are FUTURE.
>
> **No module outside the open milestone is planned or started** (rule Card 2) without
> explicit developer confirmation.

### M0 — First Playable  ← OPEN
[one sentence from the GDD, player-experience terms]
**Smoke test:** [checklist from the GDD, with the environment it must run in —
name the device and input; an Editor session does not count]
**Modules:** 01 (minimal — [stub scope]), 05 (minimal — [stub scope])
**Why 05 is in M0:** [one line, only where the module's presence is non-obvious]
**Verdict:** —

### M1 — [name]
[one sentence]
**Modules:** 02, 03, 04
**Verdict:** —

## Module Table

| # | Module | Depends on | Milestone | Priority | Status | Plan |
|---|-------|---------|-----------|---------|--------|------|
| 01 | core-loop | — | M0 | P0 | ⏳ Pending | [plan](modules/01-core-loop/tasks.md) |
| 05 | end-panels | core-loop | M0 | P0 | ⏳ Pending | [plan](modules/05-end-panels/tasks.md) |
| 02 | audio | core-loop | M1 | P2 | ❄️ Frozen — not started until M0 closes ([date]) | [plan](modules/02-audio/tasks.md) |

> Status: ⏳ Pending / 🔄 In Progress / ✅ Complete / 🚫 Blocked / ❄️ Frozen
> Priority: open-milestone modules are always P0. A module outside the open milestone is
> not planned or started while a loop-closing module of the open milestone is still
> Pending — unless the developer explicitly confirms otherwise. A module the milestone
> mapping demoted carries `❄️ Frozen` plus the condition and date that will release it,
> so the demotion is visible rather than inferred from a priority number.

## Next Step

`/plan-module 01` — plan the core-loop module (M0 — open milestone)
```

### Step 4 — Write the Summary

Show the user:
- How many modules were found (from the GDD)
- How many already have a plan
- How many are missing a plan
- **Which milestone is OPEN, which modules are left to close it, and what the human
  smoke test for closing it is**
- Suggested next command: `/plan-module <n>` — always a module of the **open** milestone

$ARGUMENTS
