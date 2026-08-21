# /fix — Debugger → Test Writer → Coder → Reviewer → Committer Pipeline

Fixes a bug using a five-agent TDD pipeline: debugger finds root cause, test writer writes a failing regression test, coder fixes to make it pass, reviewer checks, committer commits.

## Usage

```
/fix <bug description>
/fix BayManager throws NullReferenceException when a car exits during FlowEngine tick
```

If no argument is given, ask: "Describe the bug."

## Pipeline

```
[1] DEBUGGER → [2] TEST WRITER → [3] CODER → [4] REVIEWER ⟲ (loop until APPROVED) → [4.7] SILENT FAILURE AUDIT → [5] COMMITTER
```

---

## Step 0 — Flag Detection

Parse `$ARGUMENTS` for flags before any other step:

- If `$ARGUMENTS` contains `--heavy` → set `FORCE_OPUS_TIER=true`
- If `$ARGUMENTS` contains `--lite` → set `FORCE_HAIKU_TIER=true`

Strip flag tokens from the bug description passed to agents (do not include `--heavy` / `--lite` in agent prompts).

---

## Step 0 — Plugin Preflight

**Plugin availability check:**
Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:systematic-debugging` | Step 1 — root cause analysis before spawning agents | Proceed with unity-fixer directly |
| `claude-md-management:revise-claude-md` | Completion — update CLAUDE.md with session learnings | Skip |

Print availability before proceeding:
```
Plugins: superpowers:systematic-debugging [✓/✗] | claude-md-management [✓/✗]
```

---

## Step 0.25 — Knowledge Graph Query

If `.claude/project-features.json` has `graph == true` AND `.claude/graph/graph.json` exists:

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

Keep this output in your active context as `GRAPH_CONTEXT`. You will embed it into subagent prompts in Steps 1 and 2.

If graph is disabled or missing → set `GRAPH_CONTEXT` to empty, proceed.

---

## Step 0.5 — Complexity Scoring

**Step 0a — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | Skip Test Writer and Reviewer — Coder → Committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the task complexity on a 0.0–1.0 scale and decide the pipeline variant:

| Score | Label | Signals | Pipeline |
|-------|-------|---------|----------|
| 0.0–0.19 | **Trivial** | Single file, stack trace points to exact line, NullRef/missing ref/typo | Standard pipeline (use `--lite` flag for haiku tier) |
| 0.2–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Spawn Coder directly — skip Debugger and Test Writer |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Full pipeline: Test Writer → Coder → Reviewer → Committer |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Full pipeline + unity-developer reviewer (always active in `full` mode, or when score ≥ 0.7 in `lean` mode) |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputService, or a [Domain]Module? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Pipeline: [which variant]
```

**Trivial (score < 0.2):** Continue with the standard pipeline (use `--lite` flag for haiku tier). Proceed to SCOPE_GATE below.

**Complex (score ≥ 0.7):** Consider re-running with the `--heavy` flag for an opus-tier coder, or use `/fix-deep` if the root cause is uncertain. (At this tier the pipeline already adds the `unity-developer` Opus second reviewer automatically.)

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: bug description, complexity score.
Wait for `go` before spawning any agents.

After receiving `go` → run:
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"SCOPE_GATE","pipeline":"fix","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

---

For **Complex** tasks: after the standard Reviewer step passes, spawn a **unity-developer** subagent with the same changed files list and the review criteria from `.claude/agents/unity-developer.md` before proceeding to the Committer.

---

## Step 1 — Debugger

**If `superpowers:systematic-debugging` is available AND complexity score ≥ 0.4:** Invoke `superpowers:systematic-debugging` first to structure the root cause hypothesis before spawning unity-fixer. Pass the bug description and any stack traces. Use its output to enrich the unity-fixer prompt below.

**If complexity score ≥ 0.4:** Spawn **unity-fixer** and **unity-scout** simultaneously. Proceed once both complete.

**If complexity score < 0.4 (Simple):** Spawn unity-fixer only — skip to Step 2 if Simple bypasses debugger.

