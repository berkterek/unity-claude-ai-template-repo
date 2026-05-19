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
| 0.0–0.19 | **Trivial** | Single file, stack trace points to exact line, NullRef/missing ref/typo | → **route to fix-lite** |
| 0.2–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Spawn Coder directly — skip Debugger and Test Writer |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Full pipeline: Test Writer → Coder → Reviewer → Committer |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Full pipeline + unity-developer reviewer (always active in `full` mode, or when score ≥ 0.7 in `lean` mode) |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Pipeline: [which variant]
```

**Trivial routing (score < 0.2):** Stop the /fix pipeline and show:
```
Complexity: [score] — Trivial (single file, clear stack trace)
→ This fix is /fix-lite scope. Route to fix-lite? (go / full-fix)
```
- `go` → run /fix-lite pipeline (SCOPE_GATE skipped)
- `full-fix` → continue normal /fix pipeline with SCOPE_GATE below

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: bug description, complexity score.
Wait for `go` before spawning any agents.

After receiving `go` → run:
```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"fix","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
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
$BUG_DESCRIPTION

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

BUG: $BUG_DESCRIPTION

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

If the number of affected files in `$DEBUGGER_AFFECTED_FILES` is **more than 3**: fire **BREAKING_GATE** (see `.claude/docs/director-gates.md`) before proceeding to the Test Writer. Show the full affected file list and wait for `go` or `stop`.

---

## Step 2 — Find Existing Test File

For each file in `$DEBUGGER_AFFECTED_FILES`, check if a corresponding test file already exists:

```bash
find . -name "[ClassName]Tests.cs" -path "*/Tests/*"
```

**If test file found** → note the path; Test Writer adds a regression test case to that file. Skip the router entirely.

**If no test file exists** → run `.claude/skills/core/test-type-router.md` once to decide where the new test goes. Emit the decision block, then proceed.

- **NoTest** → skip Step 3 (Test Writer); proceed directly to Step 4 (Coder)
- All other decisions → Test Writer creates the file in the correct assembly

---

## Step 3 — Test Writer

Spawn Agent with `subagent_type: "claude"` with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Bug
$BUG_DESCRIPTION

## Root Cause
$DEBUGGER_ROOT_CAUSE

## Affected Files
$DEBUGGER_AFFECTED_FILES

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

**Agent routing — decide before spawning:**

| Target location | Agent |
|-----------------|-------|
| `_Framework/`, `Abstracts/`, `Concretes/` (no Unity API) | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** |

Spawn the appropriate subagent with this prompt:

```
You are a senior C# Unity developer. Fix the following bug.

## Bug
$BUG_DESCRIPTION

## Root Cause (already investigated)
$DEBUGGER_ROOT_CAUSE

## Files to Change
$DEBUGGER_AFFECTED_FILES

## Regression Test (make this pass)
$TEST_WRITER_OUTPUT

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/
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

## Step 4.5 — Unity Validator (MANDATORY — runs before Reviewer)

Spawn a **unity-verifier** subagent with this prompt:

```
You are a Unity build validator. Your only job is to verify that the project compiles and all tests pass.

## What Was Fixed
$BUG_DESCRIPTION

## Files Changed
$CODER_OUTPUT

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
Bug: $BUG_DESCRIPTION
Root Cause: $DEBUGGER_ROOT_CAUSE

## Failures (fix ALL of these)
$VALIDATOR_OUTPUT

## Rules
- Fix only what is listed — do not refactor anything else
- For assembly definition issues: check that the test assembly references the correct game assembly and has NSubstitute in precompiledReferences with overrideReferences: true
- For compile errors: fix the exact file:line reported
- For test failures: fix the implementation, never change the test

## When Done
List every file you changed. Report: DONE or BLOCKED.
```

After unity-coder fixes → re-run the **Unity Validator** on the updated files.

If still failing after **2 fix passes** → stop and show the user all errors. Ask:
- `skip` → proceed to reviewer anyway (user accepts responsibility)
- `stop` → abort

---

## Step 5 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

```
Review this bug fix.

## Bug
$BUG_DESCRIPTION

## Root Cause
$DEBUGGER_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

## Review Criteria
1. Regression test passes — the pre-written test now passes; test file was not modified
2. Does the fix actually address the root cause (not just the symptom)?
3. Does the fix introduce any new bugs or regressions?
4. Architecture — VContainer DI, no singletons, interfaces only across modules
5. Performance — no allocations in Update/FixedUpdate
6. UniTask — no async void, CancellationToken on every async method
7. Unity null safety — no ?. or is null on UnityEngine objects

## Output Format
APPROVED — fix is correct, no issues.

CHANGES NEEDED:
- [file:line] Issue and fix.
```

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **unity-coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Original Bug Fix Context
   Bug: $BUG_DESCRIPTION
   Root Cause: $DEBUGGER_ROOT_CAUSE

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After unity-coder fixes → re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 4.5.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to verifier (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 5.5 — Unity Verifier (Final Bounded Check)

Spawn a **unity-verifier** subagent once with this prompt (max 3 internal iterations):

```
You are a Unity post-fix verifier. Perform a final bounded check on the delivered bug fix.

## Bug Fixed
$BUG_DESCRIPTION

## Root Cause
$DEBUGGER_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

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

If unity-verifier reports **VERIFY FAILED** → stop and show the user all remaining issues. Ask:
- `skip` → proceed to commit (user accepts responsibility)
- `stop` → abort

---

## Step 5.7 — Silent Failure Audit

Spawn a **silent-failure-hunter** subagent with this prompt:

```
Audit the following C# files for silent failure patterns:

FILES: $CHANGED_FILES

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

If hunter reports findings → show them to the user. Ask:
```
Silent failure issues found. Options:
  fix   — spawn unity-coder to address findings, then re-audit once
  skip  — accept and proceed to commit
  stop  — abort
```

- `fix` → spawn **unity-coder** with all findings as a fix list, then re-run hunter once. Proceed to committer regardless of result.
- `skip` → proceed to committer.
- `stop` → abort.

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: bug description, all changed files, reviewer verdict, verifier verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 6 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Bug fixed: `$BUG_DESCRIPTION`
- Root cause: `$DEBUGGER_ROOT_CAUSE`
- Files changed: `$CODER_OUTPUT`
- Run: `git status`, `git diff`
- Stage only files related to this fix
- Commit message format: `"fix: <short description in English>"`
- One commit; do NOT push
- Report: commit hash and message

---

## Completion

Run: `rm -f .claude/state/gate-cleared`

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
