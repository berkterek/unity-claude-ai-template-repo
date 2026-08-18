# Orchestrate — Modül Task Executor

Bir modülün `tasks.md` dosyasını okuyarak her task'ı otomatik çalıştırır.
Kullanım: `/orchestrate docs/modules/01-core-loop/tasks.md`

---

## Step 0 — Argument Parsing & Plugin Preflight

**Parse $ARGUMENTS first:**
- `$ARGUMENTS` → tasks.md dosya yolu (zorunlu). Eksikse dur:
  ```
  tasks.md yolu gerekli. Kullanım: /orchestrate docs/modules/01-core-loop/tasks.md
  ```
- Check $ARGUMENTS for `--heavy` flag → if present, set `FORCE_OPUS_TIER=true`
- Print: `Mode: heavy (all implementation agents → opus tier)` if flag found, else nothing extra.

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:verification-before-completion` | Phase Gate — verify all acceptance criteria before proceeding | Skip verification gate |

Print availability status before proceeding:
```
Plugins: superpowers:verification-before-completion [✓/✗]
```

---

## Step 0b — Tasks.md Okuma & Complexity Scoring & SCOPE_GATE

**Step 0b.1 — Tasks.md Okuma**

1. `$ARGUMENTS`'teki tasks.md dosyasını oku. Dosya yoksa dur:
   ```
   tasks.md bulunamadı: [path]
   Modül planını önce oluşturun.
   ```
2. Checkbox'lardan durumu parse et:
   - `- [x]` → COMPLETE (skip)
   - `- [ ]` → PENDING (çalıştır)
3. Tekrar tamamlanan task'lar `[x]` checkbox ile işaretlidir — skip edilir.

**Step 0b.2 — Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | No reviewer or unity-developer — coder/unity-coder → committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

**Step 0b.3 — Complexity Scoring**

Before executing any task, score the overall workflow complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Pure C# target → **coder** / Unity target → **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Pure C# target → **coder** / Unity target → **unity-coder** + unity-developer review after each task |

**Agent routing per task — decide before spawning:**

| Target location | Simple | Medium/Complex |
|-----------------|--------|----------------|
| `_Framework/`, `Games/Abstracts/`, `Games/Concretes/` pure C# (no Unity API) | **coder** | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring | **unity-coder** | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** | **unity-coder** |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [coder | unity-coder] (per task)
Review Mode: [solo | lean | full]
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after the standard reviewer step passes for each task, spawn a **unity-developer** subagent review pass before the committer.

**Step 0b.4 — Codebase Pre-Scan**

Before spawning any agents, read the knowledge graph (or fall back to file scan):

Check `.claude/project-features.json`:
- If `.graph == true`: Read `.claude/graph/graph.json`. If missing, run `/build-knowledge-graph --full --skip-mcp` first.
- If `.graph != true`: run the original `find`-based scan (fallback below) and skip the jq queries.

**Graph path (preferred):**
- Existing `_Framework/`: `jq '.codebase.assemblies[] | select(.file | startswith("Assets/_Framework")) | {name, file}' .claude/graph/graph.json`
- Existing Abstracts: `jq '.codebase.interfaces[] | select(.file | contains("/Games/Abstracts/")) | {name, file}' .claude/graph/graph.json`
- Existing Concretes: `jq '.codebase.classes[] | select(.file | contains("/Games/Concretes/")) | {name, file, confidence}' .claude/graph/graph.json`
- Cross-reference each tasks.md task output against the graph. If a file's class exists in the graph AND is registered in an installer, mark the task as a candidate to skip.

**Fallback (no graph):**
- Run `find _Framework -type f -name "*.cs" -o -name "*.asmdef" 2>/dev/null | sort`
- Run `find _GameFolders/Scripts/Games/Abstracts -type f -name "*.cs" 2>/dev/null | sort`
- Run `find _GameFolders/Scripts/Games/Concretes -type f -name "*.cs" 2>/dev/null | sort`
- If a file already exists, read it and note whether it follows architecture rules (VContainer, UniTask, naming, #region).

Print a **Pre-Scan Report**:
```
## Pre-Scan Report
_Framework: [list of subfolders/assemblies found, or "empty"]
Existing Abstracts: [list of interfaces, or "none"]
Existing Concretes: [list of classes, or "none"]
Conflicts with tasks.md: [list files that already exist and need review, or "none"]
Architecture issues found: [list any rule violations in existing files, or "none"]
Graph confidence: [EXTRACTED | mostly_INFERRED | N/A (file-scan mode)]
```

If a tasks.md output file already exists and is correctly implemented, mark that task as a candidate to skip and ask the developer: "Task [X] output already exists and looks correct — skip or re-implement?"

**Step 0b.4b — Plan Path Validation (BLOCKING — never skip)**

The Pre-Scan above looks at what **already exists**. This step looks at what the plan is about to **create** — the folder tree in `design.md`/`tasks.md` — and validates it against `rules/architecture.md` before a single agent spawns.

Run, on the module's plan directory:

```bash
.claude/scripts/validate-plan-paths.sh <plan-dir-or-files>
.claude/scripts/validate-plan-facts.sh <plan-dir-or-files>
```

Then paste the tool's full output into the SCOPE_GATE block. Rules for reading it:

- **exit 2** → the plan contradicts `rules/architecture.md`. Do NOT proceed silently and do NOT "fix" it by inventing a folder. Present the conflict at SCOPE_GATE with the three options: (a) change the plan, (b) declare a real exception in `.claude/path-allowlist.txt` + `rules/architecture.md`, (c) stop. **The human picks.**
- **`NO PATHS FOUND`** → this is **not** a pass. Verify by hand that the plan really declares no script paths.
- **exit 0 with N paths checked** → this is the only green.

`validate-plan-facts.sh` reads the same way:

- **exit 2** → at least one task creating a new `.cs` file is missing `Callers:`/`Wiring:`, or a declared caller/module doesn't resolve on disk or in the plan. Do NOT proceed silently — present the violation at SCOPE_GATE, fix the plan or stop. **The human picks.**
- **`NO TASKS FOUND`** → this is **not** a pass — the script's own words are "this is NOT a pass". Verify by hand that the plan really declares no script paths.
- **exit 0 with N tasks checked** → this is the only green.

A hook exiting 0 is never evidence a rule was checked — only the printed `checked:` line is. Do not write "verified compliant" into any spec/AC on the basis of a hook staying silent.

**Step 0b.5 — SCOPE_GATE**

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.

```
## SCOPE_GATE — Modül Orchestration

