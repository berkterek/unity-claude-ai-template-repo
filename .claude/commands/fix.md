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
[1] DEBUGGER → [2] TEST WRITER → [3] CODER → [4] REVIEWER ⟲ (loop until APPROVED) → [5] COMMITTER
```

---

## Step 1 — Debugger

Spawn a **debugger** subagent with this prompt:

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

Show the debugger output to the user. Ask: "Root cause found — proceed with fix? (yes / stop)"

If **stop** → abort.

---

## Step 2 — Test Writer

Spawn a **test-writer** subagent with this prompt:

```
You are a senior C# Unity test engineer. Write a failing regression test that reproduces this bug BEFORE any fix is applied.

## Bug
$BUG_DESCRIPTION

## Root Cause
$DEBUGGER_ROOT_CAUSE

## Affected Files
$DEBUGGER_AFFECTED_FILES

## Project Rules
- Read .claude/CLAUDE.md and .claude/rules/testing.md before writing any tests
- Use NSubstitute for mocking — only mock interfaces, never concrete classes
- Follow AAA pattern (Arrange / Act / Assert)
- Test method naming: MethodName_WhenCondition_ExpectedBehavior
- The test must FAIL right now — do not fix the bug

## Your Task
Write a test (or tests) that:
1. Directly reproduces the bug described above
2. Will PASS once the root cause is fixed
3. Will serve as a permanent regression guard

## When Done
List every test file you created with a summary of what each test covers.
Report: DONE or BLOCKED with reason.
```

If test writer reports **BLOCKED** → stop and show the blocker to the user.

---

## Step 3 — Coder

Spawn a **coder** subagent with this prompt:

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

## Step 4 — Reviewer

First try **Codex** (`codex:rescue` subagent):

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

If Codex unavailable → fall back to **reviewer** subagent.

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **coder** subagent to fix every listed issue:
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

2. After coder fixes → re-run the reviewer (Codex first, fall back to reviewer agent) with the updated files.

3. If APPROVED → proceed to Step 4.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 5 — Committer

Spawn a **committer** subagent with this prompt:

```
You are a release engineer. Commit this bug fix.

## Bug Fixed
$BUG_DESCRIPTION

## Root Cause
$DEBUGGER_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

## Rules
- Run: git status, git diff
- Stage only files related to this fix
- Commit message format: "fix: <short description in English>"
- One commit
- Do NOT push
- Report: commit hash and message
```

---

## Completion

Print:
```
## ✓ Fixed
Bug: [description]
Root cause: [one sentence]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
