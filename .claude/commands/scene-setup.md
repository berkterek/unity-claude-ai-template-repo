# /scene-setup — Coder + Unity Setup → Reviewer → Committer Pipeline

Sets up a new scene or prefab: coder writes the C# scripts, unity-setup wires everything in the Unity Editor via MCP, reviewer checks, committer commits.

**Scene hierarchy standard:** All scenes built by this command follow `.claude/rules/scene-hierarchy.md` — six standard containers (`[Setup]`, `[Services]`, `[UI]`, `[Environment]`, `[Characters]`, `[VFX]`) are created first, every GO is placed in the correct container, every GO is a prefab instance.

## Usage

```
/scene-setup <description>
/scene-setup set up the GameScene with BayManager, FlowEngine, and 5 bay prefabs
```

If no argument is given, ask: "What needs to be set up in the scene?"

## Step 0 — Plugin Preflight

Check which of these plugins are available in the skill list:

| Plugin | Used in | Fallback |
|--------|---------|---------|
| `superpowers:brainstorming` | Step 0a — design exploration before coder (complexity ≥ 0.7) | Skip brainstorming |

Print availability status before proceeding:
```
Plugins: superpowers:brainstorming [✓/✗]
```

---

## Step 0a — MCP Preflight

Read and apply `.claude/skills/core/mcp-preflight.md`.

- **State 1** (connected) → continue to complexity scoring
- **State 2** (disconnected) → stop; offer to run code-only (skip unity-setup step 1b, list manual wiring steps instead)
- **State 3** (not installed) → skip Step 1b entirely; after coder completes, print manual wiring checklist

---

## Step 0b — Complexity Scoring & Review Mode

Read `production/review-mode.txt` (default: `lean` if file missing). This controls pipeline depth:

| Mode | Effect |
|------|--------|
| `solo` | Reviewer and unity-developer skipped — unity-coder/unity-coder-lite → unity-setup → committer only. |
| `lean` | Standard pipeline. For regular solo development. |
| `full` | Standard pipeline + unity-developer second reviewer always active (regardless of complexity score). For team review or learning sessions. |

Set mode by editing `production/review-mode.txt`. Print the active mode before proceeding.

Before spawning any agents, score the task complexity on a 0.0–1.0 scale:

| Score | Label | Signals | Coder Agent |
|-------|-------|---------|-------------|
| 0.0–0.3 | **Simple** | Single MonoBehaviour, no new interfaces, no DI wiring | **unity-coder-lite** |
| 0.4–0.6 | **Medium** | 2–4 scripts, new interface, or LifetimeScope installer | **unity-coder** |
| 0.7–1.0 | **Complex** | New module, cross-system events, ECS, or Addressables | **unity-coder** + unity-developer review |

Scene setup always targets Unity/Mixed code — `coder` agent is never used here.

**Scoring signals:**
- Creates a new module folder? +0.3
- Adds or modifies IEventBus events? +0.2
- Touches ECS systems or Addressables? +0.3
- Modifies AppScope, InputView, or an Installer? +0.2
- Single MonoBehaviour with no dependencies? −0.3

**Print before proceeding:**
```
Complexity: [score] — [Label]
Rationale: [one sentence]
Coder Agent: [unity-coder-lite | unity-coder]
Review Mode: [solo | lean | full]
```

**Step 0c — Brainstorming (Complex tasks only)**

If complexity score ≥ 0.7 AND `superpowers:brainstorming` is available → invoke `superpowers:brainstorming` before spawning the coder. Use it to explore alternative scene/prefab structures and VContainer scope placement. Document the chosen approach in one paragraph, then proceed.

If the task creates a new module folder (complexity score includes the +0.3 new-module signal): fire **ARCHITECTURE_GATE** immediately (see `.claude/docs/director-gates.md`). Show the proposed module/prefab structure and wait for `go`.

### SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: scene setup description, complexity score, expected scripts and Unity assets.
Wait for `go` before spawning any agents.

After receiving `go` → run:
```bash
mkdir -p .claude/state && echo '{"gate":"SCOPE_GATE","pipeline":"scene-setup","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > .claude/state/gate-cleared
```

For **Complex** tasks (score ≥ 0.7) in `lean` or `full` mode: after reviewer APPROVED, spawn a **unity-developer** subagent review pass before the committer.

---

## Pipeline

```
[1a] CODER (C# scripts)
[1b] UNITY-SETUP (scene/prefab wiring via MCP)  ← runs after coder
[2]  REVIEWER ⟲ (loop until APPROVED)
[2.5] UNITY-VERIFIER (bounded compile + scene/prefab integrity check)
[3]  COMMITTER
```

---

## Step 1a — Coder

Spawn the coder agent determined in Step 0 (**unity-coder-lite** for Simple, **unity-coder** for Medium/Complex) with this prompt:

```
You are a senior C# Unity developer. Write the C# scripts needed for the following Unity scene setup.

## Scene Setup Task
$SETUP_DESCRIPTION

## Project Rules
- Read .claude/CLAUDE.md before writing any code
- Follow all rules in .claude/rules/
- No singletons — VContainer only (register in scene LifetimeScope installer)
- No coroutines — UniTask only
- MonoBehaviour components must use [Inject] public void Construct(...)
- sealed classes by default

## Scope
Write ONLY C# script files (.cs). Do NOT modify scenes or prefabs — that is handled separately.

## When Done
List every .cs file you created with a one-line summary.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 1b — Unity Setup

Spawn a **unity-setup** subagent with this prompt:

```
You are a Unity scene architect. Wire up the scene and prefabs for the following task.

