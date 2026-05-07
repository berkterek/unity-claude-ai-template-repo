# /fix-deep — Evidence-First Bug Fix Pipeline

Fixes a logic bug by **proving it before touching code**. Never guesses. Never speculates. If the root cause cannot be proven with logs, it stops and asks for more evidence.

## Usage

```
/fix-deep <bug description>
/fix-deep <bug description> --log <path/to/logfile.txt>
/fix-deep <bug description> --log-text "<pasted log content>"
```

If no argument is given, ask: "Describe the bug. Paste any logs or error text if you have them."

## When to use vs /fix

| Command | Use when |
|---------|----------|
| `/fix` | Stack trace is clear, root cause is obvious |
| `/fix-deep` | Logic bug, NullRef with no clear source, race condition, wrong value at runtime, "sometimes happens" bugs |

---

## Step 0 — Log Intake

Determine the evidence source. In order of preference:

### A — User provided log file
If `--log <path>` was given → read the file.

### B — User provided log text
If `--log-text "<text>"` was given → use it directly.

### C — MCP console collection (automatic fallback)
If no log was provided → spawn a **unity-fixer** subagent with this prompt:

```
You are a Unity log collector. Do NOT fix anything. Only collect evidence.

## Bug
$BUG_DESCRIPTION

## Instructions
1. Use `mcp__UnityMCP__read_console` with type "Error" — collect all errors.
2. Use `mcp__UnityMCP__read_console` with type "Warning" — collect relevant warnings.
3. Use `mcp__UnityMCP__read_console` with type "Log" — collect any logs related to the bug.
4. Use `mcp__UnityMCP__editor_state` to confirm the editor is in a state relevant to the bug.

## Output Format
LOGS COLLECTED:
[paste all collected log lines verbatim]

EDITOR STATE:
[isPlaying, isCompiling, activeScene, etc.]

NO_LOGS_FOUND — if console is clean and no related output exists.
```

If **NO_LOGS_FOUND** → print:

```
⚠ No logs found in Unity console.
To proceed, either:
1. Reproduce the bug in the editor so logs appear, then run /fix-deep again
2. Paste your log with: /fix-deep <description> --log-text "<your log here>"
3. Continue without logs (hypothesis mode — less reliable): type "proceed"
```

Wait for user input. If "proceed" → continue with empty evidence, clearly marked as hypothesis-only.

---

## Step 1 — Hypothesis Formation

Spawn a **unity-fixer** subagent with this prompt:

```
You are a senior Unity engineer doing root cause analysis. You have log evidence. Do NOT write any fix yet.

## Bug
$BUG_DESCRIPTION

## Log Evidence
$LOG_EVIDENCE

## Project Context
- Read .claude/CLAUDE.md for architecture overview
- VContainer DI, UniTask async, IEventBus for events

## Your Task
1. Read the relevant source files — follow the call chain from the log evidence.
2. Form a hypothesis: what is the most likely root cause?
3. Identify exactly which lines/conditions need to be proven.
4. List the specific code locations where debug logs must be injected to confirm or deny your hypothesis.

## Output Format
HYPOTHESIS:
<one sentence — the suspected root cause>

CONFIDENCE: <LOW | MEDIUM | HIGH>
Reason: <why this confidence level>

FILES READ:
- <file path> — <what you found>

DEBUG INJECTION PLAN:
- <file:line> — <what log to add and what it will prove>
(list every injection point needed to confirm the hypothesis)

DO NOT fix anything. Report only.
```

Print the hypothesis to the user.

---

## Step 2 — Debug Injection

Spawn a **unity-coder** subagent with this prompt:

```
You are a Unity developer adding temporary diagnostic logs. Do NOT fix any logic. Only add Debug.Log statements.

## Bug
$BUG_DESCRIPTION

## Hypothesis to Prove
$HYPOTHESIS

## Injection Plan
$DEBUG_INJECTION_PLAN

## Rules
- Add `Debug.Log("[FIX-DEEP] <context>: " + value)` at every injection point
- Use the "[FIX-DEEP]" prefix on ALL debug logs so they are easy to find and remove later
- Do NOT change any logic — only add log lines
- Do NOT fix anything you suspect is wrong — logs only

## When Done
List every file and line you added a log to.
Report: DONE or BLOCKED with reason.
```

---

## Step 3 — Evidence Collection (Post-Injection)

Print:
```
Debug logs injected. Now reproduce the bug in the Unity editor, then press Enter to read the evidence.
```

Wait for user confirmation (Enter / "done" / "ready").

Then spawn a **unity-fixer** subagent with this prompt:

```
You are a Unity evidence reader. Collect the debug output from the injected logs.

## Hypothesis Being Tested
$HYPOTHESIS

## Expected Log Markers
All injected logs start with "[FIX-DEEP]"

## Instructions
1. Use `mcp__UnityMCP__read_console` with type "Log" — collect ALL "[FIX-DEEP]" prefixed lines.
2. Use `mcp__UnityMCP__read_console` with type "Error" — collect any errors that appeared.
3. Report verbatim — do not interpret yet.

## Output Format
EVIDENCE LOGS:
[every [FIX-DEEP] log line verbatim, in order]

ERRORS DURING REPRODUCTION:
[any error lines]

NO_EVIDENCE — if no [FIX-DEEP] logs appeared (bug was not reproduced).
```

If **NO_EVIDENCE** → print:
```
⚠ No debug logs appeared. The bug was not reproduced during this session.
Options:
1. Reproduce the bug in the editor and type "retry"
2. Describe what you did in the editor and type "manual: <description>"
3. Abort: type "stop"
```

Wait for user input.
- `retry` → repeat Step 3
- `manual: <description>` → continue with user's description as evidence
- `stop` → abort

---

## Step 4 — Evidence Gate (CRITICAL)

Spawn a **unity-fixer** subagent with this prompt:

```
You are a strict evidence evaluator. Decide if the hypothesis is proven.

## Hypothesis
$HYPOTHESIS

## Evidence Collected
$EVIDENCE_LOGS

## Task
1. Compare the evidence to the hypothesis.
2. Does the evidence PROVE the hypothesis? Be strict — "probably" is not proven.

## Output Format — choose exactly one:

PROVEN:
Evidence: <quote the specific log line(s) that prove it>
Root cause confirmed: <one sentence>

REFUTED:
Evidence shows: <what the logs actually indicate>
Revised hypothesis: <new hypothesis based on evidence>
New injection needed: <yes/no — if yes, list new injection points>

INCONCLUSIVE:
Missing evidence: <what specific log output would prove or refute>
Suggested action: <what the developer should do next in the editor>
```

### Gate Decision

**PROVEN** → proceed to Step 5 (Fix).

**REFUTED** → print the revised hypothesis. Ask:
- `retry` → go back to Step 2 with the revised hypothesis (max 2 revision cycles)
- `stop` → abort, remove debug logs

**INCONCLUSIVE** → print:
```
⚠ Cannot confirm root cause — more evidence needed.

Missing: $MISSING_EVIDENCE
Suggested action: $SUGGESTED_ACTION

Options:
1. Follow the suggested action in the editor, then type "retry"
2. Provide additional log: /fix-deep <description> --log-text "<new log>"
3. Abort: type "stop"
4. Override (proceed without full proof — your responsibility): type "force"
```

Wait for user input. `force` → proceed to Step 5 with a warning prefixed to the commit message.

If still **INCONCLUSIVE** after 2 retry cycles → stop:
```
⛔ Root cause could not be proven after multiple attempts.
This bug requires more investigation before a safe fix can be applied.
Recommendation: add persistent logging to production/staging and reproduce with real data.
Debug logs have been left in place for your review — remove them manually or run /fix-deep cleanup.
```

---

## Step 5 — Fix

**Agent routing — decide before spawning:**

