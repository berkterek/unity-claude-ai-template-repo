# /implement — Test Writer → Coder → Reviewer → Committer Pipeline

Implements a feature or task using a four-agent TDD pipeline: test writer writes failing tests first, coder implements to pass them, reviewer checks, committer commits.

## Usage

```
/implement <task description>
/implement add BoxCollectedEvent publishing to BayManager
```

If no argument is given, ask: "What needs to be implemented?"

## Pipeline

```
[1] TEST WRITER → [2] CODER → [3] REVIEWER ⟲ (loop until APPROVED) → [3.7] SILENT FAILURE AUDIT → [4] COMMITTER
```

---

## Step 0 — Flag Detection & Plugin Preflight

**Read `$ARGUMENTS` and detect flags:**

```
Check $ARGUMENTS for --heavy flag → if present, set FORCE_OPUS_TIER=true
Check $ARGUMENTS for --lite flag  → if present, set FORCE_HAIKU_TIER=true
```

Strip the flags from `$ARGUMENTS` before passing the task description to any agent prompt.

**Plugin availability check:**
Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:test-driven-development` | Step 0c — TDD constraint setup | Proceed with built-in test-type-router only |
| `superpowers:brainstorming` | Complex tasks (score ≥ 0.7) — design exploration before coding | Skip brainstorming |
| `code-simplifier` | Post-implementation quality pass | Skip simplification step |
| `claude-md-management:revise-claude-md` | Completion — update CLAUDE.md with learnings | Skip |

Print availability status before proceeding:
```
Plugins: superpowers:test-driven-development [✓/✗] | superpowers:brainstorming [✓/✗] | code-simplifier [✓/✗] | claude-md-management [✓/✗]
```

---

## Step 0.5 — MCP Preflight

Read and apply `.claude/skills/core/mcp-preflight.md`.

- **State 1** (connected) → continue; unity-verifier will use MCP for compile + test checks
- **State 2** (disconnected) → stop; offer to run pipeline without MCP validation (Steps 2.5 and 3.5 will fall back to dotnet CLI)
- **State 3** (not installed) → continue in code-only mode; Steps 2.5 and 3.5 use dotnet CLI fallback automatically

---

## Step 0a — Brainstorming (Complex tasks only)

If complexity score ≥ 0.7 AND `superpowers:brainstorming` is available → invoke `superpowers:brainstorming` before writing any code. Use it to surface design alternatives and tradeoffs for the new module or cross-system feature. Document the chosen approach in one paragraph, then proceed.

---

## Step 0a — Knowledge Graph Query

If `.claude/project-features.json` has `graph == true` AND `.claude/graph/graph.json` exists:

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

Keep this output in your active context as `GRAPH_CONTEXT`. You will embed it into subagent prompts below.

If graph is disabled or missing → set `GRAPH_CONTEXT` to empty, proceed.

---

## Step 0b — Complexity Scoring

**Step 0c — Read Review Mode**

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | Skip Test Writer and Reviewer — Coder → Committer only. For prototypes/jams. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the task complexity on a 0.0–1.0 scale and decide the pipeline variant:

| Score | Label | Signals | Pipeline |
|-------|-------|---------|----------|
| 0.0–0.3 | **Simple** | Single class, no new interfaces, no DI wiring, no events | → ask user (see Simple routing block below) |
| 0.4–0.6 | **Medium** | 2–4 classes, new interface, or touches existing event bus | Full pipeline: Test Writer → Coder → Reviewer → Committer |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS integration, or Addressables | Full pipeline + unity-developer reviewer (always active in `full` mode, or when score ≥ 0.7 in `lean` mode) |

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single method addition to existing class? −0.3

**Simple routing (score < 0.3):** Stop the /implement pipeline and show:

```
Complexity: [score] — Simple
This task is small enough for a lighter run.
  continue   — proceed with full /implement pipeline (or re-run with --lite flag for a lighter coder)
  stop       — cancel
```

- `continue` → proceed with full /implement pipeline below
- `stop` → abort
- User may also re-invoke with `--lite` flag to use the haiku-tier coder

**Print before proceeding (Medium/Complex):**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Pipeline: [which variant]
```