Plan: [tasks.md dosya yolu]
Modül: [tasks.md başlığından]
Toplam task: [sayı]
Bekleyen: [sayı] (tamamlanan [sayı] skip edilecek)
Complexity: [score] — [Label]
Review Mode: [solo|lean|full]

Devam etmek için `go` yaz:
```

Wait for `go` before spawning any agents.

After receiving `go` → run:
```bash
mkdir -p "$(git rev-parse --show-toplevel)/.claude/state" && echo '{"gate":"SCOPE_GATE","pipeline":"orchestrate","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"
```

Note: per-task COMMIT_GATE is intentionally omitted — orchestration is designed to run tasks hands-free. The Phase Gate (Checkpoint) at the end of each checkpoint serves as the human checkpoint before the next section begins.

---

## Step 1 — Initialization

Append to `docs/EVENTS.jsonl` (create if missing):
```jsonl
{"event":"ORCHESTRATION_STARTED","plan":"[tasks.md path]","tasks":[N],"timestamp":"[ISO8601]"}
```

Announce:
```
## Orchestration Starting
Plan: [tasks.md path]
Modül: [tasks.md başlığından]
Toplam task: [N]
Bekleyen task: [M]
Resuming from: [ilk pending task veya "beginning"]
```

---

## Execution Loop

Repeat for each pending task in tasks.md (skip tasks with `- [x]` checkbox):

### Task Execution

Before executing tasks, check for `parallel_group` annotations in tasks.md:

**If no tasks have `parallel_group`:** Execute all tasks sequentially (existing behavior).

**If tasks have `parallel_group` AND complexity score ≥ 0.4:**
1. Group tasks by their `parallel_group` number. Tasks without a group number are sequential.
2. **Conflict check:** For each group, read each task's `outputs` field. If two tasks in the same group list the same output file → demote the later task to sequential and warn:
   ```
   ⚠ PARALLEL CONFLICT: [T1] and [T2] both write to [file]
   [T2] demoted to sequential. Running [T1] first.
   ```
3. Execute tasks in the same group simultaneously. Each spawns its own full pipeline (tester → coder → verifier → reviewer).
4. Wait for all tasks in the group to complete before starting the next group or sequential task.
5. If any task in a group fails → stop the entire group. Report all failures. Do not proceed until user resolves.
6. Commit all group outputs in a single commit after the group completes.

**If complexity score < 0.4:** Ignore `parallel_group` — run all tasks sequentially.

---

#### Sequential Task Execution (for each task, in order)

**Announce the task:**
```
### [Task ID] [Task Title]
Type: [type] | Agent: [agent type] | Complexity: [S/M/L/XL] | Group: [parallel_group or "sequential"]
Inputs: [list]
Outputs: [list]
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_STARTED","id":"[task id]","title":"[task title]","agent":"[agent type]","timestamp":"[ISO8601]"}
```

Each task runs four steps in sequence (TDD: tests first, then implementation). A failure at any step stops the pipeline.

---

#### Step 1 — Test Writer (skip if `Agent: unity-setup`)

If `Agent: unity-setup` → skip this step, go directly to Step 2.

Spawn Agent with `subagent_type: "claude"` (`model: sonnet` — isolated tester is worker-tier) with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Acceptance Criteria (tests must cover these)
[list every criterion from tasks.md]

## Your job
1. Write failing unit tests BEFORE any implementation exists.
2. Tests must FAIL right now — no implementation exists yet.
3. Do NOT commit anything.

When done: list every test file created with a summary of what each covers.
Report: DONE or BLOCKED with reason.
```

