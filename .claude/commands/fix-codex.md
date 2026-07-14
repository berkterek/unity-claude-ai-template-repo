# /fix-codex — Codex-Driven Fix Pipeline

**Pipeline:** Knowledge Graph Preload → Codex Analysis → Human Gate → Codex Implementation → Claude Review → Committer

## Usage

```
/fix-codex <bug description>
/fix-codex --files GameManager.cs,LevelController.cs "items not dropping"
```

If no argument is given, ask: "Describe the bug. Include any error messages, stack traces, and reproduction steps."

## When to use

| Command | Use when |
|---------|----------|
| `/fix` | Stack trace clearly points to root cause, files are small (<500 lines) |
| `/fix-deep` | Logic bug, intermittent issue, root cause unclear |
| `/fix-codex` | Legacy/large codebase (2000+ line files), stuck after `/fix` or `/fix-deep`, or 30+ minutes in a loop — Codex reads code literally without forming hypotheses |

> **Why fix-codex is different:** Claude Code forms a hypothesis during analysis and confirms it in subsequent reads. Even `/clear` + restart can reach the same wrong conclusion by reading the same files in the same order. Codex follows the code literally without prior bias.

---

## Step 0 — Plugin Preflight

Check that the `codex:codex-rescue` skill is available. If not, stop and tell the user to run `/codex:setup`.

---

## Step 0.5 — Knowledge Graph Preload

Before Codex reads a single file, check whether the knowledge graph can hand it a pre-built inventory instead of a cold-start scan. `/fix-codex` exists for cases where Claude's own hypothesis-forming has already failed — the same risk applies to a stale graph: a wrong or outdated inventory would bias Codex's "fresh eyes" read exactly the way we're trying to avoid. So this follows `/search`'s stricter staleness rule, not `/fix`'s looser one.

Check `.claude/project-features.json`:
- If `.graph == true` AND `.claude/graph/graph.json` exists → candidate for the graph path.
- Otherwise → set `GRAPH_CONTEXT` empty, proceed to Step 1 (unchanged, Codex discovers everything itself).

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

- If `classes == 0` (empty graph — e.g. a fresh template with no game code yet) → set `GRAPH_CONTEXT` empty, proceed to Step 1 silently. Do NOT warn — an empty graph is a valid state.
- If `age_h > 24` (stale) → tell the user, then proceed with `GRAPH_CONTEXT` empty:
  ```
  ⚠ Knowledge graph is stale (last built > 24h ago).
    Run /build-knowledge-graph for graph-accelerated analysis. Codex will scan source files directly.
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

Keep this output as `GRAPH_CONTEXT` and embed it into the Codex Analysis prompt (Step 1). When `GRAPH_CONTEXT` is empty, Step 1 behaves exactly as before — no regression.

---

## Step 1 — Codex Analysis Pass

Have Codex analyze the code directly. Claude must do **zero pre-analysis** at this stage — no file reads, no hypothesis formation, no "probably this file" guesses. Codex starts with fresh eyes.

If `--files` was provided, pin those files for Codex. Otherwise Codex discovers them independently.

Invoke the `codex:codex-rescue` skill with this prompt:

```
TASK: Analysis only — do NOT fix yet.

BUG: <user's full description>
REPRODUCTION: <how it is triggered>
FILES (if specified): <list from --files argument, or "discover yourself">

## Knowledge Graph (class/interface/event/installer inventory — query this BEFORE scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0.5 — if empty, write "No usable graph — scan source files directly."]

If a knowledge graph inventory is provided above (non-empty), use it to locate the fault area first — e.g. callers/dependencies of a suspect class, who publishes/subscribes an event, what an installer registers — before opening any file. This narrows which files you read; it does not replace reading them. Still trace the execution path from the symptom backward to the root cause by reading the actual code the graph points you to.

If the graph inventory is empty (or absent), read the codebase directly as before — discover files yourself.

Do NOT form a hypothesis first — read the code literally and follow the data/call flow.

Report:
1. ROOT CAUSE: exact file + line number + what is wrong
2. WHY: why this causes the reported symptom (execution trace)
3. AFFECTED SCOPE: what else might be affected by the fix
4. FIX APPROACH: what should change and why (do not implement yet)
```

Show Codex's analysis output to the user.

---

## Step 2 — Human Gate

Present the analysis:

```
CODEX ANALYSIS
==============
Root Cause: <file:line — what is wrong>
Why it causes the symptom: <execution trace>
Affected scope: <what else may be impacted>
Proposed fix: <what should change>

Proceed? (go / redirect)
```

If user types `go` → move to Step 3.
If user redirects (e.g. "no, the real issue is X") → return to Step 1 with the corrected information.

---

## Step 3 — Codex Implementation

Pass the confirmed analysis to Codex for implementation. Codex implements its own findings — no translation loss.

Invoke the `codex:codex-rescue` skill with this prompt:

```
TASK: Implement the fix based on your previous analysis.

ROOT CAUSE CONFIRMED: <root cause from Step 1>
FIX APPROACH CONFIRMED: <fix approach from Step 1>

Now implement the fix. Fix at root cause — not at symptom.

PROJECT RULES (non-negotiable):
- Dependency injection: VContainer only. No singletons, no FindObjectOfType, no static mutable state.
- Async: UniTask only. No coroutines, no async Task.
- Input: New Input System only. No Input.GetKey / Input.GetAxis.
- Events: IEventBus for cross-module. C# event for intra-module. UnityEvent forbidden.
- MonoBehaviour components: assigned via [SerializeField] in Inspector, not GetComponent in Awake.
- Sealed classes by default.
- No LINQ in gameplay code.
- Unity null check: use == null, not is null or ?. on UnityEngine.Object types.

After implementing, verify: does the fix address the root cause, not just suppress the symptom?
```

---

## Step 4 — Claude Review

After Codex implementation, Claude reviews the changes directly. Claude reads the changed files and evaluates:

1. **CORRECT LOCATION?** Was the fix applied to the actual root cause location (from Step 1), or just a symptom?
2. **ROOT CAUSE UNDERSTOOD?** Does the fix address why the bug occurs, not just what it produces?
3. **COMPLETE?** Are there edge cases or related paths that also need fixing?
4. **ARCHITECTURE:** Any VContainer / UniTask / Input / event rule violations introduced?
5. **VERDICT:** APPROVED / NEEDS REVISION

If NEEDS REVISION: list exactly what must change (file + line + reason), then loop back to **Step 3** — pass the revision notes to Codex as additional context and re-implement. Then return to Step 4 for another Claude review. Max 2 revision loops total. If still unresolved after 2 loops, report to user.

**APPROVED → Step 5.**

---

## Step 5 — Committer

Run the committer agent. Commit message format:

```
fix(<scope>): <short description of what root cause was resolved>

Root cause: <one sentence>
```

---

## Output Format

On APPROVED:

```
ROOT CAUSE: <file:line — what was wrong>
FIX: <what changed and why>
CLAUDE REVIEW: APPROVED
COMMIT: <hash> — <message>
```

If unresolved after revision loops:

```
ROOT CAUSE: <what Codex found>
FIX APPLIED: <what changed>
REVIEW VERDICT: NEEDS REVISION
REMAINING ISSUES: <file:line list>
NEXT STEP: Manually address the listed locations
```