Spawn a **unity-fixer** subagent with this prompt (note: unity-fixer reads surrounding context files before patching — include all relevant file paths in the bug report so it can orient itself):

```
You are a senior Unity engineer specializing in root cause analysis. Investigate the following bug.

## Bug Report
[INSERT HERE: the bug description from the /fix argument]

## Knowledge Graph (class/interface/event/installer inventory — use as primary reference)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0.25 — if empty, write "No graph available."]

## Project Context
- Read .claude/CLAUDE.md for architecture overview
- VContainer DI, UniTask async, IEventBus for events

## Your Task
1. Read the relevant source files to understand the code paths involved.
2. Identify the root cause (not just symptoms).
3. Identify all files that need to change.

## Output Format
ROOT CAUSE: <one sentence>

AFFECTED FILES:
- <file path> — <what needs to change>

REPRODUCTION PATH:
<step-by-step sequence of calls that leads to the bug>

DO NOT fix anything. Report only.
```

### unity-scout Agent Prompt (complexity ≥ 0.4 only)

```
You are a Unity risk analyst. While the debugger investigates the bug, scan in parallel for Unity-specific risk patterns.

BUG: [INSERT HERE: the bug description from the /fix argument]

## Instructions

Scan for Unity-specific patterns that could cause or contribute to this bug:
- VContainer registration gaps or scope hierarchy issues
- UniTask async methods missing CancellationToken or using async void
- Input System lifecycle violations (missing Enable/Disable)
- ECS structural changes outside EntityCommandBuffer
- Addressables handles not released
- Unity null check violations (?. or is null on UnityEngine objects)
- Missing [Inject] Construct() methods on MonoBehaviours

## Output Format (REQUIRED)

UNITY_RISKS:
- [risk type] — [file:line] — [description]
OR: UNITY_RISKS: none
```

### Merge (after both agents complete)

Combine into unified debugger output before showing to user:

```
ROOT CAUSE: [from unity-fixer]

AFFECTED FILES:
- [from unity-fixer]

REPRODUCTION PATH:
[from unity-fixer]

UNITY_RISKS (parallel scan):
[from unity-scout, or "none"]
```

Show the debugger output to the user. Ask: "Root cause found — proceed with fix? (yes / stop)"

If **stop** → abort.

If the number of affected files reported by the debugger is **more than 3**: fire **BREAKING_GATE** (see `.claude/docs/director-gates.md`) before proceeding to the Test Writer. Show the full affected file list and wait for `go` or `stop`.

---

## Step 2 — Find Existing Test File

For each file in the debugger's AFFECTED FILES list, check if a corresponding test file already exists:

```bash
find . -name "[ClassName]Tests.cs" -path "*/Tests/*"
```

**If test file found** → note the path; Test Writer adds a regression test case to that file. Skip the router entirely.

**If no test file exists** → run `.claude/skills/core/test-type-router.md` once to decide where the new test goes. Emit the decision block, then proceed.

- **NoTest** → skip Step 3 (Test Writer); proceed directly to Step 4 (Coder)
- All other decisions → Test Writer creates the file in the correct assembly

---

## Step 3 — Test Writer

Spawn Agent with `subagent_type: "claude"` (`model: sonnet` — isolated tester is worker-tier) with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Bug
[INSERT HERE: the bug description from the /fix argument]

## Root Cause
[INSERT HERE: the ROOT CAUSE line from the debugger output]

## Affected Files
[INSERT HERE: the AFFECTED FILES list from the debugger output]

## Your job
Write regression test(s) that:
1. Directly reproduce the bug — the test must FAIL right now, do not fix the bug
2. Will PASS once the root cause is fixed
3. Serve as a permanent regression guard

