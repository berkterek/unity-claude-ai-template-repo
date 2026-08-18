# /migrate — Migrator → Reviewer → Committer Pipeline

Migrates legacy code patterns to current standards: migrator converts, reviewer checks, committer commits.

## Usage

```
/migrate <what and where>
/migrate coroutines → UniTask in Assets/_Game/Scripts/Core/
/migrate singleton GameManager to VContainer in Assets/_Game/Scripts/
```

If no argument is given, ask:
1. What pattern needs migrating? (coroutine→UniTask, singleton→VContainer, Debug.Log→wrapper, Input.GetKey→New Input System, other)
2. Which files or folder?

## Step 0 — Plugin Preflight

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:verification-before-completion` | Completion — verify migration is complete before commit (complexity ≥ 0.7) | Skip verification gate |

Print availability status before proceeding:
```
Plugins: superpowers:verification-before-completion [✓/✗]
```

---

## Step 0b — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | Test guard ve unity-developer yok — migrator → committer only. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the migration complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Pipeline variant |
|-------|-------|---------|-----------------|
| 0.0–0.3 | **Simple** | Single file, mechanical substitution (e.g. one coroutine) | migrator/unity-migrator → reviewer → committer |
| 0.4–0.6 | **Medium** | Multiple files, interface changes, or VContainer rewiring | test guard → migrator/unity-migrator → reviewer → committer |
| 0.7–1.0 | **Complex** | Cross-module migration, ECS involvement, or Addressables | test guard → migrator/unity-migrator → codex:codex-rescue reviewer → unity-developer → committer |

**Migrator agent routing — decide before spawning:**

| Migration type | Agent |
|----------------|-------|
| Pure C# pattern (no Unity API: data classes, interfaces, services) | **migrator** |
| Unity-specific (coroutine→UniTask, singleton→VContainer, Input.GetKey→New Input System) | **unity-migrator** |

**Scoring signals:**
- Touches more than 5 files? +0.3
- Changes a public interface or adds IEventBus events? +0.2
- Involves ECS systems or Addressables? +0.3
- Single file, single pattern? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Migrator Agent: [migrator | unity-migrator]
Pipeline: [which variant]
Review Mode: [solo | lean | full]
```

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: migration description, complexity score, known affected files or folder.
Wait for `go` before proceeding.

After receiving `go` → run:
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"SCOPE_GATE","pipeline":"migrate","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

If the migration scope touches more than 5 files (scoring signal "+0.3 Touches more than 5 files"): also fire **BREAKING_GATE** (see `.claude/docs/director-gates.md`). Show all files in scope and wait for `go` or `stop`.

---

## Step 0c — Knowledge Graph Preload

Before spawning the migrator, decide whether the knowledge graph can accelerate finding every affected site. This follows the graph-first pattern in `/search` Step 0a. It runs *after* the gates above and does NOT feed them — it only accelerates the Migrator's own site enumeration in Step 2, giving it a complete affected-site list and blast radius faster than grepping.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, proceed with file-scan behavior (unchanged).

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

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, fall back to file scan. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated migration scoping. Falling back to file scan.
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

Keep this output as `GRAPH_CONTEXT` and embed it into the Migrator agent prompt (Step 2). When `GRAPH_CONTEXT` is empty, the migration phase behaves exactly as before — no regression. When non-empty, the Migrator uses the graph's `callers`/`impact`/`dependencies` data to **enumerate every affected site** — a faster and more complete source for "what depends on this" than grepping.

---

## Pipeline

```
[1] TEST GUARD → [2] MIGRATOR → [3] REVIEWER ⟲ (loop until APPROVED) → [4] COMMITTER
```

---

## Step 1 — Test Guard

> **Skip this step if complexity score is Simple (0.0–0.3) and review mode is not `full`.**

Spawn Agent with `subagent_type: "claude"` (`model: sonnet` — isolated tester is worker-tier) with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Migration Task
[INSERT HERE: the migration description from the /migrate argument]

## Your job
1. Check if tests already exist for the code being migrated.
2. If tests exist and cover the relevant behavior → report: TESTS EXIST, list them.
3. If tests are missing → write them now, covering the behavior that must survive the migration.
4. These tests must pass BEFORE migration starts.

Report: TESTS EXIST or TESTS WRITTEN, with list of test files and what each covers.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 2 — Migrator

Spawn Agent with `subagent_type: "unity-migrator"` with this prompt:

```
You are a Unity code migration specialist. Migrate legacy patterns in this project.

## Migration Task
[INSERT HERE: the migration description from the /migrate argument]

## Knowledge Graph (class/interface/event/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0c — if empty, write "No usable graph — scan source files directly."]

## Instructions — Graph-First Site Discovery
1. If a knowledge graph inventory is provided above (non-empty), use it FIRST to find every site affected by this migration and its blast radius — do not re-scan folders for what it already answers:
   - Use `impact` / `dependencies` on the class or pattern being migrated to enumerate every caller and dependent, so no instance of the old pattern is missed.
   - Use `callers` to confirm which call sites must be updated alongside the migrated class.
   - Use the installers/registrations data to find every VContainer wiring point that needs updating (singleton→VContainer migrations).
   - Only read source files for the exact lines to change — not to rediscover what already depends on what.
2. If the graph inventory is empty (or absent), search the codebase directly for every instance of the old pattern (file scan, as before).

## Project Rules
- Read .claude/CLAUDE.md before making any changes
- Follow all rules in .claude/rules/
- Migrate conservatively: same behavior, different implementation
- Do NOT add features or refactor beyond the migration
- Every file you touch must compile and work after your edit
- Check every file that depends on the migrated code

## Common Migration Patterns

### Coroutine → UniTask
- IEnumerator + yield return → async UniTask
- WaitForSeconds → UniTask.Delay
- StartCoroutine → .Forget() or await
- Every async method must have CancellationToken parameter

### Singleton → VContainer
- Remove static Instance
- Register in the appropriate LifetimeScope installer
- Replace all call sites with injected interface

### Legacy Input → New Input System
- Input.GetKey / Input.GetAxis → PlayerControls actions
- All input reading must go through InputView

## When Done
List every file you changed with a one-line summary of what was migrated.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 3 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

Reviewer prompt:
```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review this code migration.

## Migration
[INSERT HERE: the migration description from the /migrate argument]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The orchestration ledger is NOT part of any migration
and must never be reported as a scope violation: `.claude/**`, `docs/**`, `*.json`,
`*.jsonl`, `*.md` (unless a `.md` is itself listed under "Files Changed").

> Criterion 3 (completeness) is the one exception that legitimately looks OUTSIDE the
> changed files: to prove no instance of the old pattern is left behind you must search
> the whole `Assets/` tree. Report such a leftover as an INCOMPLETE MIGRATION, never as
> a scope violation.

## Files Changed
[INSERT HERE: the list of files modified by the Migrator agent]

## Review Criteria
1. Tests pass — all pre-migration tests still pass after migration; no test files were modified
2. Correctness — same behavior before and after, no regressions
3. Completeness — all instances of the old pattern are migrated, no leftovers
4. Architecture — VContainer DI, no singletons, interfaces only across modules
5. UniTask rules — no async void, CancellationToken on every async method
6. Unity null safety — no ?. or is null on UnityEngine objects

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 6 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Criterion 3 (completeness) must cite the
tree-wide search you ran and its result count, not an assumption.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** See the measurement
> note in `orchestrate.md` Step 3: without the scope lock and the per-item output
> contract, the Codex reviewer made 1 tool call, answered 3 of 12 criteria, returned a
> reasonless APPROVED, and reported the orchestration ledger as a scope violation.

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **migrator** subagent to fix every listed issue:
   ```
   You are a Unity code migration specialist. Fix the following review issues.

   ## Original Migration
   [INSERT HERE: the migration description from the /migrate argument]

   ## Review Feedback (fix ALL of these)
   [INSERT HERE: the full CHANGES NEEDED list from the Reviewer]

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After migrator fixes → re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

### unity-developer Pass (Complex only)

If complexity score ≥ 0.7 and review mode is `lean` or `full`: after reviewer reports APPROVED, spawn a **unity-developer** subagent with this prompt:

```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review this migration for Unity-specific correctness.

## Migration Task
[INSERT HERE: the migration description from the /migrate argument]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The orchestration ledger is NOT part of any migration
and must never be reported as a scope violation: `.claude/**`, `docs/**`, `*.json`,
`*.jsonl`, `*.md`.

## Files Changed
[INSERT HERE: the list of files modified by the Migrator agent]

## Review Criteria (from .claude/agents/unity-developer.md)
- Hot-path allocations introduced?
- Draw call regressions?
- ECS safety (structural changes via ECB only)?
- Addressables handle lifecycle correct?
- Prefab structure intact (root=logic / Body=visual)?
- UniTask cancellation tokens present on all async methods?

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 6 review criteria above, in the order
listed. No item may be omitted, merged, or answered "n/a" without a stated reason —
"this migration does not touch ECS" is a stated reason, silence is not. Format:

  <criterion> | CONFIRMED, GAP, or N/A (+reason) | <file>:<line> | <evidence you read>

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Presence of a symbol is not evidence that
its usage is correct: an `Addressables` handle field is not proof the handle is
released, and a `CancellationToken` parameter is not proof it is passed downstream.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** See the measurement
> note in `orchestrate.md` Step 3. This pass runs `unity-developer`, not Codex, but the
> defect it guards against is the same one measured there: a reviewer that answers a
> checklist with a bare APPROVED has not been shown to have read anything.

If CHANGES NEEDED → spawn **unity-migrator** to fix, then re-run unity-developer (max 2 passes).

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: migration description, all changed files, reviewer verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 4 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Migration: `[INSERT HERE: the migration description from the /migrate argument]`
- Files changed: `[INSERT HERE: the list of files modified by the Migrator agent]`
- Run: `git status`, `git diff`
- Stage only migration-related files
- Commit message format: `"refactor: migrate <pattern> in <scope>"`
- One commit per migration type (if multiple patterns, split commits)
- Do NOT push; report: commit hash(es) and message(s)

---

## Completion

Run: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"`

**If `superpowers:verification-before-completion` is available AND complexity score ≥ 0.7:** Invoke it before reporting done. Verify every old pattern instance was replaced and no orphaned references remain.

Print:
```
## ✓ Migration Complete
Migration: [description]
Files changed: [count]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
