---
name: grill-me
description: Standalone design stress-tester — asks one pointed question at a time about a plan or decision, offers a recommended answer, and resolves every branch of the decision tree. Use before implementing anything architecturally significant.
model-tier: heavy
---

# Grill Me — Design Stress-Test

Conduct a relentless interview about a plan, design decision, or architectural choice until every ambiguous branch is resolved.

## Difference from deep-interview

| | deep-interview | grill-me |
|---|---|---|
| **When** | Before implementation — fills missing requirements | Before committing to a design — challenges an existing plan |
| **Input** | Vague feature request | A stated plan or decision |
| **Output** | Requirements Summary | Decision Record |
| **Style** | Score-gated, 5 dimensions | Priority-ordered categories, one question per turn |

## When to Use

- You have a plan and want to find holes before writing code
- You're about to make an architectural decision (new module, new pattern, DI wiring)
- You want to stress-test a GDD, TDD, or WORKFLOW phase
- You suspect a decision will cause problems later but can't articulate why

## Protocol

1. **Read the plan** — if a file path is given, read it first; if text is given inline, use that; if nothing is given, ask: "What plan or decision should I stress-test?"
2. **Identify branches** — internally map every assumption and implicit dependency; do not show this list to the user
3. **Ask one question at a time** — do not dump the list; ask sequentially
4. **Offer a recommended answer** — for each question, suggest what you'd choose and why
5. **Explore the codebase** when a question can be answered by reading existing code — do so before asking the user
6. **Record decisions** — keep a running list of resolved branches
7. **Continue until all branches resolved** or user calls `/done`

## Question Priorities

Ask in this order — stop when user calls `/done`:

1. **Scope** — What does this touch? What does it explicitly NOT touch?
2. **Dependencies** — What must exist before this can work?
3. **Conflicts** — Does this contradict an existing system, pattern, or rule?
4. **Failure modes** — What breaks if an assumption is wrong?
5. **Reversibility** — How hard is this to undo? Is there a safer incremental path?
6. **Unity-specific risks** — lifecycle order, VContainer scope, ECS structural change, Addressables handle release, async cancellation, serialization safety (FormerlySerializedAs), Unity null semantics

## Question Format

```
Q[N]: [The question — concrete, not generic]

My recommendation: [what you'd choose and the one-sentence reason]

(or type /done to finish)
```

## Output on /done

Produce a **Decision Record**:

```
## Decision Record

**Subject:** [what was grilled]

**Resolved Decisions:**
- [decision 1]: [chosen answer + rationale]
- [decision 2]: [chosen answer + rationale]

**Open Questions (user deferred):**
- [any questions the user skipped or left open]

**Risks Identified:**
- [risk 1] — [mitigation]

**Recommended next command:** /implement | /create-plan | /architect | /adr
```

## Rules

- One question per message — never batch questions
- Always offer your own recommendation — do not just ask open-ended questions
- Read the codebase before asking a question that the code can answer
- Never ask about things already explicit in the plan
- Stop asking when the user says `/done`, "that's enough", or "let's proceed"