If **BLOCKED** → stop immediately. Print:
```
⚠ BLOCKED at [task id] Step 1 (Test Writer): [reason]
Fix this before continuing. Run /orchestrate [tasks.md path] to resume.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"tester","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 2 — Coder (or Unity Setup)

If `Agent: unity-setup` → spawn a **unity-setup** subagent.

**Coder agent — use routing table from Step 0b.3:**
- Pure C# target (`_Framework/`, `Games/Abstracts/`, `Games/Concretes/` no Unity API) → **coder**
- Unity/Mixed target (MonoBehaviour, Provider, Installer, scene wiring) → **unity-coder**

**Model tier override:**
- If `FORCE_OPUS_TIER == true` → all spawned implementation agents (`coder`, `unity-coder`, `unity-setup`) use `model: opus` for this run
- Else → use default tier routing

**Coder prompt:**
```
You are a senior C# Unity developer implementing a specific task. Tests have already been written — your job is to make them pass.

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Existing Tests (make these pass)
[tester output — list of test files and what they cover]

## Input Files (read these first)
[list every input file path]

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from tasks.md]

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- Do NOT modify the test files — only write implementation code
- #region tags required in _GameFolders/Scripts/
- **Architecture Drift (BLOCKING).** Before introducing any new pattern, scan for an existing one:
  - New service / manager → check `_Framework/` and `Games/Abstracts/` for an interface to implement; if one exists, use it instead of inventing a parallel system.
  - New event → check existing `IEvent` structs under `_GameFolders/Scripts/Games/Concretes/Events/`; reuse before creating.
  - New folder under `_GameFolders/Scripts/` → forbidden unless the TDD explicitly lists it. Stop and report BLOCKED with reason "ADR required: new folder `<path>` not in TDD".
  - New singleton, ServiceLocator, static manager, or `Object.FindObjectOfType` call → forbidden. VContainer only.
  - If the task description requires a pattern that contradicts the TDD → stop and report BLOCKED with reason "ADR required: `<conflict>`. Pause for human decision before proceeding."

## When Done
List every file you created or modified with a one-line summary.
Confirm all tests now pass.
Do NOT commit anything.
Report: DONE or BLOCKED with reason.
```

**Unity Setup prompt:**
```
You are a Unity scene architect setting up a specific task.

## Task
ID: [task id]
Title: [task title]
Description: [full task description from tasks.md]

