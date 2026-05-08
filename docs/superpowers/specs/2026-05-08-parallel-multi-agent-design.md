# Parallel Multi-Agent Design

**Date:** 2026-05-08  
**Status:** Approved

---

## Purpose

Add parallel agent execution to two areas:
1. **Research parallelism** — `search`, `fix`, `fix-deep` spawn Explore + unity-scout simultaneously when complexity ≥ 0.4
2. **Orchestrate task parallelism** — tasks in the same `parallel_group` in WORKFLOW.md run simultaneously

---

## Part 1: Research Parallelism

### Affected Commands
- `search.md` — Phase 1 Research
- `fix.md` — Step 1 Debugger
- `fix-deep.md` — Step 0 Evidence Collection

### Trigger Condition
Complexity score ≥ 0.4 (Medium or Complex). Simple tasks (< 0.4) use single Explore agent — parallel overhead not worth it.

### Execution Pattern

```
[Phase 1 — Parallel Research] (complexity ≥ 0.4 only)
  ├── Explore agent      → codebase scan, file patterns, grep, directory listings
  └── unity-scout agent  → Unity-specific risks: VContainer wiring, ECS structural,
                           UniTask cancellation, Input System lifecycle, Addressables handles
        ↓ both complete
  Main agent merges structured outputs:
  CODEBASE_FINDINGS: [Explore output]
  UNITY_RISKS:       [unity-scout output, or "none" if clean]
  COMBINED_EVIDENCE: [main agent synthesizes both into unified evidence list]
        ↓
  Continue to Review phase (unchanged)
```

### Merge Format (Required Output from Each Parallel Agent)

**Explore agent output:**
```
CODEBASE_FINDINGS:
- [file:line] — [relevance to query]
- [...]
CONFIDENCE: low | medium | high
```

**unity-scout agent output:**
```
UNITY_RISKS:
- [risk type] — [file:line] — [description]
- [...]
OR: UNITY_RISKS: none
```

**Main agent merge:**
```
COMBINED_ROOT_CAUSE: [one sentence synthesizing both findings]
EVIDENCE:
- [from codebase findings]
- [from unity risks]
PROPOSED_SOLUTION: [concrete steps]
```

---

## Part 2: Orchestrate Task Parallelism

### WORKFLOW.md Schema Addition

Tasks in the same `parallel_group` number run simultaneously. Tasks without `parallel_group` run sequentially (existing behavior preserved).

```yaml
tasks:
  - id: P1.T1
    title: "Add IEnemyService interface"
    parallel_group: 1
  - id: P1.T2
    title: "Add IAudioService interface"
    parallel_group: 1        # runs at same time as P1.T1
  - id: P1.T3
    title: "Wire both services in AppInstaller"
    # no parallel_group → runs after all group 1 tasks complete
```

### Trigger Condition
- Task has `parallel_group` defined
- ≥ 2 tasks share the same group number
- Complexity score ≥ 0.4

If complexity < 0.4 → ignore `parallel_group`, run sequentially.

### Conflict Check (Before Spawning)

Before spawning parallel tasks, orchestrate agent checks for file conflicts:

1. Read each task's `outputs` field from WORKFLOW.md
2. If two tasks in the same group list the same output file → **conflict detected**
3. On conflict: demote the later task to sequential (run after group completes), warn user:
   ```
   ⚠ PARALLEL CONFLICT: P1.T1 and P1.T2 both write to EnemyInstaller.cs
   P1.T2 demoted to sequential. Running P1.T1 first.
   ```

### Execution Pattern

```
[Group N tasks] — spawn simultaneously
  ├── Task P{phase}.T{n} → coder/unity-coder → verifier → reviewer
  ├── Task P{phase}.T{m} → coder/unity-coder → verifier → reviewer
  └── Task P{phase}.T{k} → coder/unity-coder → verifier → reviewer
        ↓ all complete (or first failure stops group)
  Committer — commits all group outputs in one commit
        ↓
[Next sequential task or next group]
```

### Failure Handling
- If any task in a group fails → stop entire group, report all failures together
- Do not proceed to next group or sequential tasks until user resolves

---

## Out of Scope
- Parallel reviewer/committer agents (always sequential — race conditions on git)
- Parallel test-writer + coder (coder depends on test-writer output)
- Dynamic parallelism detection without WORKFLOW.md annotation (too risky — manual `parallel_group` is safer)
