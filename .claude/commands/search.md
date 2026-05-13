# /search — Research → Review → Present Pipeline

Investigates a query about the codebase, writes findings to a persistent file, validates completeness with a reviewer, presents the result to the user, then recommends the appropriate next action. Never executes any follow-up command automatically.

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
[Step 0] Complexity Score
    ↓
[Phase 1] Research → write .claude/state/search-findings.md
    ↓
[Phase 2] Reviewer reads file → COMPLETE / INCOMPLETE / REJECT
    ↓ (loop max 5 if INCOMPLETE)
[Phase 3] Present findings to user
    ↓
[Phase 4] Action Router → recommend next command
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

Print before proceeding:
```
Complexity: [score] — [Label]
Rationale: [one sentence]
```

---

## Phase 1 — Research

**If complexity ≥ 0.4 (Medium/Complex):** Spawn **Explore** and **unity-scout** simultaneously. Wait for both to complete, then merge.

**If complexity < 0.4 (Simple):** Spawn Explore only.

### Explore Agent Prompt

```
You are a research agent investigating a query in a Unity project.

QUERY: $QUERY
ITERATION: $ITERATION / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK (empty on first run)

## Instructions

1. Search the codebase for files, classes, and patterns relevant to the query.
   Focus on: .claude/rules/, _Framework/, _GameFolders/Scripts/Games/
2. If the query mentions a Unity API, package, or error message → web search for Unity docs or known issues.
3. If PREVIOUS_REVIEWER_FEEDBACK is not empty → specifically address the gap flagged. Do not repeat the same evidence.

## Output Format (REQUIRED)

CODEBASE_FINDINGS:
- [file:line] — [relevance to query]

PROPOSED_ANSWER:
[Concrete explanation. Reference specific files and classes. No vague language.]

CONFIDENCE: low | medium | high
```

### unity-scout Agent Prompt (complexity ≥ 0.4 only)

```
You are a Unity risk analyst. Scan the project for Unity-specific issues related to the query.

QUERY: $QUERY

Investigate for:
- VContainer registration gaps or missing .As<IInterface>() calls
- UniTask async methods missing CancellationToken
- Input System lifecycle violations (missing Enable/Disable)
- ECS structural changes outside EntityCommandBuffer
- Addressables handles not released in Dispose()
- Unity null check violations (?. or is null on UnityEngine objects)

## Output Format (REQUIRED)

UNITY_RISKS:
- [risk type] — [file:line] — [description]
OR: UNITY_RISKS: none
```

### Write Findings to File

After both agents complete, merge into a single markdown file and **write** it to `.claude/state/search-findings.md`:

```markdown
# Search Findings
**Query:** $QUERY
**Iteration:** $ITERATION
**Complexity:** $COMPLEXITY_LABEL ($SCORE)

## Root Cause / Answer
$COMBINED_ROOT_CAUSE

## Evidence
$EVIDENCE_LIST (file:line entries)

## Unity Risks
$UNITY_RISKS (or "none")

## Proposed Answer
$PROPOSED_ANSWER

## Confidence
$CONFIDENCE
```

Capture as `$ROOT_CAUSE`, `$EVIDENCE`, `$PROPOSED_ANSWER`, `$CONFIDENCE`.

---

## Phase 2 — Completeness Review Loop

**Iteration counter starts at 1. Max 5 iterations.**

Reviewer priority — try in order, fall back if unavailable:
1. `subagent_type: "unity-reviewer"`
2. `subagent_type: "codex:codex-rescue"`
3. `subagent_type: "claude"`

Spawn the reviewer with this prompt:

```
You are a completeness reviewer for a codebase investigation.

Read the findings file at: .claude/state/search-findings.md

ORIGINAL_QUERY: $QUERY

## Your Job — Three verdicts only:

**COMPLETE** — The findings fully answer the query with real evidence (file:line). The proposed answer is consistent with this project's architecture rules:
- No singletons (VContainer only)
- No coroutines (UniTask only)
- No legacy Input API (New Input System only)
- No cross-module concrete dependencies
- No UnityEngine in service classes (Provider pattern)
- IEventBus for cross-system communication

**INCOMPLETE** — The findings partially answer the query but have a specific gap. Name the gap precisely: which file, claim, or question is unresolved. Research must run again.

**REJECT** — The findings contradict the evidence, reference non-existent files, or the proposed answer violates architecture rules. Name what is wrong.

## Output Format (REQUIRED)

VERDICT: COMPLETE | INCOMPLETE | REJECT

REASON: [one sentence]

GAP: [INCOMPLETE/REJECT only — exact gap or violation the next research iteration must address]
```

### Loop Logic

- **COMPLETE** → set `$STATUS = COMPLETE`, proceed to Phase 3.
- **INCOMPLETE** and iteration < 5 → increment counter, go back to Phase 1 with `$FEEDBACK = GAP`.
- **REJECT** and iteration < 5 → increment counter, go back to Phase 1 with `$FEEDBACK = GAP`.
- Any verdict at iteration == 5 → set `$STATUS = INCONCLUSIVE`, proceed to Phase 3.

---

## Phase 3 — Present Findings to User

**Do NOT execute any follow-up command. Present only.**

### If STATUS == COMPLETE

```
SEARCH COMPLETE ✓  (approved in $ITERATION iteration(s))

QUERY
  $QUERY

ANSWER
  $ROOT_CAUSE

EVIDENCE
  $EVIDENCE (file:line list)

UNITY RISKS
  $UNITY_RISKS (or "none found")

PROPOSED ANSWER
  $PROPOSED_ANSWER
```

### If STATUS == INCONCLUSIVE

```
SEARCH INCONCLUSIVE — no definitive result after 5 iterations.

QUERY
  $QUERY

BEST GUESS (not reviewer-approved)
  $LAST_ROOT_CAUSE

UNRESOLVED GAP
  $LAST_GAP

PROPOSED ANSWER (unverified)
  $LAST_PROPOSED_ANSWER
```

---

## Phase 4 — Action Router

After presenting findings, spawn an **action router** agent to recommend the appropriate next command. Do not execute it — only recommend.

```
You are an action router. You have just seen a codebase investigation result.

QUERY: $QUERY
STATUS: $STATUS
ROOT_CAUSE: $ROOT_CAUSE
PROPOSED_ANSWER: $PROPOSED_ANSWER
UNITY_RISKS: $UNITY_RISKS

## Your Job

Decide which single action the developer should take next. Choose from:

| Action | When to recommend |
|--------|------------------|
| `/fix <summary>` | Clear bug with a known root cause and stack trace pointing to a specific file |
| `/fix-deep <summary>` | Logic bug, intermittent issue, or race condition where root cause is still uncertain |
| `/implement <summary>` | Missing feature, architectural gap, or something that needs to be built |
| `/create-plan <file> <summary>` | Complex change spanning multiple modules that needs a phased plan before implementation |
| `/update-plan <file> <summary>` | Existing plan or WORKFLOW.md needs to be updated based on the findings |
| `no action` | Pure exploration query ("how does X work") — findings are informational only |

## Output Format (REQUIRED)

RECOMMENDED_ACTION: [the exact command string, or "no action"]

REASON: [one sentence — why this action fits the findings]
```

Print the recommendation to the user:

```
NEXT ACTION
  $RECOMMENDED_ACTION
  $REASON
```

**The user decides whether to run it.**

---

## Completion

Delete `.claude/state/search-findings.md` after presenting, unless the recommended action is `/create-plan` or `/update-plan` — in that case keep it as input context.

$ARGUMENTS