## Input Files (read these first)
[list every input file path]

## Output Files (produce exactly these)
[list every output file path]

## Acceptance Criteria
[list every criterion from tasks.md]

## Rules
- Use Unity MCP tools for all scene/prefab work — do NOT read or edit .unity or .prefab files as raw text
- Check editor state first: mcpforunity://editor/state → wait until ready_for_tools == true
- Attach MonoBehaviours via MCP manage_components
- Register new components in the scene LifetimeScope installer

## Prefab Rules (NON-NEGOTIABLE — apply to every GameObject you create)
- Every GameObject placed in a scene must be a prefab instance
  — Exception: empty hierarchy organizers with no components (e.g. [Systems], [UI], [Gameplay])
- Save all prefabs under _GameFolders/Prefabs/<Domain>/  (Enemies/, Player/, UI/, VFX/, Environment/…)
- Root GameObject: logic components only (Provider, Controller, Collider, Rigidbody, injected MonoBehaviours)
- Body child GameObject: visual components only (MeshRenderer, SkinnedMeshRenderer, Animator, VFX)
- Never put Renderer components on the root; never put logic scripts on Body
- When multiple objects share the same base structure → create a base prefab first, then Prefab Variants
- Never duplicate a prefab manually — always use Prefab Variants

## Material Rules (NON-NEGOTIABLE)
- All material assets (.mat) must be saved under `Arts/Materials/<Domain>/` — NEVER inside `Prefabs/` folders
- Domain subfolder mirrors prefab domain: Items/, Environment/, Characters/, VFX/, UI/
- Every material must use a URP shader: `Universal Render Pipeline/Lit` or `Universal Render Pipeline/Simple Lit`
- Standard (Built-in) shader is FORBIDDEN — objects will render magenta in URP
- If you find a material using Standard shader → report as BLOCKED, do not proceed

## Canvas Prefab Rules (NON-NEGOTIABLE)
Before creating any Canvas prefab, check _GameFolders/Prefabs/UI/Canvases/ for an existing BaseCanvas.prefab:
- If BaseCanvas.prefab does NOT exist yet → create it first with: Canvas + CanvasScaler (Scale With Screen Size, 1080×1920, match 0.5) + GraphicRaycaster. Save to _GameFolders/Prefabs/UI/Canvases/BaseCanvas.prefab
- Every subsequent Canvas prefab (CanvasHUD, CanvasJoystick, CanvasOverlay, CanvasPopup, etc.) MUST be a Prefab Variant of BaseCanvas — NEVER a standalone prefab
- Variants override ONLY: Canvas.sortingOrder, Canvas.renderMode (if needed), and their own children
- If you find existing standalone Canvas prefabs that are NOT variants of BaseCanvas → stop and report this as a BLOCKED issue. Do not silently proceed

## Base Prefab Pattern — General (NON-NEGOTIABLE)
Before creating 2 or more prefabs of the same domain that share the same component set, check if a base prefab exists:
- If creating multiple Enemy prefabs → check for BaseEnemy.prefab first
- If creating multiple Obstacle prefabs → check for BaseObstacle.prefab first
- Same rule applies to any domain with 2+ structurally similar prefabs
- Signal: "these two prefabs would have the same components on root and Body child" → use Base + Variant

## When Done
List every scene/prefab/asset you created or modified.
Do NOT commit anything.
Report: DONE or BLOCKED with reason.
```

If **BLOCKED** → stop immediately. Print:
```
⚠ BLOCKED at [task id] Step 2 (Coder): [reason]
Fix this before continuing. Run /orchestrate [tasks.md path] to resume.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"coder","reason":"[reason]","timestamp":"[ISO8601]"}
```
Exit.

---

#### Step 3 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

**Reviewer prompt:**
```
You are acting as a CODE REVIEWER, not a fixer. Do not modify any file. Your only
output is a review verdict.

Review the following Unity C# implementation.

## Task
ID: [task id]
Title: [task title]

