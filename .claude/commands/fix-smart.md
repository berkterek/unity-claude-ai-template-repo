# /fix-smart — Codex-First Fix Pipeline

**Pipeline:** Context Package → Codex (autonomous) → Claude Review → [Codex Revision Loop]

## Usage

```
/fix-smart <bug description>
```

If no argument is given, ask: "Describe the bug. Include any error messages, stack traces, and what /fix or /fix-deep already tried."

## When to use

| Command | Use when |
|---------|----------|
| `/fix` | Stack trace is clear, root cause is obvious |
| `/fix-deep` | Logic bug, NullRef with unclear source, "sometimes happens" |
| `/fix-smart` | `/fix` and `/fix-deep` failed, or root cause is completely unclear — Codex reads code fresh without prior hypotheses |

---

## Step 0 — Plugin Preflight

Check that `codex:codex-rescue` skill is available. If not, stop and tell the user to run `/codex:setup`.

---

## Step 1 — Context Package

Before handing off to Codex, gather all relevant information from the current session and codebase. This package is critical — Codex works best with precise context.

Build the following:

**A. Bug Description**
- The exact error message or symptom the user reported
- Stack trace if available (read from MCP console or user paste)
- When it occurs (always / sometimes / specific conditions)

**B. Files Implicated**
- Files mentioned by the user or visible in the stack trace
- Any files you can identify as relevant by reading the error

**C. What Has Already Been Tried**
- If this is an escalation from `/fix` or `/fix-deep`, summarize the fix attempts and why they failed
- If this is a fresh `/fix-smart`, note "no prior attempts"

**D. Architecture Constraints (always include these)**
Inject a compact rules summary into the Codex prompt so it writes compliant code:

```
PROJECT RULES (non-negotiable):
- Dependency injection: VContainer only. No singletons, no FindObjectOfType, no static mutable state.
- Async: UniTask only. No coroutines, no async Task.
- Input: New Input System only. No Input.GetKey / Input.GetAxis.
- Events: IEventBus for cross-module. C# event for intra-module. UnityEvent forbidden.
- MonoBehaviour components: assigned via [SerializeField] in Inspector, not GetComponent in Awake.
- Sealed classes by default.
- No LINQ in gameplay code.
- Unity null check: use == null, not is null or ?. on UnityEngine.Object types.
```

---

## Step 2 — Codex Autonomous Fix

Invoke `codex:codex-rescue` with the full context package from Step 1. Structure the prompt as:

```
BUG: <exact error or symptom>
FILES: <implicated files>
PRIOR ATTEMPTS: <what failed and why, or "none">
STACK TRACE: <if available>

<Architecture Constraints block from Step 1D>

Task: Analyze the root cause, fix it, and verify the fix. Do not plan first — read the code directly and trace the actual issue. Fix at root cause, not at symptom.
```

Codex runs fully autonomously — analysis, fix, and verification. Do not interrupt.

---

## Step 3 — Claude Architecture Review

When Codex returns its output, review every changed file against the project rules.

**Review checklist:**

| Category | What to check |
|----------|--------------|
| VContainer | No `new ConcreteService()`, no singletons, no `FindObjectOfType`, no static mutable state |
| UniTask | No `IEnumerator`, no `StartCoroutine`, no `async Task` |
| Input | No `Input.GetKey`, `Input.GetAxis`, `Input.GetButton` |
| Events | No `UnityEvent` fields, no `using UnityEngine.Events` |
| Null checks | No `is null` or `?.` on UnityEngine.Object types |
| Encapsulation | No unnecessary public fields |
| Architecture direction | No `_Framework` → `_GameFolders` references |

**If review passes → done.** Summarize what Codex found and fixed. Output cleanly.

**If violations found → go to Step 4.**

---

## Step 4 — Codex Revision Loop (max 3 iterations)

Do NOT fix the violations yourself. Send Codex back with a targeted correction prompt:

```
The fix introduced architecture violations. Please revise:

VIOLATIONS:
- [list each violation with file + line + rule it breaks]
- [explain why it needs to change, not just that it's wrong]

Example: "AudioService.cs:42 — new AudioService() creates a concrete instance. 
This class is registered in AppScope via VContainer. Inject IAudioService via constructor instead."

Revise only the violations above. Keep the rest of the fix intact.
```

After revision, return to Step 3.

**If 3 iterations fail to produce clean code:** Stop, report to user with the violations list and a recommendation to manually adjust the specific lines.

---

## Output Format

On success:
```
ROOT CAUSE: <one sentence — what was actually wrong>
FIX: <what Codex changed and why>
REVIEW: Passed — no architecture violations
```

On loop exhaustion:
```
ROOT CAUSE: <what Codex identified>
FIX APPLIED: <what was changed>
REMAINING VIOLATIONS: <list with file:line>
NEXT STEP: Manually adjust the listed lines per architecture rules
```
