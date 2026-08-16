# Director Gates — Centralized Review Prompts

Named review gates used across pipeline commands. Two kinds:

- **Human-pause gates** (SCOPE_GATE, ARCHITECTURE_GATE, BREAKING_GATE, QUALITY_GATE, COMMIT_GATE) — stop the pipeline and wait for user approval before continuing.
- **Automated check gates** (TD-ARCHITECTURE, TD-UNITY-RISK, TD-PERFORMANCE, TD-COMPILE, CD-SCOPE) — spawn a reviewer subagent and evaluate verdict automatically.

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
  Installer:  [ModuleName]Installer.cs (ModuleInstaller)
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
  skip   — accept and proceed to commit (your responsibility)
  stop   — abort, leave files uncommitted
──────────────────────────────────────────────────────────
```

Wait for response. Act accordingly.

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

## Automated Check Gates

These gates spawn a subagent or run a check automatically. They do not pause for user input unless the verdict is FAIL/RISK.

---

### TD-ARCHITECTURE

**Trigger:** After any implementation — verify structural integrity.
**Context to pass:** Task description, files changed, relevant architecture rules.

**Verdict:** `PASS` — architecture is sound. `FAIL: [file:line] issue` — specific violation.

Checks:
- VContainer DI: no singletons, no static mutable state, no service locators
- Interface-driven: consumers depend on interfaces, not concrete types
- IEventBus: cross-module communication only through events, not direct calls
- Provider pattern: UnityEngine API in Games/Concretes/ only, services are pure C#
- Module boundaries: no concrete cross-module dependencies

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

Checks:
- Zero heap allocations in Update/FixedUpdate/LateUpdate (no `new`, no boxing, no LINQ, no string ops)
- `renderer.material` not used (clones material) — use `sharedMaterial` or `MaterialPropertyBlock`
- ECS structural changes use ECB, not direct `EntityManager` calls inside systems
- Addressables handles stored as fields and released in `Dispose()`
- `Camera.main`, `GetComponent<T>()` cached in Awake — not called per frame

---

### TD-COMPILE

**Trigger:** After every coder pass — mandatory before reviewer.
**Context to pass:** Files changed.

**Verdict:** `VALIDATED` — clean compile and all tests pass. `COMPILE FAILED: [errors]` or `TEST FAILED: [tests]`

Steps:
1. `mcp__unityMCP__refresh_unity` — trigger recompile
2. Poll `editor_state` until `isCompiling` is false
3. `mcp__unityMCP__read_console` with type `Error` — check for errors
4. If clean → `mcp__unityMCP__run_tests` — run Edit Mode tests
5. Report VALIDATED or list failures

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