When done: list every test file created with a summary. Report: DONE or BLOCKED with reason.
```

If test writer reports **BLOCKED** → stop and show the blocker to the user.

---

## Step 4 — Coder

**FIRST — SPARC_GATE (blocking, before any coder spawn; fires when complexity ≥ 0.4).**

Show the SPARC_GATE block from `.claude/docs/director-gates.md` → Hook-Enforced Gates: the Specification (what will be fixed) and the Architecture (which files, interfaces, data flow). Wait for `go`, then create the state file exactly as that entry specifies (absolute path — a relative `touch` creates a file the hook never reads). Delete it after the coder agent completes.

Note the hook does **not** know the complexity score: `guard-sparc-approved.sh` exits **2** for every `coder` / `unity-coder` spawn while `.claude/state/sparc-approved` is absent, including a below-threshold fix. Below 0.4, state that the gate is being cleared as a formality rather than skipping it silently.

**Agent routing — decide before spawning:**

| Target location | Agent |
|-----------------|-------|
| `_Framework/`, `Games/Abstracts/`, `Games/Concretes/` (no Unity API) | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** |

**Model tier override (apply when spawning unity-fixer or unity-coder in this step):**
- If `FORCE_HAIKU_TIER == true` → spawn with `model: haiku`
- Else if `FORCE_OPUS_TIER == true` → spawn with `model: opus`
- Else → spawn at default sonnet tier

Spawn the appropriate subagent with this prompt:

```
You are a senior C# Unity developer. Fix the following bug.

## Bug
[INSERT HERE: the bug description from the /fix argument]

## Root Cause (already investigated)
[INSERT HERE: the ROOT CAUSE line from the debugger output]

## Files to Change
[INSERT HERE: the AFFECTED FILES list from the debugger output]

## Regression Test (make this pass)
[INSERT HERE: the full output from the Test Writer agent — test file path and test method names]

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/
- Before using an unfamiliar Unity API, check `docs/engine-reference/unity/deprecated-apis.md` — the reviewer applies gate `TD-UNITY-RISK` and will return CHANGES NEEDED on a deprecated call
- No singletons — VContainer only
- No coroutines — UniTask only
- Fix only what is broken — do not refactor surrounding code
- Do NOT modify the test files

## When Done
List every file you modified with a one-line summary of the change.
Confirm the regression test now passes.
Report: DONE or BLOCKED with reason.
```

If coder reports **BLOCKED** → stop and show the blocker to the user.

---

## Step 4.5 — Unity Validator (gate `TD-COMPILE`) (MANDATORY — runs before Reviewer)

Spawn a **unity-verifier** subagent with this prompt:

```
You are a Unity build validator. Your only job is to verify that the project compiles and all tests pass.

## What Was Fixed
[INSERT HERE: the bug description from the /fix argument]

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Instructions
1. Use `mcp__unityMCP__refresh_unity` to trigger a script recompile.
2. Wait until `isCompiling` is false (poll `editor_state` resource).
3. Use `mcp__unityMCP__read_console` with type "Error" to check for compile errors.
4. If compile errors exist → report COMPILE FAILED with the full error list. Stop here.
5. If compile is clean → use `mcp__unityMCP__run_tests` to run all Edit Mode tests.
6. Check test results for any failures.
7. If any tests fail → report TEST FAILED with test names and failure messages. Stop here.
8. If all tests pass → report VALIDATED.

## Output Format
VALIDATED — zero compile errors, all tests pass.

COMPILE FAILED:
- [error message] — [file:line]

TEST FAILED:
- [test name] — [failure message]
```

### Validator Loop (max 2 fix passes)

If validator reports **COMPILE FAILED** or **TEST FAILED** → spawn a **unity-coder** subagent to fix the issues:

```
You are a senior C# Unity developer. Fix the following build or test failures.

## Original Bug Fix Context
Bug: [INSERT HERE: the bug description from the /fix argument]
Root Cause: [INSERT HERE: the ROOT CAUSE line from the debugger output]

## Failures (fix ALL of these)
[INSERT HERE: the full COMPILE FAILED or TEST FAILED output from the Unity Validator]

## Rules
- Fix only what is listed — do not refactor anything else
- For assembly definition issues: check that the test assembly references the correct game assembly and has NSubstitute in precompiledReferences with overrideReferences: true
- For compile errors: fix the exact file:line reported
- For test failures: fix the implementation, never change the test

