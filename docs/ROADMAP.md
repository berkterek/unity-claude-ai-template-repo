# ROADMAP

> Last updated: —
> Source: maintained by the `/roadmap` command

## Milestones — this sets the order, not the dependency graph

> Rule: `.claude/rules/roadmap-milestones.md`. Milestones are born in the GDD; `/roadmap`
> only maps modules onto them. A milestone closes **only** when a human writes a dated
> verdict on its line — green tests do not close it, and neither does a count of
> ✅ Complete modules. Exactly one milestone is `← OPEN`: the lowest-numbered one with an
> empty verdict. The rest are FUTURE.
>
> **No module outside the open milestone is planned or started** without explicit
> developer confirmation.

_No milestones defined yet. `/roadmap` will stop and ask for M0 — First Playable until the
GDD defines one._

## Module Table

| # | Module | Depends on | Milestone | Priority | Status | Plan |
|---|-------|---------|-----------|---------|--------|------|

> Status: ⏳ Pending / 🔄 In Progress / ✅ Complete / 🚫 Blocked / ❄️ Frozen
> Priority: open-milestone modules are always P0. A module the milestone mapping demoted
> carries `❄️ Frozen` plus the condition and date that will release it.

## Notes

This file is maintained by the `/roadmap` command — **edited in place, never regenerated.**
Verdict lines, the `← OPEN` marker and any hand-written annotation in a row are preserved
across updates; only the derived parts (module list, dependency edges, Milestone/Priority
columns, Status cells) are rewritten. A verdict exists nowhere else, so overwriting one
silently reopens a finished milestone.

For module plans: `/plan-module <n>`
For orchestration: `/orchestrate docs/modules/<n>-<name>/tasks.md`
