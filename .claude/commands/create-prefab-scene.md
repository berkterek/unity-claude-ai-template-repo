# /create-prefab-scene — Legacy Scene Migration → Prefab Inventory → Prefab Creation → Review → Commit

**Use this command to retroactively migrate existing scenes** that contain bare (non-prefab) GameObjects — e.g. scenes created before the prefab rules were in place, imported from asset store, or built outside this template.

For new development, prefab rules are already enforced by `orchestrate` and `add-feature` at creation time. This command is a one-time cleanup tool, not part of the normal workflow.

Analyzes every scene under `_Scene/`, identifies bare GameObjects, builds a prefab inventory (what to create, what should be a variant), creates all prefabs via MCP following the project's prefab rules, then reviews and commits.

## Usage

```
/create-prefab-scene
/create-prefab-scene Assets/_Scene/GameScene.unity   ← target a single scene
```

If no argument is given, scan ALL `.unity` files under `Assets/_Scene/`.

---

## Step 0 — SCOPE_GATE

Show the user the SCOPE_GATE block from `.claude/docs/director-gates.md`.
Pass: target scene(s), operation ("legacy scene migration — bare GameObjects → prefabs").
Note: this operation modifies scenes and creates prefab assets — partially reversible via git, but MCP scene changes are harder to undo.
Wait for `go` before proceeding.

---

## Step 0b — MCP Preflight

Read and apply `.claude/skills/core/mcp-preflight.md`.

- **State 1** (connected) → continue
- **State 2** (disconnected) → stop; scene inspection and prefab creation require MCP. Print: "Open Unity Editor, activate the MCP plugin, and run `/create-prefab-scene` again."
- **State 3** (not installed) → stop with the same message; all steps depend on MCP scene queries

---

## Pipeline

```
[1] ANALYZER      → Opens scenes via MCP, queries hierarchy + components
[2] PLANNER       → builds PrefabInventory.md (what to create, what's a variant)
[3] UNITY-SETUP   → creates prefabs via MCP following prefab rules
[4] UNITY-DEV     → reviews prefab structure (prefab rules 8-10)
[5] COMMITTER     → commits
```

---

## Step 1 — Analyzer

**Do NOT read `.unity` files as raw text or YAML. All scene inspection must go through MCP tools.**

For each target scene:

1. Check editor is ready: read `mcpforunity://editor/state` → wait until `ready_for_tools == true`
2. Open the scene: `manage_scene(action="open", scene_path="<path>")`
3. Get the full hierarchy with pagination:
   ```
   manage_scene(action="get_hierarchy", page_size=50, cursor=0)
   → repeat with next_cursor until exhausted
   ```
4. For each GameObject in the hierarchy, read its full data:
   ```
   mcpforunity://scene/gameobject/{instance_id}
   ```
   Extract: name, components list, parent, whether it is a prefab instance, tag, layer.
5. Identify organizers: GameObjects with **no components other than Transform** and a bracketed name (`[Systems]`, `[UI]`, `[Gameplay]`, etc.) → mark exempt.
6. Identify prefab instances: GameObjects where `prefab_asset_path` is non-empty → mark as already correct.
7. Identify bare GameObjects: everything else (not organizer, not prefab instance).

Then produce a **Scene Analysis Report** in this format for each scene:

```
## Scene: <SceneName>

### All GameObjects
| Name | Parent | Components | Prefab Instance? |
|------|--------|------------|-----------------|
| Player | (root) | Transform, PlayerProvider, CapsuleCollider, Rigidbody | NO |
| Body | Player | Transform, SkinnedMeshRenderer, Animator | NO |
| Enemy_01 | Enemies | Transform, EnemyProvider, CapsuleCollider | NO |
| Enemy_02 | Enemies | Transform, EnemyProvider, CapsuleCollider | NO |
| [Systems] | (root) | Transform | (organizer — exempt) |
...

### Bare GameObjects (need prefabs — excluding organizers)
- Player (with Body child)
- Enemy_01
- Enemy_02
...

### Already Prefab Instances
- MainCamera → Assets/_GameFolders/Prefabs/...
...

### Relationship Map (who shares components with whom)
- Enemy_01, Enemy_02 → same components → candidate for BaseEnemy prefab + variants
- Player → unique → standalone prefab
...
```

