# /search Command Design

**Date:** 2026-05-08  
**Status:** Approved

---

## Purpose

A research pipeline that investigates any query (bug, architectural question, codebase exploration) using multiple agents, then validates findings with a reviewer before presenting results to the user.

---

## Usage

```
/search <query>
/search "AudioService not injecting"
/search "EnemyMoveSystem sometimes not working"
/search "how is event bus used in this project"
```

---

## Pipeline

```
/search <query>
    ↓
[Phase 1] Research
    - Explore agent      → codebase scan, file reading, pattern analysis
    - unity-scout agent  → Unity-specific risks, lifecycle, ECS, DI issues
    - Web search         → Unity docs, known bugs (optional, based on query)
    → Output: ROOT_CAUSE + PROPOSED_SOLUTION

    ↓
[Phase 2] Review
    - unity-reviewer agent
    → Questions: Is the root cause correct? Is the solution consistent with architecture rules?
    → APPROVED or MISMATCH verdict + rationale

    ↓ MISMATCH (max 5 iterations)
    → Back to Research, with reviewer feedback added to prompt

    ↓ APPROVED
[Phase 3] Present to User
    PROBLEM:     [what was found, which file/line]
    SOLUTION:    [what should be done]
    CONFIDENCE:  [APPROVED - iteration N]
    NEXT:        [recommended command: /fix, /fix-deep, /implement]
```

---

## Iteration Loop

- Each iteration, the research agent receives the previous reviewer feedback.
- It broadens or deepens the investigation scope.
- **Still MISMATCH at iteration 5** → pipeline stops:
  ```
  INCONCLUSIVE: No definitive result found after 5 iterations.
  BEST_GUESS: [latest research findings in raw form]
  REVIEWER_CONCERN: [unresolved reviewer objection]
  ```

---

## Research Agent Prompt Template

```
You are a research agent investigating the following query in a Unity project.

QUERY: $QUERY
ITERATION: $N / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK  (empty on first iteration)

## Instructions

1. Use Explore agent to scan the codebase for relevant files, patterns, and dependencies.
2. Use unity-scout to identify Unity-specific risks (lifecycle, VContainer, ECS, UniTask, Input).
3. If the query involves a known Unity API, package, or error pattern — use web search for Unity docs or known issues.

## Output Format (REQUIRED)

ROOT_CAUSE: [one sentence — what is the actual problem or answer]
EVIDENCE:
  - [file:line or pattern that supports the root cause]
  - [...]
PROPOSED_SOLUTION: [concrete steps to fix or address]
CONFIDENCE: low | medium | high
```

---

## Reviewer Agent Prompt Template

```
You are a code reviewer validating a research finding in a Unity project.

ORIGINAL_QUERY: $QUERY
ROOT_CAUSE: $ROOT_CAUSE
EVIDENCE: $EVIDENCE
PROPOSED_SOLUTION: $PROPOSED_SOLUTION

## Your Job

1. Is ROOT_CAUSE plausible given the EVIDENCE? Does the evidence actually support the claim?
2. Is PROPOSED_SOLUTION consistent with the project's architecture rules?
   - No singletons, no coroutines, no legacy Input, VContainer DI, UniTask async, IEventBus for cross-module comms
3. Does PROPOSED_SOLUTION fully address ROOT_CAUSE, or does it only fix a symptom?

## Output Format (REQUIRED)

VERDICT: APPROVED | MISMATCH
REASON: [one sentence explaining the verdict]
FEEDBACK_FOR_RESEARCH: [if MISMATCH — specific gap or contradiction the research agent must address next iteration]
```

---

## Final Presentation Format (APPROVED)

```
SEARCH COMPLETE ✓ (approved in N iteration(s))

PROBLEM
  [root cause — one clear sentence]
  Files: [relevant file paths]

SOLUTION
  [concrete steps]

NEXT STEPS
  → /fix <description>          (if it's a bug with clear root cause)
  → /fix-deep <description>     (if it's a complex or intermittent bug)
  → /implement <description>    (if it's a missing feature or refactor)
  → no action needed            (if it was a pure exploration query)
```

---

## Constraints

- Web search is only used when the query involves a Unity API, package version, or error message that benefits from external docs.
- Research agent never modifies files — read-only.
- Reviewer agent never modifies files — evaluation only.
- Pipeline never auto-fixes — it stops at APPROVED and lets the user decide the next step.
