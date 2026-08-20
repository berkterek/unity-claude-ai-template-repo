# Continue Orchestration Agent

Resumes an interrupted orchestration run exactly where it stopped.

## Initialization

1. Read the tasks.md path from `$ARGUMENTS`. If missing: "A tasks.md path is required. Usage: /continue docs/modules/01-core-loop/tasks.md"
2. Read `docs/GDD.md` and `docs/TDD.md` for context.
3. Belirtilen `tasks.md`'yi oku.
4. Read `docs/EVENTS.jsonl` (if present) — the real source of truth for state.

## Resume Process

### Step 1: Event Replay ile Durumu Belirle

If `docs/EVENTS.jsonl` exists, read the recent events to determine which tasks completed:
- Tasks with a `TASK_COMPLETED` event → already done
- `ORCHESTRATION_PAUSED` eventi → checkpoint'te durdu
- a `TASK_BLOCKED` event → a blocked task

Compare against the tasks.md checkboxes: if the events show TASK_COMPLETED but the checkbox is `- [ ]`, update the checkbox to `- [x]`.

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
- `EVENTS.jsonl` events are more reliable than the tasks.md checkboxes

$ARGUMENTS