## Scene Setup Task
$SETUP_DESCRIPTION

## C# Scripts Already Created
$CODER_OUTPUT

## Your Responsibilities
- Use Unity MCP tools to create/modify GameObjects, add components, set references
- Create prefabs as needed
- Attach the new C# MonoBehaviour components to appropriate GameObjects
- Set up the scene LifetimeScope installer with the new VContainer registrations
- Do NOT edit .unity or .prefab files as raw text — use MCP tools only

## Canvas Prefab Rules (NON-NEGOTIABLE)
Before creating any Canvas prefab, check `_GameFolders/Prefabs/UI/Canvases/BaseCanvas.prefab`:
- If it does NOT exist → create BaseCanvas first: `Canvas` + `CanvasScaler` (Scale With Screen Size, 1080×1920, match 0.5) + `GraphicRaycaster`
- Every Canvas prefab MUST be a Prefab Variant of BaseCanvas — NEVER standalone
- Variants override only: `Canvas.sortingOrder`, `Canvas.renderMode`, and their own children

## Base Prefab Rule
Before creating 2+ prefabs in the same domain that share the same component structure → create a Base prefab first, then Prefab Variants. Never duplicate independently.

## When Done
List every scene/prefab/asset you created or modified.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 2 — Reviewer

Reviewer priority — try in order, fall back if unavailable:
1. Spawn Agent with `subagent_type: "codex:codex-rescue"`
2. Spawn Agent with `subagent_type: "unity-reviewer"` (fallback if Codex unavailable)

```
Review this Unity scene setup implementation.

## Task
$SETUP_DESCRIPTION

## C# Files Created
$CODER_OUTPUT

## Unity Assets Modified
$UNITY_SETUP_OUTPUT

## Review Criteria (C# only — Unity assets cannot be reviewed as text)
1. Architecture — VContainer DI, [Inject] Construct pattern on MonoBehaviours
2. Naming — PascalCase types, _camelCase private fields
3. No Unity API in service/domain classes
4. UniTask — no async void, CancellationToken on every async method
5. Unity null safety — no ?. or is null on UnityEngine objects

## Output Format
APPROVED or CHANGES NEEDED with file:line issues.
```

### Review Loop

Repeat until APPROVED or stopped (max 3 passes):

1. If reviewer reports **CHANGES NEEDED** → spawn a **coder** subagent to fix every listed issue:
   ```
   You are a senior C# Unity developer. Fix the following review issues.

   ## Original Scene Setup Task
   $SETUP_DESCRIPTION

   ## Review Feedback (fix ALL of these)
   $REVIEWER_FEEDBACK

   ## Rules
   - Fix only what the reviewer flagged — do not refactor anything else
   - Only modify .cs files — do not touch scene or prefab files
   - Read .claude/CLAUDE.md before making changes

   ## When Done
   List every file you changed with a one-line summary.
   Report: DONE or BLOCKED with reason.
   ```

2. After coder fixes → re-run the reviewer using the same priority order (codex:codex-rescue → unity-reviewer) with the updated files.

3. If APPROVED → proceed to Step 3.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 2.5 — Bounded Verification

Spawn a **unity-verifier** subagent:

```
You are a Unity verification agent. Run a final bounded check on this scene/prefab setup.

## Scene Setup Task
$SETUP_DESCRIPTION

## Files Changed
$CODER_OUTPUT
$UNITY_SETUP_OUTPUT

## Your Task (max 3 internal iterations)
1. Compile check via MCP refresh_assets
2. Verify scene/prefab integrity: prefab instances in scene (no bare GameObjects), root=logic/Body=visual separation, domain folder placement under _GameFolders/Prefabs/<Domain>/
3. Quick scan for Unity-specific issues in C# files (null refs, missing SerializeField, event leaks)

If you find and fix issues, list them. If cannot fix, report blockers.
Report: VERIFIED or ISSUES FOUND with details.
```

If **VERIFIED** → proceed to Step 3 Committer.
If **ISSUES FOUND** and fixed → proceed to Step 3 Committer.
If **cannot fix** → stop and surface blockers to the developer before committing.

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: setup description, all changed .cs and Unity asset files, reviewer verdict, verifier verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 3 — Committer

**Execute commits directly.** Read `.claude/agents/committer.md` for full conventions, then:

- What was set up: `$SETUP_DESCRIPTION`
- Files changed: `$CODER_OUTPUT` + `$UNITY_SETUP_OUTPUT`
- Run: `git status`, `git diff`
- Stage all related `.cs`, `.unity`, `.prefab`, `.asset`, `.meta` files
- Commit message format: `"feat: <short description in English>"`
- Do NOT push; report: commit hash and message

---

## Completion

Run: `rm -f .claude/state/gate-cleared`

Print:
```
## ✓ Scene Setup Complete
Task: [description]
Scripts: [count] files
Unity assets: [count] files
Commit: [hash] — [message]
Reviewer: [Codex | Claude] — APPROVED
```

$ARGUMENTS
