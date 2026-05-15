# /search Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a slash command at `.claude/commands/search.md` — a research → reviewer validation → present pipeline.

**Architecture:** The research phase uses Explore + unity-scout + optional web search agents. Findings are validated by a reviewer chain: `unity-reviewer` → Codex (`codex:rescue`) → `reviewer` fallback. A MISMATCH triggers a loop with a max of 5 iterations. After APPROVED, a structured report is presented to the user.

**Tech Stack:** Claude Code slash commands (`.claude/commands/`), existing agents (Explore, unity-scout, unity-reviewer, codex:rescue, reviewer)

---

## File Map

| File | Status | What to do |
|------|--------|------------|
| `.claude/commands/search.md` | Create | Main command definition — full pipeline |

Single file — no other files created or modified.

---

## Task 1: Create the `/search` command

**Files:**
- Create: `.claude/commands/search.md`

- [ ] **Step 1: Create the file**

Create `.claude/commands/search.md` with the following content:

```markdown
# /search — Research → Review → Present Pipeline

Researches a query, produces a root cause + solution, validates it through the reviewer chain (unity-reviewer → Codex → reviewer), and presents the result to the user.

## Usage

```
/search <query>
/search "AudioService not injecting"
/search "EnemyMoveSystem sometimes not running"
/search "how is the event bus used in this project"
```

If no argument is provided, ask: "What should we research?"

---

## Pipeline

```
[Phase 1] Research → [Phase 2] Review ⟲ (max 5 iter) → [Phase 3] Present
```

---

## Phase 1 — Research

Spawn an **Explore** subagent with this prompt:

```
You are a research agent investigating a query in a Unity project.

QUERY: $QUERY
ITERATION: $ITERATION / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK

## Instructions

1. Search the codebase for files, classes, and patterns relevant to the query.
   - Use file reads, grep patterns, and directory listings.
   - Focus on: .claude/rules/, _Framework/, _GameFolders/Scripts/Games/
2. If unity-scout agent is available, delegate Unity-specific risk analysis:
   - VContainer registration gaps, lifecycle issues, ECS structural violations, UniTask cancellation, Input System wiring
3. If the query mentions a Unity API, package name, or error message that could benefit from external docs → use web search for Unity documentation or known issues.
4. If PREVIOUS_REVIEWER_FEEDBACK is not empty → address the specific gap or contradiction the reviewer flagged.

## Output Format (REQUIRED — do not deviate)

ROOT_CAUSE: [one sentence — what is the actual problem or answer]

EVIDENCE:
- [file path or pattern] — [how it supports the root cause]
- [...]

PROPOSED_SOLUTION:
[Concrete steps. Reference specific files and classes. No vague language.]

CONFIDENCE: low | medium | high
```

Capture the output as `$RESEARCH_OUTPUT`.

---

## Phase 2 — Review Loop

**Iteration counter starts at 1. Max 5 iterations.**

**Reviewer priority:** First try **unity-reviewer** subagent. If unavailable → fall back to **Codex** (`codex:rescue` subagent). If Codex is also unavailable → fall back to **reviewer** subagent.

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
```

Then append the appropriate next step based on the query type:

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
```

- [ ] **Step 2: Verify the file was created**

```bash
cat .claude/commands/search.md | head -5
```

Expected output:
```
# /search — Research → Review → Present Pipeline
```

- [ ] **Step 3: Add `/search` line to the Commands section in CLAUDE.md**

In `.claude/CLAUDE.md`, find the `### Session & Context` section. Add the following line to the list:

```markdown
- `/search <query>` — Codebase research: Explore + unity-scout + web search → unity-reviewer validation → result report
```

Place it near the top of the `### Session & Context` section (e.g. immediately below `/context-prime`).

- [ ] **Step 4: Commit the change**

```bash
git add .claude/commands/search.md .claude/CLAUDE.md
git commit -m "feat: add /search command — research + review pipeline"
```

Expected output: commit hash and message.

---

## Self-Review Checklist

- [x] Spec coverage: Research (Explore + unity-scout + web search) ✓, Review loop max 5 iter ✓, APPROVED/INCONCLUSIVE outputs ✓, NEXT STEPS routing ✓
- [x] Placeholder scan: all steps contain concrete content, no TBD
- [x] Type consistency: `$QUERY`, `$ITERATION`, `$FEEDBACK`, `$ROOT_CAUSE`, `$EVIDENCE`, `$PROPOSED_SOLUTION`, `$STATUS` — all variables used consistently
