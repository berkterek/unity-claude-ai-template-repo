# /scene-setup — Coder + Unity Setup → Reviewer → Committer Pipeline

Sets up a new scene or prefab: coder writes the C# scripts, unity-setup wires everything in the Unity Editor via MCP, reviewer checks, committer commits.

## Usage

```
/scene-setup <description>
/scene-setup set up the GameScene with BayManager, FlowEngine, and 5 bay prefabs
```

If no argument is given, ask: "What needs to be set up in the scene?"

## Pipeline

```
[1a] CODER (C# scripts)
[1b] UNITY-SETUP (scene/prefab wiring via MCP)  ← runs after coder
[2]  REVIEWER ⟲ (loop until APPROVED)
[3]  COMMITTER
```

---

## Step 1a — Coder

Spawn a **coder** subagent with this prompt:

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

## When Done
List every scene/prefab/asset you created or modified.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user.

---

## Step 2 — Reviewer

First try **Codex** (`codex:rescue` subagent):

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

If Codex unavailable → fall back to **reviewer** subagent.

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

2. After coder fixes → re-run the reviewer (Codex first, fall back to reviewer agent) with the updated files.

3. If APPROVED → proceed to Step 3.

4. If still **CHANGES NEEDED** after 3 passes → stop and show the user all remaining issues. Ask:
   - `skip` → proceed to commit (user accepts responsibility)
   - `stop` → abort, leave files uncommitted

---

## Step 3 — Committer

Spawn a **committer** subagent with this prompt:

```
You are a release engineer. Commit this scene setup.

## What Was Set Up
$SETUP_DESCRIPTION

## Files Changed
$CODER_OUTPUT
$UNITY_SETUP_OUTPUT

## Rules
- Run: git status, git diff
- Stage all related .cs, .unity, .prefab, .asset, .meta files
- Commit message format: "feat: <short description in English>"
- Do NOT push
- Report: commit hash and message
```

---

## Completion

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
