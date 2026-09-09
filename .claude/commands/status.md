# Pipeline Status Reporter

Shows the project pipeline's current state at a glance.

## Process

1. Read these files (if present):
   - `docs/GDD.md` — Game Design Document
   - `docs/TDD.md` — Technical Architecture
   - `docs/ROADMAP.md` — module roadmap and status rollup
   - `docs/modules/` — scan the tasks.md of every existing module

2. Determine the pipeline stage:
   - **No documents at all** → the pipeline has not started. Run `/game-idea` or create a GDD.
   - **GDD only** → the GDD is ready. Next: `/architect`
   - **GDD + TDD** → the architecture is ready. Next: `/roadmap`
   - **GDD + TDD + ROADMAP** → the roadmap is ready. Next: `/plan-module <n>`
   - **Module plans exist** → read each tasks.md checkbox state and summarize it.

   The checkboxes are the arbiter at rest. The `> Status:` header and the ROADMAP Status
   cell are mirrors — if either disagrees with the checkboxes, report the disagreement and
   name the checkboxes as correct; do not silently prefer a header.

   **Check every module, not the one being asked about, and report the disagreements as a
   list.** A stale header is a class: `/orchestrate` only started writing both places
   recently, so every plan authored before that is a candidate, and a missing `> Status:`
   line counts as a disagreement too. Do not conclude from a correct-looking ROADMAP table
   that the mirrors agree — measured in a downstream project, 10 of 19 plans disagreed
   with their own checkboxes while the table read fine, because one row had been repaired
   by hand and that repair is what hid the rest. Output the sweep as:

   ```
   ### Status mirror disagreements (checkboxes are correct)
   - docs/modules/09-x/tasks.md — header ⏳ Pending, checkboxes 23/23 → should be ✅ Complete
   - docs/modules/01-y/tasks.md — no `> Status:` line, checkboxes 12/12 → add ✅ Complete
   ```

   Report them; do not fix them silently. Backfilling is an edit to a plan document and
   belongs to the developer's call, not to a status read.

3. If `docs/ROADMAP.md` exists, show the module table with its current statuses, and the
   open milestone (`← OPEN`) with the modules still Pending against it.

4. Show the last 10 EVENTS.jsonl events (if present):
   ```
   ### Recent Events
   - [10:35:00] ORCHESTRATION_COMPLETE — 01-core-loop
   - [10:34:00] TASK_COMPLETED — T003
   ...
   ```

5. Scan the project files:
   - `.cs` file count: `_GameFolders/Scripts/`
   - Test file count: `_GameFolders/Scripts/Tests/`
   - Prefab count: `_GameFolders/Prefabs/`

## Output Format

```
## Pipeline Status

**Project:** [game name from the GDD, or "Not started"]
**Current Stage:** [stage name]
**Next Step:** [command to run]

### Documents
- [✅|❌] GDD  — docs/GDD.md
- [✅|❌] TDD  — docs/TDD.md
- [✅|❌] ROADMAP — docs/ROADMAP.md

### Modules (ROADMAP summary)
| # | Module | Status |
|---|-------|--------|
| 01 | core-loop | ✅ Complete |
| 02 | audio | ⏳ Pending |

### Recent Events (EVENTS.jsonl)
[last 10 events]

### Produced Assets
- C# Scripts: [count]
- Test Files: [count]
- Prefabs: [count]
```

$ARGUMENTS
