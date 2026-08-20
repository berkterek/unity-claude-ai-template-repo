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

### Step 1 — Okuma

Read these files in order:
1. `docs/GDD.md` — the full game design document (if present)
2. `docs/TDD.md` — teknik mimari (varsa)
3. `docs/ROADMAP.md` — mevcut roadmap (varsa; olmayabilir)
4. Scan every module under `docs/modules/`:
   - Read the Status line inside each `docs/modules/<n>-<name>/tasks.md`
   - Build the list of existing modules

### Step 2 — Gap Analizi

Compare the game systems in the GDD against the modules that exist under `docs/modules/`:
- Which systems have a plan? (module folder exists)
- Which systems have none? (present in the GDD, no module folder)
- Dependency order: which module must come before which?

### Step 3 — ROADMAP.md Yaz

Write `docs/ROADMAP.md` (update it if present, create it otherwise):

```markdown
# ROADMAP

> Last updated: [date]
> Kaynak: GDD + TDD gap analizi

## Module Table

| # | Module | Depends on | Priority | Status | Plan |
|---|-------|---------|---------|--------|------|
| 01 | core-loop | — | P1 | ⏳ Pending | [plan](modules/01-core-loop/tasks.md) |
| 02 | audio | core-loop | P2 | ⏳ Pending | [plan](modules/02-audio/tasks.md) |

> Status: ⏳ Pending / 🔄 In Progress / ✅ Complete / 🚫 Blocked

## Next Step

`/plan-module 01` — plan the core-loop module
```

### Step 4 — Write the Summary

Show the user:
- How many modules were found (from the GDD)
- How many already have a plan
- How many are missing a plan
- Suggested next command: `/plan-module <n>`

$ARGUMENTS