If the task creates a new module folder (complexity score includes the +0.3 new-module signal): fire **ARCHITECTURE_GATE** immediately after printing the complexity block (see `.claude/docs/director-gates.md`). Show the proposed module structure (interface, service, config, installer, events) and wait for `go` before continuing.

---

## Step 0c — Test Type Routing

Read `.claude/skills/core/test-type-router.md` and apply the decision matrix to the task target.

Extract the target class or file path from `[INSERT HERE: the task description from the /implement argument]`. Run the router and emit:

```
TEST TYPE DECISION
  Target:   [class name or file path]
  Decision: [EditMode | PlayMode-ECS | PlayMode-Scene | NoTest]
  Reason:   [one sentence]
```

- **NoTest** → skip Step 1 (Test Writer) entirely; proceed directly to Step 2 (Coder)
- **PlayMode-Scene** → Test Writer writes the stub only; note that `/create-test` must be run separately for scene + TestBootstrap wiring
- **EditMode** or **PlayMode-ECS** → proceed normally; Test Writer uses the correct assembly

---

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: task description, complexity score, and known affected files (if any).
Wait for `go` before spawning any agents.

After receiving `go` → run:
```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"implement","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
```

---

For **Complex** tasks: after the standard Reviewer step passes, spawn a **unity-developer** subagent with the same changed files list and the review criteria from `.claude/agents/unity-developer.md` before proceeding to the Committer.

---

## Step 1 — Test Writer

Spawn Agent with `subagent_type: "claude"` with this prompt:

```
Read .claude/agents/tester.md for your role and testing philosophy.
Read .claude/rules/testing.md for project-specific rules — these override tester.md where they conflict.
Read .claude/CLAUDE.md for project architecture.

## Knowledge Graph (class/interface/event/installer inventory — use instead of scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0a — if empty, write "No graph available, scan source files."]

## Project overrides (take precedence over tester.md)
- Use NSubstitute for mocking, not hand-rolled fakes
- Only mock interfaces, never concrete classes

## Task
[INSERT HERE: the task description from the /implement argument]

## Your job
1. Identify what class(es) and method(s) this task requires.
2. Write all tests that define the expected behavior — they must FAIL right now (no implementation yet).
3. Do NOT write any implementation code.

When done: list every test file created with a summary of what each covers.
Report: DONE or BLOCKED with reason.
```

If test writer reports **BLOCKED** → stop, show the blocker to the user, do not continue.

---

## Step 2 — Coder

**Agent routing — decide before spawning:**

