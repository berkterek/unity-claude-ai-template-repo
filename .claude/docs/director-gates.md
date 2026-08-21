# Director Gates — Centralized Review Prompts

Named review gates used across pipeline commands. Two kinds:

- **Human-pause gates** (SCOPE_GATE, ARCHITECTURE_GATE, BREAKING_GATE, QUALITY_GATE, EXHAUSTION_GATE, EVIDENCE_GATE, HYPOTHESIS_GATE, COMMIT_GATE, BREAKING_REVISION_GATE) — stop the pipeline and wait for user approval before continuing.
- **Automated check gates** (TD-ARCHITECTURE, TD-UNITY-RISK, TD-PERFORMANCE, TD-COMPILE, CD-SCOPE) — spawn a reviewer subagent and evaluate verdict automatically.
- **Hook-enforced gates** (SPARC_GATE) — a human-pause gate whose skipping is blocked mechanically by a PreToolUse hook. Defined further down under `## How to Reference Gates in Pipeline Commands`, in table form rather than as a box.

> **When auditing this file, two heading traps.** (1) Match `####` as well as `###` — SPARC_GATE
> is a `####` heading in a later section, so a check scanning only `^### ` reports it as
> called-but-undefined and invites "fixing" a gate that was never broken. (2) Counting gate
> headings gives 11 while there are **10** gates: `### SCOPE_GATE` appears twice, once as its
> definition and once as the worked example under
> `## How to Reference Gates in Pipeline Commands`. Deduplicate before comparing that count
> against the gate tables in `README.md` and `.claude/CLAUDE.md`, which list 10.

---

## Human-Pause Gates

### SCOPE_GATE

**When:** Before any implementation starts — always fires in `/implement`, `/fix`, `/scene-setup`, `/migrate`.
**Purpose:** Confirm the user agrees on what will be built/changed before any agent writes code.

Show the user:
```
SCOPE_GATE ──────────────────────────────────────────────
Task:       $TASK_DESCRIPTION
Complexity: [score] — [Label]
Files expected to change: [list if known, else "TBD"]
─────────────────────────────────────────────────────────
Type `go` to proceed, or describe what should change.
```

Wait for response. `go` (or equivalent) → proceed to next step. Any other input → update understanding and re-show gate with revised scope.

---

### ARCHITECTURE_GATE

**When:** When complexity scoring detects a new module folder is being created (+0.3 signal).
**Purpose:** Approve the module structure and interface contracts before the coder writes anything.

Show the user:
```
ARCHITECTURE_GATE ────────────────────────────────────────
A new module will be created as part of this task.

Proposed structure (inferred from task):
  Module:     [module name]
  Interface:  I[ModuleName]Service.cs
  Service:    [ModuleName]Service.cs (sealed)
  Config:     [ModuleName]Configuration.cs (ScriptableObject)
  Module:     [ModuleName]Module.cs (static, called from AppModules)
  Events:     [ModuleName]Events.cs (if events needed)

Scope registered in: [AppScope | GameScope | MenuScope]
──────────────────────────────────────────────────────────
Type `go` to approve this structure, or describe changes.
```

Wait for response. `go` → proceed. Any other input → adjust proposed structure and re-show.

---

### BREAKING_GATE

**When:** A refactor or fix touches more than 3 files (or >5 files for `/migrate`).
**Purpose:** Confirm a wide-blast-radius change is intentional before proceeding.

Show the user:
```
BREAKING_GATE ────────────────────────────────────────────
This change touches [N] files — potential for regressions.

Files to be modified:
[list all affected files]

Are you sure you want to proceed?
──────────────────────────────────────────────────────────
Type `go` to proceed, or `stop` to abort.
```

Wait for response. `go` → proceed. `stop` → abort pipeline.

---

### QUALITY_GATE

**When:** After a reviewer pass returns CHANGES NEEDED and the user is shown the findings.
**Purpose:** Explicit user decision — accept findings for fixing, or override and proceed.