## Scope lock (MANDATORY)
Review ONLY the files listed under "Files Changed". Read each one in full before
judging it. Never run a bare `git diff` — scope every diff with explicit paths
(`git diff -- <path> <path>`). The orchestration ledger is NOT part of any task and
must never be reported as a scope violation: `.claude/**`, `docs/**`, `*.json`,
`*.jsonl`, `*.md` (unless a `.md` is itself listed under "Files Changed").

## Files Changed
[coder output — list of files with summaries]

## Acceptance Criteria (must all pass)
[list every criterion from tasks.md]

## Review Criteria
1. Tests pass — all pre-written tests pass; no test files were modified
2. Acceptance criteria — does the implementation satisfy all of them?
3. Architecture — VContainer DI, no singletons, interfaces only across modules
4. Naming — PascalCase types, _camelCase private fields
5. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
6. Events — IEvent structs past-tense + Event suffix, published via IEventBus
7. UniTask — no async void outside lifecycle, CancellationToken on every async method
8. Unity null safety — no ?. or is null on UnityEngine objects
9. Serialization — FormerlySerializedAs on any renamed [SerializeField]
10. **Architecture drift (BLOCKING)** — implementation must match the TDD: no new singletons, no `ServiceLocator`, no `FindObjectOfType`, no new folders under `_GameFolders/Scripts/` that aren't in the TDD, and no new event structs when an existing `IEvent` covers the case. If the diff introduces any of these without a paired ADR entry, the review must return **CHANGES NEEDED** with reason "Architecture drift: `<specific drift>` — open an ADR or revert."

## Output contract (MANDATORY — a verdict that violates this is invalid)
Emit one line per item, for EVERY acceptance criterion AND every one of the 10 review
criteria above. No item may be omitted, merged, or answered "n/a" without a stated
reason. Format:

  <ID> | CONFIRMED or GAP | <file>:<line> | <one sentence of evidence you actually read>

A CONFIRMED with no `file:line` is invalid. Restating the criterion back is not
evidence — cite what is actually in the file. Presence of a symbol is not evidence
that its contract is correct.

Then a final line:

  Verdict: APPROVED (only if zero GAP) or CHANGES NEEDED
```

> **Why this prompt is shaped this way — do not simplify it.** Measured on the
> piggy-doku module 03 T007a-d fixture (3 passes, 2026-08-18). With the old prompt
> Codex made 1 tool call, addressed 3 of 12 criteria, returned a reasonless APPROVED,
> and reported the orchestration ledger (`graph.json`, `EVENTS.jsonl`, `tasks.md` —
> the dirty worktree a bare `git diff` sweeps in) as a scope violation. A seeded
> known defect (a required field's contract doc removed) was **missed**. With the
> scope lock + per-item output contract above, the same agent on the same seeded
> fixture caught the defect (`GAP` with the exact line), produced 0 false positives,
> and answered all 14 items with `file:line`. The failure was the prompt's shape, not
> the Codex CLI.

On **CHANGES NEEDED** → automatically enter the review loop (no user prompt needed):

**Review Loop** (max 3 passes):

1. Spawn a **coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Task Context
   ID: [task id] — [task title]

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. Re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3.5 (Verifier).

4. If still **CHANGES NEEDED** after 3 passes → stop. Print remaining issues and ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

#### Step 3.5 — Bounded Verification

Spawn a **unity-verifier** subagent:

```
You are a Unity verification agent. Run a final bounded check on completed work.

## Task
ID: [task id]
Title: [task title]

## Files Changed
[list from coder output]

## Acceptance Criteria
[from tasks.md]

## Your Task (max 3 internal iterations)

### Step A — Compile & Assembly Check (BLOCKING — do not proceed past this if errors exist)
1. Call MCP `refresh_assets` to trigger a Unity recompile.
2. Call MCP `get_logs` (or equivalent) and read ALL console output.
3. Search for ANY of these patterns in the log output:
   - "error CS" — C# compiler errors
   - "Assembly" followed by "error" or "failed"
   - "has compiler errors" or "Scripts have compiler errors"
   - "is not allowed to reference" — assembly reference violation
   - Any line starting with "Error:" in the compiler output
4. If ANY compile or assembly error is found:
   - List every error with file path and line number
   - Attempt to fix the errors (max 2 fix attempts)
   - After each fix, call `refresh_assets` again and re-read logs
   - If errors persist after 2 fix attempts → Report: ISSUES FOUND (cannot fix) with full error list
   - Do NOT proceed to test run if compile errors remain