## When Done
List every file you changed. Report: DONE or BLOCKED.
```

After unity-coder fixes → re-run the **Unity Validator** on the updated files.

If still failing after **2 fix passes** → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`) with
`$WHAT_WAS_RETRIED` = the Unity validator, `$N` = 2, `$PASS_TYPE` = fix, and every remaining
compile error or test failure listed. Fill `Skipping ships:` from the errors themselves —
`skip` here hands the reviewer code that does not compile, so say so.

---

## Step 5 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review this bug fix.

## Bug
[INSERT HERE: the bug description from the /fix argument]

## Root Cause
[INSERT HERE: the ROOT CAUSE line from the debugger output]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The orchestration ledger is NOT part of any fix and
must never be reported as a scope violation: `.claude/**`, `docs/**`, `*.json`,
`*.jsonl`, `*.md` (unless a `.md` is itself listed under "Files Changed").

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Review Criteria
1. Regression test passes — the pre-written test now passes; test file was not modified
2. Does the fix actually address the root cause (not just the symptom)?
3. Does the fix introduce any new bugs or regressions?
4. Architecture (gate `TD-ARCHITECTURE`) — VContainer DI, no singletons, interfaces only across modules
5. Performance (gate `TD-PERFORMANCE`) — no allocations in Update/FixedUpdate
6. UniTask — no async void, CancellationToken on every async method
7. Unity null safety — no ?. or is null on UnityEngine objects
8. Unity engine risk (gate `TD-UNITY-RISK`) — no API listed in `docs/engine-reference/unity/deprecated-apis.md` is used; the change does not fall in an area listed in `breaking-changes.md`; where `current-best-practices.md` names a better alternative, it was used or the deviation is stated
9. Scope discipline (gate `CD-SCOPE`) — **count the callers of every type, method and field this change introduces.** **Zero callers anywhere is a violation** — name it, including an interface nobody implements or consumes, a private method nothing invokes, and a field nothing reads. **Exactly one production caller is not a violation** — the test suite is the second caller (`rules/architecture.md` → one-caller rule); do not read this exception as "never flag an abstraction". Also: no file was changed that the task did not require, and no unrelated code was refactored

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for every one of the 9 review criteria above. No item may be
omitted, merged, or answered "n/a" without a stated reason. Format:

  <N> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

**`GAP` requires a violation you can point at.** If you looked and the criterion is met, the verdict is `CONFIRMED` — write it and move on. A `GAP` whose own evidence sentence says no violation is present ("no `?.` misuse found", "namespace format itself is fine") is **invalid**, and so is a `GAP` for something that merely *could* have been done differently. Measured 2026-08-21 on a planted-defect fixture: 4 of 10 criteria came back `GAP` with evidence that contradicted the verdict — the per-item line requirement pressures invention. Filling every line is mandatory; finding a fault on every line is not.

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. "The root cause is addressed" needs the
line that addresses it.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** See the measurement
> note in `orchestrate.md` Step 3: without the scope lock and the per-item output
> contract, the Codex reviewer made 1 tool call, answered 3 of 12 criteria, returned a
> reasonless APPROVED, and reported the orchestration ledger as a scope violation.

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **unity-coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Original Bug Fix Context
   Bug: [INSERT HERE: the bug description from the /fix argument]
   Root Cause: [INSERT HERE: the ROOT CAUSE line from the debugger output]

   ## Review Feedback (fix ALL of these)
   [INSERT HERE: the full CHANGES NEEDED list from the Reviewer]

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After unity-coder fixes → re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 4.5.

4. If still **CHANGES NEEDED** after 3 passes → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`)
   with `$WHAT_WAS_RETRIED` = the reviewer loop, `$N` = 3, `$PASS_TYPE` = reviewer, and every
   remaining finding listed. Fill `Skipping ships:` from the reviewer's own findings — it
   already named the rule each one violates. `skip` proceeds to the verifier.

---

## Step 5.5 — Unity Verifier (Final Bounded Check)

Spawn a **unity-verifier** subagent once with this prompt (max 3 internal iterations):

```
You are a Unity post-fix verifier. Perform a final bounded check on the delivered bug fix.

