# /qa — Quality Assurance Pipeline

Runs a three-stage quality check on the current codebase state: compile + test green → silent failure audit → phase validation. Use after any implementation work to confirm the project is clean before proceeding.

## Usage

```
/qa
/qa --phase 2
/qa --files Assets/_GameFolders/Scripts/Games/Concretes/Audio/
```

| Argument | Effect |
|----------|--------|
| *(none)* | Audit all recently changed files, validate most recently completed tasks |
| `<tasks.md path>` | Validate tasks from a specific module tasks.md |
| `--files <path>` | Scope silent failure hunt to specific files or folder |

---

## Plugin Preflight

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:verification-before-completion` | Final Report — evidence gate before declaring CLEAN | Skip verification gate |

Print availability status before proceeding:
```
Plugins: superpowers:verification-before-completion [✓/✗]
```

---

## Pipeline

```
[Step 0] Knowledge Graph Preload → GRAPH_CONTEXT (or empty on stale/empty/disabled)
    ↓
[Stage 1] Ralph → [Stage 2] Silent Failure Hunt → [Stage 3] Validate → [Report]
```

---

## Step 0 — Knowledge Graph Preload

Before spawning the Stage 2 audit agent, decide whether the knowledge graph can give it a head start. This is a lightweight, optional preload — `/qa` audits specific files rather than building broad codebase understanding, so the graph mainly helps Stage 2's IEventBus Subscribe/Unsubscribe check (the graph already tracks `events_published`/`events_subscribed` per class).

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, proceed to Stage 1 unchanged.

If it is a candidate, verify the graph is **usable** (fresh AND non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, no warning — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan for this pass:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated audit. Falling back to file scan.
  ```
- Otherwise (fresh AND non-empty) → build `GRAPH_CONTEXT` from the graph inventory:

```bash
python3 -c "
import json
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
classes = cb.get('classes', [])
interfaces = cb.get('interfaces', [])
events = cb.get('events', [])
installers = cb.get('vcontainer', {}).get('installers', [])
print('CLASSES (%d):' % len(classes))
for c in classes:
    print('  %s | mono=%s | deps=%s | pub=%s | sub=%s' % (
        c['name'], c.get('is_mono_behaviour', False),
        c.get('dependencies', []), c.get('events_published', []), c.get('events_subscribed', [])))
print('INTERFACES (%d):' % len(interfaces))
for i in interfaces: print('  %s' % i['name'])
print('EVENTS (%d):' % len(events))
for e in events: print('  %s' % e['name'])
print('INSTALLERS (%d):' % len(installers))
for inst in installers:
    regs = [r.get('type','') for r in inst.get('registrations', [])]
    print('  %s | registrations=%s' % (inst['name'], regs))
"
```

Keep this output as `GRAPH_CONTEXT` and embed it into the Stage 2 (unity-linter) agent prompt. When `GRAPH_CONTEXT` is empty, Stage 2 behaves exactly as before — no regression.

---

## Stage 1 — Ralph (Compile + Tests)

Spawn a **unity-verifier** subagent to compile and run all tests.

If failures found → spawn **unity-fixer** subagent to fix each issue, then re-verify. Repeat up to **2 passes** (compile/test-fix bound — see `.claude/docs/director-gates.md` → Retry and Pass Limits).

- `PASS` → proceed to Stage 2.
- `FAIL after 2 passes` → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`) with
  `$WHAT_WAS_RETRIED` = compile and tests, `$N` = 2, `$PASS_TYPE` = fix, and every remaining
  failure listed. Fill `Skipping ships:` from those failures. `skip` proceeds to Stage 2 with
  a warning logged; `stop` aborts.

Print: `✓ Stage 1 — Ralph: compile and tests green.` or `⚠ Stage 1 — Ralph: [N] issues remain.`

---

## Stage 2 — Silent Failure Hunt

Determine scope:
- If `--files <path>` given → audit those files only
- Otherwise → audit all files modified in the most recent git commits since the last phase commit (use `git diff --name-only HEAD~5` as a heuristic, filter to `.cs` files)

Spawn a **unity-linter** subagent with this prompt:

```
Audit the following C# files for silent failure patterns:

FILES: $TARGET_FILES

## Knowledge Graph (event pub/sub inventory — query BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0 — if empty, write "No usable graph — scan source files directly."]

If a knowledge graph inventory is provided above (non-empty), use it FIRST to cross-check check #3 below —
a class listed with `sub=[...]` events but no matching `Unsubscribe<T>` call in its Dispose/OnDisable is a
strong candidate finding; confirm by reading the actual file before reporting. If the graph is empty or absent,
scan the target files directly as before.

Check for:
1. catch blocks that swallow exceptions without logging or rethrowing
2. async void outside Unity lifecycle methods (Awake, Start, OnEnable, OnDisable, OnDestroy)
3. IEventBus subscriptions (Subscribe<T>) without a matching Unsubscribe<T> in Dispose/OnDisable
4. UniTask.Forget() calls without an onException error handler
5. Empty catch blocks: catch { } or catch (Exception) { }

For each finding:
- [file:line] — [pattern type] — [description] — [suggested fix]

If nothing found: CLEAN
```

Print all findings or `✓ Stage 2 — Silent failures: CLEAN.`

---

## Stage 3 — Validate

Determine which tasks to validate:
- If a tasks.md path given → validate tasks from that file
- Otherwise → validate the most recently completed tasks from `[x]` checkboxes in `docs/modules/*/tasks.md`

If no tasks.md exists → skip this stage and note: `Stage 3 skipped — no tasks.md found.`

Spawn a **general-purpose** subagent (`model: sonnet`) with this prompt:

```
You are a strict QA gate. Validate the completed tasks.

Read:
- [tasks.md path] — task definitions and acceptance criteria
- tasks.md checkbox status — reported completion status

Checks:
1. All output files listed in WORKFLOW.md for this phase exist at the specified paths
2. Files are not empty or placeholder stubs
3. Every acceptance criterion is met — read the actual code to verify, do not assume

Output format:
PASS — all [N] criteria met.

FAIL:
- [P{phase}.T{task}] [criterion text] — [what is missing or wrong]
(list every failure)
```

Print result: `✓ Stage 3 — Validate: PASS` or `⚠ Stage 3 — Validate: FAIL — [N] criteria unmet.`

---

## Final Report

```
## QA Report
─────────────────────────────────────
Stage 1 — Ralph:          ✓ green  |  ⚠ [N issues]
Stage 2 — Silent failures: ✓ CLEAN  |  ⚠ [N findings]
Stage 3 — Validate:        ✓ PASS   |  ⚠ FAIL ([N criteria])
─────────────────────────────────────
Overall: CLEAN ✓  |  ISSUES FOUND ⚠
```

**If `superpowers:verification-before-completion` is available AND overall status is CLEAN:** Invoke it before reporting done. Confirm all three stages passed with evidence.

If **CLEAN** → print: `Project is clean. Safe to proceed.`

If **ISSUES FOUND** → list all issues grouped by stage, then show **QUALITY_GATE**
(`.claude/docs/director-gates.md`) with the issues as the CHANGES NEEDED items. Include the
optional `list` line — the issues are summarised by stage here, not printed in full.

Per-option behaviour for this caller:
- `fix` → spawn **unity-coder** with all findings as a fix list, then re-run `/qa`
- `list` → print full details for each finding, then **re-show the gate** (non-terminal)
- `skip` → exit with a warning logged to the relevant `tasks.md`
- `stop` → abort

$ARGUMENTS
