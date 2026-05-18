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

## Step 0 — Plugin Preflight

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:systematic-debugging` | Step 1 — root cause hypothesis (complexity ≥ 0.4) | Proceed with unity-fixer hypothesis directly |

Print availability status before proceeding:
```
Plugins: superpowers:systematic-debugging [✓/✗]
```

---

## Step 0b — Complexity Scoring

Score the bug complexity on a 0.0–1.0 scale before spawning any agents:

| Score | Label | Signals |
|-------|-------|---------|
| 0.0–0.3 | **Simple** | Single class, isolated method, no cross-system trace |
| 0.4–0.6 | **Medium** | 2–4 classes, event flow involved, DI wiring suspect |
| 0.7–1.0 | **Complex** | Cross-module, ECS + Mono bridge, race condition, Addressables lifecycle |

**Scoring signals:**
- Bug spans multiple modules or systems? +0.3
- Involves IEventBus events or DI wiring? +0.2
- Involves ECS, Addressables, or async lifecycle? +0.3
- Single method, single class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
```

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: bug description, complexity score.
Wait for `go` before proceeding to log intake or spawning any agents.

After receiving `go` → run:
```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"fix-deep","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
```

---

## Step 0b — Log Intake

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
1. Use `mcp__unityMCP__read_console` with type "Error" — collect all errors.
2. Use `mcp__unityMCP__read_console` with type "Warning" — collect relevant warnings.
3. Use `mcp__unityMCP__read_console` with type "Log" — collect any logs related to the bug.
4. Read `mcpforunity://editor/state` to confirm the editor is in a state relevant to the bug.

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

**If `superpowers:systematic-debugging` is available AND complexity score ≥ 0.4:** Invoke `superpowers:systematic-debugging` first to structure the root cause hypothesis. Pass the bug description and log evidence. Use its output (hypothesis + confidence + injection plan) to enrich the unity-fixer prompt below.

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

**If complexity score ≥ 0.4:** Spawn **unity-fixer** (MCP log collection) and **unity-scout** (static risk scan) simultaneously. Both complete before proceeding to Step 4.

**If complexity score < 0.4:** Spawn unity-fixer only.

Then spawn a **unity-fixer** subagent with this prompt:

```
You are a Unity evidence reader. Collect the debug output from the injected logs.

## Hypothesis Being Tested
$HYPOTHESIS

## Expected Log Markers
All injected logs start with "[FIX-DEEP]"

## Instructions
1. Use `mcp__unityMCP__read_console` with type "Log" — collect ALL "[FIX-DEEP]" prefixed lines.
2. Use `mcp__unityMCP__read_console` with type "Error" — collect any errors that appeared.
3. Report verbatim — do not interpret yet.

## Output Format
EVIDENCE LOGS:
[every [FIX-DEEP] log line verbatim, in order]

ERRORS DURING REPRODUCTION:
[any error lines]

NO_EVIDENCE — if no [FIX-DEEP] logs appeared (bug was not reproduced).
```

### unity-scout Agent Prompt (complexity ≥ 0.4 only, runs in parallel with unity-fixer)

```
You are a Unity risk analyst. While evidence logs are being collected, scan the codebase for Unity-specific patterns related to this bug hypothesis.

HYPOTHESIS: $HYPOTHESIS

## Instructions

Scan for patterns that could confirm or refute the hypothesis:
- VContainer registration and scope hierarchy
- UniTask cancellation and lifecycle
- ECS structural change patterns
- Input System Enable/Disable lifecycle
- Addressables handle management
- Unity null semantics (?. vs == null)

## Output Format (REQUIRED)

STATIC_EVIDENCE:
- [file:line] — [how this supports or refutes the hypothesis]
OR: STATIC_EVIDENCE: none
```

After both agents complete, append unity-scout findings to the evidence:
```
EVIDENCE LOGS: [from unity-fixer]
STATIC_EVIDENCE: [from unity-scout]
```
Pass both to Step 4 — Evidence Gate.

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

**PROVEN** → if the number of files in `$AFFECTED_FILES` is **more than 3**: fire **BREAKING_GATE** (see `.claude/docs/director-gates.md`) before proceeding. Show the full affected file list and wait for `go` or `stop`. Then proceed to Step 5 (Fix).

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

Spawn a **unity-verifier** subagent:

```
You are a Unity build validator.

## What Was Fixed
$BUG_DESCRIPTION — $CONFIRMED_ROOT_CAUSE

## Files Changed
$CODER_OUTPUT

## Instructions
1. Use `mcp__unityMCP__refresh_unity` to trigger recompile.
2. Wait until `isCompiling` is false.
3. Use `mcp__unityMCP__read_console` with type "Error" — check for compile errors.
4. If compile errors → report COMPILE FAILED.
5. If clean → use `mcp__unityMCP__run_tests` to run Edit Mode tests.
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

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

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

## Step 6.7 — Silent Failure Audit

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
Pass: bug description, all changed files (with [FIX-DEEP] logs removed), reviewer verdict, verifier verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 7 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Bug fixed: `$BUG_DESCRIPTION`
- Proven root cause: `$CONFIRMED_ROOT_CAUSE`
- Files changed: `$CODER_OUTPUT`
- Run: `git status`, `git diff`
- Stage only files related to this fix
- Commit message format: `"fix(proven): <short description in English>"`
  Note: `proven` scope signals this fix was evidence-verified, not speculative
- One commit; do NOT push
- Report: commit hash and message

---

## Completion

Run: `rm -f .claude/state/gate-cleared`

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