## Bug Fixed
[INSERT HERE: the bug description from the /fix argument]

## Root Cause
[INSERT HERE: the ROOT CAUSE line from the debugger output]

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Instructions
Run up to 3 internal fix-check iterations. In each iteration:
1. Use `mcp__unityMCP__refresh_unity` and wait for compile to finish.
2. Check `mcp__unityMCP__read_console` for errors.
3. Run `mcp__unityMCP__run_tests` and check for failures.
4. Verify prefab structure is intact: root holds logic components, Body child holds visual components.
5. If compile errors or test failures exist and iterations remain — fix and re-check.
6. If clean after any iteration → stop and report VERIFIED.
7. If still failing after 3 iterations → report VERIFY FAILED with all remaining issues.

## Output Format
VERIFIED — compile clean, all tests pass, prefab structure valid.

VERIFY FAILED:
- [issue description]
```

If unity-verifier reports **VERIFY FAILED** → show **EXHAUSTION_GATE** (`.claude/docs/director-gates.md`) with
`$WHAT_WAS_RETRIED` = the verifier, `$N` = 3, `$PASS_TYPE` = iteration, and every remaining
issue listed. Fill `Skipping ships:` from those issues — `skip` commits code the verifier
could not get compiling and passing in three tries, so name what is still broken.

---

## Step 5.6 — Play Mode Smoke Test (NON-SKIPPABLE)

> **Lesson:** compiling and passing tests does not guarantee runtime behavior. In the TapToStartView.cs case the wrong state condition was written (Idle instead of TapToStart) — the compiler said nothing, the reviewer missed it, and Play mode would have shown it in ten seconds. It cost three fix cycles.

**This step always waits for manual approval from the user. A successful compile or a passing test cannot stand in for it.**

Show the user this message:

```
⚠️  Play Mode Smoke Test — Manual Step

Please check the following in Unity:
  1. Play moduna gir
  2. [INSERT HERE: 1-2 sentences showing whether the original bug reproduces — derive from the root cause]
  3. Any errors or unexpected behavior in the Console?

Result:
  ok    — devam et
  fail  — describe the problem and we will fix it
```

Wait for `ok` or `fail`. On `fail` → spawn unity-coder with the reported issue, then repeat from Step 5.5 and Step 5.6.

---

## Step 5.7 — Silent Failure Audit

Spawn a **silent-failure-hunter** subagent with this prompt:

```
Audit the following C# files for silent failure patterns:

FILES: [INSERT HERE: the list of files modified by the Coder agent]

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

If hunter reports **CLEAN** → proceed to Committer.

If hunter reports findings → show **QUALITY_GATE**.

Show the QUALITY_GATE block from `.claude/docs/director-gates.md`, passing the hunter's findings as the CHANGES NEEDED items. Then:

- `fix` → spawn **unity-coder** with all findings as a fix list, then re-run the hunter **exactly once** — no further re-audit. Proceed to committer regardless of that second result.
- `skip` → proceed to committer.
- `stop` → abort.

> The one-re-audit cap is caller-specific and deliberately **not** part of the QUALITY_GATE definition, which describes only the human decision surface. Do not delete it as redundant.

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: bug description, all changed files, reviewer verdict, verifier verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 6 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Bug fixed: [the bug description]
- Root cause: [one sentence root cause]
- Files changed: [list of modified files]
- Run: `git status`, `git diff`
- Stage only files related to this fix
- Commit message format: `"fix: <short description in English>"`
- One commit; do NOT push
- Report: commit hash and message

---

## Completion

Run: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"`

Invoke the **learner** skill to capture debugging insights from this session — extract non-obvious root causes, codebase-specific patterns, and hard-won fixes into `.claude/skills/learned/` and append to CLAUDE.md's `## Project Learnings` section.

If `claude-md-management:revise-claude-md` is available → invoke it to update CLAUDE.md with any architectural decisions or constraints discovered during this fix session.

Print:
```
## ✓ Fixed
Bug: [description]
Root cause: [one sentence]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