### Step B — Test Run (only if Step A passes with zero errors)
5. Call MCP `run_tests` and report results.
6. If tests fail → attempt fixes, re-run (max 2 attempts).

### Step C — Unity-Specific Issues (only if Steps A and B pass)
7. **Play Mode entry (BLOCKING).** Use MCP `manage_editor` to enter Play Mode. Wait up to 10 s for `editor_state.isPlaying == true`. If Play Mode never engages → report ISSUES FOUND with reason "PlayMode failed to start".
8. **Console error pattern scan (BLOCKING).** While in Play Mode for at least 2 frames, then exit Play Mode and call `read_console`. Search the full console output for ANY of:
   - `VContainerException` — DI binding missing
   - `NullReferenceException` originating from `_GameFolders/` or `_Framework/`
   - `MissingReferenceException`
   - `MissingComponentException`
   - Any log line at level `Error` containing `Installer`, `Resolve`, or `Bind`
9. If ANY of the patterns above appear:
   - Attempt to fix (max 2 attempts), re-enter Play Mode, re-scan.
   - If still present → Report: ISSUES FOUND with the full matching log lines.
   - Do NOT report VERIFIED while any pattern persists.
10. Quick scan for the remaining Unity-specific issues (missing SerializeField, event leaks, leftover Debug.Log spam). These are WARNING-level — list them but do not block.

If you find and fix issues, list them. If cannot fix, report blockers.
Report: VERIFIED or ISSUES FOUND with details.
```

**CRITICAL:** If the verifier reports compile or assembly errors and cannot fix them → the pipeline **MUST STOP**. Do NOT spawn the committer. Print:
```
⛔ BLOCKED at [task id] Step 3.5 (Verification): Assembly/compile errors found.
[paste error list]
Fix these errors before this task can be committed.
Run /orchestrate [tasks.md path] to resume after fixing.
```
Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_BLOCKED","id":"[task id]","step":"verifier","reason":"compile errors","timestamp":"[ISO8601]"}
```
Exit.

If **VERIFIED** → append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"VERIFICATION_PASSED","id":"[task id]","title":"[task title]","timestamp":"[ISO8601]"}
```
Then proceed to Step 4 Committer.

If **ISSUES FOUND** and fixed → append VERIFICATION_PASSED event and proceed to Step 4 Committer.

If **cannot fix** → stop. Print blockers and surface to developer before committing.

---

#### Step 4 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Task completed: `[task id]` — `[task title]`
- Files changed: `[coder/unity-setup output — list of files]`
- Run: `git status`, `git diff` to confirm what changed
- Stage only files related to this task
- Commit message format: `"feat: [task id] [task title]"`
- Do NOT push — user pushes manually
- Report: commit hash and message

---

#### After Each Task

Mark the checkbox in tasks.md:
```
- [ ] T001 [task title]  →  - [x] T001 [task title]
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"TASK_COMPLETED","id":"[task id]","title":"[task title]","commit":"[hash]","reviewer":"[Codex|Claude]","timestamp":"[ISO8601]"}
```

---

### Phase Gate (Checkpoint)

tasks.md'de `**Checkpoint:**` ile başlayan satırlar phase gate noktalarıdır.

Her Checkpoint'e ulaşıldığında:

1. Run the automated QA sequence below before asking the developer.

#### Step 1 — Ralph (compile + test green)

Spawn a **unity-verifier** subagent with this prompt:

```
Run a full compile and test check for the end of a phase.

1. Call MCP `refresh_assets` to trigger Unity recompile.
2. Call MCP `get_logs` and read ALL console output.
3. Search for ANY compile or assembly error:
   - "error CS" — C# compiler errors
   - "Assembly" with "error" or "failed"
   - "has compiler errors" / "Scripts have compiler errors"
   - "is not allowed to reference" — assembly violation
4. If ANY compile/assembly error found → list all errors. Attempt fixes (max 2). Re-check after each fix.
5. If errors persist → Report: COMPILE ERRORS with full list. Do NOT run tests.
6. If compile is clean → call MCP `run_tests` and report results.