**Organizer rule:** Empty GameObjects with no components other than `Transform` and a name in brackets like `[Systems]`, `[UI]`, `[Gameplay]` → mark as `(organizer — exempt)`, do NOT create prefabs for these.

---

## Step 2 — Planner

Based on the Scene Analysis Report, produce a **`docs/PrefabInventory.md`** file:

```markdown
# Prefab Inventory
Generated: <date>
Source scenes: <list>

## Prefabs to Create

### New Prefabs (standalone)
| Prefab Name | Domain Folder | Source GameObject | Logic Components (Root) | Visual Components (Body) |
|-------------|---------------|-------------------|------------------------|--------------------------|
| Player.prefab | Player/ | Player + Body child | PlayerProvider, CapsuleCollider, Rigidbody | SkinnedMeshRenderer, Animator |
| ...

### Base Prefab + Variants
| Base Prefab | Variants | Shared Components | Differing Components |
|-------------|----------|-------------------|----------------------|
| BaseEnemy.prefab | FastEnemy.prefab, TankEnemy.prefab | EnemyProvider, CapsuleCollider | MoveSpeed (data), visual mesh |
| ...

### Already Correct (skip)
| Prefab | Reason |
|--------|--------|
| MainCamera.prefab | already a prefab instance in correct folder |
| ...

## Target Folder Structure
_GameFolders/Prefabs/
├── Player/
│   └── Player.prefab
├── Enemies/
│   ├── BaseEnemy.prefab
│   ├── FastEnemy.prefab
│   └── TankEnemy.prefab
├── UI/
├── VFX/
└── Environment/

## Prefab Rules Compliance Checklist
- [ ] Every non-organizer scene GameObject will be a prefab instance
- [ ] All prefabs placed under _GameFolders/Prefabs/<Domain>/
- [ ] All prefabs: Root = logic, Body child = visual
- [ ] Shared-base objects use Prefab Variants
```

**Show this inventory to the user and ask for confirmation before proceeding.**

```
## Prefab Inventory Ready

[paste PrefabInventory.md summary]

Proceed with prefab creation? (yes / edit first / stop)
```

If user says **edit first** → wait for their changes to `docs/PrefabInventory.md`, then re-read it.
If user says **stop** → abort.
If user says **yes** → continue to Step 3.

---

## Step 3 — Unity Setup

Spawn a **unity-setup** subagent with this prompt:

```
You are a Unity scene architect. Create all prefabs listed in the Prefab Inventory following the project's NON-NEGOTIABLE prefab rules.

## Prefab Inventory
$PREFAB_INVENTORY_CONTENT

## Source Scenes
$SCENE_PATHS

## Prefab Rules (NON-NEGOTIABLE)

### Folder Structure
Every prefab must be saved under: _GameFolders/Prefabs/<Domain>/
Never dump prefabs at the root Prefabs/ level.

### Logic / Visual Separation
Every prefab has exactly two levels:
- Root GameObject: holds Provider, Controller, Collider, Rigidbody, injected MonoBehaviours ONLY — NO Renderer components
- Body child: holds MeshRenderer, SkinnedMeshRenderer, Animator, particle systems ONLY — NO logic scripts

Example:
  Enemy.prefab (root)
    ├── EnemyProvider (component)
    ├── CapsuleCollider (component)
    └── Body/ (child GameObject)
        ├── SkinnedMeshRenderer (component)
        └── Animator (component)

### Prefab Variants
When the inventory lists a Base + Variants:
1. Create the base prefab first
2. Create each variant FROM the base prefab (Prefab Variant, not a copy)
3. Only override what actually differs in each variant

### Steps for Each Prefab
1. Use MCP to create the prefab at the correct path
2. Add logic components to root
3. Create Body child GameObject
4. Add visual components to Body child
5. Verify structure matches the inventory

### After All Prefabs Created
For each source scene, replace bare GameObjects with the newly created prefab instances using MCP.

## Completion Checklist
For each prefab, confirm:
- [ ] Saved at _GameFolders/Prefabs/<Domain>/<Name>.prefab
- [ ] Root has logic components only
- [ ] Body child has visual components only
- [ ] Variants created from base (not copied)
- [ ] Scene GameObjects replaced with prefab instances

## When Done
List every prefab created (path + type: standalone / base / variant).
List every scene modified.
Report: DONE or BLOCKED with reason.
```