Show the user:
```
QUALITY_GATE ─────────────────────────────────────────────
Reviewer found issues:
[list all CHANGES NEEDED items]

Options:
  fix    — spawn coder to address all findings
  list   — show full details for each finding   (optional; omit when already shown in full)
  skip   — accept and proceed to commit (your responsibility)
  stop   — abort, leave files uncommitted
──────────────────────────────────────────────────────────
```

Wait for response. Act accordingly.

**`list` is display-only and non-terminal.** It prints the full detail of each finding and
then **re-shows this gate** — it is not a choice that advances the pipeline. A caller that
treats `list` as terminal exits with the decision never made. Include the line only when the
findings were summarised; if they were already printed in full, omit it rather than offering
a no-op.

Answering `fix` starts a fresh coder → reviewer round. That round is bounded — see
`## Retry and Pass Limits`. Once the budget is spent, this gate is no longer the right
one: fall through to **EXHAUSTION_GATE** below.

---

### EXHAUSTION_GATE

**When:** A bounded retry loop has spent its budget and the work is still failing. It is the
branch QUALITY_GATE (and every other bounded fix loop) falls through to.
**Purpose:** The budget is gone. Only a human can decide whether to ship the known-bad state
or abandon the run.

Show the user:
```
EXHAUSTION_GATE ──────────────────────────────────────────
$WHAT_WAS_RETRIED still failing after $N $PASS_TYPE passes:
[list every remaining issue]

Skipping ships: [what each remaining issue costs at runtime]

Options:
  skip   — proceed anyway (your responsibility)
  stop   — abort
──────────────────────────────────────────────────────────
```

Wait for response. `skip` → continue to the next step with the issues unresolved, and log
them. `stop` → abort, leave files uncommitted.

**The caller supplies `$WHAT_WAS_RETRIED`, `$N` and `$PASS_TYPE`** — a fixed string cannot
serve callers with four different budgets (2 validator passes, 3 reviewer passes, 3 verifier
iterations, 3 planner passes).

