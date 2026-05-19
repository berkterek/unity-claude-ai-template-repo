# /fix-codex — Codex-Driven Fix Pipeline

**Pipeline:** Codex Analysis → Human Gate → Codex Implementation → Claude Review → Committer

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

## Step 1 — Codex Analysis Pass

Have Codex analyze the code directly. Claude must do **zero pre-analysis** at this stage — no file reads, no hypothesis formation, no "probably this file" guesses. Codex starts with fresh eyes.

If `--files` was provided, pin those files for Codex. Otherwise Codex discovers them independently.

Invoke the `codex:codex-rescue` skill with this prompt:

```
TASK: Analysis only — do NOT fix yet.

BUG: <user's full description>
REPRODUCTION: <how it is triggered>
FILES (if specified): <list from --files argument, or "discover yourself">

Read the codebase directly. Trace the execution path from the symptom backward to the root cause.
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
