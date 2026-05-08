# /search — Research → Review → Present Pipeline

Investigates a query, produces a root cause + solution, validates with the reviewer chain (unity-reviewer → Codex → reviewer), and presents the result to the user.

## Usage

```
/search <query>
/search "AudioService not injecting"
/search "EnemyMoveSystem sometimes stops working"
/search "how is the event bus used in this project"
```

If no argument is given, ask: "What should I investigate?"

---

## Pipeline

```
[Step 0] Complexity Score → [Phase 1] Research → [Phase 2] Review ⟲ (max 5 iter) → [Phase 3] Present
```

---

## Step 0 — Complexity Scoring

Score the query complexity on a 0.0–1.0 scale before spawning any agents:

| Score | Label | Signals |
|-------|-------|---------|
| 0.0–0.3 | **Simple** | Single class lookup, "how does X work", no cross-system trace needed |
| 0.4–0.6 | **Medium** | Multiple classes, event flow, DI wiring trace |
| 0.7–1.0 | **Complex** | Cross-module investigation, ECS + Mono bridge, Addressables lifecycle, race conditions |

**Scoring signals:**
- Query spans multiple modules or systems? +0.3
- Query involves event flow or DI wiring? +0.2
- Query involves ECS, Addressables, or async lifecycle? +0.3
- Simple "where is X defined" or "how does X work" lookup? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
```

---

## Phase 1 — Research

**If complexity score ≥ 0.4 (Medium/Complex):** Spawn **Explore** and **unity-scout** simultaneously. Proceed once both complete.

**If complexity score < 0.4 (Simple):** Spawn Explore only — skip unity-scout.

### Explore Agent Prompt

```
You are a research agent investigating a query in a Unity project.

QUERY: $QUERY
ITERATION: $ITERATION / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK

## Instructions

1. Search the codebase for files, classes, and patterns relevant to the query.
   - Use file reads, grep patterns, and directory listings.
   - Focus on: .claude/rules/, _Framework/, _GameFolders/Scripts/Games/
2. If the query mentions a Unity API, package name, or error message → use web search for Unity documentation or known issues.
3. If PREVIOUS_REVIEWER_FEEDBACK is not empty → specifically address the gap flagged. Don't repeat the same evidence.

## Output Format (REQUIRED)

CODEBASE_FINDINGS:
- [file path or pattern] — [how it supports the query]
- [...]

PROPOSED_SOLUTION:
[Concrete steps. Reference specific files and classes. No vague language.]

CONFIDENCE: low | medium | high
```

### unity-scout Agent Prompt (complexity ≥ 0.4 only)

```
You are a Unity risk analyst. Scan the project for Unity-specific issues related to the following query.

QUERY: $QUERY

## Instructions

Investigate for Unity-specific risks:
- VContainer registration gaps or missing .As<IInterface>() calls
- UniTask async methods missing CancellationToken
- Input System lifecycle violations (missing Enable/Disable in OnEnable/OnDisable)
- ECS structural changes outside EntityCommandBuffer
- Addressables handles not released in Dispose()
- Unity null check violations (?. or is null on UnityEngine objects)

## Output Format (REQUIRED)

UNITY_RISKS:
- [risk type] — [file:line] — [description]
OR: UNITY_RISKS: none
```

### Merge (after both agents complete)

Synthesize into unified research output:

```
COMBINED_ROOT_CAUSE: [one sentence — synthesize CODEBASE_FINDINGS + UNITY_RISKS]

EVIDENCE:
- [from CODEBASE_FINDINGS]
- [from UNITY_RISKS if any]

PROPOSED_SOLUTION: [from Explore, refined with any Unity risk findings]

CONFIDENCE: [take the lower of the two if they differ]
```

Capture as `$ROOT_CAUSE`, `$EVIDENCE`, `$PROPOSED_SOLUTION`, `$CONFIDENCE`.

---

## Phase 2 — Review Loop

**Iteration counter starts at 1. Max 5 iterations.**

**Reviewer priority:** First try **unity-reviewer** subagent. If unavailable → fall back to **Codex** (`codex:rescue`). If Codex is also unavailable → fall back to **reviewer** subagent.

Spawn the reviewer with this prompt:

```
You are a code reviewer validating a research finding in a Unity project.

ORIGINAL_QUERY: $QUERY
ROOT_CAUSE: $ROOT_CAUSE
EVIDENCE:
$EVIDENCE
PROPOSED_SOLUTION:
$PROPOSED_SOLUTION

## Your Job

1. Does the EVIDENCE actually support the ROOT_CAUSE?
   - Is it a real problem or just a suspicious pattern?
   - Are the referenced files/lines real and relevant?
2. Is the PROPOSED_SOLUTION consistent with this project's architecture?
   - No singletons (VContainer only)
   - No coroutines (UniTask only)
   - No legacy Input API (New Input System only)
   - No cross-module concrete dependencies (interfaces only)
   - No UnityEngine in service classes (Provider pattern)
   - IEventBus for cross-system communication
3. Does the PROPOSED_SOLUTION fully address the ROOT_CAUSE, or does it only treat a symptom?

## Output Format (REQUIRED — do not deviate)

VERDICT: APPROVED | MISMATCH

REASON: [one sentence]

FEEDBACK_FOR_RESEARCH: [if MISMATCH only — the specific gap or contradiction the research agent must address in the next iteration. Be precise: name the file, claim, or architecture rule that failed.]
```

### Loop Logic

**If VERDICT is MISMATCH and iteration < 5:**
- Increment iteration counter.
- Go back to Phase 1 with `$FEEDBACK = FEEDBACK_FOR_RESEARCH`.

**If VERDICT is MISMATCH and iteration == 5:**
- Skip to Phase 3 with `$STATUS = INCONCLUSIVE`.

**If VERDICT is APPROVED:**
- Set `$STATUS = APPROVED`.
- Proceed to Phase 3.

---

## Phase 3 — Present to User

### If STATUS == APPROVED

```
SEARCH COMPLETE ✓  (approved in $ITERATION iteration(s))

PROBLEM
  $ROOT_CAUSE
  Files: $EVIDENCE_FILES

SOLUTION
  $PROPOSED_SOLUTION

NEXT STEPS
  [see routing table below]
```

Append the appropriate next step based on the query type:

| Query type | Next step |
|------------|-----------|
| Clear bug with stack trace | `→ /fix <root cause summary>` |
| Logic bug, race condition, intermittent | `→ /fix-deep <root cause summary>` |
| Missing feature or architectural gap | `→ /implement <solution summary>` |
| Pure exploration (how does X work) | `→ no action needed` |

### If STATUS == INCONCLUSIVE

```
SEARCH INCONCLUSIVE — no definitive result after 5 iterations.

BEST GUESS (not reviewer-approved)
  ROOT_CAUSE: $LAST_ROOT_CAUSE
  PROPOSED_SOLUTION: $LAST_PROPOSED_SOLUTION

REVIEWER CONCERN (unresolved)
  $LAST_FEEDBACK_FOR_RESEARCH

SUGGESTION
  More evidence needed. Options:
  → /fix-deep <description>   (let the evidence-first pipeline investigate)
  → /debug-session            (structured manual investigation)
```

$ARGUMENTS