**The `Skipping ships:` line is mandatory, not decoration.** Measured 2026-08-21 by A/B-ing
this gate against the inline option bullets it replaces: both forms offered the same two
options, but the inline arm volunteered what skipping would cost ("a per-frame allocation and
a broken DIP seam that also blocks NSubstitute mocking") while the pointer arm emitted the
bare box and nothing else. A gate that pauses for a human decision and then withholds the
basis for it is worse than the restatement it replaced.

> **`fix` is deliberately absent — do not add it.** This gate is only reachable once the fix
> loop has already spent its full budget, so `fix` is not a missing option; it is the option
> that just failed N times. The pass counts in `## Retry and Pass Limits` count passes
> *before* the gate, not gate visits — so a `fix` offered here decrements nothing and
> forbids no fourth, fifth or tenth visit. Measured 2026-08-21: given a block that did offer
> `fix` past exhaustion, an agent reported `BOUNDED: no` and reached that reasoning
> independently. Stronger still: when the finding set is **unchanged** across rounds, the
> fixer demonstrably cannot resolve those findings, so another `fix` cannot help by
> construction. A user who wants another attempt picks `stop` and re-runs the command with
> the findings in hand.
>
> If a loop genuinely needs more attempts, raise its budget in `## Retry and Pass Limits`.
> That keeps the bound in one place instead of moving it to the call site, where it becomes
> unbounded.

---

### EVIDENCE_GATE

**When:** An automated reproduction attempt produced no evidence, and only the human at the
keyboard can produce it. Fires in `/fix-deep` — **its only caller.**
**Purpose:** The agent cannot reproduce the bug itself. Rather than guess a cause from no
evidence, ask the human to supply it.

Show the user:
```
EVIDENCE_GATE ────────────────────────────────────────────
⚠ No debug logs appeared. The bug was not reproduced this session.

Options:
  retry              — reproduce it in the editor, then type this
  manual: <text>     — describe what you did in the editor; the text becomes the evidence
  stop               — abort
──────────────────────────────────────────────────────────
```

Wait for response. `retry` → re-run the reproduction step. `manual: <text>` → continue with
that text as the evidence. `stop` → abort and remove any debug logs already added.

**`manual:` takes free-form input** — it is the only option in this file that is a prefix
rather than a fixed word. Parse everything after the first `:` as the evidence text; do not
require quoting. An empty description is not evidence — re-show the gate.

**A diagnosis with no evidence is the failure this gate exists to prevent.** Do not fall
through to "proceed anyway": there is no third path here, which is why the option set has no
`skip`.

---

### HYPOTHESIS_GATE

**When:** The evidence refuted the current hypothesis. Fires in `/fix-deep` — **its only
caller.**
**Purpose:** Decide whether to spend another investigation cycle on a revised hypothesis.

Show the user:
```
HYPOTHESIS_GATE ──────────────────────────────────────────
Hypothesis REFUTED. Revised hypothesis:
[the revised hypothesis]

Cycles used: $N of 2

Options:
  retry  — investigate the revised hypothesis
  stop   — abort, remove debug logs
──────────────────────────────────────────────────────────
```

Wait for response. `retry` → re-enter the investigation step with the revised hypothesis.
`stop` → abort and remove debug logs.

**Bound: 2 revision cycles.** The number lives here, and the call site must not restate a
different one — a loop whose gate says 2 and whose call site says 3 is a defect even though
both numbers are individually plausible (see `## Retry and Pass Limits`). Once the 2 cycles
are spent, this gate is exhausted: fall through to **EXHAUSTION_GATE**.

---

### COMMIT_GATE

**When:** After all verification passes, immediately before the committer runs.
**Purpose:** Final human sign-off on what gets committed.

Show the user:
```
COMMIT_GATE ──────────────────────────────────────────────
Ready to commit:

Task:         $TASK_DESCRIPTION
Files staged: [list all changed files]
Reviewer:     APPROVED
Verifier:     VERIFIED (or SKIPPED)
──────────────────────────────────────────────────────────
Type `go` to commit, or `stop` to leave uncommitted.
```

Wait for response. `go` → spawn committer. `stop` → leave files staged, print summary without committing.

---

### BREAKING_REVISION_GATE

**When:** A plan reviewer returns CHANGES NEEDED carrying `REVISION_TYPE: BREAKING` — fires in `/create-plan` and `/update-plan`.
**Purpose:** A breaking revision means the codebase was not fully read before planning. Let the human choose to re-research now, rather than cascade breaking fixes into implementation.

Show the user:
```
BREAKING_REVISION_GATE ───────────────────────────────────
⚠️  BREAKING REVISION DETECTED (v$PLAN_VERSION)

The reviewer flagged a structural change — this means the codebase
was not fully read before planning. Proceeding risks another round
of breaking fixes during implementation.

Reviewer feedback:
[list all CHANGES NEEDED items]

Options:
  re-research  — re-run the research stage with expanded scope, then re-plan
  accept       — proceed with the breaking revision (your responsibility)
  stop         — abort, do not save the plan
──────────────────────────────────────────────────────────
```

Wait for response. `re-research` → re-run this command's upstream research stage, then re-plan and re-review; the caller names which agent that is (`/create-plan` → Researcher, `/update-plan` → Analyzer). `accept` → proceed to save with the breaking revision. `stop` → abort, save nothing.

---

## Automated Check Gates

These gates spawn a subagent or run a check automatically. They do not pause for user input unless the verdict is FAIL/RISK.

---

### TD-ARCHITECTURE

**Trigger:** After any implementation — verify structural integrity.
**Context to pass:** Task description, files changed, relevant architecture rules.

**Verdict:** `PASS` — architecture is sound. `FAIL: [file:line] issue` — specific violation.

Checks — all five, every pass. The rule each one enforces is cited so a disagreement can be settled against the rule rather than argued:
- VContainer DI: no singletons, no static mutable state, no service locators (`rules/architecture.md:28` — `FindObjectOfType` is a singleton in disguise; `rules/csharp-unity.md:202`)
- Interface-driven: consumers depend on interfaces, not concrete types (`rules/architecture.md:348`, and Interface-First Registration at 812)
- IEventBus: cross-module communication only through events, not direct calls (`rules/architecture.md:202`)
- Provider pattern: UnityEngine API in Games/Concretes/ only, services are pure C# (`rules/architecture.md:32-58`, Card 2)
- Module boundaries: no concrete cross-module dependencies (`rules/architecture.md:532-533`, Module Portability Checklist)

> **The list is the coverage contract — do not collapse it into a pointer.** Measured 2026-08-21 on a planted-defect fixture: with the five bullets a reviewer emitted a verdict for **5/5** axes; given only a prose pointer to the same rules it emitted **3/5**, silently skipping IEventBus and module boundaries because nothing told it those axes existed. Both arms caught the primary defect, so the loss is in coverage, not in sharpness. Duplication with `rules/` is not a cost here: these five lines name axes, they do not restate rule content, so they do not rot when a rule changes.

---

### TD-UNITY-RISK

**Trigger:** Before writing any architecture decision or implementation touching Unity APIs.
**Context to pass:** Unity API names being used, Unity 6 version, `docs/engine-reference/unity/`.

**Verdict:** `CLEAR` — no post-cutoff risk. `RISK: [api] [risk-level] [mitigation]`

Checks:
- Read `docs/engine-reference/unity/deprecated-apis.md` — is any listed API used?
- Read `docs/engine-reference/unity/breaking-changes.md` — does the task touch any affected area?
- Read `docs/engine-reference/unity/current-best-practices.md` — are better alternatives available?

---

### TD-PERFORMANCE

**Trigger:** After implementation of any system with Update/FixedUpdate paths or ECS systems.
**Context to pass:** Files changed, hot path locations.

**Verdict:** `PASS` or `FAIL: [file:line] [allocation-type]`

Checks — all five, every pass. Note the rules live in **three** different files, so "see performance.md" would miss two of them:
- Zero heap allocations in Update/FixedUpdate/LateUpdate (no `new`, no boxing, no LINQ, no string ops) — `rules/performance.md`, the golden rule at the top
- `renderer.material` not used (clones material) — use `sharedMaterial` or `MaterialPropertyBlock` (`rules/performance.md:142-159`)
- ECS structural changes use ECB, not direct `EntityManager` calls inside systems (`rules/ecs-dots.md:209-214`)
- Addressables handles stored as fields and released in `Dispose()` (`rules/addressables.md:60-84`)
- `Camera.main` (`rules/performance.md:54`) and `GetComponent<T>()` (`:13-33`) assigned in the Inspector, not called per frame

Four hooks already enforce parts of this mechanically, so this gate is a second line of defence rather than the only one: `check-no-hotpath-expensive-calls.sh`, `check-no-linq-hotpath.sh`, `check-getcomponent-in-awake.sh`, `check-ecs-structural-changes.sh`.

---

### TD-COMPILE

**Trigger:** After every coder pass — mandatory before the reviewer runs.
**Context to pass:** Files changed.

**Verdict:** `VALIDATED` — clean compile and all tests pass. `COMPILE FAILED: [errors]` or `TEST FAILED: [tests]`

Steps: the Unity Validator step in the pipeline that spawned you — `implement.md` Step 2.5 and `fix.md` Step 4.5 (`fix-deep.md` inherits it by reference). The MCP call sequence lives there, operationally, next to its own fix loop; it is deliberately not duplicated here. See also `## Retry and Pass Limits` → order between the two loop kinds.

> This gate was briefly deleted on the grounds that nothing named it and its body was a third copy of the two Validator steps. Both halves of that were true, but the conclusion was wrong: the fix for "nothing names it" is to name it — which is exactly what was done for `TD-ARCHITECTURE` and `TD-PERFORMANCE` in the same pass. Deleting it instead left the automated-gate list with no compile gate at all, which reads as though compile validation is not gated. The body stays a pointer; the name stays.

---

### CD-SCOPE

**Trigger:** Before starting any task — verify scope is well-defined.
**Context to pass:** Task description, affected files.

**Verdict:** `CLEAR` — scope is bounded. `BLOATED: [what's out of scope]`

Checks:
- Does the task touch files not mentioned in the original request? Flag them.
- Is the task trying to refactor unrelated code? Flag it.
- Are new abstractions being created that have no current callers? Flag it.
- YAGNI: is everything being implemented actually needed right now?

---

## Retry and Pass Limits

Every retry loop in a pipeline command uses one of exactly two bounds. Which one depends on what the loop is waiting for:

- **Reviewer-verdict loops — max 3 passes.** A reviewer, linter, or auditor returns APPROVED / CHANGES NEEDED. A judgement call can legitimately improve across iterations, so a third attempt has expected value.
- **Compile/test-fix loops — max 2 passes.** A validator or verifier reports COMPILE FAILED / TEST FAILED. A compile error is deterministic: if two passes cannot fix it, a third is usually the same agent making the same wrong guess, and the human should see the errors instead.

**Order between the two:** in every pipeline that has both, the compile/test validator runs *before* the reviewer — a reviewer verdict on code that has not compiled is void, because the reviewer is judging text that the compiler has not yet agreed is a program. The two Validator step headers state this at their own call sites; do not add a third copy of the validator's MCP call sequence anywhere.

When a loop exhausts its passes the pipeline **stops and shows the human what is left** — it never silently proceeds. For the reviewer case that stop is QUALITY_GATE (above); state the remaining findings there rather than inventing a second options list.

State the bound once per loop. A loop whose body says "max 2" and whose failure branch says "after 3 passes" is a defect even though both numbers are individually plausible — the two must be the same number.

> Placed here, immediately before the referencing rules, because both sections answer the same question: what a command author must write rather than invent. Deliberately no per-command line numbers — those rot; grep for `passes` in `.claude/commands/` instead.

---

## How to Reference Gates in Pipeline Commands

Human-pause gates (inline block in the pipeline step):
```
### SCOPE_GATE

Show the user the SCOPE_GATE block from .claude/docs/director-gates.md.
Wait for `go` before continuing.
```

Automated gates (spawn a subagent or inline check):
```
Apply gate TD-ARCHITECTURE from .claude/docs/director-gates.md.
Files to check: $CODER_OUTPUT
```

### Hook-Enforced Gates

These gates are enforced automatically by PreToolUse hooks — the hook exits 2 to block the spawn if the approval state file is missing.

#### SPARC_GATE

| Property | Value |
|----------|-------|
| **Fires** | Before `coder` / `unity-coder` spawn, after SCOPE_GATE |
| **Commands** | Any pipeline command spawning a coder-class agent (`/implement`, `/orchestrate`, `/fix` when complexity ≥ 0.4) |
| **State file** | `.claude/state/sparc-approved` (independent of `gate-cleared`) |
| **Shows user** | Specification (what will be built) + Architecture (which files, interfaces, data flow) |
| **Cleared by** | User types "go" → `mkdir -p "$(git rev-parse --show-toplevel)"/.claude/state && touch "$(git rev-parse --show-toplevel)"/.claude/state/sparc-approved` — absolute, because `guard-sparc-approved.sh` reads `${UNITY_HOOK_STATE_DIR}` and a relative path run from anywhere but the repo root creates a file the hook never checks |
| **Deleted** | After gated coder agent completes — same pattern as `gate-cleared` (pipeline deletes before committer runs) |
| **Guard hook** | `guard-sparc-approved.sh` (PreToolUse on Agent, exits 2 if state file absent) |

**Note:** `.claude/state/sparc-approved` and `.claude/state/gate-cleared` are independent files.