If BLOCKED → stop and show the user with exact blocker message.

---

## Step 4 — Unity Developer Review

Spawn a **unity-developer** subagent with this prompt:

```
You are a Unity 6 specialist. Review the prefabs created by the unity-setup agent.

## Prefab Inventory (expected state)
$PREFAB_INVENTORY_CONTENT

## Assets Created
$UNITY_SETUP_OUTPUT

## Review Checklist (prefab rules 8-10)

8. PREFAB STRUCTURE
   - Every scene GameObject that is not a hierarchy organizer must be a prefab instance
   - Root holds logic components only (Provider, Controller, Collider, Rigidbody, injected MonoBehaviours)
   - Body child holds visual components only (MeshRenderer, SkinnedMeshRenderer, Animator, VFX)
   - No bare GameObjects in scenes (except empty organizers with no components)

9. PREFAB VARIANTS
   - Shared-base objects use Prefab Variants (not manually duplicated prefabs)
   - Variants only override what actually differs

10. PREFAB FOLDER
    - All prefabs under _GameFolders/Prefabs/<Domain>/
    - No prefabs at root Prefabs/ level
    - Domain subfolder name matches object type (Enemies, Player, UI, VFX, Environment...)

Use Unity MCP tools to read actual prefab and scene state — do NOT read `.prefab` or `.unity` files as raw text.
Use `manage_scene`, `find_gameobjects`, and `mcpforunity://scene/gameobject/{id}` to verify actual state.

## Output Format
APPROVED or FAIL: list every violation as [asset:path] description
```

### Review Loop

If **FAIL** → spawn **unity-setup** subagent again with only the failing items to fix. Re-run unity-developer. Max 3 passes.

If still FAIL after 3 passes → stop, show user all remaining issues. Ask:
- `skip` → proceed to commit (user accepts responsibility)
- `stop` → abort, leave files uncommitted

---

### COMMIT_GATE

Show the user the COMMIT_GATE block from `.claude/docs/director-gates.md`.
Pass: scenes analyzed, prefabs created (list), scenes modified, reviewer verdict.
Wait for `go` before spawning the committer. `stop` → leave files staged, print summary without committing.

---

## Step 5 — Committer

Spawn a **committer** subagent with this prompt:

```
You are a release engineer. Commit the prefab creation work.

## What Was Done
Analyzed scenes under _Scene/, created prefabs following project prefab rules.

## Scenes Analyzed
$SCENE_PATHS

## Prefabs Created
$UNITY_SETUP_OUTPUT

## Rules
- Run: git status, git diff --stat
- Stage: all .prefab, .unity, .asset, .meta files changed + docs/PrefabInventory.md
- NEVER use git add -A or git add .  — add specific files only
- Commit message format: "feat(prefabs): <short description>"
- Do NOT push
- Report: commit hash and message
```

---

## Completion

Print:
```
## ✓ Prefab Creation Complete

Scenes analyzed: [N]
Prefabs created: [N] ([X] standalone, [Y] base, [Z] variants)
Scenes updated: [N] (bare GameObjects replaced)
Inventory: docs/PrefabInventory.md

Commit: [hash] — [message]
Reviewer: unity-developer — APPROVED
```

$ARGUMENTS
