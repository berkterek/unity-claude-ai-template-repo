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

3. If `docs/ROADMAP.md` exists, show the module table with its current statuses.

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