| Target location | Agent |
|-----------------|-------|
| `_Framework/`, `Games/Abstracts/`, `Games/Concretes/` (no Unity API) | **coder** |
| MonoBehaviour, Provider, Installer, scene wiring, Unity lifecycle | **unity-coder** |
| Mixed (both pure C# and Unity glue) | **unity-coder** |

If the task targets `_Framework/` or pure C# service/interface code with no Unity API, spawn a **coder** subagent. Otherwise spawn a **unity-coder** subagent.

**Tier override (apply after agent type is decided):**

```
If FORCE_HAIKU_TIER == true  → spawn the chosen agent with model: haiku
Else if FORCE_OPUS_TIER == true → spawn the chosen agent with model: opus
Else                         → spawn the chosen agent (default sonnet tier)
```

```
You are a senior C# Unity developer. Implement the following task.

## Task
[INSERT HERE: the task description from the /implement argument]

## Knowledge Graph (class/interface/event/installer inventory — use instead of scanning source files)
[INSERT HERE: the GRAPH_CONTEXT output from Step 0a — if empty, write "No graph available, scan source files."]

## Existing Tests (make these pass)
[INSERT HERE: the full output from the Test Writer agent]

## Project Rules (read first)
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/ (architecture, csharp-unity, performance, serialization, unity-specifics)
- No singletons — VContainer only
- No coroutines — UniTask only
- No legacy Input API
- sealed classes by default
- IEventBus for cross-system communication
- #region tags required in _GameFolders/Scripts/
- Do NOT modify the test files — only write implementation code

## When Done
List every file you created or modified with a one-line summary of the change.
Confirm all tests now pass.
Report: DONE or BLOCKED with reason.
```

If coder reports **BLOCKED** → stop, show the blocker to the user, do not continue.

---

## Step 2.5 — Unity Validator (MANDATORY — runs before Reviewer)

Spawn a **unity-verifier** subagent with this prompt:

```
You are a Unity build validator. Your only job is to verify that the project compiles and all tests pass.

## What Was Implemented
[INSERT HERE: the task description from the /implement argument]

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Instructions
1. Use `mcp__unityMCP__refresh_unity` to trigger a script recompile.
2. Wait until `isCompiling` is false (poll `editor_state` resource).
3. Use `mcp__unityMCP__read_console` with type "Error" to check for compile errors.
4. If compile errors exist → report COMPILE FAILED with the full error list. Stop here.
5. If compile is clean → use `mcp__unityMCP__run_tests` to run all Edit Mode tests.
6. Check test results for any failures.
7. If any tests fail → report TEST FAILED with test names and failure messages. Stop here.
8. If all tests pass → report VALIDATED.

## Output Format
VALIDATED — zero compile errors, all tests pass.

COMPILE FAILED:
- [error message] — [file:line]

TEST FAILED:
- [test name] — [failure message]
```

### Validator Loop (max 2 fix passes)

If validator reports **COMPILE FAILED** or **TEST FAILED** → spawn a **unity-coder** subagent to fix the issues:

```
You are a senior C# Unity developer. Fix the following build or test failures.

## Original Task
[INSERT HERE: the task description from the /implement argument]

## Failures (fix ALL of these)
[INSERT HERE: the full COMPILE FAILED or TEST FAILED output from the Unity Validator]

## Rules
- Fix only what is listed — do not refactor anything else
- For assembly definition issues: check that the test assembly references the correct game assembly and has NSubstitute in precompiledReferences with overrideReferences: true
- For compile errors: fix the exact file:line reported
- For test failures: fix the implementation, never change the test

## When Done
List every file you changed. Report: DONE or BLOCKED.
```

After unity-coder fixes → re-run the **Unity Validator** on the updated files.

If still failing after **2 fix passes** → stop and show the user all errors. Ask:
- `skip` → proceed to reviewer anyway (user accepts responsibility)
- `stop` → abort

---

## Step 3 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

```
Review the following Unity C# implementation.

## What Was Implemented
[INSERT HERE: the task description from the /implement argument]

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Review Criteria
1. Tests — all pre-written tests pass; no test files were modified
2. Architecture — VContainer DI, no singletons, interfaces only across modules
3. Naming — PascalCase types, _camelCase private fields
4. Performance — no allocations in Update/FixedUpdate, no LINQ on hot paths
5. Events — IEvent structs past-tense with Event suffix, published via IEventBus
6. UniTask — no async void outside lifecycle, CancellationToken on every async method
7. Unity null safety — no ?. or is null on UnityEngine objects
8. Serialization — FormerlySerializedAs on any renamed [SerializeField]

## Output Format
APPROVED — if all criteria pass, nothing to change.

CHANGES NEEDED:
- [file:line] Issue description and fix.
(list every issue)
```

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **unity-coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Original Task
   [INSERT HERE: the task description from the /implement argument]

   ## Review Feedback (fix ALL of these)
   [INSERT HERE: the full CHANGES NEEDED list from the Reviewer]

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After unity-coder fixes → re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3.5.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to verifier (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 3.5 — Unity Verifier (Final Bounded Check)

Spawn a **unity-verifier** subagent once with this prompt (max 3 internal iterations):

```
You are a Unity post-implementation verifier. Perform a final bounded check on the delivered implementation.

## What Was Implemented
[INSERT HERE: the task description from the /implement argument]

## Files Changed
[INSERT HERE: the list of files modified by the Coder agent]

## Instructions
Run up to 3 internal fix-check iterations. In each iteration:
1. Use `mcp__unityMCP__refresh_unity` and wait for compile to finish.
2. Check `mcp__unityMCP__read_console` for errors.
3. Run `mcp__unityMCP__run_tests` and check for failures.
4. Verify prefab structure is intact: root holds logic components, Body child holds visual components.
5. If compile errors or test failures exist and iterations remain — fix and re-check.
6. If clean after any iteration → stop and report VERIFIED.
7. If still failing after 3 iterations → report VERIFY FAILED with all remaining issues.

## Output Format
VERIFIED — compile clean, all tests pass, prefab structure valid.

VERIFY FAILED:
- [issue description]
```

If unity-verifier reports **VERIFY FAILED** → stop and show the user all remaining issues. Ask:
- `skip` → proceed to commit (user accepts responsibility)
- `stop` → abort

---

## Step 3.6 — Play Mode Smoke Test (NON-SKIPPABLE)

> **Ders:** Derleme ve testlerin geçmesi runtime davranışını garanti etmez. TapToStartView.cs vakasında yanlış state koşulu (TapToStart yerine Idle) yazıldı — derleyici hata vermedi, reviewer kaçırdı, ama Play mode'da 10 saniyede görülürdü. 3 fix döngüsü yaşandı.

**Bu adım her zaman kullanıcıdan manuel onay alır. Code review veya derleme başarısı bu adımın yerini tutamaz.**

Show the user this message:

```
⚠️  Play Mode Smoke Test — Manuel Adım

Lütfen Unity'de şunları kontrol et:
  1. Play moduna gir
  2. [INSERT HERE: 1-2 cümleyle ne görülmesi/olması gerektiği — implement edilen feature'dan türet]
  3. Console'da hata veya beklenmedik davranış var mı?

Sonuç:
  ok    — devam et
  fail  — sorunu açıkla, düzeltelim
```

Wait for `ok` or `fail`. On `fail` → spawn unity-coder with the reported issue, then repeat from Step 3.5 and Step 3.6.

---

## Step 3.7 — Silent Failure Audit

Spawn a **silent-failure-hunter** subagent with this prompt:

```
Audit the following C# files for silent failure patterns:

FILES: [INSERT HERE: the list of files modified by the Coder agent]

Check for:
1. catch blocks that swallow exceptions without logging or rethrowing
2. async void outside Unity lifecycle methods (Awake, Start, OnEnable, OnDisable, OnDestroy)
3. IEventBus subscriptions (Subscribe<T>) without a matching Unsubscribe<T> in Dispose/OnDisable
4. UniTask.Forget() calls without an onException error handler
5. Empty catch blocks: catch { } or catch (Exception) { }

For each finding:
- [file:line] — [pattern type] — [description] — [suggested fix]

If nothing found: CLEAN
```

If hunter reports **CLEAN** → proceed to Committer.

If hunter reports findings → show them to the user. Ask:
```
Silent failure issues found. Options:
  fix   — spawn unity-coder to address findings, then re-audit once
  skip  — accept and proceed to commit
  stop  — abort
```

- `fix` → spawn **unity-coder** with all findings as a fix list, then re-run hunter once. Proceed to committer regardless of result.
- `skip` → proceed to committer.
- `stop` → abort.

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: task description, all changed files, reviewer verdict, verifier verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 4 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- Task implemented: `[INSERT HERE: the task description from the /implement argument]`
- Files changed: `[INSERT HERE: the list of files modified by the Coder agent]`
- Run: `git status`, `git diff` to confirm all changes
- Stage only files related to this task
- Commit message format: `"feat: <short description in English>"`
- One commit unless changes are clearly separable into logical units
- Do NOT push — user pushes manually
- Report: commit hash and message when done

---

## Completion

Run: `rm -f .claude/state/gate-cleared`

If `superpowers:verification-before-completion` is available → invoke it before reporting done.

If `claude-md-management:revise-claude-md` is available → invoke it to update CLAUDE.md with any new patterns or constraints discovered during this implementation.

If `code-simplifier` is available → run a final simplification pass on all changed files.

Print:
```
## ✓ Implemented
Task: [task description]
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
Plugins used: [list of plugin skills invoked, or "none"]
```

$ARGUMENTS