| Target location | Agent |
|-----------------|-------|
| `_Framework/`, `Abstracts/`, `Concretes/` (no Unity API) | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** |

Spawn the appropriate subagent with this prompt:

```
You are a senior C# Unity developer. Fix a confirmed bug.

## Bug
$BUG_DESCRIPTION

## Proven Root Cause
$CONFIRMED_ROOT_CAUSE

## Evidence
$EVIDENCE_LOGS

## Files to Change
$AFFECTED_FILES

## Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/
- Fix ONLY the proven root cause — do not refactor surrounding code
- Remove ALL "[FIX-DEEP]" debug log lines as part of this fix
- No singletons — VContainer only
- No coroutines — UniTask only

## When Done
List every file you modified with a one-line summary.
Confirm all [FIX-DEEP] debug logs have been removed.
Report: DONE or BLOCKED with reason.
```

---

## Step 5.5 — Unity Validator

Spawn a **reviewer** subagent (always — never Codex, because Codex has no Unity MCP access):

```
You are a Unity build validator.

## What Was Fixed
$BUG_DESCRIPTION — $CONFIRMED_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

## Instructions
1. Use `mcp__UnityMCP__refresh_unity` to trigger recompile.
2. Wait until `isCompiling` is false.
3. Use `mcp__UnityMCP__read_console` with type "Error" — check for compile errors.
4. If compile errors → report COMPILE FAILED.
5. If clean → use `mcp__UnityMCP__run_tests` to run Edit Mode tests.
6. If any tests fail → report TEST FAILED.
7. If all pass → report VALIDATED.
8. Also verify: no "[FIX-DEEP]" strings remain in any modified file.

## Output Format
VALIDATED — zero compile errors, all tests pass, no debug logs remaining.

COMPILE FAILED:
- [error] — [file:line]

TEST FAILED:
- [test name] — [failure]

DEBUG_LOGS_REMAINING:
- [file:line] — [log content]
```

Validator loop: same as `/fix` — max 2 fix passes before stopping and asking user.

---

## Step 6 — Reviewer

First try **unity-reviewer**. If unavailable → **Codex** (`codex:rescue`). If unavailable → **reviewer**.

```
Review this evidence-proven bug fix.

## Bug
$BUG_DESCRIPTION

## Proven Root Cause
$CONFIRMED_ROOT_CAUSE

## Evidence That Proved It
$EVIDENCE_LOGS

## Files Changed
$CODER_OUTPUT

## Review Criteria
1. Fix addresses the proven root cause — not a broader change
2. No [FIX-DEEP] debug logs remain
3. No new bugs introduced
4. Architecture — VContainer DI, no singletons, interfaces only across modules
5. UniTask — no async void, CancellationToken on every async method
6. Unity null safety — no ?. or is null on UnityEngine objects
7. Performance — no allocations in Update/FixedUpdate

## Output Format
APPROVED

CHANGES NEEDED:
- [file:line] Issue and fix.
```

Review loop: max 3 passes (same as `/fix`).

---

## Step 7 — Committer

Spawn a **committer** subagent:

```
You are a release engineer. Commit this evidence-proven bug fix.

## Bug Fixed
$BUG_DESCRIPTION

## Proven Root Cause
$CONFIRMED_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

## Rules
- Run: git status, git diff
- Stage only files related to this fix
- Commit message format: "fix(proven): <short description in English>"
  Note: "proven" scope signals this fix was evidence-verified, not speculative
- One commit
- Do NOT push
- Report: commit hash and message
```

---

## Completion

Invoke the **learner** skill to capture debugging insights.

Print:
```
## ✓ Fixed (Evidence-Proven)
Bug: [description]
Root cause: [one sentence]
Evidence: [the log line(s) that proved it]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

---

## Cleanup Command

If the user types `/fix-deep cleanup` → spawn a **unity-coder** subagent to find and remove any remaining `[FIX-DEEP]` debug logs across the entire project.

$ARGUMENTS
