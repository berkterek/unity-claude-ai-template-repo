# Continue Orchestration Agent

Resumes an interrupted orchestration run exactly where it stopped.

## Initialization

1. Read the tasks.md path from `$ARGUMENTS`. If missing: "A tasks.md path is required. Usage: /continue docs/modules/01-core-loop/tasks.md"
2. Read `docs/GDD.md` and `docs/TDD.md` for context.
3. Read the specified `tasks.md`.
4. Read `docs/EVENTS.jsonl` (if present) — authoritative for what the **interrupted run**
   completed, which is exactly the window the checkboxes can be behind in (`/orchestrate`
   writes the event first and the checkbox second, so a crash between the two leaves a
   completed task unticked).

## Resume Process

### Step 1: Event Replay ile Durumu Belirle

If `docs/EVENTS.jsonl` exists, read the recent events to determine which tasks completed:
- Tasks with a `TASK_COMPLETED` event → already done
- `ORCHESTRATION_PAUSED` eventi → checkpoint'te durdu
- a `TASK_BLOCKED` event → a blocked task

Compare against the tasks.md checkboxes: if an event shows TASK_COMPLETED but the checkbox
is `- [ ]`, tick it — **but only for events belonging to the run being resumed** (newer than
that run's start or its most recent `ORCHESTRATION_PAUSED`).

`EVENTS.jsonl` is append-only **across runs**, so an unscoped re-tick silently overwrites a
human decision: someone who unticks a finished task to redo it leaves an older
`TASK_COMPLETED` in the ledger, and a blanket "events beat checkboxes" rule re-ticks it and
skips the work. **A deliberate untick outranks any event older than the current run.** If an
older event and an unticked box disagree, leave the box alone and report the disagreement
rather than resolving it silently.

### Step 2: Recovery Plan

Based on the state in tasks.md:
- `- [x]` checkbox → complete, skip it
- `- [ ]` checkbox → pending, run it
- `TASK_BLOCKED` in EVENTS.jsonl → report the block and ask the user how to resolve it

### Step 3: Report to the User

```
## Devam Ediliyor

tasks.md: [path]
Complete: [N] tasks
Bekliyor: [M] task
Bloke: [K] task

Type `go` to continue:
```

### Step 4: Devam Et

After the user approves, continue with the same logic as `/orchestrate docs/modules/<n>-<name>/tasks.md`:
- Skip completed tasks (`[x]`)
- Run the pending tasks
- Create orchestration-active.json:
  ```bash
  echo '{"started":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","module":"[module name]"}' > .claude/orchestration-active.json
  ```

## Kurallar
- Never re-run a completed task
- Never skip the review step
- For the run being resumed, `EVENTS.jsonl` is more reliable than the tasks.md checkboxes —
  the event is written before the checkbox, so a crash lands in that gap. Outside that
  window the checkboxes are authoritative and a human's untick wins; the ledger spans every
  past run and is not a statement about the current one.

$ARGUMENTS
