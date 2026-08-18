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
[Step 0a] Knowledge Graph Preload → GRAPH_CONTEXT (or empty on stale/empty/disabled)
    ↓
[Step 0b] Complexity Score
    ↓
[Phase 1] Research (graph-first if GRAPH_CONTEXT set) → write .claude/state/search-findings.md
    ↓
[Phase 2] Reviewer reads file → COMPLETE / INCOMPLETE / REJECT
    ↓ (loop max 5 if INCOMPLETE)
[Phase 3] Present findings to user
    ↓
[Phase 4] Action Router → recommend next command
```

---

## Step 0a — Knowledge Graph Preload

Before spawning any research agent, decide whether the knowledge graph can accelerate this investigation. This follows the graph-first spirit of `/implement`, `/create-plan`, `/fix`, and `/catch-up`, but is deliberately **stricter on staleness**: `/catch-up` proceeds on a stale graph (an overview tolerates slightly-old data), whereas `/search` answers pointed questions where a stale graph can give a flatly wrong answer (e.g. "who publishes X" after X moved) — so a stale or empty graph here falls back to a fresh file scan rather than risk a wrong investigation result.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, skip to Step 0b (file-scan behavior, unchanged).

If it is a candidate, verify the graph is **usable** (fresh AND non-empty):

```bash
python3 -c "
import json, os, time
g = json.load(open('.claude/graph/graph.json'))
cb = g.get('codebase', {})
n = len(cb.get('classes', []))
lb = '.claude/graph/.last-build'
age_h = (time.time() - os.path.getmtime(lb)) / 3600 if os.path.exists(lb) else 1e9
print('classes=%d age_h=%.1f' % (n, age_h))
"
```

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, fall back to file scan. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then fall back to file scan:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated search. Falling back to file scan.
  ```
- Otherwise (fresh AND non-empty) → build `GRAPH_CONTEXT` from the graph inventory:

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

Keep this output as `GRAPH_CONTEXT` and embed it into the Explore agent prompt (Phase 1). When `GRAPH_CONTEXT` is empty, the research phase behaves exactly as before — no regression.

---

## Step 0b — Complexity Scoring

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

**If complexity ≥ 0.4 (Medium/Complex):** Spawn **Explore** (`model: haiku`) and **unity-scout** simultaneously. Wait for both to complete, then merge.

**If complexity < 0.4 (Simple):** Spawn Explore (`model: haiku`) only.

### Explore Agent Prompt

```
You are a research agent investigating a query in a Unity project.

QUERY: $QUERY
ITERATION: $ITERATION / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK (empty on first run)

## Knowledge Graph (class/interface/event/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0a — if empty, write "No usable graph — scan source files directly."]

## Instructions

1. If a knowledge graph inventory is provided above (non-empty), use it FIRST — do not re-scan folders for what it already answers:
   - "who implements interface X" → the graph's implements/interfaces data
   - "who publishes/subscribes to event E" → the graph's pub/sub data
   - "what does installer I register" / "what is class C's blast radius" → the graph's registrations / dependencies
   Only read source files for the specific detail (exact line, logic body) the graph cannot provide.
2. If the graph inventory is empty (or absent), search the codebase for files, classes, and patterns relevant to the query.
   Focus on: .claude/rules/, _Framework/, _GameFolders/Scripts/Games/
3. If the query mentions a Unity API, package, or error message → web search for Unity docs or known issues.
4. If PREVIOUS_REVIEWER_FEEDBACK is not empty → specifically address the gap flagged. Do not repeat the same evidence.

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
1. `subagent_type: "codex:codex-rescue"`
2. `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

Spawn the reviewer with this prompt:

```
You are a completeness reviewer for a codebase investigation. You are a REVIEWER, not a
researcher and not a fixer — do not modify the findings file or any other file, and do
not run the investigation yourself. Your only output is the verdict format below.

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

EVIDENCE: [COMPLETE only — cite the file:line the findings rest on for each of the six
architecture rules above, or state which rules the query does not touch and why. A
COMPLETE with no file:line is invalid: it certifies an answer nobody checked. Restating
the finding back is not evidence.]

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

After presenting findings, spawn an **action router** agent (`subagent_type: "general-purpose"`, `model: haiku`) to recommend the appropriate next command. Do not execute it — only recommend.

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
| `/update-plan <file> <summary>` | Existing plan or module tasks.md needs to be updated based on the findings |
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