Report: GREEN (compile clean, tests pass) or ERRORS (list all failures).
```

If failures found → spawn **unity-fixer** to fix, re-verify (max 3 passes). If still failing after 3 passes → **stop and report to user. Do not proceed to Step 2 until green.**

Print: `✓ Ralph passed — compile and tests green.` or `⛔ Ralph failed after 3 passes — [issues]. Fix before proceeding.`

#### Step 2 — Silent Failure Hunt

Spawn a **unity-linter** subagent with this prompt:

```
Audit all files changed in this checkpoint for silent failure patterns:
- catch blocks that swallow exceptions without logging
- async void outside Unity lifecycle methods
- IEventBus subscriptions without matching Unsubscribe
- UniTask.Forget() without an error handler
- empty catch blocks

Files to audit: [list of output files from this checkpoint's tasks]

Report each finding as: [file:line] — [pattern] — [fix]
If none found: CLEAN
```

Print findings or `✓ Silent failure hunt — CLEAN.`

#### Step 3 — Validate

Spawn a **general-purpose** subagent (`model: sonnet`) with the validate prompt:

```
You are a strict QA gate. Validate the tasks completed up to this checkpoint.

tasks.md checkpoint tasks and acceptance criteria: [paste from tasks.md]

Checks:
1. All output files exist at specified paths
2. Files are not empty or placeholder
3. Every acceptance criterion is met (read the code to verify)

Output:
PASS — all criteria met.
FAIL:
- [task] [criterion] — [what's missing]
```

If **FAIL** → print failures, ask user: `Validation failed. Fix issues and type "retry" to re-run QA, or "skip" to proceed anyway.`
- `retry` → restart from Step 1
- `skip` → proceed with warning logged

If **PASS** → proceed to developer prompt.

**If `superpowers:verification-before-completion` is available:** Invoke it now before reporting Checkpoint complete. Verify all acceptance criteria from tasks.md up to this checkpoint are genuinely met.

#### Step 4 — Developer Prompt

Print:
```
## Checkpoint: [checkpoint metni]
Ralph: green | Silent failures: [CLEAN / N findings] | Validate: PASS

Devam edilecek sonraki task'lar: [list]

Devam? (yes / no / stop)
```

**Wait for the developer's response.**
- `yes` → append to `docs/EVENTS.jsonl`:
  ```jsonl
  {"event":"CHECKPOINT_COMPLETED","checkpoint":"[checkpoint metni]","timestamp":"[ISO8601]"}
  ```
  Then continue to next tasks.
- `no` or `stop` → append to `docs/EVENTS.jsonl`:
  ```jsonl
  {"event":"ORCHESTRATION_PAUSED","checkpoint":"[checkpoint metni]","timestamp":"[ISO8601]"}
  ```
  Exit gracefully. Remind them to run `/orchestrate [tasks.md path]` to resume.

---

## Rules

- **Never skip acceptance criteria.** Re-read tasks.md criteria if a result is ambiguous.
- **Never continue past a BLOCKED task.** Fix it first.
- **Checkpoints are mandatory.** Always pause and ask at every `**Checkpoint:**` line.
- **One pipeline per task.** Never batch multiple tasks into one subagent call.
- **Subagents get no session history.** Write every prompt as if they know nothing about this conversation.
- **Reviewer tries Codex first.** Fall back to unity-reviewer if Codex is unavailable.

---

## On Completion

Run: `rm -f "$(git rev-parse --show-toplevel)/.claude/state/gate-cleared"`

Update `docs/ROADMAP.md` — ilgili modül satırını bul ve Status'u güncelle: `→ ✅ Complete`

```
## Orchestration Complete

tasks.md: [path]
Tamamlanan task'lar: [N]
Skip edilen (zaten tamamlanmış): [M]

Sıradaki adım: /roadmap ile ROADMAP.md'yi güncelle
```

Append to `docs/EVENTS.jsonl`:
```jsonl
{"event":"ORCHESTRATION_COMPLETE","plan":"[tasks.md path]","tasks":[N],"skipped":[M],"timestamp":"[ISO8601]"}
```

$ARGUMENTS
